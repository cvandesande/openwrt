#!/usr/bin/env bash
set -euo pipefail

ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/openwrt/openwrt.git}"
UPSTREAM_TAG="${UPSTREAM_TAG:?UPSTREAM_TAG is required}"
MONO_REVISION="${MONO_REVISION:-r1}"
MONO_NUMBER="${MONO_NUMBER:-mono1}"
MAIN_BRANCH="${MAIN_BRANCH:-main}"
MONO_OSS_BRANCH="${MONO_OSS_BRANCH:-mono-oss}"
MONO_ASK_BRANCH="${MONO_ASK_BRANCH:-mono-ask}"
UPSTREAM_EXCLUDE_PATHS="${UPSTREAM_EXCLUDE_PATHS:-.github/workflows .github/llm-review-rules.md}"

summary() {
	if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
		printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"
	fi
}

set_output() {
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
	fi
}

remote_ref() {
	printf 'refs/remotes/%s/%s' "$ORIGIN_REMOTE" "$1"
}

remote_branch_exists() {
	git show-ref --verify --quiet "$(remote_ref "$1")"
}

remote_tag_exists() {
	git ls-remote --exit-code --tags "$ORIGIN_REMOTE" "refs/tags/$1" >/dev/null 2>&1
}

require_remote_branch() {
	local branch="$1"

	if ! remote_branch_exists "$branch"; then
		printf '::error::Required branch %s/%s was not found\n' "$ORIGIN_REMOTE" "$branch" >&2
		exit 1
	fi
}

require_absent_branch() {
	local branch="$1"

	if remote_branch_exists "$branch"; then
		printf '::error::Release branch %s/%s already exists; use a new Mono revision\n' "$ORIGIN_REMOTE" "$branch" >&2
		exit 1
	fi
}

require_absent_tag() {
	local tag="$1"

	if git show-ref --verify --quiet "refs/tags/$tag" || remote_tag_exists "$tag"; then
		printf '::error::Release tag %s already exists; use a new Mono revision\n' "$tag" >&2
		exit 1
	fi
}

abort_rebase_if_needed() {
	if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
		git rebase --abort >/dev/null 2>&1 || true
	fi
}

fail_rebase() {
	local branch="$1"
	local detail="$2"

	printf '::error::%s\n' "$detail" >&2
	printf '::group::Conflicted files\n' >&2
	git diff --name-only --diff-filter=U >&2 || true
	git status --short >&2 || true
	printf '::endgroup::\n' >&2

	summary "### Release candidate preparation failed"
	summary ""
	summary "$detail"
	summary ""
	summary "Conflicted files:"
	git diff --name-only --diff-filter=U | sed 's/^/- `/' | sed 's/$/`/' >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || true

	abort_rebase_if_needed
	exit 1
}

resolve_mono_gateway_image_conflict() {
	local branch="$1"
	local path="target/linux/layerscape/image/armv8_64b.mk"
	local conflicted
	local tmpdir
	local ours_file
	local theirs_file
	local block_file

	conflicted="$(git diff --name-only --diff-filter=U)"
	if [ "$conflicted" != "$path" ]; then
		return 1
	fi

	tmpdir="$(mktemp -d)"
	ours_file="${tmpdir}/ours"
	theirs_file="${tmpdir}/theirs"
	block_file="${tmpdir}/mono-gateway-block"

	if ! git show ":2:${path}" > "$ours_file" || ! git show ":3:${path}" > "$theirs_file"; then
		rm -rf "$tmpdir"
		return 1
	fi

	if grep -Fxq "define Device/mono_gateway-dk" "$ours_file"; then
		rm -rf "$tmpdir"
		return 1
	fi

	if ! grep -Fxq "define Device/traverse_ten64_mtd" "$ours_file"; then
		rm -rf "$tmpdir"
		return 1
	fi

	sed -n '/^define Device\/mono_gateway-dk$/,/^TARGET_DEVICES += mono_gateway-dk$/p' "$theirs_file" > "$block_file"
	if ! grep -Fxq "define Device/mono_gateway-dk" "$block_file" ||
		! grep -Fxq "TARGET_DEVICES += mono_gateway-dk" "$block_file"; then
		rm -rf "$tmpdir"
		return 1
	fi

	if ! awk -v block_file="$block_file" '
		BEGIN {
			inserted = 0
			block_count = 0
			while ((getline line < block_file) > 0) {
				block[++block_count] = line
			}
			close(block_file)
			if (block_count == 0) {
				exit 2
			}
		}
		/^define Device\/traverse_ten64_mtd$/ && inserted == 0 {
			for (i = 1; i <= block_count; i++) {
				print block[i]
			}
			print ""
			inserted = 1
		}
		{ print }
		END {
			if (inserted == 0) {
				exit 1
			}
		}
	' "$ours_file" > "$path"; then
		rm -rf "$tmpdir"
		return 1
	fi

	rm -rf "$tmpdir"

	grep -Fxq "TARGET_DEVICES += mono_gateway-dk" "$path"
	grep -Fxq "TARGET_DEVICES += traverse_ten64_mtd" "$path"
	git add "$path"

	summary "Resolved known Mono Gateway DK image conflict while updating \`${branch}\`."
	GIT_EDITOR=true git rebase --continue
}

