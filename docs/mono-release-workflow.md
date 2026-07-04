# Mono Release Workflow

Mono OpenWrt maintains two, deliberately separate branch tiers:

- **Rolling** (`main` → `mono-oss` → `mono-ask`): a dev trunk that tracks
  upstream OpenWrt `main` and is rebuilt every night (see
  `docs/nightly-next-workflow.md`). It never ships directly. Upstream `main`
  moves ahead of any release branch over time — including structural changes
  like the 6.12 → 6.18 kernel bump in mid-2026 — so rolling `mono-oss`/
  `mono-ask` commits are continuously re-expressed in terms of whatever `main`
  currently looks like. That makes them unsuitable for replaying directly onto
  an older, frozen release tag once the two have structurally diverged.
- **Stable, per release line** (`mono-base-<line>` → `mono-oss-<line>` →
  `mono-ask-<line>`, e.g. `mono-oss-25.12`/`mono-ask-25.12`): a persistent
  tracking branch pair per upstream `openwrt-YY.MM` release branch (upstream
  cuts one of these roughly yearly: `openwrt-21.02`, `22.03`, `23.05`, `24.10`,
  `25.12`, ...). This is the only tier that ever actually ships a numbered
  Mono release, and it is advanced independently of whatever the rolling tier
  is doing.

There are three ways to produce a hardware-validatable Mono OpenWrt
pre-release: forking a brand new stable line (`Fork Mono ASK Release Line`),
advancing an existing stable line to the next upstream point release
(`Advance Mono ASK Release Line`), and an ad-hoc snapshot cut from the current
`mono-ask` tip (`Cut Mono ASK Snapshot Release`) for smoke testing
in-progress dev-trunk work without waiting for any official release. All
three produce a GitHub pre-release, and all are gated on manual hardware
smoke testing before promotion; see `docs/nightly-next-workflow.md`'s
"Hardware Validation" section for the smoke-test procedure that applies to
any of them.

Nightly CI (`Nightly Build`) only proves that `main`, `mono-oss`, and
`mono-ask` build; it does not gate on hardware validation and does not itself
produce a release.

## Forking a New Stable Line

Use `Fork Mono ASK Release Line` only once per upstream release branch: the
first time you ship against a new `openwrt-YY.MM` line, ideally soon after
upstream forks it off `main` (before the rolling trunk drifts structurally
ahead of it). It takes an official upstream OpenWrt release tag, replays the
rolling trunk's own patches onto it via
`fork-mono-ask-release-line.sh`, builds the candidate firmware, and publishes
the successful CI output as a GitHub pre-release.

The prep step narrows the replay ranges for a stable release cut: `main..
mono-oss` is replayed onto the official OpenWrt tag, then `mono-oss..
mono-ask` is replayed onto that Mono OSS release branch. That avoids
accidentally carrying unrelated upstream snapshot commits from `main` into a
stable release candidate. Because this replays the *rolling* trunk's
commits, it only works while `main` and the target release tag are still
close enough in tree structure that the replay applies cleanly — if `main`
has since moved (e.g. past a kernel version bump the release line never
takes), use "Advancing an Existing Stable Line" below instead, or the fork
will fail with rebase conflicts in the prep job.

Example inputs:

```text
upstream_tag:  v25.12.4
mono_revision: r1
mono_number:   mono1
```

Those inputs derive:

```text
base_branch:    mono-base-v25.12.4-r1
oss_branch:     mono-oss-v25.12.4-r1
ask_branch:     mono-ask-v25.12.4-r1-candidate
release_tag:    mono-ask-v25.12.4-r1
version_number: 25.12.4-mono1
version_code:   mono-ask-v25.12.4-r1
```

After a successful fork, create the persistent stable-line tracking branches
(`mono-base-<line>`, `mono-oss-<line>`, `mono-ask-<line>`) pointing at the
`_candidate`/base/oss branches this run produced — future point releases on
that line advance from there.

## Advancing an Existing Stable Line

Use `Advance Mono ASK Release Line` for every point release after the initial
fork (e.g. `v25.12.4` → `v25.12.5` → `v25.12.6`, ...). It takes the persistent
`mono-base-<line>`/`mono-oss-<line>`/`mono-ask-<line>` tracking branches for
the line you name, replays only *that line's own* commits
(`advance-mono-ask-release-line.sh`) onto the new upstream point-release tag,
builds, and — on success — fast-forwards those tracking branches to the newly
cut release branches, then publishes the pre-release. This never touches or
depends on the rolling `main`/`mono-oss`/`mono-ask` trunk, so it stays correct
no matter how far the rolling trunk has drifted (different kernel version,
renamed directories, etc.) — point releases within one upstream release
branch don't carry that kind of structural change.

Example inputs:

```text
release_line: 25.12
upstream_tag: v25.12.6
mono_revision: r1
mono_number:  mono1
```

These derive the same style of output refs as a fork (`mono-base-v25.12.6-r1`,
`mono-oss-v25.12.6-r1`, `mono-ask-v25.12.6-r1-candidate`,
`mono-ask-v25.12.6-r1`), while reading from and then updating
`mono-base-25.12`/`mono-oss-25.12`/`mono-ask-25.12`.

If a Mono-specific fix needs to reach the stable line and was only ever
developed on rolling `mono-ask`, cherry-pick that commit onto
`mono-ask-<line>` by hand before running this workflow — there is no
automatic porting between the rolling trunk and any stable line once they've
diverged.

