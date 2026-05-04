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
- [docs/nightly-next-workflow.md](docs/nightly-next-workflow.md)

Those docs cover:

- current platform and lab state
- architecture and ownership boundaries
- user-facing control boundary
- stage status
- observability and proof model
- remaining work
- local `clangd` and `compile_commands.json` developer workflow
  ([docs/04-developer-tooling.md](docs/04-developer-tooling.md))
- nightly tracking-branch automation, smoke testing, and manual promotion

SELinux support is included for the Mono Gateway DK image, with policy kept in
the OpenWrt package layer and shaped by observed access rather than broad
allowances. Images default to permissive mode during policy validation, with
enforcing-mode testing available.

## Support Information

For a list of supported devices see the [OpenWrt Hardware Database](https://openwrt.org/supported_devices)

### Documentation

* [Quick Start Guide](https://openwrt.org/docs/guide-quick-start/start)
* [User Guide](https://openwrt.org/docs/guide-user/start)
* [Developer Documentation](https://openwrt.org/docs/guide-developer/start)
* [Technical Reference](https://openwrt.org/docs/techref/start)

### Support Community

* [Forum](https://forum.openwrt.org): For usage, projects, discussions and hardware advise.
* [Support Chat](https://webchat.oftc.net/#openwrt): Channel `#openwrt` on **oftc.net**.

### Developer Community

* [Bug Reports](https://bugs.openwrt.org): Report bugs in OpenWrt
* [Dev Mailing List](https://lists.openwrt.org/mailman/listinfo/openwrt-devel): Send patches
* [Dev Chat](https://webchat.oftc.net/#openwrt-devel): Channel `#openwrt-devel` on **oftc.net**.

## License

OpenWrt is licensed under GPL-2.0
