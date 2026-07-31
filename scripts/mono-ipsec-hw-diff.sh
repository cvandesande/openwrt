#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/mono-ipsec-hw-diff.sh <before-snapshot> <after-snapshot>

Compare two ipsec-hw-snapshot outputs and print only changed counter lines.
Snapshot counters must use:
  counter name=value
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 2
fi

before="$1"
after="$2"

if [[ ! -f "$before" || ! -f "$after" ]]; then
  echo "Both snapshot files must exist." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

extract_counters() {
  awk '
    /^counter [^=]+=.*$/ {
      sub(/^counter /, "")
      key=$0
      sub(/=.*/, "", key)
      value=$0
      sub(/^[^=]+=/, "", value)
      print key "\t" value
    }
  ' "$1" | sort -u
}

extract_counters "$before" >"$tmpdir/before"
extract_counters "$after" >"$tmpdir/after"

changed="$tmpdir/changed"
join -t "$(printf '\t')" -a1 -a2 -e '<missing>' -o '0,1.2,2.2' \
  "$tmpdir/before" "$tmpdir/after" |
awk -F '\t' '
  $2 != $3 {
    delta = ""
    if ($2 ~ /^-?[0-9]+$/ && $3 ~ /^-?[0-9]+$/)
      delta = sprintf(" delta=%+d", $3 - $2)
    printf "%s: %s -> %s%s\n", $1, $2, $3, delta
  }
' >"$changed"

if [[ -s "$changed" ]]; then
  cat "$changed"
else
  echo "No counter changes."
fi
