# ASK Kernel Patch Correctness Backlog

Status: open backlog from a patch-correctness review of `mono-ask`
(2026-07-10, HEAD `77c843c20a`). Scope was the Mono-owned kernel patch
series and its userspace ABI counterparts — not a full code review.

Goal restated: keep hardware acceleration working while keeping the
Mono patch delta as narrow as possible so kernel/OpenWrt progression
stays easy to follow.

## What was reviewed (do not re-audit)

Mono-owned patches in `target/linux/layerscape/patches-6.18/`:

- `306`/`307` — Mono Gateway DK DTS Makefile hooks. Fine.
- `720` — SDK DPAA/FMAN/QBMan build entry points. Fine (vendor SDK
  bodies live in `files/`, which is the right rebase-friendly shape).
- `721` — conntrack fast-path metadata ABI (`comcerto_fp_info`,
  `IPS_PERMANENT`, `CTA_LAYERSCAPE_FP_*`). One dead-code item below.
- `722` — `skb->layerscape_underlying_iif` plumbing. One consistency
  question below.
- `723` — permanent-conntrack pin/unpin via ctnetlink. One sharp edge
  below.
- `724` — xfrm/NLKEY IPsec SA-handle plumbing (the big one). Items 1,
  2, 6, 9 below.
- `725` — SELinux 4RD nlmsg mapping. Permanent no-op, item 5.
- `950` — swphy 10G fixed-link. Load-bearing but undocumented, item 8.
- Local edits folded into upstream-shared `701`/`703` (PFE cdev
  hardening). Item 7.
- `package/libs/libnetfilter-conntrack/patches/100`+`101` — reviewed,
  correct, and `101` is well documented. No action.

Checked and found OK (skip re-deriving): `nf_conn.fp_info` lands inside
the zeroed init region; the IPv4/IPv6 postrouting hook priorities are
equivalent (`INT_MAX - 1` both); the double-`ntohl` id comparison in
`ctnetlink_change_permanent` is sparse-dirty but functionally correct;
NLKEY multicast reads require `CAP_NET_ADMIN` (no key leak); the
`ipsec_nlkey_send` state machine cannot loop forever; the seed config
enables `INET_IPSEC_OFFLOAD`, `INET6_IPSEC_OFFLOAD`,
`FSL_SDK_DPAA_ETH`, `FSL_SDK_FMAN` (`armv8_64b/config-6.18`).

## Fix items, in priority order

### 1. `spin_lock` → `spin_lock_bh` in NLKEY receive path (bug, fix first)

Patch `724`, `net/key/af_key.c`, function `ipsec_nlkey_rcv()`. All three
handlers (`NLKEY_SA_NOTIFY`, `NLKEY_SA_INFO_UPDATE`,
`NLKEY_SA_SET_OFFLOAD`) take `spin_lock(&x->lock)` in process context
(netlink input). The same lock is taken from softirq context by
`xfrm_input()` (NAPI) and the SA hrtimer (`HRTIMER_MODE_*_SOFT`), so a
softirq preempting the holder on the same CPU deadlocks. Every other
process-context taker in the kernel uses `spin_lock_bh`.

Fix: replace the three `spin_lock`/`spin_unlock` pairs with
`spin_lock_bh`/`spin_unlock_bh` inside the patch. Low risk, no ABI
change.

### 2. u16 SA handle allocator can hand out duplicates (bug)

Patch `724`, `net/xfrm/xfrm_state.c`. In `xfrm_state_alloc()`:
`do { x->handle = xfrm_state_handle++; } while (x->handle == 0);` where
`xfrm_state_handle` is a global non-atomic `u16`.

Two defects: (a) concurrent allocs race the increment; (b) it wraps at
65,536 allocations with no check against live states — reachable on a
long-uptime box that rekeys. A duplicate handle makes
`xfrm_state_lookup_byhandle()` and the hardware sagd ambiguous, so SEC
can be programmed/queried against the wrong SA.

