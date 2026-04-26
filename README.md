# Mono OpenWrt Fork

This repository is a Mono-specific OpenWrt fork for LS1046A-based Mono Gateway
systems.

Its main purpose is to integrate NXP ASK/FMAM/DPAA hardware acceleration into
OpenWrt while keeping:

- OpenWrt and Linux authoritative for routing, firewall, conntrack, and
  service control
- the vendor acceleration stack boxed behind an explicit dataplane boundary
- the integration layer maintainable and rebase-friendly

## Acknowledgment

Special thanks to the [Mono team](https://mono.si/), and especially to team
leader Tomaž Zaman, for building an exceptional router platform and for their
commitment to open design.

Mono updates and related videos are also available on the
[Tomaž Zaman YouTube channel](https://www.youtube.com/@tomazzaman).

## What This Fork Delivers

Completed:

- [x] working NXP FMAN/DPAA hardware offload on Mono Gateway for the
  currently validated 1G routed WAN classes
- [x] ASK integration for route, VLAN, PPPoE, and conntrack programming,
  with installed versus fallback state visible through `cmm`
- [x] first true hardware-offload proof on a validated preferred 1G routed
  WAN path
- [x] direct-routed production-path and reply-half proof on a validated 1G
  production path
- [x] first upload-side CEETM hardware egress-shaping proof on the current
  validated WAN path

Remaining work:

- [ ] 10G physical validation on the remaining 10G ports
- [ ] Stage 4 user-facing OpenWrt integration
- [ ] WiFi offload
- [ ] IPsec offload
- [ ] validated IPv6 offload
- [ ] production-ready hardware QoS controls
- [ ] Stage 6 soak and repeatability

The current validated scope is 1G-only, with upload-side CEETM egress shaping
validated only on the current WAN path. This is not a CAKE/SQM-equivalent or
download-side bufferbloat-control claim.

## How This Fork Differs From Vendor Firmware

This fork does not use the vendor firmware tree as the active build system.

Instead it uses:

- [cvandesande/openwrt](https://github.com/cvandesande/openwrt) as the
  integration and build repo
- [we-are-mono/OpenWRT-ASK](https://github.com/we-are-mono/OpenWRT-ASK) as
  the vendor reference firmware/source tree
- dedicated pinned source repos for large ASK package sources
- a narrow local kernel patch layer for target integration

At a high level, the vendor firmware and this fork solve the same problem in
different ways:

- `OpenWRT-ASK` carries most of the acceleration stack as two large kernel
  patch imports. Its main kernel drops, `950-nxp-lsdk.patch` and
  `951-nxp-ask.patch`, total 222,509 lines and touch 480 unique files.
- This fork keeps OpenWrt as the integration repo and limits the ASK-specific
  kernel integration layer to 456 lines across 15 files in patches
  `720` through `723`
  ([view the patch series](https://github.com/cvandesande/openwrt/tree/mono-ask/target/linux/layerscape/patches-6.12)).
  The larger ASK package sources live in pinned external repos and are fetched
  through normal OpenWrt package recipes.

From an operator point of view, this fork is not just "vendor firmware with a
different patch stack." It is also restoring normal OpenWrt lifecycle behavior
on Mono Gateway, including image handling and upgrade flows that fit standard
OpenWrt operation better than the vendor firmware.

The goal of that design is not to remove vendor code. The goal is to make the
integration easier to understand, easier to review, and easier to keep aligned
with upstream OpenWrt over time.

In practice, that means:

- normal OpenWrt `sysupgrade` support
- normal OpenWrt package and image build workflow
- pinned fetched-source package integration for major ASK components instead of
  keeping all vendor package sources directly in the integration repo
- a narrower and easier-to-review local kernel integration layer
- a clearer separation between vendor source ownership and OpenWrt integration
  ownership
- a cleaner separation between OpenWrt/Linux policy ownership and NXP hardware
  acceleration ownership
- explicit hardware proof and observability requirements for offload claims,
  rather than treating installed state alone as success
- proven 1G hardware-offload on validated preferred and production routed WAN
  classes
- proven upload-side CEETM hardware egress shaping on the current WAN path

## Building

This fork builds through the normal OpenWrt workflow.

There is no separate manual vendor-source import step for the ASK packages.
The larger vendor-owned package sources are fetched automatically from pinned
source revisions by the package recipes during the normal OpenWrt
download/prepare flow.

For host prerequisites and general OpenWrt build-system usage, see the
official OpenWrt developer guides:

- https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem
- https://openwrt.org/docs/guide-developer/toolchain/use-buildsystem

On a fresh checkout, the expected build flow is:

1. Install the normal OpenWrt host build dependencies.
2. Run `./scripts/feeds update -a`
3. Run `./scripts/feeds install -a`
4. Create `.config`
5. Run `make -j"$(nproc)"`

This repository does not ship a checked-in `.config`. For the current
validated Mono Gateway image, the recommended non-interactive workflow is:

```sh
cp config/mono_gateway-dk.seed .config
make defconfig
make -j"$(nproc)"
```

That seed is intentionally small. The `mono_gateway-dk` device profile pulls
the board-support packages for LEDs, thermal/hwmon, SFP, and fan control, and
the seed adds the explicit ASK, PPPoE, and LuCI selections needed for the
current delivered stack.

For smoother parallel builds, you may also want to prefetch sources first:

```sh
make download -j"$(nproc)"
```

This is a normal OpenWrt download step, not a separate vendor-source import
step.

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
- [docs/nightly-next-workflow.md](docs/nightly-next-workflow.md)

Those docs cover:

- current platform and lab state
- architecture and ownership boundaries
- user-facing control boundary
- stage status
- observability and proof model
- remaining work
- nightly tracking-branch automation, smoke testing, and manual promotion
