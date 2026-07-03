#!/usr/bin/env bash
set -euo pipefail

ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/openwrt/openwrt.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
MAIN_BRANCH="${MAIN_BRANCH:-main}"
MONO_OSS_BRANCH="${MONO_OSS_BRANCH:-mono-oss}"
MONO_ASK_BRANCH="${MONO_ASK_BRANCH:-mono-ask}"
UPSTREAM_EXCLUDE_PATHS="${UPSTREAM_EXCLUDE_PATHS:-.github/workflows .github/llm-review-rules.md}"
MODE="${1:-${NIGHTLY_BUILD_MODE:-prepare}}"

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

require_remote_branch() {
	local branch="$1"

	if ! remote_branch_exists "$branch"; then
		printf '::error::Required branch %s/%s was not found\n' "$ORIGIN_REMOTE" "$branch" >&2
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

	summary "### Branch update failed"
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
		fail_rebase "$branch" "Rebase conflict while updating ${branch}."
	fi
}

run_rebase_keep_theirs_for_paths() {
	local branch="$1"
	shift
	local paths=()

	while [ "$#" -gt 0 ]; do
		case "$1" in
		--)
			shift
			break
			;;
		*)
			paths+=("$1")
			shift
			;;
		esac
	done

	if git rebase "$@"; then
		return
	fi

	local conflicts path allowed=false
	conflicts="$(git diff --name-only --diff-filter=U)"
	if [ -n "$conflicts" ]; then
		allowed=true
		while IFS= read -r path; do
			local match=false
			local allowed_path
			for allowed_path in "${paths[@]}"; do
				if [ "$path" = "$allowed_path" ]; then
					match=true
					break
				fi
			done
			if [ "$match" != true ]; then
				allowed=false
				break
			fi
		done <<< "$conflicts"
	fi

	if [ "$allowed" != true ]; then
		fail_rebase "$branch" "Rebase conflict while updating ${branch}."
	fi

	printf '::notice::Keeping rebased %s version for allowed conflict path(s): %s\n' "$branch" "$(printf '%s' "$conflicts" | tr '\n' ' ')" >&2
	for path in "${paths[@]}"; do
		if git diff --name-only --diff-filter=U -- "$path" | grep -qxF "$path"; then
			git checkout --theirs -- "$path"
			git add -- "$path"
		fi
	done

	if ! GIT_EDITOR=true git rebase --continue; then
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

force_with_lease_arg() {
	local branch="$1"

	if remote_branch_exists "$branch"; then
		printf -- '--force-with-lease=refs/heads/%s:%s' "$branch" "$(git rev-parse "$(remote_ref "$branch")")"
	else
		printf -- '--force-with-lease=refs/heads/%s:' "$branch"
	fi
}

prepare() {
	if ! git diff --quiet || ! git diff --cached --quiet; then
		printf '::error::Working tree is not clean before branch update\n' >&2
		exit 1
	fi

	if git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
		git remote set-url "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
	else
		git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
	fi

	git fetch --prune "$ORIGIN_REMOTE" "+refs/heads/*:refs/remotes/${ORIGIN_REMOTE}/*"
	git fetch --prune "$UPSTREAM_REMOTE" "+refs/heads/${UPSTREAM_BRANCH}:refs/remotes/${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"

	require_remote_branch "$MAIN_BRANCH"
	require_remote_branch "$MONO_OSS_BRANCH"
	require_remote_branch "$MONO_ASK_BRANCH"

	upstream_main_ref="refs/remotes/${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"
	if ! git show-ref --verify --quiet "$upstream_main_ref"; then
		printf '::error::Required upstream branch %s/%s was not found\n' "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH" >&2
		exit 1
	fi

	exclude_ref="$(remote_ref "$MAIN_BRANCH")"

	git switch --force-create "$MAIN_BRANCH" "$upstream_main_ref"
	restore_paths_from_ref "$exclude_ref"
	commit_if_needed "${MAIN_BRANCH}: track upstream source without imported workflows"
	main_sha="$(git rev-parse HEAD)"
	set_output main_sha "$main_sha"

	git switch --force-create "$MONO_OSS_BRANCH" "$(remote_ref "$MONO_OSS_BRANCH")"
	run_rebase "$MONO_OSS_BRANCH" "$MAIN_BRANCH"
	mono_oss_sha="$(git rev-parse HEAD)"

	git switch --force-create "$MONO_ASK_BRANCH" "$(remote_ref "$MONO_ASK_BRANCH")"
	run_rebase_keep_theirs_for_paths "$MONO_ASK_BRANCH" README.md -- --onto "$MONO_OSS_BRANCH" "$(remote_ref "$MONO_OSS_BRANCH")"
	mono_ask_sha="$(git rev-parse HEAD)"

	set_output mono_oss_sha "$mono_oss_sha"
	set_output mono_ask_sha "$mono_ask_sha"

	summary "### Branch preparation"
	summary ""
	summary "| Branch | Local result SHA | Update policy |"
	summary "| --- | --- | --- |"
	summary "| \`${MAIN_BRANCH}\` | \`${main_sha}\` | Constructed from \`${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}\`; excluded upstream paths restored from \`${exclude_ref}\`; not pushed yet |"
	summary "| \`${MONO_OSS_BRANCH}\` | \`${mono_oss_sha}\` | Rebuilt from current \`${MONO_OSS_BRANCH}\`, then rebased onto \`${MAIN_BRANCH}\`; not pushed yet |"
	summary "| \`${MONO_ASK_BRANCH}\` | \`${mono_ask_sha}\` | Rebuilt from current \`${MONO_ASK_BRANCH}\`, then rebased onto the rebuilt \`${MONO_OSS_BRANCH}\`; not pushed yet |"
	summary ""
	summary "All three branches publish atomically, only after the \`${MONO_ASK_BRANCH}\` build succeeds."
	summary "These branches are compile/build-validated only by this workflow. Hardware"
	summary "validation happens exclusively through the release pipeline"
	summary "(\`Cut Mono ASK Release Candidate\` / \`Cut Mono ASK Snapshot Release\`, followed by"
	summary "manual smoke testing before promoting a GitHub pre-release)."
}

