# Platform And Lab State

## Purpose

This file records the current Mono Gateway platform state and the current
validation status of the hardware-acceleration work.

For repository ownership, package-source layout, and architecture boundaries,
see [02-fast-path-architecture.md](02-fast-path-architecture.md). This file is
only the current status snapshot.

## Current Stage Status

- Stage 1: completed for the boxed vendor kernel dataplane stack on the
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

## Hardware QoS Status

The first upload-side CEETM hardware egress-shaping proof is validated, but
production-ready hardware QoS controls remain future work.

Validated state on April 26, 2026:

- the CEETM/QM query and set surfaces are compiled in
- the Mono kernel has the narrow CEETM-capable TX owner path enabled
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

This work should remain boxed as an NXP hardware-control feature and should
not change OpenWrt/Linux ownership of routing, firewall, conntrack, or
software queueing policy.

For the detailed architecture and proof model, see
[02-fast-path-architecture.md](02-fast-path-architecture.md) and
[03-fman-backend-design.md](03-fman-backend-design.md).
