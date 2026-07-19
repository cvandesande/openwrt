# SELinux and audit diagnostics on Mono Gateway images

The Mono Gateway images run SELinux in **enforcing** mode
(`/etc/selinux/config`, policy `selinux-policy` — Defensec CIL policy,
`package/system/selinux-policy`). This has two consequences that are easy
to miss and have already cost real debugging time:

1. A denied action surfaces to the application as a plain `EACCES`
   ("Permission denied") with **nothing in `dmesg` or `logread`**.
2. The actual denial records are all there — but only in
   **`/var/log/audit/audit.log`**.

## Where denials actually go

These images ship the full audit userspace (`auditd`, `ausearch`,
`aureport`, `auditctl`). `auditd` runs from boot and drains every kernel
audit record — including all SELinux AVC denials — over netlink into
`/var/log/audit/audit.log`. Because the records are consumed by `auditd`,
the kernel's printk fallback never fires, which is why `dmesg`/`logread`
stay clean. Nothing is `dontaudit`ed away; it is just in a different file.

Practical commands on the router:

```sh
ausearch -m avc -ts recent            # denials from the last 10 minutes
ausearch -m avc -c wg                 # denials for a specific comm
grep type=AVC /var/log/audit/audit.log | tail
aureport -a                           # denial summary
grep MAC_STATUS /var/log/audit/audit.log   # every setenforce toggle, timestamped
```

`/var/log` is tmpfs, so the log is RAM-only (lost at reboot) and bounded:
`auditd.conf` rotates at `max_log_file = 8` MiB with `num_logs = 5`
(~40 MiB worst case).

Since the `16_selinux-audit-visibility` uci-defaults script, the audisp
syslog plugin (`/etc/audit/plugins.d/syslog.conf`) is activated so AVC
records are additionally mirrored into `logread`, and the logd ring buffer
default is raised to 1024 KiB so a denial burst cannot churn away recent
history. `audit.log` remains the complete record (syslog mirroring is
best-effort and interleaved with everything else).

## Diagnosing a suspected denial

```sh
getenforce                             # is enforcing actually on?
ausearch -m avc -ts recent | tail      # did the failing action log an AVC?
```

If a tool fails with `Permission denied` as root with correct DAC
permissions, suspect SELinux **before** filesystem permissions. To
confirm causality without changing policy: `setenforce 0`, retry the
action, `setenforce 1`. Every toggle is itself recorded (`MAC_STATUS` in
audit.log), so this leaves an auditable trail.

## Fixing a policy gap

The policy is built from CIL source by `package/system/selinux-policy`
(external upstream, patched in `patches/`). The workflow that fixed the
WireGuard case (see below) is the template:

1. Reproduce and capture the AVC record (source context, target context,
   class, permission).
2. Find the module under `src/` in the package build dir (e.g.
   `src/agent/sysagent/wireguardtoolssysagent.cil`).
3. Add the minimal `(allow ...)` in a new numbered patch in
   `package/system/selinux-policy/patches/`, bump `PKG_RELEASE`, rebuild.
4. Verify the compiled `policy.33` from the build dir with `sesearch`
   (host `setools`) before flashing:
   `sesearch -A -s <source> -t <target> -c <class> policy.33`.

A compiled policy can also be hot-loaded on the router for validation
(`load_policy <file>`), and persists across reboots if
`/etc/selinux/selinux-policy/policy/policy.33` is replaced — but not
across a sysupgrade, so the package patch is the real fix.

## Case study: WireGuard `wg syncconf` (2026-07-19)

netifd's wireguard proto script pipes the generated config into
`wg syncconf <iface> /dev/stdin`. `wg` re-opens the inherited pipe via
`/proc/self/fd/0`, which with the `open_perms` policy capability requires
`open` on netifd's fifo — and the policy granted only the inherited
read/write set:

```
type=AVC ...: avc:  denied  { open } for  comm="wg" path="pipe:[...]"
  dev="pipefs" scontext=sys.id:sys.role:wireguard.wg.subj
  tcontext=sys.id:sys.role:netif.server.subj tclass=fifo_file permissive=0
```

Result: `wg0` wedged in a netifd pending/retry loop on every boot/ifup,
with only `netifd: wg0 (<pid>): fopen: Permission denied` in logread —
classic "looks like a file permission bug". Fixed by
`patches/011-wireguard-allow-netifd-fifo-reopen.patch` (an explicit
`(allow subj .netif.server.subj (fifo_file (open)))`, mirroring the ucode
equivalent that already existed).

## Known remaining denial noise (harmless but unfixed)

Steady-state `audit.log` shows recurring denials that have not been
triaged as user-visible breakage, dominated by `hotplug-call`
(`getattr` on `/usr/sbin/xtables-nft-multi`, `search` on `/tmp/lock`,
`getattr` on `/etc/mwan3.user` — a triple per mwan3 hotplug event) plus
occasional `rpcd`/`iptables` records. If mwan3 or hotplug behavior ever
looks subtly wrong, start there.
