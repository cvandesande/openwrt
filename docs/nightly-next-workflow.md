# Nightly Next Workflow

The `Nightly Next Branch Build` GitHub Actions workflow keeps automated
tracking branches current without moving validated/public Mono branches. The
`*-next` branches represent the most recent successful build of rebased
validated branches, not merely the most recent successful rebase.

It runs nightly and can also be started manually with `workflow_dispatch`.
Scheduled workflows are loaded from the repository default branch, so changes
to this workflow only affect nightly automation after they are present on the
default branch.

The repository default branch is `mono-ask`, not `main`. That is compatible
with keeping `main` as a pure fast-forward mirror of upstream OpenWrt: the
scheduled workflow definition is loaded from `mono-ask`, while the workflow
updates `main` as data. Workflow changes therefore take effect after they are
manually promoted onto `mono-ask`.

## Branch Policy

The workflow is allowed to update only these branches:

- `main`
- `mono-oss-next`
- `mono-ask-next`

It does not update `mono-oss` or `mono-ask`, does not create nightly tags, and
does not promote nightly results into validated branches.

The branch and build sequence is:

1. Fetch `upstream/main` from `https://github.com/openwrt/openwrt.git`.
2. Fast-forward `main` from `upstream/main` and push `main` to `origin`.
3. Rebuild the local `mono-oss-next` candidate from the current validated
   `mono-oss` tip, then rebase it onto `main`.
4. Rebuild the local `mono-ask-next` candidate from the current validated
   `mono-ask` tip, then rebase it onto the local `mono-oss-next` candidate.
5. Save the prepared candidate refs into a short-lived Git bundle artifact.
6. Build the local `mono-ask-next` candidate in a separate read-only job.
7. Push `mono-oss-next` and `mono-ask-next` with `--force-with-lease` only
   after the `mono-ask-next` build succeeds.

The workflow's `--force-with-lease` push is intentional for the `*-next`
branches because rebasing rewrites those tracking branches. The workflow does
not use it for `main`, `mono-oss`, or `mono-ask`. Manual promotion of a
validated result also uses `--force-with-lease`, but only after human smoke
testing.

Each run starts from the current validated `mono-oss` and `mono-ask` branches.
It does not use the previous `mono-oss-next` or `mono-ask-next` tips as rebase
inputs, so unresolved nightly-only drift is discarded on the next run.

## Conflict Handling

Any failed fast-forward, rebase, build, or publication exits non-zero and fails
the workflow using normal GitHub Actions failure semantics. GitHub Actions
email notifications can therefore be configured through normal repository/user
notification settings.

For rebase conflicts, the helper script prints conflicted paths and writes a
failure section to the workflow summary. The workflow does not try to resolve
conflicts automatically. Rebase failures do not move `mono-oss-next` or
`mono-ask-next`; only `main` may already have moved if its upstream
fast-forward succeeded first.

## Build

After local rebases succeed, the workflow passes the unpushed candidate refs
to the build job through a Git bundle artifact. The build job checks out the
candidate `mono-ask-next` commit from that bundle and runs the normal OpenWrt
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

If that build succeeds, the workflow publishes both `*-next` branches. If the
build fails, the `*-next` branches keep their previous remote values.

Build logs, `.config`, and target output under
`bin/targets/layerscape/armv8_64b/` are uploaded as workflow artifacts.

## Smoke Testing mono-ask-next

The nightly workflow proves that the rebased `mono-ask-next` candidate builds.
It does not prove hardware behavior and must not be treated as validation by
itself.

Use the latest successful `Nightly Next Branch Build` run on the default
branch as the source of truth for a candidate. The run summary records the
`main`, `mono-oss-next`, and `mono-ask-next` SHAs. Download the
`mono-ask-next-firmware` artifact from that same run, and keep the
`mono-ask-next-build-logs` artifact with the test record.

If building locally instead of using the workflow artifact, prefer a detached
checkout of the current remote tracking branch. The `*-next` branches are
automation-owned and rewritten by rebase, so `git pull` on a local
`mono-ask-next` branch can leave confusing ahead/behind state.

