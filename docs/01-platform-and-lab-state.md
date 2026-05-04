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