run_rebase() {
	local branch="$1"
	shift

	if ! git rebase "$@"; then
		if resolve_mono_gateway_image_conflict "$branch"; then
			return
		fi

		fail_rebase "$branch" "Rebase conflict while updating ${branch}."
	fi
}

restore_paths_from_ref() {
	local ref="$1"
	local path

	for path in $UPSTREAM_EXCLUDE_PATHS; do
		git rm -r --quiet --ignore-unmatch -- "$path"

		if git cat-file -e "${ref}:${path}" 2>/dev/null; then
			git restore --source "$ref" --staged --worktree -- "$path"
		fi
	done
}

commit_if_needed() {
	local message="$1"

	if ! git diff --quiet || ! git diff --cached --quiet; then
		git commit -m "$message"
	fi
}

if ! printf '%s\n' "$UPSTREAM_TAG" | grep -Eq '^v[0-9]+[.][0-9]+[.][0-9]+$'; then
	printf '::error::Unexpected upstream tag format: %s\n' "$UPSTREAM_TAG" >&2
	exit 1
fi

if ! printf '%s\n' "$MONO_REVISION" | grep -Eq '^r[0-9]+$'; then
	printf '::error::Unexpected mono_revision format: %s\n' "$MONO_REVISION" >&2
	exit 1
fi

if ! printf '%s\n' "$MONO_NUMBER" | grep -Eq '^mono[0-9]+$'; then
	printf '::error::Unexpected mono_number format: %s\n' "$MONO_NUMBER" >&2
	exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
	printf '::error::Working tree is not clean before release candidate preparation\n' >&2
	exit 1
fi

release_version="${UPSTREAM_TAG#v}"
release_tag="mono-ask-v${release_version}-${MONO_REVISION}"
version_number="${release_version}-${MONO_NUMBER}"
version_code="$release_tag"
base_branch="mono-base-v${release_version}-${MONO_REVISION}"
oss_branch="mono-oss-v${release_version}-${MONO_REVISION}"
ask_branch="mono-ask-v${release_version}-${MONO_REVISION}-candidate"

if git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
	git remote set-url "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
else
	git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
fi

git fetch --prune "$ORIGIN_REMOTE" \
	"+refs/heads/*:refs/remotes/${ORIGIN_REMOTE}/*" \
	"+refs/tags/*:refs/tags/*"
git fetch --prune "$UPSTREAM_REMOTE" "+refs/tags/${UPSTREAM_TAG}:refs/tags/${UPSTREAM_TAG}"

require_remote_branch "$MAIN_BRANCH"
require_remote_branch "$MONO_OSS_BRANCH"
require_remote_branch "$MONO_ASK_BRANCH"
require_absent_branch "$base_branch"
require_absent_branch "$oss_branch"
require_absent_branch "$ask_branch"
require_absent_tag "$release_tag"

upstream_tag_type="$(git cat-file -t "refs/tags/${UPSTREAM_TAG}")"
if [ "$upstream_tag_type" != tag ]; then
	printf '::error::%s must be an annotated upstream tag; got Git object type %s\n' "$UPSTREAM_TAG" "$upstream_tag_type" >&2
	exit 1
fi

upstream_sha="$(git rev-parse "refs/tags/${UPSTREAM_TAG}^{}")"
exclude_ref="$(remote_ref "$MAIN_BRANCH")"

git switch --force-create "$base_branch" "$upstream_sha"
restore_paths_from_ref "$exclude_ref"
commit_if_needed "${MAIN_BRANCH}: track OpenWrt ${UPSTREAM_TAG} without imported workflows"
base_sha="$(git rev-parse HEAD)"

git switch --force-create "$oss_branch" "$(remote_ref "$MONO_OSS_BRANCH")"
run_rebase "$oss_branch" --onto "$base_branch" "$(remote_ref "$MAIN_BRANCH")"
oss_sha="$(git rev-parse HEAD)"

git switch --force-create "$ask_branch" "$(remote_ref "$MONO_ASK_BRANCH")"
run_rebase "$ask_branch" --onto "$oss_branch" "$(remote_ref "$MONO_OSS_BRANCH")"
ask_sha="$(git rev-parse HEAD)"

set_output upstream_tag "$UPSTREAM_TAG"
set_output upstream_sha "$upstream_sha"
set_output release_version "$release_version"
set_output release_tag "$release_tag"
set_output version_number "$version_number"
set_output version_code "$version_code"
set_output base_branch "$base_branch"
set_output oss_branch "$oss_branch"
set_output ask_branch "$ask_branch"
set_output base_sha "$base_sha"
set_output oss_sha "$oss_sha"
set_output ask_sha "$ask_sha"

summary "### Mono ASK release candidate preparation"
summary ""
summary "| Item | Value |"
summary "| --- | --- |"
summary "| upstream tag | \`${UPSTREAM_TAG}\` |"
summary "| upstream commit | \`${upstream_sha}\` |"
summary "| release tag | \`${release_tag}\` |"
summary "| image version | \`${version_number}\` |"
summary "| image code | \`${version_code}\` |"
summary "| base branch | \`${base_branch}\` @ \`${base_sha}\` |"
summary "| mono-oss branch | \`${oss_branch}\` @ \`${oss_sha}\` |"
summary "| mono-ask branch | \`${ask_branch}\` @ \`${ask_sha}\` |"
summary ""
summary "The prepared refs are local only until the build succeeds."
