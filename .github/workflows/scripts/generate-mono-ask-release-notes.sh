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

commit_list() {
	local range="$1"
	local count

	count="$(commit_count "$range")"
	if [ "$count" -eq 0 ]; then
		printf -- '- None\n'
		return
	fi

	git log --reverse --no-merges --abbrev=12 --pretty=format:'- `%h` %s' "$range"
	printf '\n'
}

commit_details() {
	local title="$1"
	local range="$2"
	local count

	count="$(commit_count "$range")"
	printf '<details>\n'
	printf '<summary>%s (%s commits)</summary>\n\n' "$title" "$count"
	commit_list "$range"
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
	printf 'This is a Mono OpenWrt pre-release for controlled smoke testing.\n\n'

	if [ -f "$curated_notes" ]; then
		printf '## Release Notes\n\n'
		cat "$curated_notes"
		printf '\n\n'
	fi

	printf '## Commit Appendix\n\n'
	printf 'The lists below are generated from the exact rebased release-candidate ranges for traceability. They are not curated notable-change notes.\n\n'
	commit_details "Included Mono ASK commits" "${OSS_SHA}..${ASK_SHA}"
	printf '\n'
	commit_details "Included Mono OSS commits" "${BASE_SHA}..${OSS_SHA}"
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
