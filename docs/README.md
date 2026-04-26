# Documentation Index

This documentation set describes the current Mono OpenWrt fork as it exists
today:

- a boxed NXP ASK/FMAM/DPAA hardware-acceleration port for Mono Gateway
- an OpenWrt-first integration repo with pinned vendor package sources
- a staged validation path from kernel bring-up to true hardware offload
- the bounded upload-side CEETM hardware egress-shaping proof on the current
  WAN path

Read in this order:

1. [01-platform-and-lab-state.md](01-platform-and-lab-state.md)
   Current validation status and active priorities.

2. [02-fast-path-architecture.md](02-fast-path-architecture.md)
   The fork architecture, ownership boundaries, control-plane split, and
   user-facing control boundary.

3. [03-fman-backend-design.md](03-fman-backend-design.md)
   The detailed porting design, delivered stages, observability model, and
   next work.

These docs intentionally describe the current supported design only.
