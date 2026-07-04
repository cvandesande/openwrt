# Nightly Build Workflow

The `Nightly Build` GitHub Actions workflow keeps `main`, `mono-oss`, and `mono-ask`
current automatically. `main` is a filtered upstream tracking branch: it follows
upstream OpenWrt source while preserving local exclusions such as workflow files.
`mono-oss` and `mono-ask` are rebased on top of `main` every run, so all three branches
represent the most recent successful nightly build, not merely the most recent rebase.

**These three branches are compile/build-validated only.** A successful nightly run
proves the rebased tree builds; it proves nothing about hardware behavior. Hardware
validation happens exclusively through the release pipeline (see
`docs/mono-release-workflow.md`): cut a release or snapshot pre-release, smoke test it
on a controlled Mono Gateway, then promote the GitHub pre-release once validated. There
is no separate "validated branch" tier and no manual promotion step between nightly CI
and the release pipeline.

It runs nightly and can also be started manually with `workflow_dispatch`.
Scheduled workflows are loaded from the repository default branch, so changes
to this workflow only affect nightly automation after they are present on the
default branch.

The repository default branch is `mono-ask`. That is compatible with the workflow
updating `main`, `mono-oss`, and `mono-ask` directly, since the scheduled workflow
definition itself is loaded from `mono-ask`'s current tip at run time.

## Branch Policy

The workflow updates these branches directly, after a successful build:

- `main`
- `mono-oss`
- `mono-ask`

It does not create nightly tags and does not gate these updates on hardware validation.

The branch and build sequence is:

1. Fetch `upstream/main` from `https://github.com/openwrt/openwrt.git`.
2. Build a local `main` candidate from `upstream/main`, then restore excluded
   upstream paths such as `.github/workflows` from `origin/main`.
3. Rebuild the local `mono-oss` candidate from the current `mono-oss` tip, then rebase
   it onto the local `main` candidate.
4. Rebuild the local `mono-ask` candidate from the current `mono-ask` tip, then rebase
   it onto the local `mono-oss` candidate.
5. Save the prepared candidate refs into a short-lived Git bundle artifact.
6. Build the local `mono-ask` candidate in a separate read-only job.
7. Push `main`, `mono-oss`, and `mono-ask` atomically with `--force-with-lease` only
   after the `mono-ask` build succeeds.

The workflow's `--force-with-lease` push is intentional. `main` is reconstructed
from upstream OpenWrt plus local path exclusions, and `mono-oss`/`mono-ask` are rebased
on top of it every run, so all three automation-managed refs may be rewritten.

Each run starts from the current remote `mono-oss` and `mono-ask` tips as rebase
inputs, so the branches move forward incrementally rather than being torn down and
rebuilt from scratch every night. A failed run leaves them unchanged; the next
successful run picks up from wherever they currently are.

## Conflict Handling

Any failed fetch, rebase, build, or publication exits non-zero and fails
the workflow using normal GitHub Actions failure semantics. GitHub Actions
email notifications can therefore be configured through normal repository/user
notification settings.

For rebase conflicts, the helper script prints conflicted paths and writes a
failure section to the workflow summary. The workflow does not try to resolve
conflicts automatically. Rebase failures do not move `main`, `mono-oss`,
or `mono-ask`. Publication happens only after the build succeeds, and the
publish push is atomic, so a lease or branch-protection failure leaves all
three branches unchanged.

## Build

After local rebases succeed, the workflow passes the candidate refs to the
build job through a Git bundle artifact. The build job checks out the
candidate `mono-ask` commit from that bundle and runs the normal OpenWrt
build flow:

```sh
./scripts/feeds update -a
./scripts/feeds install -a
cp config/mono_gateway-dk.seed .config
make defconfig
make download -j"$(nproc)"
make -j"$(nproc)"
```

The CI job appends OpenWrt build options for ccache and build logs before
`make defconfig`; it does not change the checked-in seed config.

Before the global source download and firmware build, the workflow runs
`scripts/mono-check-vendor-hashes.sh`. This validates the Mono vendor git
packages selected by the product image against their checked-in
`PKG_MIRROR_HASH` values. The helper removes only those packages' matching
source archives from `dl/` before checking, so a stale cached tarball cannot
mask a `PKG_SOURCE_VERSION` update that forgot to refresh `PKG_MIRROR_HASH`.
For this preflight it disables OpenWrt source mirrors, regenerates the archive
from the package's pinned `PKG_SOURCE_URL` and `PKG_SOURCE_VERSION`, and then
compares the regenerated archive hash directly with `PKG_MIRROR_HASH`.
Duplicate package recipes that share the exact same source archive, such as
`ask-fci` and `libfci`, are checked once.
If this preflight fails, verify the pinned vendor commit and update the hash
printed by OpenWrt rather than using `PKG_MIRROR_HASH:=skip`.