Fix while keeping the vendor u16 ABI: make the counter atomic
(`atomic_t` + `atomic_inc_return` truncated to u16, skip 0), and at
insert time (`xfrm_state_insert_byhandle()`) skip/re-roll candidates
already present in the `byh` hash. Keep it simple; a walk of one hash
bucket under `xfrm_state_lock` is enough.

### 3. ctnetlink pin/unpin intercept swallows unrelated updates (sharp edge) — RESOLVED (fixed twice)

First pass gated on the status delta *and* rejected the message outright
if `CTA_TIMEOUT`, `CTA_MARK`, `CTA_PROTOINFO`, etc. were present — on
the assumption CMM's pin/unpin messages carry only `CTA_STATUS`/`CTA_ID`.
An independent review caught that this was wrong: `ask-cmm`'s
`cmmCtSetPermanent()` clones the *entire* last-received conntrack event
(`nfct_copy(..., NFCT_CP_OVERRIDE)`) before sending the pin/unpin
update, and the kernel's own `ctnetlink_conntrack_event()` always dumps
`CTA_TIMEOUT` for NEW/UPDATE events (`ctnetlink_dump_timeout(skb, ct,
false)`), so real CMM messages routinely carry `CTA_TIMEOUT` (and
`CTA_PROTOINFO` for TCP). The blacklist rejected every real CMM
pin/unpin message, sending it down the `ctnetlink_change_conntrack()`
fallback — whose status-change path only ever *sets* bits
(`__nf_ct_change_status(ct, status, 0)`, `off` mask hardcoded to `0`),
so unpin silently stopped working entirely while pin appeared to keep
working via the fallback. Removed the attribute blacklist; the
status-delta check (`(status ^ ct->status) & ~IPS_PERMANENT`) is
sufficient on its own to reject genuine third-party updates, since any
real update changing other status bits fails that comparison.

Patch `723`, `net/netfilter/nf_conntrack_netlink.c`,
`ctnetlink_change_permanent()` called from `ctnetlink_new_conntrack()`.
Any non-EXCL update carrying both `CTA_STATUS` and `CTA_ID` is consumed
as a pin/unpin:

- if it matches, the rest of the message (timeout, mark, …) is
  silently ignored and no conntrack event is emitted;
- an update whose status merely lacks `IPS_PERMANENT` while the entry
  is pinned unpins it — a conntrackd-style tool doing status updates
  by id could unpin hardware-resident flows.

Fix: only intercept when the message is unambiguously the CMM dialect —
e.g. require that the status delta is exactly the `IPS_PERMANENT` bit
(compare requested status vs `ct->status` masked to `IPS_PERMANENT`),
fall through to `ctnetlink_change_conntrack()` otherwise, and call
`nf_conntrack_eventmask_report()` (or at least
`nf_conntrack_event_cache`) on pin-state change so it is observable.
Coordinate with `ask-cmm` before changing accepted message shapes —
CMM is the only intended sender.

### 4. Dead/misleading VLAN fallback in fp metadata capture (cleanup)

Patch `721`, `net/netfilter/nf_conntrack_core.c`,
`nf_ct_update_layerscape_fp()`. `underlying_iif` already falls back to
`dev->ifindex`, so in the `is_vlan_dev(dev)` branch the ternary
`underlying_iif ? underlying_iif : (real_dev ? real_dev->ifindex : ...)`
can never reach the `real_dev` arm. Behaviour is fine today because
722's `__netif_receive_skb_core` hook fills the skb field for every
received packet, but the code implies an intent it doesn't implement.
Fix: delete the dead arm (keep behaviour identical), or if the intent
really was "physical dev for VLAN ingress", restructure so
`real_dev->ifindex` is used when `skb->layerscape_underlying_iif == 0`.
Resolve together with item 10.

