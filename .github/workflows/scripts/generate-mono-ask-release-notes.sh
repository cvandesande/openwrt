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

# Best-effort lookup of the most recently published release on this line, so
# the appendix can show only what's actually new instead of the full
# cumulative patch stack every time. Every fork/advance rebases the ASK and
# OSS branches fresh onto the new upstream base, so there is no shared git
# ancestor to diff a range against -- matching by commit subject against the
# previous release's own published appendix is the only thing that survives
# that rebase. This must never fail the release build, so every failure mode
# here just falls back to the full range.
previous_release_tag() {
	[ -n "${GITHUB_REPOSITORY:-}" ] || return 1
	command -v gh >/dev/null 2>&1 || return 1

	gh api "repos/${GITHUB_REPOSITORY}/releases" --paginate \
		--jq '[.[] | select(.draft == false) | select(.tag_name | test("^mono-ask-v[0-9]+\\.[0-9]+\\.[0-9]+-r[0-9]+$"))] | sort_by(.published_at) | reverse | .[0].tag_name // empty' \
		2>/dev/null || return 1
}

previous_release_subjects() {
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

# Renders one <details> block for a commit range, newest first. If a previous
# release is available, scopes the list to only commits not already present
# (by subject) in that release's own appendix section, so the notes read as
# "what changed since last time" instead of the entire patch stack. Falls
# back to the full range -- e.g. for the very first release on a line, or if
# the previous-release lookup failed -- rather than showing nothing.
commit_details() {
	local title="$1"
	local range="$2"
	local map_file="$3"
	local prev_tag="$4"
	local heading="$5"
	local prev_subjects_file="" sha subject count=0 body

	if [ -n "$prev_tag" ]; then
		prev_subjects_file="$(mktemp)"
		if ! previous_release_subjects "$prev_tag" "$heading" > "$prev_subjects_file"; then
			rm -f "$prev_subjects_file"
			prev_subjects_file=""
		fi
	fi

	printf '<details>\n'

	if [ -n "$prev_subjects_file" ]; then
		body="$(mktemp)"
		while IFS=$'\t' read -r sha subject; do
			if [ -s "$prev_subjects_file" ] && grep -Fxq "$subject" "$prev_subjects_file"; then
				continue
			fi
			format_commit_line "$sha" "$subject" "$map_file" >> "$body"
			count=$((count + 1))
		done < <(git log --no-merges --pretty=tformat:'%H%x09%s' "$range")

		printf '<summary>%s since `%s` (%s commits)</summary>\n\n' "$title" "$prev_tag" "$count"
		if [ "$count" -eq 0 ]; then
			printf -- '- None\n'
		else
			cat "$body"
		fi
		rm -f "$body" "$prev_subjects_file"
	else
		printf '<summary>%s (%s commits)</summary>\n\n' "$title" "$(commit_count "$range")"
		commit_list "$range" "$map_file"
	fi

	printf '\n</details>\n'
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

{
	printf '# Mono OpenWrt %s %s\n\n' "$VERSION_NUMBER" "$RELEASE_TAG"
	printf 'This is a Mono OpenWrt pre-release for controlled smoke testing. Built from OpenWrt upstream tag `%s`.\n\n' "$UPSTREAM_TAG"

	if [ -f "$curated_notes" ]; then
		printf '## Release Notes\n\n'
		cat "$curated_notes"
		printf '\n\n'
	fi

	prev_tag="$(previous_release_tag || true)"

	printf '## Commit Appendix\n\n'
	printf 'Commits are listed newest first. When a previous release is found on this line, each list is scoped to commits new since that release; otherwise the full range is shown. `orig` cites the pre-rebase commit SHA on the source branch, where known.\n\n'
	commit_details "Included Mono ASK commits" "${OSS_SHA}..${ASK_SHA}" "${ASK_SHA_MAP:-}" "${prev_tag:-}" "Included Mono ASK commits"
	printf '\n'
	commit_details "Included Mono OSS commits" "${BASE_SHA}..${OSS_SHA}" "${OSS_SHA_MAP:-}" "${prev_tag:-}" "Included Mono OSS commits"
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
