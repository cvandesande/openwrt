# Build Commands

Local build recipes for this fork. The rules that govern *when* to build —
in particular that builds are user-driven and must be asked for — live in
`AGENTS.md` under Build Discipline.

## Normal firmware build

```sh
./scripts/feeds update -a
./scripts/feeds install -a
cp config/mono_gateway-dk.seed .config
make defconfig
make download -j"$(nproc)"
make -j"$(nproc)"
```

Use parallel builds for normal work:

```sh
make -j"$(nproc)" target/linux/compile
```

Use `-j1 V=s` only when readable failure logs are needed.

## Focused package builds

```sh
make -j1 package/kernel/ask-cdx/compile V=s
make -j1 package/network/ask-cmm/compile V=s
make -j1 package/kernel/ask-fci/compile V=s
make -j1 package/libs/libfci/compile V=s
```

## After `make dirclean`

**Never jump straight to `make -jN package/X/compile` after a `dirclean`.** It
races: host cmake packages configure before ninja is staged, autoreconf host
packages (musl-fts, audit) stamp `.configured` without generating a Makefile,
and the target toolchain never gets built. The poisoned stamps persist across
retries — the fix is `rm -rf build_dir/hostpkg staging_dir/hostpkg`.

Correct sequence:

```sh
make -j"$(nproc)" tools/install
make -j"$(nproc)" toolchain/install
make -j1 package/<path>/compile V=s
```

`make world` sequences this itself.

`dirclean` preserves `.config`, `dl/`, and installed feeds; it removes
`build_dir`, `tmp`, and the staging toolchain.

## Cross-compiling a package for the router

Enable it in `.config`, then:

```sh
make defconfig
make package/<path>/{clean,compile}
```

The `kmod-openvswitch-*` recursive-dependency warnings from `defconfig` are
pre-existing and harmless. Transfer the result with `ssh root@host 'cat > f'`
(there is no sftp-server on the router) and install with
`apk add --allow-untrusted`; its repo-index wget failures are harmless.

## Vendor package pin validation

When owned vendor package pins change, validate hashes:

```sh
scripts/mono-check-vendor-hashes.sh --no-clean \
  package/kernel/ask-cdx package/network/ask-cmm \
  package/kernel/ask-fci package/libs/libfci
```

## Verifying what a build produced

Embedded timestamps are pinned for reproducibility and `BUILD_ID` is inherited
from the upstream base, so neither indicates freshness. Verify by content:
`apk list -I`, `PKG_RELEASE`, `lsmod`, sha256.

A kmod package owns its `CONFIG_` symbol, so setting that symbol `=y` in a
target config is silently downgraded to `=m`: the `.ko` builds but is never
packaged unless `CONFIG_PACKAGE_kmod-<name>=y` selects the package. Verify
kmods by manifest and rootfs, not by the kernel `.config`.