### 5. Patch 725 is a permanent no-op (narrowness) — RESOLVED, dropped

`725-selinux-map-ask-4rd-rtnetlink-messages.patch` guarded on
`CONFIG_CPE_4RD_TUNNEL`, which no Kconfig anywhere in the tree defines
(verified: only the patch itself and a comment in
`package/network/ask-cmm/Makefile` mentioned it; the cmm option only sets
userspace `-DCMM_4RD_SUPPORT`). The SELinux mapping could never compile
in.

`docs/02-fast-path-architecture.md`'s "4RD Compatibility Boundary"
section documented this as an intentional forward stub, which raised
the question of whether dropping was still right. User confirmed:
drop it. The patch has been removed, and the doc section's paragraph
about the SELinux mapping being pre-emptively gated has been updated to
say there is currently no mapping and that one should be added
alongside the future kernel-side 4RD port, gated on whatever Kconfig
symbol that port actually introduces.

### 6. Missing Kconfig dependency for the SEC submit symbol (robustness)

Patch `724` adds a call in built-in `net/xfrm/xfrm_input.c` to
`dpaa_submit_inb_pkt_to_SEC()`, defined in
`target/linux/layerscape/files/.../sdk_dpaa/dpaa_eth_sg.c`. With
`INET_IPSEC_OFFLOAD=y` and `FSL_SDK_DPAA_ETH=n` the vmlinux link fails.
Fix: add `depends on FSL_SDK_DPAA_ETH` to both `INET_IPSEC_OFFLOAD`
(`net/ipv4/Kconfig` hunk) and `INET6_IPSEC_OFFLOAD` (`net/ipv6/Kconfig`
hunk) in patch 724.

### 7. Un-fold PFE cdev hardening from upstream patch 701 (maintainability)

The cdev read/ioctl hardening (buffer-size check, `put_user`,
`__user` annotations, eventfd local) was edited directly into
upstream-shared `701-staging-add-fsl_ppfe-driver.patch`, with
compensating hunk removals in `703-...`. Both files now differ from
upstream OpenWrt, so every upstream refresh of the (huge) 701 conflicts
and the Mono delta is invisible.

Fix: restore `701` and `703` to byte-exact upstream copies
(`git show upstream/main:target/linux/layerscape/patches-6.18/<name>`),
and move the hardening into a new
`704-staging-fsl_ppfe-harden-cdev-user-copies.patch` applied on top.
Verify the series still applies (`make target/linux/{clean,prepare}`)
and the resulting sources are identical to today's
(diff the prepared `drivers/staging/fsl_ppfe/pfe_cdev.c` before/after).

### 8. Give patch 950 a proper header (documentation)

`950-swphy-10g-fixed-link.patch` is the only Mono patch with no
subject/rationale. Content: adds `case 10000:` mapping to
`SWMII_SPEED_1000` in `drivers/net/phy/swphy.c`. It is load-bearing —
without it `fixed_phy` registration fails for 10G fixed-link (used by
the SFP+ ports fixed in `a893de4e22`). Side effect worth recording in
the header: the emulated BMSR makes ethtool report 1000 Mb/s on a 10G
link (cosmetic; datapath is unaffected).

### 9. Deduplicate the ~100-line MSS clamp helper (maintainability)

Patch `724` duplicates `xfrm_ipsec_native_mss_clamp()` verbatim in
`net/xfrm/xfrm_input.c` and `net/xfrm/xfrm_output.c` (only the MTU
helper feeding it differs). Hoist the shared body into
`net/xfrm/xfrm_inout.h` (already included by both) taking `mtu` as a
parameter; keep the two thin MTU wrappers where they are. Halves the
hairiest refresh surface in 724.

### 10. Decide the intended identity for VLAN-over-bridge ingress (design question)

