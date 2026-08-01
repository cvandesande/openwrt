#!/usr/bin/env bash
set -euo pipefail

out="${1:?output path required}"

require_env() {
	local name="$1"
	if [ -z "${!name:-}" ]; then
		printf '::error::Required environment variable is not set: %s\n' "$name" >&2
		exit 1
	fi
}

commit_count() {
	local range="$1"

	git rev-list --no-merges --count "$range"
}

lookup_orig_sha() {
	local sha="$1"
	local map_file="$2"

	[ -n "$map_file" ] && [ -s "$map_file" ] || return 0
	awk -F'\t' -v s="$sha" '$1 == s { print $2; exit }' "$map_file"
}

format_commit_line() {
	local sha="$1"
	local subject="$2"
	local map_file="$3"
	local short orig

	short="${sha:0:12}"
	orig="$(lookup_orig_sha "$sha" "$map_file")"
	if [ -n "$orig" ]; then
		printf -- '- `%s` %s (orig `%s`)\n' "$short" "$subject" "${orig:0:12}"
	else
		printf -- '- `%s` %s\n' "$short" "$subject"
	fi
}

commit_list() {
	local range="$1"
	local map_file="${2:-}"
	local sha subject

	if [ "$(commit_count "$range")" -eq 0 ]; then
		printf -- '- None\n'
		return
	fi

	while IFS=$'\t' read -r sha subject; do
		format_commit_line "$sha" "$subject" "$map_file"
	done < <(git log --no-merges --pretty=tformat:'%H%x09%s' "$range")
}

# Every release publishes the full cumulative commit list of both layers as a
# machine-readable asset, so the next release can diff against it and show only
# what is actually new. Every fork/advance rebases the ASK and OSS branches
# fresh onto the new upstream base, so there is no shared git ancestor to diff a
# range against -- commit subject is the only identity that survives that
# rebase, and the manifest records it explicitly rather than making the next
# release re-parse rendered markdown.
COMMIT_MANIFEST_NAME="mono-ask-release-commits.tsv"

# Emits "layer<TAB>sha<TAB>orig<TAB>subject" for a range. This is the
# cumulative stack, not the delta -- a delta would be useless as the next
# release's baseline.
write_manifest_layer() {
	local layer="$1"
	local range="$2"
	local map_file="$3"
	local sha subject orig

	while IFS=$'\t' read -r sha subject; do
		orig="$(lookup_orig_sha "$sha" "$map_file")"
		printf '%s\t%s\t%s\t%s\n' "$layer" "$sha" "$orig" "$subject"
	done < <(git log --no-merges --pretty=tformat:'%H%x09%s' "$range")
}

# Best-effort lookup of the most recently published release on this line. This
# must never fail the release build, so every failure mode here falls back to
# reporting the full range -- clearly labelled as such, never as a delta.
previous_release_tag() {
	[ -n "${GITHUB_REPOSITORY:-}" ] || return 1
	command -v gh >/dev/null 2>&1 || return 1

	gh api "repos/${GITHUB_REPOSITORY}/releases" --paginate \
		--jq '[.[] | select(.draft == false) | select(.tag_name | test("^mono-ask-v[0-9]+\\.[0-9]+\\.[0-9]+-r[0-9]+$"))] | sort_by(.published_at) | reverse | .[0].tag_name // empty' \
		2>/dev/null || return 1
}

# Downloads the previous release's commit manifest. Prints its path on success.
download_previous_manifest() {
	local tag="$1"
	local dir

	dir="$(mktemp -d)"
	if gh release download "$tag" \
		--repo "$GITHUB_REPOSITORY" \
		--pattern "$COMMIT_MANIFEST_NAME" \
		--dir "$dir" >/dev/null 2>&1 &&
		[ -s "${dir}/${COMMIT_MANIFEST_NAME}" ]
	then
		printf '%s\n' "${dir}/${COMMIT_MANIFEST_NAME}"
		return 0
	fi

	rm -rf "$dir"
	return 1
}

