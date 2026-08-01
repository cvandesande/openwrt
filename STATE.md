# Current state

Deliberately short. If something here needs a paragraph, it belongs in `docs/`;
if it is a record of what happened, it belongs in `journal/`; if it is an open
question, it belongs in an issue.

## Production

The router's WAN runs PPPoE over the 10G port (`eth4`) at a true 10G copper
link, with hardware fast-path offload active, **IPsec offload active on the
IPsec OFFLINE port**, cmm crash-supervised under procd, RFC 4638 baby-jumbo MTU
proven end-to-end, QoS shaping UCI-persisted via `cmmqos`, and WireGuard
syncing cleanly at boot.

- Image `25.12.5` (`BUILD_ID r33051-f5dae5ece4`, kernel 6.12.94, 25.12 line),
  built and flashed 2026-08-01 from `mono-ask-25.12` `9ec05f6134`. Booted
  18:28 IST.
- `wan10g` = PPPoE on `eth4.10`, MAC-cloned, mtu 1508 parent+child, ppp 1500.
- `wan` (1G) stays `disabled=1` as a manual fallback — one active at a time.
- cmm r27 with `cmmqos`; **kmod-ask-cdx r55, ask-dpa-app r5** — the six-port
  config with the IPsec OH port, verified loaded by content.
- `kmod-phy-maxlinear` driving the three 1G PHYs; `wg0` on port 443, 5 peers.
- selinux-policy **r8** loaded; enforcing mode depends on the reboot state —
  see below.

**SELinux mode is permissive or enforcing depending on whether the box has
been rebooted since the flash.** `/etc/selinux/config` always says
`SELINUX=enforcing`; the running mode is what varies. Immediately after a
flash it comes up permissive, and a subsequent reboot brings it to enforcing.
So `sestatus` reporting `Current mode: permissive` against `Mode from config
file: enforcing` is expected on a freshly flashed box and is not a fault —
check the reboot state before treating it as one.

Observed permissive after the 2026-08-01 flash, with five AVC denials, both
kinds already known: `xtables.subj` -> `netif.data.file` (x3) and
`hotplug.call.subj` -> `mwan3.runtmp.file` (x2), the latter being the #32
survivor that unbuilt `selinux-policy-r9` addresses.

## Branches

- `mono-ask` — default branch; docs, journal, and this file live here.
- `mono-ask-25.12` — the release line that gets flashed; at `9ec05f6134`,
  which is what is currently on the router.
- `selinux-policy-r9` — in flight: the #32 survivor's fix
  (`read_file_files` → `manage_file_files`, PKG_RELEASE 8→9). Pushed, but
  **not built, not flashed, not ported to `mono-ask`**.

**Both branches** carry the #29 IPsec OH-port change: ask-cdx **r55** and
ask-dpa-app r5 re-adding portid 9. r53 raised the port ceiling 5→16 (derived
from `FMC_PORTS_PER_FMAN`) and fixed two OH-path bugs — a `==`→`&` bitmap test
and a missing bounds check. r54 added no functional change, only logging of
which bound rejected a config, because the first failure was silent.

**The r54 diagnostics found it.** The six-port boot on 2026-08-01 failed
because of `CDX_CTRL_MAX_TABLES_PER_FMAN`, not the distribution cap:

```
cdx_ioc_set_dpa_params::fman 0 rejected: index 0 (max 2),
  max_ports 6 (max 16), num_tables 72 (max 64), portinfo set, tbl_info set
```

The fmc model expands the PCD per port, so classifier tables scale with port
count. Five ports produced 60 and fit under the vendor's 64; the sixth made it
72. The 64 was sized for the same 5-port world as the old port ceiling — r53
raised one and left the other behind.

**r55 raises it to 1024, derived not chosen.** `num_tables` only bounds a
`kcalloc()` of a userspace-supplied count and sizes no array (verified by
grep). dpa_app sets it to `ccnode_count + htnode_count`, both indexing arrays
declared `[FMC_CC_NODES_NUM]` with `FMC_CC_NODES_NUM == 512`, so 1024 is the
tightest bound a working dpa_app cannot exceed. Sixteen ports at the observed
ratio is 192. r55 also bounds `td[tinfo->type]` in `get_tableInfo_by_portid()`,
which indexed a 12-entry array with a value `copy_from_user()`'d without
validation — the sibling lookup in `dpa_ipsec.c` already checked it.

**There is only one router.** #29's "bench only" cannot mean a spare board —
there isn't one. In practice bench means physically off production, with serial
attached, and every change on this path must be recoverable that way. Budget
for downtime rather than a second unit.

**The six-port config boots.** Proven on hardware 2026-08-01, remotely, no
bench trip:

```
cdx_module_init::start_dpa_app successful
ipsec_init_ohport:: ipsec of port id = 9
IPSEC_CGR / IPSEC_REINJECT / IPSEC_SIGNAL / IPSEC_FROMSEC: stage=init
```

The IPsec OH port allocates for the first time on this board, all five IPsec
subsystems initialise, and no `rejected:` or `MAX_MATCH_TABLES` line appears —
so the OFFLINE port introduced no unknown table type. No regression: WAN
forwarding flows are still `fp-state: installed` with `fpp-dir:
orig+reply(0x3)` through `pppoe-wan10g`, PPPoE is up, and every `fallback`
entry is `local-conn: yes` or router-originated.

**IPsec offload is proven in hardware**, same day, on the `yul_tunnel`
site-to-site tunnel (ESP tunnel mode, AES-GCM-16-256) carrying a live video
stream from a camera on the remote subnet:

