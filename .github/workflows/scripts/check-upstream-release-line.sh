#!/usr/bin/env bash
# Watches for upstream OpenWrt branching a NEW stable release line
# (openwrt-YY.MM off main) newer than the newest line this repo has
# forked via fork-mono-ask-release-line.sh. Files a single tracking issue
# per new line so it doesn't get missed between the infrequent (roughly
# yearly) moments this actually happens; it never dispatches the fork
# itself, since forking commits this repo to maintaining a new stable
# line for months and should stay a deliberate human action.
#
# Deliberately NOT reported: upstream lines OLDER than the newest one
# forked here. This project has no intention of supporting anything older
# than its current line, and treating every historical openwrt-* branch
# as "not forked yet" is what made this check file six stale issues on
# every run.
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

# Only lines strictly newer than the newest line forked here are of
# interest. MIN_RELEASE_LINE is the floor used if no mono-base-* branch
# exists yet (a fresh clone of this tooling), so the check can never
# regress into reporting the whole history of upstream branches.
newest_known="$(printf '%s\n' "$known_lines" | sort -V | tail -n1)"
newest_known="${newest_known:-${MIN_RELEASE_LINE:-25.12}}"

# sort -V so 25.12 > 24.10 > 9.07; a plain sort would order these wrong.
new_lines="$(
	printf '%s\n' "$upstream_lines" \
		| while IFS= read -r line; do
			[ -n "$line" ] || continue
			[ "$line" = "$newest_known" ] && continue
			# newer iff it sorts last against newest_known
			if [ "$(printf '%s\n%s\n' "$newest_known" "$line" | sort -V | tail -n1)" = "$line" ]; then
				printf '%s\n' "$line"
			fi
		done
)"

if [ -z "$new_lines" ]; then
	summary "No upstream OpenWrt release line newer than ${newest_known}. Forked lines: $(printf '%s' "$known_lines" | tr '\n' ' ')"
	exit 0
fi

while IFS= read -r line; do
	[ -n "$line" ] || continue

	title="Upstream OpenWrt branched openwrt-${line} — fork a Mono stable line?"

	# --state all: a CLOSED tracking issue means "seen and decided", so
	# closing one must stop the re-file. Matching titles exactly out of a
	# plain label listing rather than via `--search` also avoids depending
	# on GitHub's search index, which lags behind issue creation and can
	# itself cause a duplicate file on a closely-following run.
	existing_issue="$(
		gh issue list --repo "$REPO" --state all --label "$ISSUE_LABEL" \
			--limit 200 --json number,title \
			| jq -r --arg t "$title" 'map(select(.title == $t)) | .[0].number // empty'
	)"

	if [ -n "$existing_issue" ]; then
		summary "Tracking issue #${existing_issue} already filed for openwrt-${line} (any state)."
		continue
	fi

	latest_tag="$(git ls-remote --tags --refs "$UPSTREAM_REMOTE" "v${line}.*" | sed -E 's#.*refs/tags/##' | sort -V | tail -n1)"

	body="$(cat <<EOF
Upstream branched \`openwrt-${line}\` off their \`main\`, which this repo hasn't forked into a Mono stable line yet.

${latest_tag:+Latest upstream tag on that line so far: \`${latest_tag}\`.}

If this repo's own \`main\`/\`mono-oss\`/\`mono-ask\` trunk is still close to where upstream branched from (see the caution in \`fork-mono-ask-release-line.sh\`), run **Fork Mono ASK Release Line** with \`upstream_tag\` set to the first (or latest available) \`v${line}.*\` tag.

This issue was filed automatically by the upstream-release-line check. **Closing it is how you decline (or record completion of) this line** — the check looks for a tracking issue in any state, so a closed one is never re-filed. Point releases on a line already forked here are handled by Advance Mono ASK Release Line, not by this check.
EOF
	)"

	gh issue create --repo "$REPO" --title "$title" --body "$body" --label "$ISSUE_LABEL"
	summary "Filed tracking issue for new upstream line openwrt-${line}."
done <<< "$new_lines"
