# AGENTS.md

## Scope

These instructions apply to the `openwrt/` integration repo. The parent
workspace `AGENTS.md` contains cross-repo context.

## Repository Role

- This repo is the Mono OpenWrt integration and build repo.
- Primary branch is `mono-ask`.
- `main` tracks upstream OpenWrt.
- `mono-oss` carries minimal Mono board support.
- `mono-ask` layers ASK/FMAM/DPAA/CEETM hardware acceleration on top.
- `mono-oss-next` and `mono-ask-next` are automation-owned rebased test
  branches; do not treat them as validated release branches.

## Design Rules

- Prefer boxed, rebase-friendly changes over broad vendor-style patch imports.
- Keep OpenWrt/Linux authoritative for routing, firewall, conntrack, services,
  config, package builds, images, and sysupgrade.
- Keep NXP ASK/FMAM/DPAA/CEETM behavior behind explicit hardware-control
  boundaries.
- Do not make hardware-offload claims from build success or CMM installed state
  alone.
- Do not commit firmware blobs when a source-fetch OpenWrt package can pull
  firmware during build.

## Safety Boundaries

- Be extra cautious with NOR, eMMC, bootloader, rootfs, recovery, sysupgrade,
  DTS power/reset/mux, and board bring-up logic.
- Do not change NOR/eMMC/boot/root partition logic unless explicitly required
  and the failure mode is understood.
- Do not make speculative DTS changes for radios, SDIO, UART muxing, reset
  lines, or power sequencing without source evidence or hardware validation.
- Do not alter ASK/CDX/CMM/CEETM/FMAM/DPAA fastpath behavior while working on
  unrelated docs, build, packaging, or UI tasks.
- Never treat software fallback as acceptable unless the task explicitly allows
  it and docs/reporting say so.

## Build Commands

Normal firmware build:

```sh
./scripts/feeds update -a
./scripts/feeds install -a
cp config/mono_gateway-dk.seed .config
make defconfig
make download -j"$(nproc)"
make -j"$(nproc)"
```

Use parallel builds for normal work:

```sh
make -j"$(nproc)" target/linux/compile
```

Use `-j1 V=s` only when readable failure logs are needed.

Focused package builds:

```sh
make -j1 package/kernel/ask-cdx/compile V=s
make -j1 package/network/ask-cmm/compile V=s
make -j1 package/kernel/ask-fci/compile V=s
make -j1 package/libs/libfci/compile V=s
```

When owned vendor package pins change, validate hashes:

```sh
scripts/mono-check-vendor-hashes.sh --no-clean package/kernel/ask-cdx package/network/ask-cmm package/kernel/ask-fci package/libs/libfci
```

## Validation Standards

- For hardware offload claims, collect route state, CMM connection state,
  tuple-level hardware stats, FMAN/DPAA counters, and CPU-path evidence.
- `fp-state: installed` alone is not proof of hardware residency.
- For CEETM/QoS work, distinguish upload-side hardware egress shaping from
  SQM/CAKE or download-side bufferbloat control.
- For security-review fixes, prefer narrow fixes plus harness/build
  validation; use router-side runtime validation when the risk crosses
  kernel/user boundaries.
- If the accepted scope cannot be honestly completed, stop and report the
  blocker rather than widening scope silently.

## Compile Database And Clangd

Use clangd when compiler-aware C understanding is useful: kernel, CDX, CMM,
FCI, DPAA/FMAM/CEETM, macros, struct layouts, callback paths, or
include/config-sensitive diagnostics.

The combined local database is:

```text
compile_commands.json
```

Refresh the merged database after regenerating fragments:

```sh
scripts/mono-refresh-compile-commands.py
```

If fragments are stale or missing, follow `docs/04-developer-tooling.md`.

Terminal checks:

```sh
clangd --check=/home/cvandesande/mono-openwrt-project/ask-cmm/src/conntrack.c --compile-commands-dir=/home/cvandesande/mono-openwrt-project/openwrt
clangd --check=/home/cvandesande/mono-openwrt-project/ask-cdx/cdx-5.03.1/control_ipv4.c --compile-commands-dir=/home/cvandesande/mono-openwrt-project/openwrt
```

Do not treat clangd as proof of correctness. The source of truth remains
OpenWrt builds and hardware validation.

## Documentation

- Keep public docs focused on the current architecture and validated state.
- Remove stale experimental history rather than documenting abandoned paths.
- Link to detailed docs instead of duplicating long explanations in multiple
  READMEs.
- When documenting unfinished work, call it remaining work rather than out of
  scope unless it is truly out of scope.
