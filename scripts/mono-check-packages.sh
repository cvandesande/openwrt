#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENWRT="$ROOT"

cd "$OPENWRT"

git diff --check

if [[ -x scripts/mono-check-vendor-hashes.sh ]]; then
  scripts/mono-check-vendor-hashes.sh --no-clean \
    package/kernel/ask-cdx \
    package/network/ask-cmm \
    package/kernel/ask-fci \
    package/libs/libfci
fi

make -j1 package/kernel/ask-cdx/compile V=s
make -j1 package/network/ask-cmm/compile V=s
make -j1 package/kernel/ask-fci/compile V=s
make -j1 package/libs/libfci/compile V=s
