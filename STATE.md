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

`mono-ask` also carries the #29 IPsec OH-port change: ask-cdx **r55** and
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

r55 is **installed on the router and unproven**: the on-disk `cdx.ko` carries
it, but the running module is still r54 and the config is still 5 ports, so
nothing has exercised the fix. The next test is a bench trip — re-add the
OFFLINE line, reboot, and confirm CDX initialises. Whether the stages of
`set_dpa_params` past validation work with an OFFLINE port has never been
tested. **Not ported to `mono-ask-25.12`**, which is kernel 6.12.94 and is what
actually gets flashed; all of the above is 6.18.39 on `mono-ask`.

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
