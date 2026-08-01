# Current state

Deliberately short. If something here needs a paragraph, it belongs in `docs/`;
if it is a record of what happened, it belongs in `journal/`; if it is an open
question, it belongs in an issue.

## Production

The router's WAN runs PPPoE over the 10G port (`eth4`) at a true 10G copper
link, with hardware fast-path offload active, cmm crash-supervised under procd,
RFC 4638 baby-jumbo MTU proven end-to-end, QoS shaping UCI-persisted via
`cmmqos`, and SELinux enforcing with WireGuard syncing cleanly at boot.

- Image `25.12.5-mono1` (`mono-ask-v25.12.5-r6`, kernel 6.12.94, 25.12 line),
  built 2026-07-26 from `mono-ask-25.12` `6c21493790`.
- `wan10g` = PPPoE on `eth4.10`, MAC-cloned, mtu 1508 parent+child, ppp 1500.
- `wan` (1G) stays `disabled=1` as a manual fallback — one active at a time.
- cmm r27 with `cmmqos`; selinux-policy **r8** loaded, enforcing.
- `kmod-phy-maxlinear` driving the three 1G PHYs; `wg0` on port 443, 5 peers.

## Branches

- `mono-ask` — default branch; docs, journal, and this file live here.
- `mono-ask-25.12` — the release line that gets flashed.
- `selinux-policy-r9` — in flight: the #32 survivor's fix
  (`read_file_files` → `manage_file_files`, PKG_RELEASE 8→9). Pushed, but
  **not built, not flashed, not ported to `mono-ask`**.

`mono-ask` also carries the #29 IPsec OH-port change: ask-cdx **r54** and
ask-dpa-app r5 re-adding portid 9. r53 raised the port ceiling 5→16 (derived
from `FMC_PORTS_PER_FMAN`, so WiFi needs no further kernel change) and fixed
two OH-path bugs — a `==`→`&` bitmap test and a missing bounds check. r54 adds
no functional change: it logs which bound rejected a config, because the
failure below was silent.

**Built and flashed on 2026-08-01, and it failed.** CDX did not initialise:
`cdx_ioc_set_dpa_params` returned `-EINVAL`, `dpa_app` exited 255, and the
kernel printed nothing but `start_dpa_app failed rc 65280`. WAN and LAN did not
come up. Recovered by taking the router off production to the bench, deleting
the `type="OFFLINE"` line from `/usr/share/ask-dpa-app/cdx_cfg.xml`, rebooting,
and returning it to service. It is back on the 5-port config with r53's
`cdx.ko` still installed, which is itself evidence the kernel changes are
harmless on their own.

**There is only one router.** #29's "bench only" cannot mean a spare board —
there isn't one. In practice bench means physically off production, with serial
attached, and every change on this path must be recoverable that way. Budget
for downtime rather than a second unit.

Ruled out: the loaded module was confirmed to be r53 (its `port out of range`
string is present in `cdx.ko`), so `CDX_CTRL_MAX_PORTS_PER_FMAN` is 16 and
`max_ports = 6` passes. Both OH ports probe and are `enabled` at ~2.3s with no
FMan resource errors. The surviving candidates are the other bounds in
`dpa_cfg.c` — `CDX_CTRL_MAX_DIST_PER_PORT` (12, and the OFFLINE policy lists
exactly 12 distributions) and `CDX_CTRL_MAX_TABLES_PER_FMAN` (64). r54 is what
distinguishes them.

Next step is the r54 kmod alone — no reflash — then re-add the OFFLINE line and
read dmesg. **Not built, not ported to `mono-ask-25.12`.**

Issue #29's stated risks are refuted: the cap was never a vendor constant, and
FIFO/tasks/DMAs are committed at FMan probe from the DTS, so `cdx_cfg.xml`
does not affect them. See `journal/2026-08-01.md`.

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
