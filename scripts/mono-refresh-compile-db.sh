#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENWRT="$ROOT"

cd "$OPENWRT"

make -j"$(nproc)" target/linux/compile

KDIR="$(find build_dir/target-aarch64_generic_musl/linux-layerscape_armv8_64b \
  -maxdepth 1 -type d -name 'linux-[0-9]*' | sort -V | tail -1)"

if [[ -z "$KDIR" ]]; then
  echo "Could not find layerscape kernel build directory" >&2
  exit 1
fi

python3 "$KDIR/scripts/clang-tools/gen_compile_commands.py" \
  -d "$KDIR" \
  -o compile_commands.kernel.json

make package/kernel/ask-cdx/clean
bear --output compile_commands.ask-cdx.json -- \
  make -j"$(nproc)" package/kernel/ask-cdx/compile

make package/network/ask-cmm/clean
bear --output compile_commands.ask-cmm.json -- \
  make -j"$(nproc)" package/network/ask-cmm/compile

make package/kernel/ask-fci/clean package/libs/libfci/clean
bear --output compile_commands.fci.json -- \
  make -j"$(nproc)" package/kernel/ask-fci/compile package/libs/libfci/compile

scripts/mono-refresh-compile-commands.py

jq length compile_commands.json
