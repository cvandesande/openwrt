#!/usr/bin/env bash
set -euo pipefail

OPENWRT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CODEQL="${CODEQL:-$HOME/codeql/codeql}"
DB_ROOT="$OPENWRT/codeql-db"
RESULTS_ROOT="$OPENWRT/codeql-results"
JOBS="$(nproc)"
CODEQL_RAM="${CODEQL_RAM:-}"

clean=true
create_db=true
analyze_db=true
download_queries=false
disable_ccache=true
run_packages=true
run_kernel=false
list_only=false

queries=()
selected_packages=()

default_packages=(
	"ask-cdx:package/kernel/ask-cdx"
	"ask-fci:package/kernel/ask-fci"
	"libfci:package/libs/libfci"
	"ask-cmm:package/network/ask-cmm"
)

kernel_patches=(
	"target/linux/layerscape/patches-6.12/720-drivers-staging-and-freescale-add-sdk-dpaa-entry-points.patch"
	"target/linux/layerscape/patches-6.12/721-netfilter-add-ask-conntrack-metadata-abi.patch"
	"target/linux/layerscape/patches-6.12/722-net-preserve-ask-underlying-iif-across-bridge-handoff.patch"
	"target/linux/layerscape/patches-6.12/723-netfilter-honor-ask-permanent-conntracks.patch"
	"target/linux/layerscape/patches-6.12/724-net-xfrm-add-ask-ipsec-sa-handle-plumbing.patch"
)

kernel_file_roots=(
	"target/linux/layerscape/files/drivers/net/ethernet/freescale/sdk_dpaa"
	"target/linux/layerscape/files/drivers/net/ethernet/freescale/sdk_fman"
)

usage() {
	cat <<'EOF'
Usage: scripts/codeql-openwrt-scoped.sh [options]

Runs CodeQL only on Mono-owned ASK OpenWrt integration surfaces.

Default package scope:
  ask-cdx  -> package/kernel/ask-cdx
  ask-fci  -> package/kernel/ask-fci
  libfci   -> package/libs/libfci
  ask-cmm  -> package/network/ask-cmm

By default the script:
  1. cleans each selected package target,
  2. recreates that package's CodeQL database,
  3. builds the package under CodeQL tracing,
  4. writes one SARIF file per package.

Options:
  --package NAME|PATH       Analyze one scoped package. Can be repeated.
  --with-kernel-patches     Also trace target/linux/compile for ASK kernel patches.
  --kernel-only             Analyze only the ASK kernel patch surface.
  --packages-only           Analyze only the scoped packages.
  --no-clean                Do not run package or target/linux clean first.
  --analyze-only            Reuse existing databases and regenerate SARIF.
  --create-only             Create databases but skip SARIF analysis.
  --download-queries        Allow CodeQL to download query packs if needed.
  --query QUERY             Query pack, suite, directory, or .ql file. Repeatable.
  --jobs N                  Pass -jN to OpenWrt make. Default: nproc.
  --ram MB                  Pass --ram=MB to CodeQL.
  --codeql PATH             CodeQL CLI path. Default: $CODEQL or ~/codeql/codeql.
  --db-root DIR             Database output root. Default: OpenWrt root/codeql-db.
  --results-root DIR        SARIF output root. Default: OpenWrt root/codeql-results.
  --use-ccache              Do not set CCACHE_DISABLE=1 for traced builds.
  --list                    Print selected scope and exit.
  -h, --help                Show this help.

Outputs:
  codeql-db/<name>-openwrt/
  codeql-results/<name>-openwrt.sarif

With --with-kernel-patches:
  codeql-results/kernel-ask-patches.full.sarif
  codeql-results/kernel-ask-patches.sarif
  codeql-results/kernel-ask-patches.files

The kernel SARIF is filtered to primary result locations whose URI ends with a
file touched by the ASK kernel patch set or by the SDK DPAA/FMAN kernel source
integrated by those patches. The full SARIF is retained separately.
EOF
}

log() {
	printf '==> %s\n' "$*"
}

