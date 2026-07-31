#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENWRT_DIR="${OPENWRT_DIR:-$ROOT}"
LOG_DIR="${LOG_DIR:-$ROOT/.cache/build-logs}"

usage() {
  cat <<'EOF'
Usage: scripts/mono-build-summary.sh [--] <command> [args...]

Run an OpenWrt build command, write the full output to a timestamped log,
and print a compact pass/fail summary.

Environment:
  OPENWRT_DIR   OpenWrt checkout to run in. Defaults to ./openwrt.
  LOG_DIR       Directory for full logs. Defaults to ./.cache/build-logs.

Examples:
  scripts/mono-build-summary.sh make -j"$(nproc)" V=s
  scripts/mono-build-summary.sh make -j1 package/kernel/ask-cdx/compile V=s
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--" ]]; then
  shift
fi

if [[ $# -eq 0 ]]; then
  echo "No command provided." >&2
  usage >&2
  exit 2
fi

mkdir -p "$LOG_DIR"
stamp="$(date +%Y%m%d-%H%M%S)"
log="$LOG_DIR/openwrt-build-$stamp.log"
start="$(date +%s)"

printf 'OpenWrt dir: %s\n' "$OPENWRT_DIR"
printf 'Log: %s\n' "$log"
printf 'Command:'
printf ' %q' "$@"
printf '\n\n'

set +e
(
  cd "$OPENWRT_DIR"
  "$@"
) >"$log" 2>&1
rc=$?
set -e

end="$(date +%s)"
printf 'Exit: %d\n' "$rc"
printf 'Duration: %ss\n' "$((end - start))"

if [[ $rc -eq 0 ]]; then
  echo "Result: PASS"
  exit 0
fi

echo "Result: FAIL"
echo
echo "First relevant errors:"
grep -nEi \
  '(^|[^[:alpha:]])(error:|ERROR:|fatal:|undefined reference|No rule to make target|failed to build|unable to find library|cannot find|No such file|recipe for target|make\[[0-9]+\]: \*\*\*)' \
  "$log" | head -n 80 || true

echo
echo "Last 80 log lines:"
tail -n 80 "$log"

exit "$rc"