# Legacy fallback for releases cut before the manifest asset existed: recover
# the baseline by parsing that release's own rendered appendix. Note this only
# yields a correct baseline when the older release listed its full stack; a
# release whose appendix was itself a delta, or whose body was replaced by hand,
# cannot serve as a baseline at all -- hence the empty-result failure below.
previous_release_subjects_from_body() {
	local tag="$1"
	local heading="$2"
	local body

	body="$(gh api "repos/${GITHUB_REPOSITORY}/releases/tags/${tag}" --jq '.body' 2>/dev/null)" || return 1
	printf '%s\n' "$body" | awk -v h="$heading" '
		$0 ~ "<summary>" h { found=1; next }
		found && /<\/details>/ { exit }
		found && /^- `/ {
			line = $0
			sub(/^- `[0-9a-f]+` /, "", line)
			sub(/ \(orig `[0-9a-f]+`\)$/, "", line)
			print line
		}
	'
}

# Writes the baseline subjects for one layer to $2 and sets BASELINE_SOURCE to
# manifest|body. Returns non-zero when no usable baseline exists -- including
# when a lookup "succeeds" but yields zero commits, which is how a hand-edited
# release body silently produced a full stack labelled as a delta.
BASELINE_SOURCE=""
baseline_subjects() {
	local layer="$1"
	local dest="$2"
	local prev_manifest="$3"
	local heading="$4"

	BASELINE_SOURCE=""

	if [ -n "$prev_manifest" ]; then
		awk -F'\t' -v l="$layer" '$1 == l { print $4 }' "$prev_manifest" > "$dest"
		if [ -s "$dest" ]; then
			BASELINE_SOURCE="manifest"
			return 0
		fi
	fi

	if previous_release_subjects_from_body "$PREV_TAG" "$heading" > "$dest" && [ -s "$dest" ]; then
		BASELINE_SOURCE="body"
		return 0
	fi

	: > "$dest"
	return 1
}

# Renders one <details> block for a commit range, newest first. When a usable
# baseline for the previous release exists, scopes the list to only commits not
# already in it (matched by subject, the only identity that survives the
# per-release rebase), so the notes read as "what changed since last time"
# instead of the entire patch stack.
#
# When no baseline exists -- the first release on a line, a lookup failure, or a
# previous release whose body was replaced by hand -- this falls back to the
# full range and SAYS SO in the summary line. The previous version fell back
# silently while still printing "since <tag>", which reported the whole
# cumulative stack as if it were one release's worth of change.
commit_details() {
	local title="$1"
	local range="$2"
	local map_file="$3"
	local prev_manifest="$4"
	local layer="$5"
	local heading="$6"
	local baseline_file sha subject new_count=0 total body

	total="$(commit_count "$range")"
	baseline_file="$(mktemp)"

	if [ -z "$PREV_TAG" ] || ! baseline_subjects "$layer" "$baseline_file" "$prev_manifest" "$heading"; then
		rm -f "$baseline_file"
		printf '<details>\n'
		if [ -n "$PREV_TAG" ]; then
			printf '<summary>%s: full stack (%s commits, no usable baseline for `%s`)</summary>\n\n' \
				"$title" "$total" "$PREV_TAG"
		else
			printf '<summary>%s: full stack (%s commits, no previous release found)</summary>\n\n' \
				"$title" "$total"
		fi
		commit_list "$range" "$map_file"
		printf '\n</details>\n'
		return
	fi

	body="$(mktemp)"
	while IFS=$'\t' read -r sha subject; do
		if grep -Fxq "$subject" "$baseline_file"; then
			continue
		fi
		format_commit_line "$sha" "$subject" "$map_file" >> "$body"
		new_count=$((new_count + 1))
	done < <(git log --no-merges --pretty=tformat:'%H%x09%s' "$range")

	printf '<details>\n'
	if [ "$BASELINE_SOURCE" = body ]; then
		printf '<summary>%s since `%s` (%s new of %s total, baseline recovered from release notes)</summary>\n\n' \
			"$title" "$PREV_TAG" "$new_count" "$total"
	else
		printf '<summary>%s since `%s` (%s new of %s total)</summary>\n\n' \
			"$title" "$PREV_TAG" "$new_count" "$total"
	fi

	if [ "$new_count" -eq 0 ]; then
		printf -- '- None\n'
	else
		cat "$body"
	fi
	printf '\n</details>\n'

	rm -f "$body" "$baseline_file"
}

for name in \
	RELEASE_TAG \
	VERSION_NUMBER \
	VERSION_CODE \
	UPSTREAM_TAG \
	UPSTREAM_SHA \
	BASE_BRANCH \
	OSS_BRANCH \
	ASK_BRANCH \
	BASE_SHA \
	OSS_SHA \
	ASK_SHA
do
	require_env "$name"
done

curated_notes="docs/releases/${RELEASE_TAG}.md"
mkdir -p "$(dirname "$out")"

# Published as a release asset next to the images, and read back by the next
# release on this line as its baseline.
manifest="$(dirname "$out")/${COMMIT_MANIFEST_NAME}"
{
	write_manifest_layer ask "${OSS_SHA}..${ASK_SHA}" "${ASK_SHA_MAP:-}"
	write_manifest_layer oss "${BASE_SHA}..${OSS_SHA}" "${OSS_SHA_MAP:-}"
} > "$manifest"

PREV_TAG="$(previous_release_tag || true)"
prev_manifest=""
if [ -n "$PREV_TAG" ]; then
	prev_manifest="$(download_previous_manifest "$PREV_TAG" || true)"
	if [ -z "$prev_manifest" ]; then
		printf '::warning::No %s asset on %s; falling back to release-notes parsing for the baseline\n' \
			"$COMMIT_MANIFEST_NAME" "$PREV_TAG" >&2
	fi
fi

{
	printf '# Mono OpenWrt %s %s\n\n' "$VERSION_NUMBER" "$RELEASE_TAG"
	printf 'This is a Mono OpenWrt pre-release for controlled smoke testing. Built from OpenWrt upstream tag `%s`.\n\n' "$UPSTREAM_TAG"

	if [ -f "$curated_notes" ]; then
		printf '## Release Notes\n\n'
		cat "$curated_notes"
		printf '\n\n'
	fi

	printf '## Commit Appendix\n\n'
	printf 'Commits are listed newest first, scoped to what is new since the previous release on this line. A summary line reading "full stack" means no baseline was available and the entire cumulative patch stack is shown instead. `orig` cites the pre-rebase commit SHA on the source branch, where known. The complete cumulative list ships as the `%s` release asset.\n\n' "$COMMIT_MANIFEST_NAME"
	commit_details "Included Mono ASK commits" "${OSS_SHA}..${ASK_SHA}" "${ASK_SHA_MAP:-}" "$prev_manifest" ask "Included Mono ASK commits"
	printf '\n'
	commit_details "Included Mono OSS commits" "${BASE_SHA}..${OSS_SHA}" "${OSS_SHA_MAP:-}" "$prev_manifest" oss "Included Mono OSS commits"
	printf '\n\n'

	printf '## Source\n\n'
	printf -- '- Tag: `%s`\n' "$RELEASE_TAG"
	printf -- '- Commit: `%s`\n' "$ASK_SHA"
	printf -- '- Upstream base: OpenWrt `%s` (`%s`)\n' "$UPSTREAM_TAG" "$UPSTREAM_SHA"
	printf -- '- Base branch: `%s` (`%s`)\n' "$BASE_BRANCH" "$BASE_SHA"
	printf -- '- Mono OSS branch: `%s` (`%s`)\n' "$OSS_BRANCH" "$OSS_SHA"
	printf -- '- Mono ASK branch: `%s` (`%s`)\n' "$ASK_BRANCH" "$ASK_SHA"
	printf -- '- Image version: `%s`\n' "$VERSION_NUMBER"
	printf -- '- Image code: `%s`\n\n' "$VERSION_CODE"

	printf '## CI Validation\n\n'
	printf -- '- Mono vendor source hash preflight passed.\n'
	printf -- '- `make download -j$(nproc)` passed.\n'
	printf -- '- `make -j$(nproc)` passed.\n'
	printf -- '- Rootfs release metadata matches `Mono OpenWrt %s %s`.\n\n' "$VERSION_NUMBER" "$VERSION_CODE"

	printf '## Hardware Validation\n\n'
	printf 'Hardware smoke validation is pending. Do not promote this pre-release to a full release until the Mono Gateway DK smoke-test record passes.\n'
} > "$out"