warn() {
	printf 'warning: %s\n' "$*" >&2
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

normalize_path() {
	case "$1" in
	/*)
		printf '%s\n' "$1"
		;;
	*)
		printf '%s\n' "$OPENWRT/$1"
		;;
	esac
}

package_spec_for() {
	local selector="${1%/}"
	selector="${selector#openwrt/}"
	local spec name path

	for spec in "${default_packages[@]}"; do
		name="${spec%%:*}"
		path="${spec#*:}"
		if [ "$selector" = "$name" ] || [ "$selector" = "$path" ]; then
			printf '%s\n' "$spec"
			return 0
		fi
	done

	return 1
}

append_unique_package() {
	local spec="$1"
	local existing

	for existing in "${selected_packages[@]}"; do
		if [ "$existing" = "$spec" ]; then
			return 0
		fi
	done

	selected_packages+=("$spec")
}

require_arg() {
	local opt="$1"
	local value="${2:-}"

	if [ -z "$value" ]; then
		die "$opt requires an argument"
	fi
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	-h|--help)
		usage
		exit 0
		;;
	--package)
		require_arg "$1" "${2:-}"
		spec="$(package_spec_for "$2")" || die "package is not in CodeQL scope: $2"
		append_unique_package "$spec"
		shift
		;;
	--package=*)
		value="${1#*=}"
		require_arg "--package" "$value"
		spec="$(package_spec_for "$value")" || die "package is not in CodeQL scope: $value"
		append_unique_package "$spec"
		;;
	--with-kernel-patches)
		run_kernel=true
		;;
	--kernel-only)
		run_packages=false
		run_kernel=true
		;;
	--packages-only)
		run_packages=true
		run_kernel=false
		;;
	--no-clean)
		clean=false
		;;
	--analyze-only)
		clean=false
		create_db=false
		analyze_db=true
		;;
	--create-only)
		create_db=true
		analyze_db=false
		;;
	--download-queries)
		download_queries=true
		;;
	--query)
		require_arg "$1" "${2:-}"
		queries+=("$2")
		shift
		;;
	--query=*)
		value="${1#*=}"
		require_arg "--query" "$value"
		queries+=("$value")
		;;
	--jobs)
		require_arg "$1" "${2:-}"
		JOBS="$2"
		shift
		;;
	--jobs=*)
		JOBS="${1#*=}"
		require_arg "--jobs" "$JOBS"
		;;
	--ram)
		require_arg "$1" "${2:-}"
		CODEQL_RAM="$2"
		shift
		;;
	--ram=*)
		CODEQL_RAM="${1#*=}"
		require_arg "--ram" "$CODEQL_RAM"
		;;
	--codeql)
		require_arg "$1" "${2:-}"
		CODEQL="$2"
		shift
		;;
	--codeql=*)
		CODEQL="${1#*=}"
		require_arg "--codeql" "$CODEQL"
		;;
	--db-root)
		require_arg "$1" "${2:-}"
		DB_ROOT="$2"
		shift
		;;
	--db-root=*)
		DB_ROOT="${1#*=}"
		require_arg "--db-root" "$DB_ROOT"
		;;
	--results-root)
		require_arg "$1" "${2:-}"
		RESULTS_ROOT="$2"
		shift
		;;
	--results-root=*)
		RESULTS_ROOT="${1#*=}"
		require_arg "--results-root" "$RESULTS_ROOT"
		;;
	--use-ccache)
		disable_ccache=false
		;;
	--list)
		list_only=true
		;;
	--*)
		die "unknown option: $1"
		;;
	*)
		die "unexpected argument: $1"
		;;
	esac
	shift
done

if [ "${#selected_packages[@]}" -eq 0 ]; then
	selected_packages=("${default_packages[@]}")
fi

DB_ROOT="$(normalize_path "$DB_ROOT")"
RESULTS_ROOT="$(normalize_path "$RESULTS_ROOT")"

if [ "$download_queries" = true ] && [ "${#queries[@]}" -eq 0 ]; then
	queries=("codeql/cpp-queries")
fi

if [ "$list_only" = true ]; then
	if [ "$run_packages" = true ]; then
		printf 'Packages:\n'
		for spec in "${selected_packages[@]}"; do
			printf '  %s -> %s\n' "${spec%%:*}" "${spec#*:}"
		done
	fi
	if [ "$run_kernel" = true ]; then
		printf 'Kernel patches:\n'
		printf '  %s\n' "${kernel_patches[@]}"
		printf 'Kernel file roots:\n'
		printf '  %s\n' "${kernel_file_roots[@]}"
	fi
	exit 0
fi

[ -d "$OPENWRT" ] || die "OpenWrt tree not found: $OPENWRT"
[ -f "$OPENWRT/include/toplevel.mk" ] || die "not an OpenWrt tree: $OPENWRT"
[ -f "$OPENWRT/.config" ] || die "OpenWrt .config is missing; configure the tree before running CodeQL"
[ -x "$CODEQL" ] || die "CodeQL CLI is not executable: $CODEQL"

case "$JOBS" in
''|*[!0-9]*)
	die "--jobs must be a positive integer"
	;;
0)
	die "--jobs must be greater than zero"
	;;
esac

if [ -n "$CODEQL_RAM" ]; then
	case "$CODEQL_RAM" in
	''|*[!0-9]*)
		die "--ram must be an integer number of MB"
		;;
	esac
fi

mkdir -p "$DB_ROOT" "$RESULTS_ROOT"

if [ "$analyze_db" = true ] && [ "$download_queries" = false ] && [ "${#queries[@]}" -eq 0 ]; then
	warn "no query was supplied; CodeQL will use installed defaults. If analysis cannot resolve queries, rerun with --download-queries or --query."
fi

codeql_database_create() {
	local name="$1"
	local db="$2"
	local command="$3"
	local category="$4"
	local args

	args=(
		database create
		--language=cpp
		--source-root "$OPENWRT"
	)

	if [ -n "$CODEQL_RAM" ]; then
		args+=(--ram "$CODEQL_RAM")
	fi

	args+=(--command "$command" "$db")

	log "Creating CodeQL database for $name"
	log "Build command: $command"
	(
		cd "$OPENWRT"
		"$CODEQL" "${args[@]}"
	)
}

codeql_database_analyze() {
	local name="$1"
	local db="$2"
	local sarif="$3"
	local category="$4"
	local args

	[ -d "$db" ] || die "CodeQL database not found for $name: $db"

	args=(
		database analyze "$db"
		--format sarifv2.1.0
		--output "$sarif"
		--sarif-category "$category"
		--no-sarif-minify
	)

	if [ "$download_queries" = true ]; then
		args+=(--download)
	else
		args+=(--no-download)
	fi

	if [ -n "$CODEQL_RAM" ]; then
		args+=(--ram "$CODEQL_RAM")
	fi

	if [ "${#queries[@]}" -gt 0 ]; then
		args+=("${queries[@]}")
	fi

	log "Analyzing CodeQL database for $name"
	"$CODEQL" "${args[@]}"
}

clean_openwrt_target() {
	local target="$1"

	log "Cleaning $target"
	(
		cd "$OPENWRT"
		make "$target" V=s
	)
}

remove_database() {
	local db="$1"

	[ -n "$db" ] || die "refusing to remove an empty database path"
	[ "$db" != "/" ] || die "refusing to remove /"
	rm -rf -- "$db"
}

run_package_codeql() {
	local spec="$1"
	local name="${spec%%:*}"
	local path="${spec#*:}"
	local db="$DB_ROOT/${name}-openwrt"
	local sarif="$RESULTS_ROOT/${name}-openwrt.sarif"
	local build_command="make -j${JOBS} ${path%/}/compile V=s"
	local category="mono-openwrt/${name}"

	[ -f "$OPENWRT/$path/Makefile" ] || die "package Makefile not found: $OPENWRT/$path/Makefile"

	if [ "$disable_ccache" = true ]; then
		build_command="env CCACHE_DISABLE=1 $build_command"
	fi

	if [ "$create_db" = true ]; then
		if [ "$clean" = true ]; then
			clean_openwrt_target "${path%/}/clean"
		fi
		remove_database "$db"
		codeql_database_create "$name" "$db" "$build_command" "$category"
	fi

	if [ "$analyze_db" = true ]; then
		codeql_database_analyze "$name" "$db" "$sarif" "$category"
	fi
}

write_kernel_patch_manifest() {
	local manifest="$1"
	local patch
	local root

	for patch in "${kernel_patches[@]}"; do
		[ -f "$OPENWRT/$patch" ] || die "kernel patch not found: $OPENWRT/$patch"
	done

	for root in "${kernel_file_roots[@]}"; do
		[ -d "$OPENWRT/$root" ] || die "kernel file root not found: $OPENWRT/$root"
	done

	{
		awk '
			/^(---|\+\+\+) [ab]\// {
				path = $2
				sub(/^[ab]\//, "", path)
				if (path != "/dev/null")
					print path
			}
		' "${kernel_patches[@]/#/$OPENWRT/}"

		for root in "${kernel_file_roots[@]}"; do
			find "$OPENWRT/$root" -type f | sed "s#^$OPENWRT/target/linux/layerscape/files/##"
		done
	} | sort -u > "$manifest"
}

filter_kernel_sarif() {
	local full_sarif="$1"
	local filtered_sarif="$2"
	local manifest="$3"
	local tmp_sarif="${filtered_sarif}.tmp"

	if ! command -v jq >/dev/null 2>&1; then
		warn "jq is not installed; leaving only unfiltered kernel SARIF at $full_sarif"
		return 0
	fi

	if jq --rawfile touched "$manifest" '
		def touched_files:
			$touched | split("\n") | map(select(length > 0));

		def touched_uri($uri):
			touched_files as $files |
			any($files[]; . as $file | $uri == $file or ($uri | endswith("/" + $file)) or ($uri | endswith($file)));

		def keep_result($result):
			any($result.locations[]?; (.physicalLocation.artifactLocation.uri? // "") as $uri | touched_uri($uri));

		.runs |= map(
			if has("results") then
				.results = [.results[] | select(keep_result(.))]
			else
				.
			end
		)
	' "$full_sarif" > "$tmp_sarif"; then
		mv "$tmp_sarif" "$filtered_sarif"
	else
		rm -f "$tmp_sarif"
		warn "failed to filter kernel SARIF with jq; leaving full SARIF at $full_sarif"
		return 0
	fi
}

run_kernel_patch_codeql() {
	local name="kernel-ask-patches"
	local db="$DB_ROOT/${name}-openwrt"
	local full_sarif="$RESULTS_ROOT/${name}.full.sarif"
	local filtered_sarif="$RESULTS_ROOT/${name}.sarif"
	local manifest="$RESULTS_ROOT/${name}.files"
	local build_command="make -j${JOBS} target/linux/compile V=s"
	local category="mono-openwrt/${name}"

	if [ "$disable_ccache" = true ]; then
		build_command="env CCACHE_DISABLE=1 $build_command"
	fi

	write_kernel_patch_manifest "$manifest"

	if [ "$create_db" = true ]; then
		if [ "$clean" = true ]; then
			clean_openwrt_target "target/linux/clean"
		fi
		remove_database "$db"
		codeql_database_create "$name" "$db" "$build_command" "$category"
	fi

	if [ "$analyze_db" = true ]; then
		codeql_database_analyze "$name" "$db" "$full_sarif" "$category"
		filter_kernel_sarif "$full_sarif" "$filtered_sarif" "$manifest"
	fi
}

log "Using CodeQL: $CODEQL"
log "Databases: $DB_ROOT"
log "Results: $RESULTS_ROOT"
log "OpenWrt jobs: $JOBS"

if [ "$run_kernel" = true ]; then
	run_kernel_patch_codeql
fi

if [ "$run_packages" = true ]; then
	for spec in "${selected_packages[@]}"; do
		run_package_codeql "$spec"
	done
fi

log "Done"
