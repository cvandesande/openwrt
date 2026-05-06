# Platform And Lab State

## Purpose

This file records the current Mono Gateway platform state and the current
validation status of the hardware-acceleration work.

For repository ownership, package-source layout, and architecture boundaries,
see [02-fast-path-architecture.md](02-fast-path-architecture.md). This file is
only the current status snapshot.

## Current Stage Status

- Stage 1: completed for the vendor kernel dataplane stack on the
  validated 1G topology.
- Stage 2: completed for the ASK runtime-state and control-path foundation on
  the accepted wired-routed scope.
- Stage 3: completed for the first true hardware-offload proof on the
  preferred routed WAN class.
- Stage 4: intentionally deferred until after soak and validation work. When
  implemented, it should add the dedicated NXP hardware-control boundary
  described in [02-fast-path-architecture.md](02-fast-path-architecture.md).
- Stage 5: completed for reply-half ownership and the direct-routed production
  path.
- Stage 6: the current active milestone, focused on soak and repeatability,
  reboot/reconnect/reload behavior, cleanup, rebase hygiene, and final
  operator readiness.

## Runtime FMAN Microcode

Runtime check on May 5, 2026, against the lab router showed the kernel using
FMAN controller code `210.10.1`:

```text
FM_Config(3425) FMan-Controller code (ver 210.10.1) (0xd20a01)
```

The live device tree also contains an embedded
`/soc/fman@1a00000/fman-firmware` node whose `fsl,firmware` property reports
`Microcode version 210.10.1 for LS1043 r1.0`. That satisfies the ASK package
number requirement used by the `mt-6.12.y` CDX microcode guard.

The OpenWrt rootfs currently also contains `/boot/fman-ucode.bin`, but that file
reports `106.4.18`. Current evidence points to Linux using the bootloader-provided
device-tree firmware, not the `/boot` copy. Treat the `/boot` file as misleading
until its fallback role is proven.

## Current Audit And Maintenance Fixes

The May 6, 2026 image includes the first-pass ASK security and reliability audit
fixes, limited to owned vendor repositories and the 700-series OpenWrt ASK
integration patches:

| Fix area | Delivered as | Runtime or validation check |
| --- | --- | --- |
| ASK NLKEY receive-path hardening | OpenWrt 700-series XFRM patch, revision `r34318-64b2feacfa` | Flashed router reports `OpenWrt SNAPSHOT r34318-64b2feacfa`. |
| PFE cdev and ioctl hardening | OpenWrt 700-series PFE patches | Target kernel compile passed; focused `pfe_cdev.o` compile passed. The lab router did not expose a PPFE runtime module or cdev. |
| CDX SAGD lookup, XFRM cleanup, allocation flags, and procfs pointer formatting | `kmod-ask-cdx-6.12.85.5.03.1-r48` | Installed on the lab router; `cdx` module loaded; installed module contains `contexta\t%pK` and not the stale raw `contexta\t%llx` or `proc_entry %px` strings. |
| CMM IPC sizing and multicast cleanup | `ask-cmm-17.03.1-r23` | Installed on the lab router; `/usr/sbin/cmm` running. |
| libFCI netlink response validation | `libfci-9.00.12-r5` | Installed on the lab router. |
| FMC libxml2 2.12+ compatibility guards | `fmc-6.12.49-r2` with `libxml2-16-2.15.1-r1` | Installed on the lab router; `fmc --help` runs. |

These checks confirm the fixed packages and binaries are present on the flashed
router. Follow-up traffic tests passed after flashing this build. Use
hardware-counter evidence separately when making hardware-offload residency
claims.

## IPsec Status

The first IPv4 tunnel-mode IPsec SEC-offload baseline is validated on the
current lab tunnel.

Validated state on May 3, 2026:

- CMM starts cleanly with the IPsec-enabled package and no active startup
  crash.
- StrongSwan establishes the IPv4 tunnel-mode child SA between the local and
  remote protected subnets.
- CMM `query sa` reports inbound and outbound hardware SAs with real MTU
  values, not the previous `65535` route-MTU failure.
- CMM connection state can show inner tunnel flows carrying inbound and
  outbound IPsec SA handles.
- CMM IPsec statistics, QM/SEC rate statistics, and DPAA ethtool IPsec
  counters move during real tunnel traffic.
- Linux XFRM software state counters stay at zero for the validated hardware
  path.
- Remote-side StrongSwan counters advance consistently with the OpenWrt-side
  hardware-counter evidence.
- ICMP, SSH login, and bulk TCP smoke tests over the tunnel pass after the
  diagnostic log cleanup and CMM route-MTU fallback.
- Bulk TCP has reached the available uplink range in the current lab. Earlier
  lower readings were a measurement/interpretation error or came from broken
  packet-size and buffer-ownership paths, not the current validated baseline.
- A later bulk-TCP stability fix corrected DPAA TX buffer ownership for
  skb-less IPsec compat frames. Successful pool-backed TX buffers are released
  by FMan; the DPAA TX-confirm cleanup path must not manually release those
  buffers a second time. Before this fix, bulk TCP could show deterministic ESP
  sequence holes, very low throughput, and hard router resets with no useful
  kernel log. After the fix, CMM IPsec counters, remote ESP capture, and
  SEC/BMan/QMan health checks showed sustained hardware traffic without the
  previous corruption signature.

Current conclusion:

- hardware-assisted IPv4 tunnel-mode IPsec crypto is working for the current
  lab path
- SA-handle metadata is present and useful for proof collection
- this proves IPsec SEC crypto offload for the current lab tunnel; it does not
  claim every broader vendor CPE/FPP IPsec behavior
- IPv6 IPsec support is compiled and plumbed, but IPv6 hardware success is not
  validated
- the current SEC-offload path remains the baseline and fallback while any
  additional vendor CPE/FPP behavior is audited separately
- the first lost packet after tunnel setup can still occur during warmup; it is
  not by itself a hardware-offload failure, but long-running bulk TCP should
  keep SEC failure counters at zero and avoid BMan/QMan depletion or resets
- the latest CPU-path observation is much better than the earlier diagnostic
  builds, but additional per-flow FPP behavior still needs hardware evidence
  before it can be claimed

## Hardware QoS Status

The first upload-side CEETM hardware egress-shaping proof is validated, but
production-ready hardware QoS controls remain future work.

Validated state on April 26, 2026:

- the CEETM/QM query and set surfaces are compiled in
- the Mono kernel has the CEETM-capable TX owner path enabled
- `eth0` can be assigned to CEETM channel 1 and switched to egress QoS mode
- `query qm interface eth0` reports active CEETM egress state instead of
  `Interface eth0 qos disabled`
- a CEETM port shaper can be set and queried back honestly
- a host-side upload through `pppoe-wan` was capped below the higher-rate
  comparison run by the hardware path

Current conclusion:

- do not treat hardware QoS as a small config toggle
- do not treat it as a generic OpenWrt SQM/CAKE equivalent
- treat the current proof as upload-side WAN egress shaping only
- keep Stage 4 user-facing controls deferred
- keep Stage 6 soak/repeatability as active future work

This work should remain an NXP hardware-control feature and should not change
OpenWrt/Linux ownership of routing, firewall, conntrack, or software queueing
policy.

For the detailed architecture and proof model, see
[02-fast-path-architecture.md](02-fast-path-architecture.md) and
[03-fman-backend-design.md](03-fman-backend-design.md).
