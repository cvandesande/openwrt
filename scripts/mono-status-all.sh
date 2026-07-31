#!/usr/bin/env bash
# Show git status for this repo and the owned vendor source repos.
#
# The vendor repos are separate checkouts. They are looked for under
# --project-root, which defaults to the parent directory of this repo, matching
# the default used by scripts/mono-refresh-compile-commands.py. Repos that are
# not present are skipped, so this is safe in a clone of this repo alone.
set -euo pipefail

OPENWRT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$OPENWRT_ROOT/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/mono-status-all.sh [--project-root DIR]

Print `git status --short --branch` for this repo and for each owned vendor
source repo (ask-cdx, ask-cmm, fci) found under the project root. Missing
repos are skipped silently.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project-root) PROJECT_ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

printf '\n== openwrt ==\n'
git -C "$OPENWRT_ROOT" status --short --branch

for repo in ask-cdx ask-cmm fci; do
  path="$PROJECT_ROOT/$repo"
  [[ -d "$path/.git" ]] || continue
  printf '\n== %s ==\n' "$repo"
  git -C "$path" status --short --branch
done