```sh
git fetch origin
git switch --detach origin/mono-ask-next

./scripts/feeds update -a
./scripts/feeds install -a
cp config/mono_gateway-dk.seed .config
make defconfig
make download -j"$(nproc)"
make -j"$(nproc)"
```

For a custom local config, copy your config to `.config` in place of the seed
config and still run `make defconfig` before building. If you choose to keep a
named local `mono-ask-next` branch, refresh it explicitly before each local
smoke-test build:

```sh
git fetch origin
git switch mono-ask-next
git reset --hard origin/mono-ask-next
```

`reset --hard` discards uncommitted local changes on that branch. Do not use it
with a dirty worktree.

Before flashing, record the exact candidate and artifact checksum:

```sh
git fetch origin
git rev-parse origin/mono-oss-next
git rev-parse origin/mono-ask-next
find . -name '*mono_gateway-dk*sysupgrade*' -type f -exec sha256sum {} +
```

Flash only a lab or otherwise controlled Mono Gateway first. On the target,
make a config backup before testing the sysupgrade path:

```sh
IMAGE=/tmp/openwrt-layerscape-armv8_64b-mono_gateway-dk-ext4-sysupgrade.bin.gz
sysupgrade -b /tmp/pre-mono-ask-next-backup.tar.gz
sysupgrade "$IMAGE"
```

Use `sysupgrade -n` only when deliberately testing a clean-config boot. The
normal promotion smoke test should exercise the expected upgrade path and known
test configuration.

After boot, the minimum smoke test is:

- Confirm the device boots the tested image and stays reachable over the
  management path.
- Confirm `/etc/openwrt_release`, `uname -a`, and the recorded branch SHA or
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

Record at least the workflow run, candidate SHAs, firmware checksum, device
serial, test configuration, topology, pass/fail result, and any deviations. If
any smoke test fails, do not promote the `*-next` branches.

## Promoting Tested Next Branches

Promotion is manual. The nightly workflow never moves `mono-oss` or
`mono-ask`, never tags nightly runs, and never claims that a successful build is
hardware validation.

Promote only after the matching `mono-ask-next` firmware has passed the smoke
tests above. Promote `mono-oss` first, then `mono-ask`, because
`mono-ask-next` is rebased on top of `mono-oss-next`.

Because the `*-next` branches are rebuilt by rebasing, `mono-oss` is usually
not an ancestor of `mono-oss-next`, and `mono-ask` is usually not an ancestor
of `mono-ask-next`. A fast-forward merge is therefore not the correct
promotion operation for this branch model.

Promotion is a controlled remote branch update from the already tested
`*-next` refs. Run this from a trusted local checkout:

```sh
git fetch origin main mono-oss mono-ask mono-oss-next mono-ask-next

git merge-base --is-ancestor origin/main origin/mono-oss-next
git merge-base --is-ancestor origin/mono-oss-next origin/mono-ask-next

oss_old="$(git rev-parse origin/mono-oss)"
ask_old="$(git rev-parse origin/mono-ask)"

git push --atomic \
  --force-with-lease=refs/heads/mono-oss:"$oss_old" \
  --force-with-lease=refs/heads/mono-ask:"$ask_old" \
  origin \
  origin/mono-oss-next:refs/heads/mono-oss \
  origin/mono-ask-next:refs/heads/mono-ask
```

The ancestry checks ensure the tested `mono-oss-next` contains the current
`main` and that the tested `mono-ask-next` contains the tested `mono-oss-next`.
If either check fails, stop.

The lease values ensure the push updates `mono-oss` and `mono-ask` only if
GitHub still has the exact branch tips you fetched. If someone else updated a
validated branch after your fetch, the push fails instead of overwriting their
work.

After a successful promotion, refresh local branch checkouts if you use them:

```sh
git fetch origin

git switch mono-oss
git reset --hard origin/mono-oss

git switch mono-ask
git reset --hard origin/mono-ask
```

Use `reset --hard` only with a clean worktree. If a local `mono-ask-next` or
`mono-oss-next` branch exists, it must also be explicitly reset to the remote
tracking ref before use, or avoided by using `git switch --detach
origin/mono-ask-next`.

Do not use `git merge --no-ff` to promote a tested next branch unless the
branch model is intentionally being changed from rebase-based history to
merge-based history.

