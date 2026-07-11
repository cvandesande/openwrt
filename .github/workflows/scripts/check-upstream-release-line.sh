#!/usr/bin/env bash
# Watches for upstream OpenWrt branching a new stable release line
# (openwrt-YY.MM off main) that this repo hasn't forked yet via
# fork-mono-ask-release-line.sh. Files or updates a single tracking issue
# per new line so it doesn't get missed between the infrequent (roughly
# yearly) moments this actually happens; it never dispatches the fork
# itself, since forking commits this repo to maintaining a new stable
# line for months and should stay a deliberate human action.
set -euo pipefail

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/openwrt/openwrt.git}"
ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
REPO="${REPO:?REPO is required}"
ISSUE_LABEL="${ISSUE_LABEL:-upstream-release-line}"

summary() {
	if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
		printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"
	fi
}

if git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
	git remote set-url "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
else
	git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
fi

if ! gh label list --repo "$REPO" --search "$ISSUE_LABEL" --json name --jq '.[].name' | grep -Fxq "$ISSUE_LABEL"; then
	gh label create "$ISSUE_LABEL" --repo "$REPO" --color "0e8a16" \
		--description "Filed by the upstream-release-line check"
fi

# Lines already forked here: any mono-base-<line> tracking branch names the
# line directly (e.g. mono-base-25.12), independent of how many -vX.Y.Z-rN
# revisions have been cut on top of it.
known_lines="$(
	git ls-remote --heads "$ORIGIN_REMOTE" 'mono-base-*' \
		| sed -E 's#.*refs/heads/mono-base-([0-9]+\.[0-9]+)$#\1#' \
		| sort -u
)"

upstream_lines="$(
	git ls-remote --heads "$UPSTREAM_REMOTE" 'openwrt-*' \
		| sed -E 's#.*refs/heads/openwrt-([0-9]+\.[0-9]+)$#\1#' \
		| sort -u
)"

new_lines="$(comm -13 <(printf '%s\n' "$known_lines") <(printf '%s\n' "$upstream_lines"))"

if [ -z "$new_lines" ]; then
	summary "No new upstream OpenWrt release line. Known lines: $(printf '%s' "$known_lines" | tr '\n' ' ')"
	exit 0
fi

while IFS= read -r line; do
	[ -n "$line" ] || continue

	title="Upstream OpenWrt branched openwrt-${line} — fork a Mono stable line?"

	existing_issue="$(
		gh issue list --repo "$REPO" --state open --label "$ISSUE_LABEL" \
			--search "in:title \"${title}\"" --json number --jq '.[0].number // empty'
	)"

	if [ -n "$existing_issue" ]; then
		summary "Tracking issue #${existing_issue} already open for openwrt-${line}."
		continue
	fi

	latest_tag="$(git ls-remote --tags --refs "$UPSTREAM_REMOTE" "v${line}.*" | sed -E 's#.*refs/tags/##' | sort -V | tail -n1)"

	body="$(cat <<EOF
Upstream branched \`openwrt-${line}\` off their \`main\`, which this repo hasn't forked into a Mono stable line yet.

${latest_tag:+Latest upstream tag on that line so far: \`${latest_tag}\`.}

If this repo's own \`main\`/\`mono-oss\`/\`mono-ask\` trunk is still close to where upstream branched from (see the caution in \`fork-mono-ask-release-line.sh\`), run **Fork Mono ASK Release Line** with \`upstream_tag\` set to the first (or latest available) \`v${line}.*\` tag.

This issue was filed automatically by the upstream-release-line check. Closing it does not stop future openwrt-${line} point releases from being tracked — it only stops re-filing for this specific line.
EOF
	)"

	gh issue create --repo "$REPO" --title "$title" --body "$body" --label "$ISSUE_LABEL"
	summary "Filed tracking issue for new upstream line openwrt-${line}."
done <<< "$new_lines"
