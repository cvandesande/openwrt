# Fast-Path Architecture

## Purpose

This file describes the active architecture of the Mono OpenWrt fork.

The key architectural choice is:

- use a boxed NXP ASK/FMAM/DPAA acceleration stack for the dataplane
- keep OpenWrt and Linux authoritative for system policy and service control

This is not a generic Linux flowtable extension. It is a separate hardware
acceleration plane integrated into OpenWrt with explicit boundaries.

## Architecture Summary

### OpenWrt / Linux Control Plane

OpenWrt and Linux remain authoritative for:

- routing
- firewall policy
- conntrack state
- PPPoE and VLAN control plane
- package and service lifecycle
- user-facing configuration

### NXP Acceleration Plane

The active hardware-acceleration plane is built from:

- `ask-cmm`
- `ask-fci`
- `libfci`
- `ask-cdx`
- `sdk_dpaa`
- `sdk_fman`
- vendor wrapper/bootstrap ownership for FMAN, PCD, and queue resources

These components own fast-path programming and resident hardware forwarding for
the supported classes.

## Boxed Design

“Boxed” in this fork means:

- no mixed mainline/vendor ownership on the active dataplane nodes
- vendor acceleration logic stays inside a dedicated dataplane/control stack
- OpenWrt integration is kept narrow and explicit
- vendor-specific controls are not presented as generic Linux networking APIs

This keeps the port understandable and reduces the maintenance cost compared
with carrying a broad vendor firmware diff inside the OpenWrt tree.

## Source Ownership Model

The fork uses three layers of ownership:

### 1. OpenWrt integration layer

[cvandesande/openwrt](https://github.com/cvandesande/openwrt) owns:

- target integration
- kernel patches
- DTS and config
- package recipes
- init scripts and config files
- local OpenWrt-specific patch queues where needed

### 2. Dedicated package source repos

Large vendor source trees are now fetched through normal OpenWrt package
recipes from pinned source revisions.

Current examples:

- [cvandesande/ask-cmm](https://github.com/cvandesande/ask-cmm)
- [cvandesande/ask-cdx](https://github.com/cvandesande/ask-cdx)
- shared [cvandesande/fci](https://github.com/cvandesande/fci) source for
  `ask-fci` and `libfci`

### 3. Vendor reference tree

[we-are-mono/OpenWRT-ASK](https://github.com/we-are-mono/OpenWRT-ASK)
remains the vendor reference tree for comparison, future ports, and
documentation, but it is not the active build tree.

## Normal OpenWrt Build Workflow

The dedicated package repos are integrated through normal OpenWrt packaging:

- package recipes fetch pinned source revisions
- OpenWrt unpacks them into `build_dir/`
- local integration files remain in `openwrt/package/...`
- package outputs are produced through normal OpenWrt package targets

That means the fork keeps reproducible builds without relying on ad-hoc source
copies, submodules, or developer-local working trees.

## User-Facing Boundary

The future user-facing control boundary should be:

- a dedicated NXP LuCI/UCI page for hardware controls
- separate from upstream OpenWrt SQM/CAKE controls
- separate from upstream firewall flow-offload toggles

The UI model should report:

- requested state
- actual state
- blocked or incompatible reason

It should not silently flip upstream software controls or hide software
fallback behind a generic “hardware offload” switch.

## Future Architecture Work

Future architecture work still includes:

- the Stage 4 NXP hardware-control boundary
- extending the validated scope beyond the current 1G proof paths
- WiFi offload
- IPsec offload
- validated IPv6 offload
- hardware QoS as a finished user-facing feature

## Why This Architecture Is Maintainable

This design is easier to maintain than a broad vendor firmware import because:

- the kernel integration layer is narrow and explicit
- vendor package sources are separated from the integration repo
- package recipes use pinned revisions
- OpenWrt-specific integration remains local and reviewable
- user-facing software ownership stays with OpenWrt instead of being absorbed
  into the vendor stack

For the current validation scope and stage status, see
[01-platform-and-lab-state.md](01-platform-and-lab-state.md). For the detailed
proof model and stage breakdown, see
[03-fman-backend-design.md](03-fman-backend-design.md).
