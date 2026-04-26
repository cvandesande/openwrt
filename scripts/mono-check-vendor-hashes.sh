#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PACKAGES=(
	package/kernel/ask-cdx
	package/kernel/ask-fci
	package/libs/libfci
	package/network/ask-cmm
	package/network/ask-dpa-app
)

usage() {
	cat <<'EOF'
Usage: scripts/mono-check-vendor-hashes.sh [--list] [--no-clean] [package/path ...]

Checks Mono vendor git package source archives against their PKG_MIRROR_HASH
values by running each package's OpenWrt download target.

By default, the script first removes only the selected package source archives
from dl/. That forces OpenWrt to regenerate the archive from PKG_SOURCE_VERSION
instead of accepting an older cached tarball that still matches the old hash.
The check skips OpenWrt source mirrors and verifies the regenerated archive
hash directly against PKG_MIRROR_HASH.

If a hash is stale, OpenWrt prints the generated hash. Verify the pinned source
commit is intended before updating PKG_MIRROR_HASH.
EOF
}

read_make_var() {
	local makefile="$1"
	local var="$2"

	sed -nE "s/^[[:space:]]*${var}[[:space:]]*[:+?]?=[[:space:]]*//p" "$makefile" | tail -n 1
}

expand_simple_vars() {
	local value="$1"
	local pkg_name="$2"
	local pkg_version="$3"

	value="${value//\$\{PKG_NAME\}/$pkg_name}"
	value="${value//\$\(PKG_NAME\)/$pkg_name}"
	value="${value//\$\{PKG_VERSION\}/$pkg_version}"
	value="${value//\$\(PKG_VERSION\)/$pkg_version}"
	printf '%s\n' "$value"
}

list_only=false
clean_archives=true
packages=()

while [ "$#" -gt 0 ]; do
	case "$1" in
	--help|-h)
		usage
		exit 0
		;;
	--list)
		list_only=true
		;;
	--no-clean)
		clean_archives=false
		;;
	--*)
		printf 'Unknown option: %s\n' "$1" >&2
		usage >&2
		exit 2
		;;
	*)
		packages+=("$1")
		;;
	esac
	shift
done

if [ "${#packages[@]}" -eq 0 ]; then
	packages=("${DEFAULT_PACKAGES[@]}")
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

if [ ! -f include/toplevel.mk ]; then
	printf 'Run this script from an OpenWrt tree.\n' >&2
	exit 2
fi

shopt -s nullglob
failures=0
declare -A checked_sources=()

for package_path in "${packages[@]}"; do
	makefile="${package_path%/}/Makefile"
	if [ ! -f "$makefile" ]; then
		printf '::error::Package Makefile not found: %s\n' "$makefile" >&2
		failures=1
		continue
	fi

	pkg_name="$(read_make_var "$makefile" PKG_NAME)"
	pkg_version="$(read_make_var "$makefile" PKG_VERSION)"
	pkg_source_url="$(read_make_var "$makefile" PKG_SOURCE_URL)"
	pkg_source_version="$(read_make_var "$makefile" PKG_SOURCE_VERSION)"
	pkg_mirror_hash="$(read_make_var "$makefile" PKG_MIRROR_HASH)"
	source_subdir="$(read_make_var "$makefile" PKG_SOURCE_SUBDIR)"

	if [ -z "$pkg_name" ] || [ -z "$pkg_version" ]; then
		printf '::error::Could not read PKG_NAME/PKG_VERSION from %s\n' "$makefile" >&2
		failures=1
		continue
	fi

	if [ -z "$source_subdir" ]; then
		source_subdir='$(PKG_NAME)-$(PKG_VERSION)'
	fi
	source_subdir="$(expand_simple_vars "$source_subdir" "$pkg_name" "$pkg_version")"
	archive_pattern="${source_subdir}.tar.*"
	source_key="${source_subdir}|${pkg_source_url}|${pkg_source_version}|${pkg_mirror_hash}"

	if [ "$list_only" = true ]; then
		printf '%s -> dl/%s\n' "$package_path" "$archive_pattern"
		continue
	fi

	printf '==> Checking %s (%s)\n' "$package_path" "$archive_pattern"

	if [ -n "${checked_sources[$source_key]:-}" ]; then
		printf 'Skipping duplicate source already checked via %s\n' "${checked_sources[$source_key]}"
		continue
	fi

	if [ -z "$pkg_mirror_hash" ] || [ "$pkg_mirror_hash" = skip ] || [ "$pkg_mirror_hash" = x ]; then
		printf '::error::%s must have a real PKG_MIRROR_HASH for Mono vendor source checks\n' "$makefile" >&2
		failures=1
		continue
	fi

	if [ "$clean_archives" = true ]; then
		archives=(dl/$archive_pattern)
		if [ "${#archives[@]}" -gt 0 ]; then
			printf 'Removing cached source archive(s):'
			printf ' %s' "${archives[@]}"
			printf '\n'
			rm -f -- "${archives[@]}"
		fi
	fi

	printf 'Regenerating from PKG_SOURCE_URL with OpenWrt source mirrors disabled for this preflight.\n'

	if make "${package_path%/}/download" V=s MIRROR=; then
		archives=(dl/$archive_pattern)
		source_archives=()
		for archive in "${archives[@]}"; do
			case "$archive" in
			*.hash)
				continue
				;;
			esac
			source_archives+=("$archive")
		done

		if [ "${#source_archives[@]}" -ne 1 ]; then
			printf '::error::Expected exactly one regenerated source archive for %s, found %s\n' \
				"$package_path" "${#source_archives[@]}" >&2
			failures=1
			continue
		fi

		actual_hash="$(sha256sum "${source_archives[0]}" | awk '{ print $1 }')"
		if [ "$actual_hash" != "$pkg_mirror_hash" ]; then
			printf '::error::Hash mismatch for %s: expected %s, got %s\n' \
				"${source_archives[0]}" "$pkg_mirror_hash" "$actual_hash" >&2
			failures=1
			continue
		fi

		checked_sources[$source_key]="$package_path"
		printf 'OK: %s (%s)\n' "$package_path" "$actual_hash"
	else
		printf '::error::Vendor source hash check failed for %s\n' "$package_path" >&2
		failures=1
	fi
done

if [ "$failures" -ne 0 ]; then
	cat >&2 <<'EOF'

One or more vendor source hash checks failed.

If the PKG_SOURCE_VERSION change is intentional, verify the source commit and
update the package's PKG_MIRROR_HASH to the hash printed by OpenWrt. Do not use
PKG_MIRROR_HASH:=skip for Mono product packages.
EOF
	exit 1
fi
