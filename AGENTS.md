# AGENTS.md

Instructions for the Mono OpenWrt integration repo. `CLAUDE.md` imports this
file so every agent reads the same rules.

- **Current state** — `STATE.md`: what is deployed, which branches are in flight.
- **What happened, when** — `journal/YYYY-MM-DD.md`, append-only, never edited.
- **Open work** — GitHub issues on `cvandesande/openwrt` (`gh issue list`).
- **Reference** — `docs/`. Note `05-*` and `06-*` exist only on `mono-ask`.

## Sibling Repositories

This repo pins package sources from **separate repositories**. Tooling defaults
to finding them in the parent directory of this checkout, but a clone of this
repo alone is self-contained for building — only vendor-source editing and
navigation need them.

- `ask-cdx/`, `ask-cmm/`, `fci/` — owned source repos used by OpenWrt package pins.
- `ASK/` — vendor ASK source/reference. Third-party input, not an owned repo.
- `OpenWRT-ASK/` — vendor reference firmware tree, not the active build system.

All implementation goes here, in `openwrt/`. Use the vendor trees only to look
up prior art. Do not commit, branch, push, or repin to an unowned vendor repo
such as `ASK/` without explicit authorization — prefer an owned fork, a small
OpenWrt patch, or a vendor-upstream request. When changing owned vendor repos,
update the corresponding package pins and hashes together, then validate
package fetch/build from the pinned refs.

## Branches

- `mono-ask` — default branch; ASK/FMAN/DPAA/CEETM integration work.
- `mono-ask-25.12` — the 25.12 release line. **This is what gets flashed.**
- `mono-oss` / `mono-oss-25.12` — minimal Mono board support, no ASK layer.
- `mono-base-25.12` — base line for release cuts.
- `main` — filtered upstream OpenWrt tracking branch.

Nightly CI keeps `main`, `mono-oss`, and `mono-ask` current and is
**compile-validated only** — it proves the tree builds, nothing about hardware.
Hardware validation happens through the release pipeline. See
`docs/nightly-next-workflow.md` and `docs/mono-release-workflow.md`.

## Design Rules

- Prefer boxed, rebase-friendly changes over broad vendor-style patch imports.
- Keep OpenWrt/Linux authoritative for routing, firewall, conntrack, policy,
  config, service control, package builds, images, and sysupgrade.
- Keep NXP ASK/FMAN/DPAA/CEETM behavior behind explicit hardware-control
  boundaries.
- Do not alter ASK/CDX/CMM/CEETM/FMAN/DPAA fastpath behavior while working on
  unrelated docs, build, packaging, or UI tasks.
- Give confidence levels for suggested approaches.
- Push back when an approach risks bootability, hardware recovery, data loss,
  licensing problems, or false validation claims.

## Evidence and Scope Discipline

- Treat sandbox, host terminal, remote Git, and router state as separate
  scopes. State the scope of every process, signing, network, and runtime claim.
- Never infer global absence from sandbox-local inspection. If a user-facing
  terminal or tool reports background work, that is authoritative for its scope.
- When evidence conflicts or is incomplete, stop and report the uncertainty.
  Do not fill gaps with assumptions or present scoped observations as global facts.
- **One confirming source is not a conclusion.** Identify the field, file, or
  branch that would show the opposite and check that too — committer (`%cn`) not
  just author (`%an`), recipe ordering not just the config flag, this board's
  code path not the generic helper.
- If a conclusion contradicts something the user stated, or something the project
  already records in `STATE.md`/`journal/`/`docs/`, treat that contradiction as
  evidence the conclusion is wrong. Verify rather than correcting them. Absence
  of pushback is not agreement.
- Prefer "I checked X, which does not rule out Y" over a confident table built on
  a single data point. State verified vs not-verified explicitly, in commit
  messages too.
- **Do not claim hardware success from build success, installed state, or
  `fp-state: installed` alone.** For offload claims collect route state, CMM
  connection state, tuple-level hardware stats, FMAN/DPAA counters, and CPU-path
  evidence. For CEETM/QoS work, distinguish upload-side hardware egress shaping
  from SQM/CAKE or download-side bufferbloat control.
- Known silent-lie traps — each fails in the direction that looks like success:
  - `ausearch` reads stdin unless stdin is a tty, so `ssh host 'ausearch ...'`
    hits EOF and prints `<no matches>` regardless of how many denials exist.
    **Always pass `--input-logs`**, or grep `/var/log/audit/audit.log` directly.
  - `ubus network.device status` echoes configured MTU even when the kernel
    refused it. Verify with `ip -d link show`.
  - Pinned build timestamps and an inherited `BUILD_ID` never indicate
    freshness. Verify by content — `apk list -I`, `PKG_RELEASE`, `lsmod`, sha256.

## Safety Boundaries

- Be extra cautious with NOR, eMMC, bootloader, rootfs, recovery, sysupgrade,
  and DTS power/reset/mux logic. Do not change partition or boot logic unless
  explicitly required and the failure mode is understood.
- Do not make speculative hardware-sequencing or DTS changes for radios, SDIO,
  UART muxing, reset lines, or power sequencing without source evidence or
  hardware validation.