The default checked package paths are `package/kernel/ask-cdx`,
`package/kernel/ask-fci`, `package/libs/libfci`, `package/network/ask-cmm`,
and `package/network/ask-dpa-app`.

If that build succeeds, the workflow publishes `main`, `mono-oss`, and `mono-ask`
atomically. If the build fails, those branches keep their previous remote values.

Build logs, `.config`, and target output under
`bin/targets/layerscape/armv8_64b/` are uploaded as workflow artifacts.

## Hardware Validation

The nightly workflow proves that the rebased `mono-ask` candidate builds. It does not
prove hardware behavior and must not be treated as validation by itself.

Hardware validation happens only through the release pipeline, not against nightly
`mono-ask` directly:

- To fork a brand new stable release line, use `Fork Mono ASK Release Line`. To
  advance an existing stable line to its next upstream point release, use
  `Advance Mono ASK Release Line` instead — see `docs/mono-release-workflow.md`
  for when each applies.
- To smoke test current in-progress work without waiting for an official upstream
  release, use `Cut Mono ASK Snapshot Release` to tag current `mono-ask` and publish it
  as a pre-release.

Both paths produce a GitHub pre-release firmware artifact. See
`docs/mono-release-workflow.md` for the exact commands and inputs.

Regardless of which path produced the candidate, the minimum smoke test before
promoting a pre-release is:

- Confirm the device boots the tested image and stays reachable over the
  management path.
- Confirm `/etc/openwrt_release`, `uname -a`, and the recorded release tag or
  artifact checksum match the candidate under test.
- Confirm the expected packages are installed with
  `opkg list-installed | grep -E 'ask-cmm|ask-dpa-app|ask-fci|ask-cdx|libfci'`.
- Confirm the ASK services/modules needed for this image are present with
  `ls -l /etc/init.d/cdx /etc/init.d/fci /etc/init.d/cmm`,
  `lsmod | grep -E '^(cdx|fci)'`, `pgrep -a cmm`, and `cmm -c "help"`.
- Confirm the expected LAN/WAN interfaces, routes, and DNS behavior with
  `ip -br link`, `ip route`, and controlled ping or traffic tests from the lab
  topology.
- Check boot and runtime logs with
  `logread | grep -Ei 'ask|cdx|cmm|fci|dpaa|fman|ceetm|error|fail|warn'` and
  `dmesg | grep -Ei 'ask|cdx|cmm|fci|dpaa|fman|ceetm|error|fail|warn'`.
- Re-run the currently validated 1G routed WAN and upload-side CEETM checks
  that are in scope for the release being promoted.

For offload claims, follow the proof model in
`docs/02-fast-path-architecture.md` and `docs/03-fman-backend-design.md`.
Control-plane installed state alone is not enough; keep traffic-generator
results, relevant `cmm` output, hardware counters, and CPU-path observations
with the test record.

Record at least the release tag, firmware checksum, device serial, test
configuration, topology, pass/fail result, and any deviations. If any smoke test
fails, do not promote the GitHub pre-release.

Before flashing, record the exact candidate and artifact checksum:

```sh
git fetch origin --tags
git rev-parse "$RELEASE_TAG"
find . -name '*mono_gateway-dk*sysupgrade*' -type f -exec sha256sum {} +
```

Flash only a lab or otherwise controlled Mono Gateway first. On the target,
make a config backup before testing the sysupgrade path:

```sh
IMAGE=/tmp/openwrt-layerscape-armv8_64b-mono_gateway-dk-ext4-sysupgrade.bin.gz
sysupgrade -b /tmp/pre-release-backup.tar.gz
sysupgrade "$IMAGE"
```

Use `sysupgrade -n` only when deliberately testing a clean-config boot. The
normal smoke test should exercise the expected upgrade path and known test
configuration.

## Security Model

The workflow separates branch mutation from build execution:

- `prepare-candidates` has `contents: read`; it fetches, rebases, and uploads
  a short-lived Git bundle containing the unpushed candidate refs. It does not
  run the OpenWrt build.
- `build-candidate` has only read-level permissions; it downloads the bundle
  and runs `feeds`, `defconfig`, `make download`, and `make`. This keeps the
  repository write token out of the job that executes OpenWrt package and build
  logic.
