#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/mono-redact-lab-output.sh [file...]

Redact lab-sensitive values from logs before pasting into docs or chat.
Reads stdin when no files are provided.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

sed_expr=(
  -E
  -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<ip>/g'
  -e 's/([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}/<mac>/g'
  -e 's/([Ss][Pp][Ii][ =:]*)(0x)?[[:xdigit:]]+/\1<spi>/g'
  -e 's/(sagd=0x)[[:xdigit:]]+/\1<handle>/g'
  -e 's/(skb_sagd=0x)[[:xdigit:]]+/\1<handle>/g'
  -e 's/(selected_sagd=0x)[[:xdigit:]]+/\1<handle>/g'
  -e 's/(handle[ =:]+)(0x)?[[:xdigit:]]+/\1<handle>/g'
  -e 's/(ct=)0{8}[[:xdigit:]]+/\1<ptr>/g'
  -e 's/(dev_addr[ =:]+)<mac>/\1<mac>/g'
)

if [[ $# -gt 0 ]]; then
  sed "${sed_expr[@]}" "$@"
else
  sed "${sed_expr[@]}"
fi