Patch `722`: every site sets `skb->layerscape_underlying_iif` only if
zero, except the `net/bridge/br_input.c` hunk which overwrites
unconditionally with the bridge-port ifindex. For a VLAN device as a
bridge port (e.g. `eth0.100` in `br-wan`): the `net/core/dev.c` hook
records physical `eth0` first, then br_input replaces it with
`eth0.100`. If CMM needs the physical port, the bridge hunk loses it;
if it needs the bridge-port device, the patch description ("physical
ingress interface") is wrong. Decide with reference to how
`ask-cmm`/`ask-cdx` consume `CTA_COMCERTO_FP_UNDERLYING_IIF`, then make
the sites consistent and fix the patch description. Ties into item 4.

### 11. Add ABI drift tripwires (insurance for future kernel bumps)

Two exposed integer ABIs renumber silently if upstream appends to their
enums — exactly the failure documented after the fact in
`package/libs/libnetfilter-conntrack/patches/101-fix-cta-layerscape-fp-attr-abi-drift.patch`
and in memory note "ASK bundled uapi header ABI drift".

Current pinned values (kernel 6.18.37 with patch 721 applied):

- `CTA_LAYERSCAPE_FP_ORIG = 28`, `CTA_LAYERSCAPE_FP_REPLY = 29`
  (appended after `CTA_TIMESTAMP_EVENT = 27`; `__CTA_MAX = 30`)
- `IPS_PERMANENT_BIT = 16` (`__IPS_MAX_BIT = 17`)
- `NETLINK_KEY = 32` (`MAX_LINKS` bumped 32 → 33)

Fix: in patch 721 add
`static_assert(CTA_LAYERSCAPE_FP_ORIG == 28);` (e.g. in the
`nf_conntrack_netlink.c` hunk) and
`static_assert(IPS_PERMANENT_BIT == 16);`, and add matching
compile-time asserts in ask-cmm's bundled header copy. On the next
kernel bump these fail the build loudly instead of misfiling netlink
attributes at runtime; whoever hits the assert re-pins the values *and*
updates the libnetfilter-conntrack/cmm bundled headers together.

## Design facts to record in docs (not bugs)

- Patch `724` makes offloaded ESP wrapper packets skip `LOCAL_OUT` and
  `POST_ROUTING` netfilter entirely (`ip_output.c` / `ip6_output.c` /
  `output_core.c` hunks). The inner packet still traverses
  FORWARD/POSTROUTING before transformation, so firewall policy on user
  traffic holds — but rules matching the ESP packets themselves never
  fire for offloaded SAs. Should be stated in
  `docs/02-fast-path-architecture.md` (AGENTS.md: "Linux authoritative
  for firewall").
- `LAYERSCAPE_PERMANENT_TIMEOUT = 1000` (patch 723) is a display-only
  value in jiffies units — userspace sees `1000/HZ` seconds. Pinned
  entries survive until unpinned; if CMM dies without unpinning, they
  persist until reboot. Known tradeoff.

## Working notes for a fresh session

- Branch: `mono-ask`. Patches:
  `target/linux/layerscape/patches-6.18/`. Upstream comparison baseline:
  `git fetch upstream && git diff upstream/main -- target/linux/layerscape/`.
- Items 1, 6, 8, 9, 11 are pure patch edits: edit the `.patch` file,
  then validate with
  `make target/linux/clean target/linux/prepare` followed by
  `make -j"$(nproc)" target/linux/compile` (seed:
  `cp config/mono_gateway-dk.seed .config && make defconfig`).
- Items 2 and 3 change runtime behaviour of the hw-accel control plane:
  per AGENTS.md, do not claim offload correctness from build success —
  router-side validation (CMM connection state, tuple-level hw stats)
  is required before calling them done.
- Item 7 must produce a zero source-level diff of prepared kernel
  sources; verify mechanically.
- Suggested commit granularity: one commit per item, patch-refresh
  style subjects like the existing history
  (`layerscape: ...`, `ask-cmm: ...`).
