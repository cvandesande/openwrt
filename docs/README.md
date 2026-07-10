# Documentation Index

This documentation set describes the current Mono OpenWrt fork as it exists
today:

- an NXP ASK/FMAM/DPAA hardware-acceleration port for Mono Gateway
- an OpenWrt-first integration repo with pinned vendor package sources
- a staged validation path from kernel bring-up to true hardware offload
- the upload-side CEETM hardware egress-shaping proof on the current
  WAN path
- the current IPv4 tunnel-mode IPsec SEC-offload baseline
- the current SELinux bring-up status, with permissive mode as the default
  while policy coverage is still being validated

Read in this order:

1. [01-platform-and-lab-state.md](01-platform-and-lab-state.md)
   Current validation status and active priorities.

2. [02-fast-path-architecture.md](02-fast-path-architecture.md)
   The fork architecture, ownership boundaries, control-plane split, and
   user-facing control boundary.

3. [03-fman-backend-design.md](03-fman-backend-design.md)
   The detailed porting design, delivered stages, observability model, and
   next work.

Optional developer tooling:

- [04-developer-tooling.md](04-developer-tooling.md)
  Local `clangd` and `compile_commands.json` workflow for navigating the
  kernel and ASK package C code, plus notes on building this fork on NixOS.

- [codeql-scoped-analysis.md](codeql-scoped-analysis.md)
  Scoped CodeQL database and SARIF workflow for ASK package integrations and
  the optional ASK kernel patch surface.

These docs intentionally describe the current supported design only.
