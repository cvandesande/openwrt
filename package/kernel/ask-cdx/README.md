# ask-cdx Module Guide

This README describes how to use `ask-cdx`, what runtime counters/signals are available, which debug options exist, and how to interpret common hardware/offload errors.

## 1) What `ask-cdx` Does

`ask-cdx` is the ASK dataplane kernel module for NXP Layerscape (LS10xx) acceleration.

Primary responsibilities:
- fast-path packet handling and queue steering
- IPsec offload submit/return integration with SEC/QMan/BMan/FMan
- compat/native return-path handling for inbound LAN delivery

## 2) Where It Lives

- Package dir: `package/kernel/ask-cdx`
- Source repo: `https://github.com/cvandesande/ask-cdx`
- The OpenWrt package fetches a pinned source revision through the normal
  package workflow.
- Local OpenWrt ownership stays with package metadata and service integration
  under `files/`.

## 3) Build / Install Basics

From OpenWrt tree:
- prepare: `make -j1 V=s package/kernel/ask-cdx/prepare`
- compile: `make -j1 V=s package/kernel/ask-cdx/compile`

On target, module is typically loaded by package/service wiring. If needed manually:
- `insmod cdx.ko`

## 4) Runtime Debug Options

Module parameters are exposed under:
- `/sys/module/cdx/parameters/`

Set temporarily with:
- `echo <value> > /sys/module/cdx/parameters/<param>`

### Common Parameters (active baseline)

| Parameter | Default | Purpose |
|---|---:|---|
| `ipsec_compat_reinject_mode` | `1` | Controls reinject behavior for return-path handling |
| `ipsec_compat_diag_enable` | `0` | Enables compat success-path diagnostics |
| `ipsec_lan_neigh_diag_enable` | `0` | Enables LAN neighbor-resolution diagnostics |
| `ipsec_excp_copy_skb` | `0` | Diagnostic exception copy behavior (not for normal production) |
| `ipsec_dbg_sa_handle` | `22089` | Scope debug to one SA handle (`0` = all) |

### Snapshot Toggles (debug only)

| Toggle | Period Param |
|---|---|
| `ipsec_nofq_snapshot_enable` | `ipsec_nofq_snapshot_period` |
| `ipsec_reinject_snapshot_enable` | `ipsec_reinject_snapshot_period` |
| `ipsec_signal_snapshot_enable` | `ipsec_signal_snapshot_period` |
| `ipsec_fromsec_snapshot_enable` | `ipsec_fromsec_snapshot_period` |
| `ipsec_cgr_snapshot_enable` | `ipsec_cgr_snapshot_period` |

Production recommendation: keep all snapshot toggles disabled unless actively debugging.

## 5) Counters / Signals You Can Use

The module tracks internal atomic counters and surfaces them through structured logs and SA runtime behavior.

Useful signal families in logs:
- `IPSEC_FROMSEC_STATUS` (status transitions, including sticky failures)
- `IPSEC_FROMSEC_SNAP` (from-SEC entry/status distribution snapshots)
- `IPSEC_SIGNAL_SNAP` (aggregate remap/reinject/exception buckets)
- `IPSEC_REINJECT_SNAP` (reinject decisions and outcomes)
- `IPSEC_CGR` (congestion transitions/snapshots)

Operational command:
- `cmm -c "query sa"` for SA runtime state
- `dmesg -w | grep -E 'IPSEC_FROMSEC|IPSEC_REINJECT|IPSEC_SIGNAL|IPSEC_CGR|IPSEC_COMPAT'`

## 6) Error Meanings

### SEC status quick decoding

The SEC status word uses source in high nibble (`status >> 28`).

- `0x5xxxxxxx` = QI source
- `0x6xxxxxxx` = Job Ring source

### Important known code

- `0x50000008`
  - source: `0x5` (QI)
  - bit 3 set: `BPDERR` (buffer pool depletion class)
  - practical meaning: dataplane buffer resource issue on return/offload path; investigate pool/release paths and sustained failure run-length.

### QI bit meanings (source `0x5`)

- bit 8: `TBTSERR` (table buffer too small)
- bit 7: `TBPDERR` (table buffer pool depletion)
- bit 6: `OFTLERR` (output frame too large)
- bit 5: `CFWRERR` (compound frame write)
- bit 4: `BTSERR` (buffer too small)
- bit 3: `BPDERR` (buffer pool depletion)
- bit 2: `OFWRERR` (output frame write)
- bit 1: `CFRDERR` (compound frame read)
- bit 0: `PHRDERR` (preheader read)

### Job Ring examples (source `0x6`)

- `0x1E`: descriptor address read error
- `0x1F`: descriptor read error

## 7) Production vs Debug Guidance

Production defaults:
- keep `ipsec_compat_diag_enable=0`
- keep snapshot toggles disabled
- rely on rate-limited error logs + counters/state

Debug session pattern:
1. Enable only one relevant toggle.
2. Capture bounded `dmesg` window during reproduction.
3. Disable toggle immediately after capture.

## 8) Troubleshooting Shortlist

1. Confirm SA health:
- `cmm -c "query sa"`

2. Confirm return-path status trend:
- watch `IPSEC_FROMSEC_STATUS` for enter/sticky/exit behavior

3. Confirm inbound LAN bind/shape:
- check `IPSEC_COMPAT_BIND` + `IPSEC_COMPAT` logs

4. If sticky `0x50000008` appears:
- treat as resource/path failure (not simple policy issue)
- collect status transitions, reinject outcomes, and queue/error logs together