publish() {
	if ! git show-ref --verify --quiet "refs/heads/${MAIN_BRANCH}" ||
		! git show-ref --verify --quiet "refs/heads/${MONO_OSS_BRANCH}" ||
		! git show-ref --verify --quiet "refs/heads/${MONO_ASK_BRANCH}"; then
		printf '::error::Prepared local branches are missing; run prepare before publish\n' >&2
		exit 1
	fi

	if ! git merge-base --is-ancestor "$MAIN_BRANCH" "$MONO_OSS_BRANCH"; then
		printf '::error::%s is not based on %s\n' "$MONO_OSS_BRANCH" "$MAIN_BRANCH" >&2
		exit 1
	fi

	if ! git merge-base --is-ancestor "$MONO_OSS_BRANCH" "$MONO_ASK_BRANCH"; then
		printf '::error::%s is not based on %s\n' "$MONO_ASK_BRANCH" "$MONO_OSS_BRANCH" >&2
		exit 1
	fi

	main_sha="$(git rev-parse "$MAIN_BRANCH")"
	mono_oss_sha="$(git rev-parse "$MONO_OSS_BRANCH")"
	mono_ask_sha="$(git rev-parse "$MONO_ASK_BRANCH")"
	main_lease="$(force_with_lease_arg "$MAIN_BRANCH")"
	oss_lease="$(force_with_lease_arg "$MONO_OSS_BRANCH")"
	ask_lease="$(force_with_lease_arg "$MONO_ASK_BRANCH")"

	git push --atomic \
		"$main_lease" \
		"$oss_lease" \
		"$ask_lease" \
		"$ORIGIN_REMOTE" \
		"${main_sha}:refs/heads/${MAIN_BRANCH}" \
		"${mono_oss_sha}:refs/heads/${MONO_OSS_BRANCH}" \
		"${mono_ask_sha}:refs/heads/${MONO_ASK_BRANCH}"

	set_output main_sha "$main_sha"
	set_output mono_oss_sha "$mono_oss_sha"
	set_output mono_ask_sha "$mono_ask_sha"

	summary "### Branch publication"
	summary ""
	summary "| Branch | Published SHA | Update policy |"
	summary "| --- | --- | --- |"
	summary "| \`${MAIN_BRANCH}\` | \`${main_sha}\` | Published atomically with force-with-lease after successful \`${MONO_ASK_BRANCH}\` build |"
	summary "| \`${MONO_OSS_BRANCH}\` | \`${mono_oss_sha}\` | Published atomically with force-with-lease after successful \`${MONO_ASK_BRANCH}\` build |"
	summary "| \`${MONO_ASK_BRANCH}\` | \`${mono_ask_sha}\` | Published atomically with force-with-lease after successful build |"
	summary ""
	summary "These branches are compile/build-validated only. Hardware validation happens"
	summary "exclusively through the release pipeline."
}

case "$MODE" in
prepare)
	prepare
	;;
publish)
	publish
	;;
*)
	printf '::error::Unknown mode %s. Expected prepare or publish.\n' "$MODE" >&2
	exit 1
	;;
esac
