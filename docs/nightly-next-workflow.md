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
5. Build the local `mono-ask-next` candidate.
6. Push `mono-oss-next` and `mono-ask-next` with `--force-with-lease` only
   after the `mono-ask-next` build succeeds.

The `--force-with-lease` push is intentional for the `*-next` branches because
rebasing rewrites those tracking branches. It is not used for `main`, and it is
never used for `mono-oss` or `mono-ask`.

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

After local rebases succeed, the workflow stays on the unpushed
`mono-ask-next` candidate and runs the normal OpenWrt build flow:

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

If that build succeeds, the workflow publishes both `*-next` branches. If the
build fails, the `*-next` branches keep their previous remote values.

Build logs, `.config`, and target output under
`bin/targets/layerscape/armv8_64b/` are uploaded as workflow artifacts.

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

The workflow uses `GITHUB_TOKEN` with `contents: write` because the same job
pushes `main` before the build and publishes `*-next` after a successful build.

This requires repository Actions workflow permissions to allow read/write
tokens. If `main` is branch-protected against direct pushes by GitHub Actions,
the fast-forward push to `main` will fail. If `mono-oss-next` or
`mono-ask-next` are protected against force pushes, their publication push will
fail. In those cases, either relax protection for the automation branches or
switch to an explicit GitHub App/PAT with the required bypass rights.

The workflow intentionally treats nightly `*-next` builds as integration
signals only. They are not hardware validation and are not release points.
