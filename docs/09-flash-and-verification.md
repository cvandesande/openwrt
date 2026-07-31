# Flashing And Post-Flash Verification

Hard-won facts about getting an image onto the Mono Gateway DK and confirming
what is actually running. Build recipes are in `08-build-commands.md`; the rules
that govern runtime changes are in `AGENTS.md` under Router Runtime Safety.

## Getting files to and from the router

There is **no sftp-server** on the router, and `scp` is unreliable even with
`-O`. The dependable transfer method in both directions is piping through ssh:

```sh
ssh root@<router> 'cat > /tmp/pkg.apk' < pkg.apk     # to the router
ssh root@<router> 'cat /tmp/file'      > file        # from the router
```

This is what has been used for apks and images throughout. Serial console is the
last-resort recovery path; it has been needed twice.

## U-Boot boot flow

`bootcmd=run emmc || run recovery`. The `emmc` path tries a standalone
`/boot/Image.gz` plus DTB pair **first**, and only falls back to
`/boot/kernel.itb`, which is what this build produces.

**If a standalone `Image.gz`+DTB pair ever lands in `/boot`, it silently shadows
every future sysupgrade.** If a kernel or DTS change appears not to take effect,
check `/boot` before anything else.

Rootfs is a single ext4 on `mmcblk0p1` (eMMC), with a journal.
`/boot/kernel.itb` is a FIT image bundling the gzipped kernel and the DTB.

## Image metadata and sysupgrade

Since `c879085263` the `.bin.gz` is flashable directly with plain `sysupgrade` —
no `-F`. Metadata is appended *after* compression, so the fwtool trailer sits
outside the gzip stream.

Verify any image before flashing:

```sh
fwtool -q -i /dev/null <image>-ext4-sysupgrade.bin.gz   # must succeed
gzip -t <image>-ext4-sysupgrade.bin.gz                  # "trailing garbage ignored"
```

That `gzip -t` warning **is** the metadata trailer, not corruption.

Only images built the old way must be gunzipped first. The reason `-F` used to
appear to work: the write path (`get_image`) gunzips, but the metadata check in
`lib/upgrade/fwtool.sh` does not.

## apk conffile semantics

Proven 2026-07-26; generalizes well beyond the case that prompted it.

A package's `conffiles` entry is preserved across sysupgrade **without any
`keep.d` entry**. Sysupgrade unions `list_static_conffiles` (keep.d plus
`sysupgrade.conf`) with `list_changed_conffiles`, which reads the apk records in
`/lib/apk/packages/*.conffiles_static` and backs up any file whose live checksum
differs from the shipped one.

apk also never clobbers an existing differing file: it diverts **its own** copy
to `<file>.apk-new`, even on a fresh install with no prior conffile record.

Two consequences:

- Before blaming sysupgrade for a lost config, check both mechanisms first.
- **Treat every leftover `.apk-new` as a foot-gun.** Copying one into place is
  the one way to actually lose the live file. This is the same trap behind
  `/etc/selinux/config.apk-new`, which says `SELINUX=permissive` while the live
  config stays enforcing.

To test install behaviour safely, use a scratch root:

```sh
apk add --root /tmp/scratch --initdb <pkg>
```

with `/etc/apk/{repositories.d,keys,arch}` copied in. The
`post-install ... error 127` in that scratch root is just the missing shell, not
a failure.

## Post-flash verification

The first boot after a flash runs **permissive by design**; the next reboot is
enforcing. See `06-selinux-audit-diagnostics.md`.

Do not identify an image by `BUILD_ID` or by file dates — both are pinned or
inherited. Use `apk list -I` and `lsmod`.

```sh
ip -s link show eth4                  # netdev view (accepted frames only)
ip -d link show eth4                  # real MTU; ubus reports the configured one
cat /sys/class/net/eth4/mac_rx_stats  # MAC-level FCS/error counters
cat /sys/class/net/eth1/carrier_down_count   # link flap count
readlink /sys/bus/mdio_bus/devices/0x0000000001afd000:01/driver   # PHY driver
dmesg | grep -i -E 'fman|cdx|sfp|dpa|Qman ErrInt'
grep '<port ' /usr/share/ask-dpa-app/cdx_cfg.xml
cat /tmp/dpa_app.log                  # always populated
cmm -c "show connections"             # per-flow fp-state installed/fallback
cmm -c "query qm interface eth4"      # QoS shaper state
uci show cmmqos                       # persisted shaper config
getenforce
ausearch --input-logs -m AVC -ts recent      # --input-logs is REQUIRED
grep 'avc:  denied' /var/log/audit/audit.log # dependable fallback
i2csfp /dev/i2c-9 rollball read 1 1          # copper link bit, eth4 cage
```

`ip -s link` counts only accepted frames, so MAC-level FCS and RX errors are
invisible there — that is what `mac_rx_stats` is for. Details on the SFP cages
and Rollball access are in `05-sfp-module-diagnostics.md`; the shaper is in
`07-cmmqos-persistent-shaper.md`.
