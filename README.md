# CVan's Mono OpenWrt Fork

This repository is a Mono-specific OpenWrt fork for LS1046A-based Mono Gateway
systems.

This is a custom, unofficial fork that uses the
[Mono-provided OpenWrt work](https://github.com/we-are-mono/OpenWRT-ASK/tree/mono-25.12.0-rc3)
as reference input. It tests an OpenWrt-native way to add hardware offload:
OpenWrt and Linux keep policy and service ownership, while the
hardware-specific code stays behind explicit integration points. The goal is to
make hardware offload easier to review, validate, and keep updated with
OpenWrt.

## Acknowledgment

Special thanks to the [Mono team](https://mono.si/), and especially to team
leader Tomaž Zaman, for building an exceptional router platform and for their
commitment to open design.

Mono updates and related videos are also available on the
[Tomaž Zaman YouTube channel](https://www.youtube.com/@tomazzaman).

## What Makes This Fork Different

This fork takes a different approach from the Mono-provided OpenWRT-ASK tree.
OpenWRT-ASK remains the vendor reference, but this tree keeps OpenWrt in charge
of normal router behavior: configuration, services, firewall and routing
decisions, packages, images, and sysupgrade.

OpenWRT-ASK keeps the NXP hardware acceleration stack together as one large
firmware integration. That makes sense for a vendor image: the hardware pieces
are developed and tested together. The tradeoff is that acceleration code
reaches into several parts of Linux networking at the same time, including the
Ethernet driver, connection tracking, VLAN/PPPoE/bridge handling, IPsec, and
QoS. That can make later Linux and OpenWrt updates harder, because more of the
networking stack has to move together.

This fork keeps those contact points smaller and easier to inspect. Linux still
decides what traffic is allowed and where it should go. The ASK components then
program eligible traffic into hardware offload. Traffic that cannot use
hardware offload stays on the normal Linux path. The goal is to make the port
easier to update as OpenWrt and Linux change.

SELinux support is included for the Mono Gateway DK image, with policy kept in
the OpenWrt package layer and shaped by observed access rather than broad
allowances. Images default to permissive mode during policy validation, with
enforcing-mode testing available.

The result is meant to feel like OpenWrt first: normal build commands, normal
packages, normal services, and native sysupgrade, with the Mono Gateway
hardware offload added where it is needed.

## Before You Install

Use this port if you are comfortable with OpenWrt, backing up and restoring
configuration, and basic Linux/OpenWrt troubleshooting. This port is intended
to be a drop-in replacement for OpenWRT-ASK, but that has not been fully tested
or validated yet. **Restoring an OpenWRT-ASK
backup may work, but it is not guaranteed.** Keep a copy of your current
firmware/config and know your recovery path before installing.

## What Works Today

- Native OpenWrt `sysupgrade` support.
- NXP hardware offload for 1G routed WAN traffic, including FMAN/DPAA routing
  paths with VLAN, PPPoE, firewall, and NAT, plus IPsec crypto.
- Runtime tools to show whether traffic is using hardware offload.
- Upload-side hardware QoS on the WAN path.

## Needs Testing

- 10G hardware offload.
- IPv6 hardware offload.

## Future Work

- WiFi offload.
- Download-side bufferbloat control or CAKE/SQM-equivalent hardware QoS.
- LuCI control panel for hardware acceleration.

## Building

This fork builds through the normal OpenWrt workflow.

For host prerequisites and general OpenWrt build-system usage, see the
official OpenWrt developer guides:

- https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem
- https://openwrt.org/docs/guide-developer/toolchain/use-buildsystem

This repository does not ship a checked-in `.config`. Install the normal
OpenWrt host build dependencies first, then use the commands below.

Run this once for a fresh checkout, and again after feed changes:

```sh
./scripts/feeds update -a
./scripts/feeds install -a
```

Run this whenever you want to create or refresh the validated Mono Gateway
build config:

```sh
cp config/mono_gateway-dk.seed .config
make defconfig
```

Run this every time you want to build the image:

```sh
make -j"$(nproc)"
```

To start from a clean OpenWrt build tree and produce both scoped CodeQL SARIF
files and a complete firmware image, run the scoped CodeQL helper:

```sh
cd /home/cvandesande/mono-openwrt-project/openwrt

make clean
make download -j"$(nproc)"

scripts/codeql-openwrt-scoped.sh \
  --with-kernel-patches \
  --download-queries \
  --jobs "$(nproc)"

make -j"$(nproc)" world
```

The helper uses `~/codeql/codeql` by default. It cleans and traces only the
Mono-owned ASK integration scope:

- `package/kernel/ask-cdx`
- `package/kernel/ask-fci`
- `package/libs/libfci`
- `package/network/ask-cmm`
- the ASK kernel interaction patches under
  `target/linux/layerscape/patches-6.12/720-724`, when
  `--with-kernel-patches` is used

The SARIF files are written in the OpenWrt tree:

```text
codeql-results/kernel-ask-patches.full.sarif
codeql-results/kernel-ask-patches.sarif
codeql-results/ask-cdx-openwrt.sarif
codeql-results/ask-fci-openwrt.sarif
codeql-results/libfci-openwrt.sarif
codeql-results/ask-cmm-openwrt.sarif
```

Treat those reports as static analysis for the scoped ASK integration surface,
not as a whole-OpenWrt or whole-firmware security review. Build success and
SARIF generation also do not prove hardware offload behavior; runtime hardware
validation is still required for hardware claims.

That seed is intentionally small. The `mono_gateway-dk` device profile pulls
the board-support packages for LEDs, thermal/hwmon, SFP, and fan control, and
the seed adds the hardware acceleration, PPPoE, and LuCI selections needed for
the current delivered stack.

If you want to create or customize a config interactively instead, use the
normal OpenWrt flow:

- run `make menuconfig`
- select:
  - `Target System` -> `NXP Layerscape`
  - `Subtarget` -> `ARMv8 64b`
  - `Target Profile` -> `Mono Gateway DK`
- save and exit
- run `make defconfig`

If you already have a suitable `.config`, place it in the repo root and run
`make defconfig` before building.

## Documentation

More detail lives in:

- [docs/README.md](docs/README.md)
- [docs/01-platform-and-lab-state.md](docs/01-platform-and-lab-state.md)
- [docs/02-fast-path-architecture.md](docs/02-fast-path-architecture.md)
- [docs/03-fman-backend-design.md](docs/03-fman-backend-design.md)
- [docs/04-developer-tooling.md](docs/04-developer-tooling.md)
- [docs/codeql-scoped-analysis.md](docs/codeql-scoped-analysis.md)
- [docs/nightly-next-workflow.md](docs/nightly-next-workflow.md)

Those docs cover:

- current platform and lab state
- architecture and ownership boundaries
- user-facing control boundary
- stage status
- observability and proof model
- remaining work
- local `clangd` and `compile_commands.json` developer workflow
- scoped CodeQL SARIF workflow for ASK integration surfaces
- nightly tracking-branch automation, smoke testing, and manual promotion