After promotion, trigger a manual `Nightly Next Branch Build` run or wait for
the next scheduled run. The next run should rebuild `mono-oss-next` and
`mono-ask-next` from the newly promoted validated branches.

Create a tag only if you intentionally want to mark a validated release point.
Nightly automation must not create tags, and a tag should refer to the tested
validated branch SHA, not to an untested intermediate result.

If tagging a validated smoke-test point, tag after promotion and tag
`origin/mono-ask`, not `mono-ask-next`:

```sh
git fetch origin mono-ask

sha="$(git rev-parse origin/mono-ask)"
short_sha="$(git rev-parse --short=10 origin/mono-ask)"
tag_name="mono-ask-validated-$(date -u +%Y-%m-%d)-${short_sha}"

git tag -a "$tag_name" "$sha" \
  -m "Validated mono-ask $(date -u +%Y-%m-%d) at ${short_sha}"

git push origin "refs/tags/${tag_name}"
```

Use a date-plus-SHA tag name so more than one validated build can be recorded
on the same day without tag-name collisions. Do not move existing validation
tags; create a new tag for a new validation point.

## Security Model

The workflow separates branch mutation from build execution:

- `prepare-candidates` has `contents: write`; it fetches, rebases, pushes
  `main`, and uploads a short-lived Git bundle containing the unpushed
  candidate refs. It does not run the OpenWrt build.
- `build-candidate` has only read-level permissions; it downloads the bundle
  and runs `feeds`, `defconfig`, `make download`, and `make`. This keeps the
  repository write token out of the job that executes OpenWrt package and build
  logic.
- `publish-next` has `contents: write`; it downloads the already-built bundle
  and publishes `mono-oss-next` and `mono-ask-next`. It does not run the build.

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
- `staging_dir/toolchain-*`

`dl/` uses a loose key based on runner OS/architecture, cache epoch, and feed
configuration, with a restore prefix for the same epoch. This is safe because
OpenWrt verifies downloaded source hashes.

`.ccache` uses a stable compatibility family based on runner OS/architecture,
cache epoch, toolchain tree hash, and generated `.config` hash. The workflow
restores the current UTC week key first, then falls back to the newest cache in
that same compatibility family. It saves a refreshed cache only after a
successful full run, using the current UTC ISO week key.

This creates at most one new `.ccache` cache per compatible
OS/architecture/epoch/toolchain/config family per week. It deliberately does
not include the GitHub run id or run attempt. Because GitHub caches are
immutable, exact hits within the same week are reused but not rewritten; the
cache evolves on the next week boundary or when the compatibility family
changes.

`staging_dir/host`, `staging_dir/hostpkg`, and `staging_dir/toolchain-*` use
tight keys derived from the generated `.config`, relevant OpenWrt source tree
ids, feed revisions where applicable, runner OS/architecture, and cache epoch.
They intentionally do not use broad restore prefixes.

Caches can be invalidated by changing the repository variable
`MONO_NIGHTLY_CACHE_EPOCH`, by passing a `cache_epoch` value during manual
dispatch, or by running a manual `cold_build`, which skips cache restore and
save for that run.

## Token And Branch Protection Caveats

The workflow uses `GITHUB_TOKEN` with `contents: write` only in jobs that push
branches. The build job uses read-level permissions and should not be granted
repository write access.

This requires repository Actions workflow permissions to allow read/write
tokens. If `main` is branch-protected against direct pushes by GitHub Actions,
the fast-forward push to `main` will fail. If `mono-oss-next` or
`mono-ask-next` are protected against force pushes, their publication push will
fail. In those cases, either relax protection for the automation branches or
switch to an explicit GitHub App/PAT with the required bypass rights.

Manual promotion updates `mono-oss` and `mono-ask` with `--force-with-lease`
because the validated branches move to rebased, tested commits. If those
validated branches are protected against force pushes, manual promotion will
fail unless the maintainer has bypass rights, protection is temporarily
relaxed, or the branch model is redesigned to avoid rebased promotion.

The workflow intentionally treats nightly `*-next` builds as integration
signals only. They are not hardware validation and are not release points.