The older `Mono ASK Release Build` workflow remains available for rebuilding
and publishing an already cut, annotated Mono ASK release tag (official format
only). Its first intended use was:

```text
release_tag:    mono-ask-v25.12.3-r1
version_number: 25.12.3-mono1
version_code:   mono-ask-v25.12.3-r1
```

## Snapshot Pre-releases

Use `Cut Mono ASK Snapshot Release` to smoke test current in-progress work
without waiting for the next official upstream release cut. It takes a single
`ref` input (default: `mono-ask`), tags that commit directly — no replay onto
an upstream tag, no `mono-oss`/`mono-ask` split, since it snapshots whatever
`ref` already is — and builds/publishes it through the same
`Mono ASK Build and Publish` reusable workflow as an official release.

Tag and version derivation:

```text
release_tag:    mono-ask-snapshot-<UTC date>-<short SHA>
version_number: snapshot-<UTC date>
version_code:   mono-ask-snapshot-<UTC date>-<short SHA>
```

For example, tagging current `mono-ask` on 2026-07-04 might produce
`mono-ask-snapshot-2026-07-04-a1b2c3d4e5`. The workflow refuses to reuse an
existing snapshot tag; if you need another snapshot the same day, wait for a
new commit or use a different `ref`.

Snapshot pre-releases are not tied to an official upstream version and are
not expected to be long-lived — they exist to get a specific commit onto real
hardware quickly. Promote one to a full release the same way as an official
release candidate (`Promote Mono ASK Release`) only if you specifically want
to keep it around; more often a snapshot will simply be superseded by the next
one or by an official release cut.

## Release Publication

The release workflows deliberately do not create a full stable release. The
GitHub release is marked as a pre-release and explicitly not marked as
`Latest`, so the firmware can be downloaded and smoke tested on a controlled
Mono Gateway DK first. After hardware smoke validation passes, promote the
GitHub release manually in the GitHub Web UI.

## Security Model

Both the fork and advance workflows keep the same CI/CD safety posture as the
nightly workflow:

- External GitHub Actions are pinned to full commit SHAs.
- A guard step fails the run if any external action in `.github/workflows` is
  not pinned.
- The OpenWrt build job has only read-level permissions and does not persist
  checkout credentials into the source tree.
- The job with `contents: write` only downloads the already built release
  payload and creates the GitHub pre-release. It does not run OpenWrt build
  code from the candidate tag.
- Release publication refuses to overwrite an existing GitHub release for the
  same tag.
- Both workflows refuse to overwrite an existing release branch or tag; use a
  new Mono revision such as `r2` instead.
- The release workflow requires `version_code` to match `release_tag`, and the
  image version must match the version embedded in the tag.
- Advancing a stable line only fast-forwards its tracking branches
  (`mono-base-<line>`/`mono-oss-<line>`/`mono-ask-<line>`) after the new
  versioned release branches and tag have already been pushed successfully, so
  a failed or interrupted run never leaves the tracking branches ahead of a
  published release.

## Validation

The candidate preparation and build jobs verify:

- the upstream input is an official annotated OpenWrt tag,
- the derived Mono release tag, image version, and image code are coherent,
- the checked-out candidate commit matches the prepared `mono-ask` release
  branch,
- Mono vendor source hashes match the checked-in package hashes,
- restored cache state is reported in the GitHub step summary,
- `make toolchain/install` builds or installs the required toolchain before the
  firmware build,
- `make download` and the full firmware build complete,
- output filenames use the `mono-openwrt-<version>` prefix,
- `config.buildinfo`, `profiles.json`, `/etc/openwrt_release`,
  `/usr/lib/os-release`, and `/etc/openwrt_version` report the expected Mono
  release identity.

If the replay conflicts, the workflow stops in the preparation job before
pushing any release branches, tags, or GitHub releases. The failed job summary
lists the conflicted files.

- For a **fork** conflict: this usually means `main` has moved too far past
  the target release tag for the rolling trunk's patches to replay cleanly
  (see "Forking a New Stable Line" above) — use "Advance Mono ASK Release
  Line" against an already-forked line instead, or land the minimal
  compatibility fix on `mono-oss`/`mono-ask` and rerun.
- For an **advance** conflict: this means a real content conflict between a
  Mono patch and an upstream point-release backport touching the same lines
  — land the minimal compatibility fix directly on `mono-oss-<line>` or
  `mono-ask-<line>`, then rerun with the same upstream tag and Mono revision
  if still unused.

The fork script (`fork-mono-ask-release-line.sh`) has one narrow built-in
resolver for the known `v25.12.4` image makefile conflict: it preserves
upstream's `traverse_ten64_mtd` device block and inserts the Mono Gateway DK
device block before it. Any other conflict still fails closed. The advance
script (`advance-mono-ask-release-line.sh`) has no such resolver — point
releases within one upstream line aren't expected to reproduce that class of
conflict.

Build-log artifacts include `make-toolchain-install.log` and
`ccache-stats.txt` so cache effectiveness can be checked separately from total
firmware build time. The `staging_dir/toolchain-*` cache is intentionally
disabled because release-candidate telemetry showed that an Actions cache hit
could still spend tens of minutes in `make toolchain/install`.

Do not promote the release from pre-release to full release until the hardware
smoke-test record confirms boot, management reachability, package/service
presence, route/interface behavior, relevant logs, and any in-scope ASK/CEETM
runtime checks. Build success alone is not hardware validation.