- `publish-branches` has only read-level `GITHUB_TOKEN` permissions while it
  downloads and verifies the already-built bundle. Only after those checks pass
  does it mint a short-lived GitHub App installation token with `contents: write`
  and `workflows: write`, then uses that token only for the final authenticated
  fetch and atomic push of `main`, `mono-oss`, and `mono-ask`. It does not run
  the OpenWrt build or any package/feed logic.

The publish GitHub App must be installed only on this repository and should have
only these repository permissions:

- Metadata: read
- Contents: read/write
- Workflows: read/write

The workflow expects these repository secrets:

- `MONO_NIGHTLY_PUBLISH_APP_ID`
- `MONO_NIGHTLY_PUBLISH_APP_PRIVATE_KEY`

The App token is generated by the checked-in
`.github/workflows/scripts/generate-github-app-token.sh` helper from the trusted
workflow checkout rather than by a third-party action or from the unpushed
candidate tree. Do not add third-party actions after the publish token is
created.

External GitHub Actions are pinned to full commit SHAs, with comments recording
the corresponding release versions. This is intentional: recent CI/CD supply
chain attacks, including TeamPCP's March 2026 Trivy and Checkmarx action tag
poisoning campaign, showed that mutable action tags can be force-moved to
malicious commits. The workflow includes a guard step that fails if a future
external action reference is not pinned to a full SHA.

As of the April 2026 security audit, the workflow pins current releases of the
official GitHub Actions it uses: `actions/checkout` v6.0.2, `actions/cache`
v5.0.5, `actions/upload-artifact` v7.0.1, and `actions/download-artifact`
v8.0.1.

## Cache Strategy

The workflow does not cache `build_dir/`.

It uses separate caches for:

- `dl/`
- `.ccache`
- `staging_dir/host`
- `staging_dir/hostpkg`

`dl/` uses a loose key based on runner OS/architecture, cache epoch, and feed
configuration, with a restore prefix for the same epoch. This is safe because
OpenWrt verifies downloaded source hashes.

`.ccache` uses a stable compatibility family based on runner OS/architecture,
cache epoch, the toolchain tree hash, and the filtered toolchain config hash.
The workflow restores the current UTC week key first, then falls back to the
newest cache in that same compatibility family. It saves a refreshed cache only
after a successful full run, using the current UTC ISO week key.

This creates at most one new `.ccache` cache per compatible
OS/architecture/epoch/toolchain/config family per week. It deliberately does
not include the GitHub run id or run attempt. Because GitHub caches are
immutable, exact hits within the same week are reused but not rewritten; the
cache evolves on the next week boundary or when the compatibility family
changes.

`staging_dir/host` and `staging_dir/hostpkg` still use tight keys derived from
the generated `.config`, relevant OpenWrt source tree ids, feed revisions where
applicable, runner OS/architecture, and cache epoch. GitHub cache entries are
immutable, so these caches stay conservative until telemetry proves that a
looser key would not repeatedly restore incomplete host-tool state.

`staging_dir/toolchain-*` caching is disabled. Telemetry from release-candidate
runs showed that an Actions cache hit could still spend tens of minutes in
`make toolchain/install`, so the cache was not effective enough to justify the
download/upload cost or the misleading hit label.

The workflow does not use broad restore prefixes for `staging_dir/host`,
or `staging_dir/hostpkg`.

After cache restore and source download, the workflow runs:

```sh
make -j"$(nproc)" toolchain/install V=s
```

This lets OpenWrt build or install the required toolchain before the full
firmware build. The workflow records the elapsed time and the number of
`toolchain/*` subdir rebuild lines in the GitHub step summary.

The build summary also records exact cache states for `dl/`, `.ccache`,
`staging_dir/host`, and `staging_dir/hostpkg`; `staging_dir/toolchain-*` is
reported as disabled. Build-log artifacts include `make-toolchain-install.log`
and `ccache-stats.txt`, so cache effectiveness can be checked without
inferring it from total job runtime.

Caches can be invalidated by changing the repository variable
`MONO_NIGHTLY_CACHE_EPOCH`, by passing a `cache_epoch` value during manual
dispatch, or by running a manual `cold_build`, which skips cache restore and
save for that run.

## Token And Branch Protection Caveats

The workflow uses `GITHUB_TOKEN` with `contents: write` only in jobs that push
branches. The build job uses read-level permissions and should not be granted
repository write access.

This requires repository Actions workflow permissions to allow read/write
tokens. If `main`, `mono-oss`, or `mono-ask` are branch-protected against direct
or force pushes by GitHub Actions, the atomic publication push will fail. In
those cases, either relax protection for these branches or switch to an
explicit GitHub App/PAT with the required bypass rights.

The workflow intentionally treats nightly builds as integration signals only.
They are not hardware validation and are not release points.
