# Developer Tooling

This page documents optional local tooling for working on C code in this fork.
It is not part of the firmware build or validation path.

## Clangd And Compile Commands

`clangd` is a C/C++ language server. Editors and tooling use it for
go-to-definition, find-references, diagnostics, type information, and
autocomplete.

OpenWrt C code is hard for `clangd` to understand without help because files
depend on the exact target compiler, generated kernel headers, staged package
headers, OpenWrt config defines, and package-specific include paths.

A `compile_commands.json` file records the exact compile command for each
source file. With it, `clangd` can analyze the code using the same context the
OpenWrt build used.

This repository keeps generated compile databases out of Git. They are local
developer artifacts and should be regenerated when needed.

## Prerequisites

Install the local analysis tools:

```sh
sudo apt install clangd bear jq
```

`bear` records compiler invocations while `make` runs. It does not change the
firmware build output.

## When To Regenerate

Regenerate the compile database when the compile context changes:

- after rebasing onto newer OpenWrt
- after deleting `build_dir/` or running a broad clean
- after meaningful `.config` or seed changes
- after changing ASK package pins
- after clangd starts showing clearly stale missing-header or missing-macro
  diagnostics

You do not need to regenerate after every source edit. Edit normally, build
normally, and refresh the database only when the compiler context changes.

## Full Refresh

Run this from the OpenWrt repo root:

```sh
cd /home/cvandesande/mono-openwrt-project/openwrt

make -j"$(nproc)" target/linux/compile

KDIR="$(find build_dir/target-aarch64_generic_musl/linux-layerscape_armv8_64b \
  -maxdepth 1 -type d -name 'linux-[0-9]*' | sort -V | tail -1)"

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
```

The final command writes one root-level `compile_commands.json` for editor and
tooling use.

## Focused Refresh

If only one package's compile context changed, refresh only that package
fragment and then rebuild the merged database.

For CMM:

```sh
make package/network/ask-cmm/clean
bear --output compile_commands.ask-cmm.json -- \
  make -j"$(nproc)" package/network/ask-cmm/compile
scripts/mono-refresh-compile-commands.py
```

For CDX:

```sh
make package/kernel/ask-cdx/clean
bear --output compile_commands.ask-cdx.json -- \
  make -j"$(nproc)" package/kernel/ask-cdx/compile
scripts/mono-refresh-compile-commands.py
```

For FCI and libfci:

```sh
make package/kernel/ask-fci/clean package/libs/libfci/clean
bear --output compile_commands.fci.json -- \
  make -j"$(nproc)" package/kernel/ask-fci/compile package/libs/libfci/compile
scripts/mono-refresh-compile-commands.py
```

If a parallel package build fails and the output is hard to read, rerun that
single package with `-j1 V=s` for a readable failure log.

## What The Helper Does

`scripts/mono-refresh-compile-commands.py` merges these local fragments:

- `compile_commands.kernel.json`
- `compile_commands.ask-cdx.json`
- `compile_commands.ask-cmm.json`
- `compile_commands.fci.json`

It then rewrites ASK package source paths back to the editable sibling repos:

- `/home/cvandesande/mono-openwrt-project/ask-cdx`
- `/home/cvandesande/mono-openwrt-project/ask-cmm`
- `/home/cvandesande/mono-openwrt-project/fci`

Kernel entries remain pointed at the generated kernel build tree because that
is where OpenWrt applies patches and generates kernel headers.

The helper also removes a small set of GCC-only or build-only flags that make
`clangd` reject otherwise useful compile commands. This affects only the
local analysis database; it does not change real OpenWrt builds.

## Using It

After the merged database exists, point `clangd` or your editor at:

```text
/home/cvandesande/mono-openwrt-project/openwrt/compile_commands.json
```

For a terminal smoke test:

```sh
clangd --check=/home/cvandesande/mono-openwrt-project/ask-cmm/src/conntrack.c \
  --compile-commands-dir=/home/cvandesande/mono-openwrt-project/openwrt

clangd --check=/home/cvandesande/mono-openwrt-project/ask-cdx/cdx-5.03.1/control_ipv4.c \
  --compile-commands-dir=/home/cvandesande/mono-openwrt-project/openwrt
```

The purpose is faster navigation and better diagnostics while editing. The
source of truth for correctness remains the normal OpenWrt build and hardware
validation.
