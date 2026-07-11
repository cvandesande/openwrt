#!/usr/bin/env bash
# Advances an existing Mono stable release line to a new upstream point
# release (e.g. v25.12.5 -> v25.12.6), without touching the rolling
# main/mono-oss/mono-ask trunk. This is the routine tool for cutting the next
# point release of a line already established by fork-mono-ask-release-line.sh.
#
# Source refs are STABLE_BASE_BRANCH/STABLE_OSS_BRANCH/STABLE_ASK_BRANCH
# (persistent tracking branches for the release line, e.g. mono-base-25.12/
# mono-oss-25.12/mono-ask-25.12) rather than main/mono-oss/mono-ask. Only the
# release line's own patch commits (STABLE_BASE_BRANCH..STABLE_OSS_BRANCH and
# STABLE_OSS_BRANCH..STABLE_ASK_BRANCH) are replayed onto the new tag, so this
# stays correct even though the rolling trunk has since moved to a different
# kernel version.
#
# CI workflow files are still restored from WORKFLOW_SOURCE_BRANCH (the live
# rolling main), deliberately decoupled from the stable-line source branches,
# so a release line doesn't ship CI definitions frozen at its original fork
# point.
#
# Produces the same output contract (release_tag, base_branch, oss_branch,
# ask_branch, and their SHAs) as fork-mono-ask-release-line.sh, plus the
# stable-line branch names so the caller can fast-forward them after a
# successful build/publish.
set -euo pipefail

ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/openwrt/openwrt.git}"
UPSTREAM_TAG="${UPSTREAM_TAG:?UPSTREAM_TAG is required}"
MONO_REVISION="${MONO_REVISION:-r1}"
MONO_NUMBER="${MONO_NUMBER:-mono1}"
WORKFLOW_SOURCE_BRANCH="${WORKFLOW_SOURCE_BRANCH:-main}"
STABLE_BASE_BRANCH="${STABLE_BASE_BRANCH:?STABLE_BASE_BRANCH is required}"
STABLE_OSS_BRANCH="${STABLE_OSS_BRANCH:?STABLE_OSS_BRANCH is required}"
STABLE_ASK_BRANCH="${STABLE_ASK_BRANCH:?STABLE_ASK_BRANCH is required}"
UPSTREAM_EXCLUDE_PATHS="${UPSTREAM_EXCLUDE_PATHS:-.github/workflows .github/llm-review-rules.md}"
SHA_MAP_DIR="${SHA_MAP_DIR:-/tmp/mono-ask-sha-maps}"

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

	summary "### Release line advance failed"
	summary ""
	summary "$detail"
	summary ""
	summary "Conflicted files:"
	git diff --name-only --diff-filter=U | sed 's/^/- `/' | sed 's/$/`/' >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || true

	abort_rebase_if_needed
	exit 1
}

run_rebase() {
	local branch="$1"
	shift

	if ! git rebase "$@"; then
		fail_rebase "$branch" "Rebase conflict while advancing ${branch}. Point-release rebases should normally be conflict-free; a real upstream backport must be touching the same lines as a Mono patch."
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

# Records old-SHA -> new-SHA -> subject for every commit replayed by a rebase,
# so release notes can cite the pre-rebase commit a contributor actually
# pushed alongside the rebased SHA that ends up in a release. Rebases don't
# preserve or expose this mapping on their own, and the pre-rebase remote
# refs the old range is read from stay resolvable for the life of the job, so
# this is safe to compute right after each rebase rather than snapshotting
# beforehand.
write_sha_map() {
	local name="$1"
	local old_range="$2"
	local new_range="$3"
	local out="${SHA_MAP_DIR}/${name}.tsv"
	local old_file new_file old_count new_count

	mkdir -p "$SHA_MAP_DIR"
	: > "$out"

	old_file="$(mktemp)"
	new_file="$(mktemp)"
	git log --no-merges --reverse --pretty=tformat:'%H%x09%s' "$old_range" > "$old_file"
	git log --no-merges --reverse --pretty=tformat:'%H%x09%s' "$new_range" > "$new_file"
	old_count="$(wc -l < "$old_file")"
	new_count="$(wc -l < "$new_file")"

	if [ "$old_count" = "$new_count" ] && [ "$old_count" -gt 0 ]; then
		paste "$new_file" "$old_file" | awk -F'\t' '{ print $1 "\t" $3 "\t" $2 }' > "$out"
	elif [ "$old_count" != "$new_count" ]; then
		printf '::warning::Skipping %s SHA map: pre-rebase commit count (%s) does not match post-rebase count (%s)\n' "$name" "$old_count" "$new_count" >&2
	fi

	rm -f "$old_file" "$new_file"
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
	printf '::error::Working tree is not clean before release line advance\n' >&2
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

require_remote_branch "$WORKFLOW_SOURCE_BRANCH"
require_remote_branch "$STABLE_BASE_BRANCH"
require_remote_branch "$STABLE_OSS_BRANCH"
require_remote_branch "$STABLE_ASK_BRANCH"
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
workflow_source_ref="$(remote_ref "$WORKFLOW_SOURCE_BRANCH")"

git switch --force-create "$base_branch" "$upstream_sha"
restore_paths_from_ref "$workflow_source_ref"
commit_if_needed "${STABLE_BASE_BRANCH}: track OpenWrt ${UPSTREAM_TAG} without imported workflows"
base_sha="$(git rev-parse HEAD)"

git switch --force-create "$oss_branch" "$(remote_ref "$STABLE_OSS_BRANCH")"
run_rebase "$oss_branch" --onto "$base_branch" "$(remote_ref "$STABLE_BASE_BRANCH")"
oss_sha="$(git rev-parse HEAD)"
write_sha_map "oss" "$(remote_ref "$STABLE_BASE_BRANCH")..$(remote_ref "$STABLE_OSS_BRANCH")" "${base_branch}..${oss_branch}"

git switch --force-create "$ask_branch" "$(remote_ref "$STABLE_ASK_BRANCH")"
run_rebase "$ask_branch" --onto "$oss_branch" "$(remote_ref "$STABLE_OSS_BRANCH")"
ask_sha="$(git rev-parse HEAD)"
write_sha_map "ask" "$(remote_ref "$STABLE_OSS_BRANCH")..$(remote_ref "$STABLE_ASK_BRANCH")" "${oss_branch}..${ask_branch}"

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
set_output stable_base_branch "$STABLE_BASE_BRANCH"
set_output stable_oss_branch "$STABLE_OSS_BRANCH"
set_output stable_ask_branch "$STABLE_ASK_BRANCH"

summary "### Mono ASK release line advance"
summary ""
summary "| Item | Value |"
summary "| --- | --- |"
summary "| stable line | \`${STABLE_ASK_BRANCH}\` |"
summary "| upstream tag | \`${UPSTREAM_TAG}\` |"
summary "| upstream commit | \`${upstream_sha}\` |"
summary "| release tag | \`${release_tag}\` |"
summary "| image version | \`${version_number}\` |"
summary "| image code | \`${version_code}\` |"
summary "| base branch | \`${base_branch}\` @ \`${base_sha}\` |"
summary "| mono-oss branch | \`${oss_branch}\` @ \`${oss_sha}\` |"
summary "| mono-ask branch | \`${ask_branch}\` @ \`${ask_sha}\` |"
summary ""
summary "The prepared refs are local only until the build succeeds. On success,"
summary "\`${STABLE_BASE_BRANCH}\`/\`${STABLE_OSS_BRANCH}\`/\`${STABLE_ASK_BRANCH}\` will be"
summary "fast-forwarded to match."