| | inbound `c94964bb` | outbound `c0945d09` |
|---|---|---|
| SEC engine (`cmm -c "show stat ipsec query"`) | 8116 pkts / 7,136,218 B | 3983 pkts / 290,640 B |
| Kernel (`swanctl --list-sas`) | 0 / 0 | 0 / 0 |

Counters advance in real time while the kernel stays at exactly zero, CPU sits
at `100% idle` with `0% sirq` during the stream, and ICV/HW error counters are
zero. The flow shows `fp-state: installed`, `local-conn: no`,
`fpp-dir: orig+reply(0x3)`. Traffic must be encapsulated — the remote is
RFC1918 and reachable — and the kernel is demonstrably not doing it.

Note the earlier claim that `ip xfrm state` showed no SAs was unfounded:
`/sbin/ip` is `ip-tiny`, which has no `xfrm` object and **exits 0** after
printing `Object "xfrm" is unknown` to stderr. See the silent-lie trap list in
`AGENTS.md`.

**Ported to `mono-ask-25.12` as `9ec05f6134`, built, flashed, and proven there
on 2026-08-01.** Everything above was 6.18.39 on `mono-ask`; the release line
is 6.12.94 and is what actually gets flashed, so it was not real until it ran
there. The four `mono-ask` commits are collapsed to their end state — the
r52/r53/r54 diagnostic pins are not reproduced on the release line, and
`PKG_RELEASE` numbering is kept in lockstep so a given rNN is the same content
on both branches. On 6.12.94:

```
cdx_module_init::start_dpa_app successful
ipsec_init_ohport:: ipsec of port id = 9
```

with SEC-engine counters advancing (+505 / +273 packets over six seconds) on
SPIs `c634c987` / `c6c933e8` while `swanctl --list-sas` holds both at exactly
0 bytes / 0 packets. Loaded `cdx.ko` confirmed r55 by content string, not by
version label. `PKG_MIRROR_HASH` on 25.12 is copied from the `mono-ask`-verified
pin, not regenerated.

Two operational notes. The packaged `cdx_cfg.xml` is **not** a conffile, so any
`ask-dpa-app` upgrade or flash overwrites the runtime copy — the six-port
config is what a flash delivers. And `/root/cdx-6port-failsafe.sh` plus
`/root/.cdx-6port-confirmed` **did not survive sysupgrade** (`/root` is not on
the keep list, unlike `/etc`), so the 25.12 six-port boot ran with no safety net
and succeeded anyway. `/etc/rc.local` was kept and still hooked the absent
script behind an inert `[ -x ... ] &&` guard; **removed 2026-08-01**, restored
to stock, with the previous contents backed up to `/etc/rc.local.bak-29`.
`/etc` is on the keep list, so both the cleanup and that backup persist across
flashes — delete the backup when it is no longer wanted.

Issue #29's stated risks are refuted: the cap was never a vendor constant, and
FIFO/tasks/DMAs are committed at FMan probe from the DTS, so `cdx_cfg.xml`
does not affect them. See `journal/2026-08-01.md`.

**#33 is fixed** — `yul_tunnel` now establishes after a cold boot with no
manual `swanctl --initiate`, verified hands-off on hardware 2026-08-01 on the
same 6.18.39 `mono-ask` build. The fix is `option startaction 'route'`
(`start_action = trap`), which re-initiates on every matching packet instead of
once at load.

There were two boot failures, not one. The reported DNS race is real, and
`charon.retry_initiate_interval` closes it. But **the WAN IP changes on every
reboot** (three boots, three addresses) and DDNS lags by minutes, so the peer
answers `NO_PROPOSAL_CHOSEN` until its resolution of `ork.opendmz.com` catches
up — which `retry_initiate_interval` does not cover, and `keyingtries` does not
either, because an explicit error notify destroys the IKE_SA and
`start_action = start` never fires again. Only the trap policy retries
indefinitely. It took three acquires over six minutes to come up.

Deployed as runtime config only — no code change, no build, nothing to port:

| Change | Where |
|---|---|
| `startaction 'route'` — **the fix** | `uci ipsec.yul_tunnel.startaction` |
| `closeaction 'hold'` — coherence with trap | `uci ipsec.yul_tunnel.closeaction` |
| `keyingtries '%forever'` — did not help, kept | `uci ipsec.yul.keyingtries` |
| `retry_initiate_interval = 5s` | `/etc/strongswan.d/charon-retry-initiate.conf` |

Offload survives the change: the acquire-created SA offloads exactly like an
initiate-created one, hardware counters advancing while the kernel stays at
zero. `/lib/upgrade/keep.d/strongswan` keeps `/etc/strongswan.d/`, so both
files survive sysupgrade — and **this is now verified on 25.12**. After the
2026-08-01 flash, `startaction=route`, `closeaction=hold`,
`keyingtries=%forever` and `charon-retry-initiate.conf` all carried across, and
`yul_tunnel` established about four minutes after boot with no manual
`swanctl --initiate`.

The DDNS lag itself is tolerated, not solved; the tunnel is down for the few
minutes propagation takes. Fixing that is peer-side work.

## Where things are

| What | Where |
|---|---|
| Open work | GitHub issues on `cvandesande/openwrt` (`gh issue list`) |
| What happened, when | `journal/YYYY-MM-DD.md` — append-only, never edited |
| How to work here | `AGENTS.md` (+ `CLAUDE.md` symlink) |
| Reference docs | `docs/` — note `05-*` and `06-*` exist only on `mono-ask` |

## Known caution

Closed but worth remembering: `haproxy.cfg` was lost once on 2026-07-19 and the
sysupgrade theory was disproven (#27). Prime suspect is something copying an
`.apk-new` over a live file. Reopen only if a real flash loses config.