- Do not commit firmware blobs when a source-fetch OpenWrt package can pull them
  during build.
- Never treat software fallback as acceptable unless the task explicitly allows
  it and the docs and reporting say so.
- If work cannot be honestly completed under the accepted scope, stop and report
  the blocker rather than widening scope silently.

## Router Runtime Safety

Applies to the Mono Gateway DK and any board on the same `sdk_dpaa`/FMan/CDX
stack, which tolerates concurrent interface teardown far worse than a stock
Linux NIC driver.

- **NEVER run `/etc/init.d/network restart` remotely.** It is not
  interface-scoped — trailing arguments are ignored and it restarts networking
  wholesale, tearing down the SSH path with everything else. It has wedged the
  FMan/CDX stack hard enough to need a physical power cycle. For one interface
  use `ifdown <iface> && ifup <iface>`, or
  `uci commit network && /etc/init.d/network reload`.
- **`network reload` is gentler but not free.** Repeated reloads while
  reconfiguring a VLAN or device stanza on a CDX-managed port can desync the CDX
  classifier table, and the damage is not confined to the port being touched.
  Batch UCI changes into as few reloads as practical.
- If fast path shows `fp-state: rejected` / `last-fci-rc: -1` after config churn,
  check `dmesg` for `insert_entry_in_classif_table` or `dpa_get_tdinfo` errors.
  `cmm restart` will NOT fix these — the failure is in the kernel/CDX driver, and
  only a full reboot reinitializes the port and classifier tables.
- Never run `tcpdump` on a CDX-managed interface at the same time as any
  `ifdown`/`ifup` touching that interface or its parent device.
- Do not trust driver state after live `rmmod cdx; insmod` cycles — leftover
  procfs/hook state produces spurious `already registered` errors. Only a real
  reboot (confirmed by a reset `uptime`) is a valid cold-boot signal.
- Keep management traffic on a different physical port from whatever is under
  test. That isolation is the margin a wholesale restart discards.

## Build Discipline

- **Ask the user before running any OpenWrt build** — `make ... compile`,
  `prepare`, or `defconfig`. `build_dir`/`staging_dir`/toolchain are not
  branch-scoped and carry whatever branch last built them, so a compile can
  succeed while staging against another branch's artifacts. Confirm which tree
  and branch, and whether the toolchain state matches.
- Never deploy an apk built from a mixed-branch tree.
- Source-only work — editing patches, Makefiles, regenerating patch files with
  `diff` — needs no ask.
- Recipes, the post-`dirclean` sequence, and pin-hash validation:
  `docs/08-build-commands.md`. Local clangd setup: `docs/04-developer-tooling.md`.

## Git Discipline

- Preserve user changes. Do not revert or overwrite unrelated dirty files.
- Do not use destructive Git commands, and do not amend commits, unless
  explicitly requested.
- Only push signed commits. A signing failure is a blocker to report, not
  permission to push unsigned.
- Before a push, branch operation, runtime change, or long-running command,
  state the target, branch, expected side effects, and stop/rollback method.
- **Push only the exact branch the user names.** A push request never extends to
  whatever branch is checked out, and an earlier push never authorizes a later
  one. If pushing a second branch seems useful, propose it and wait for a yes.
- **`github-actions[bot]` force-push-rewrites both `mono-ask` branches, and has
  silently dropped a tip commit.** Before any push to either:
  1. `git fetch origin mono-ask mono-ask-25.12` and check for `(forced update)`.
     A stale fetch makes `git cherry` meaningless.
  2. Compare by **content, never by hash** — a commit can be absent from the
     ancestry while its content is present verbatim, so a hash-only check reports
     a false loss. Use `git cherry`, `git diff --stat`, and grep commit subjects.
  3. `git rebase --onto origin/<branch> <old-base> <branch>`, then push
     fast-forward. **Never force-push over the bot.** Rebasing re-signs every
     commit, so a hardware key needs a touch per commit.
- GitHub runs workflows from the **default branch** (`mono-ask`), which carries
  different copies of the CI scripts than `mono-ask-25.12`. Reading the 25.12
  copy leads to the wrong conclusion.

## Work Delegation

- Prefer the established prompt-and-review workflow for risky implementation:
  one bounded implementation chat, then a separate review before pulling work
  into validated branches.
- Use sub-agents only for low-risk sidecar exploration, comparison, search,
  documentation drafting, or validation checklist generation.
- Do not use sub-agents as the primary mechanism for NOR/eMMC/sysupgrade, DTS
  power/reset/mux, ASK/CDX/CMM/CEETM behavior, security-review fixes, or
  hardware-state-changing work unless explicitly requested.

## Documentation and Handoff

- Keep public docs focused on the current architecture and validated state.
  Remove stale experimental history rather than documenting abandoned paths.
- Link to detailed docs instead of duplicating long explanations. A fact should
  live in exactly one file.
- When documenting unfinished work, call it remaining work rather than out of
  scope unless it is truly out of scope.
- Before stopping at a milestone or awaiting input, state the concrete next
  steps — including required approval, target scope, expected disruption, and
  rollback point whenever the next action changes Git, services, router state,
  or a long-running process.
