# Scoped CodeQL Analysis

This OpenWrt tree uses CodeQL as an owned-code and owned-integration signal, not
as a claim that the whole OpenWrt tree has been security reviewed.

## Scope

The default script scope is:

- `package/kernel/ask-cdx`
- `package/kernel/ask-fci`
- `package/libs/libfci`
- `package/network/ask-cmm`

These cover the OpenWrt package integration points for the owned ASK/CDX/CMM
and FCI source repos. `fci.git` is intentionally represented by two OpenWrt
packages: `ask-fci` for the kernel module and `libfci` for the userspace
library.

The optional kernel-patch scope covers the ASK interaction patches under
`target/linux/layerscape/patches-6.12/720-724`. CodeQL analyzes the patched
kernel source after OpenWrt applies those patches; it does not analyze the
patch files directly.

The filtered kernel SARIF also includes the copied SDK DPAA/FMAN kernel source
under `target/linux/layerscape/files/drivers/net/ethernet/freescale/`, because
patch `720` is the OpenWrt integration point that makes those kernel drivers
part of the Layerscape build.

## Requirements

- CodeQL CLI at `~/codeql/codeql`, or pass `--codeql PATH`.
- A configured OpenWrt tree with `openwrt/.config`.
- C/C++ CodeQL query packs available locally, or allow download with
  `--download-queries`.

The installed CLI may include the C/C++ extractor without the C/C++ query pack.
If analysis cannot resolve queries, rerun with `--download-queries` or pass an
explicit local query suite with `--query`.

## Commands

Run the default scoped package analysis from the OpenWrt tree:

```sh
scripts/codeql-openwrt-scoped.sh --download-queries
```

Analyze a single package with serial OpenWrt build output:

```sh
scripts/codeql-openwrt-scoped.sh --package ask-cdx --jobs 1 --download-queries
```

Include the ASK kernel patch surface:

```sh
scripts/codeql-openwrt-scoped.sh --with-kernel-patches --download-queries
```

When package and kernel scopes are both enabled, the script runs the kernel
patch analysis first. That keeps the `target/linux/clean` step from invalidating
kernel-module package outputs created later in the run.

Regenerate SARIF from existing databases:

```sh
scripts/codeql-openwrt-scoped.sh --analyze-only --download-queries
```

## Outputs

Databases are written below:

```text
codeql-db/
```

SARIF results are written below:

```text
codeql-results/
```

Package analysis writes one SARIF file per package:

```text
codeql-results/ask-cdx-openwrt.sarif
codeql-results/ask-fci-openwrt.sarif
codeql-results/libfci-openwrt.sarif
codeql-results/ask-cmm-openwrt.sarif
```

Kernel-patch analysis writes both the full kernel compile result and a filtered
result whose primary locations match files touched by the ASK kernel patch set
or by the SDK DPAA/FMAN kernel source integrated by that patch set:

```text
codeql-results/kernel-ask-patches.full.sarif
codeql-results/kernel-ask-patches.sarif
codeql-results/kernel-ask-patches.files
```

## Interpretation

Treat these SARIF files as static-analysis findings for scoped ASK integration
surfaces. They do not prove hardware offload behavior, boot safety, runtime
correctness, or whole-firmware security.
