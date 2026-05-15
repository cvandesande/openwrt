# Mono Release Workflow

The preferred release path is `Cut Mono ASK Release Candidate`. It takes an
official upstream OpenWrt release tag, prepares the three Mono release refs,
builds the candidate firmware, and publishes the successful CI output as a
GitHub pre-release.

The candidate prep step uses the normal branch hierarchy but narrows the replay
ranges for a stable release cut: `main..mono-oss` is replayed onto the official
OpenWrt tag, then `mono-oss..mono-ask` is replayed onto that Mono OSS release
branch. That avoids accidentally carrying unrelated upstream snapshot commits
from `main` into a stable release candidate.

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

The older `Mono ASK Release Build` workflow remains available for rebuilding
and publishing an already cut, annotated Mono ASK release tag. Its first
intended use was:

```text
release_tag:    mono-ask-v25.12.3-r1
version_number: 25.12.3-mono1
version_code:   mono-ask-v25.12.3-r1
```

The release workflows deliberately do not create a full stable release. The
GitHub release is marked as a pre-release and explicitly not marked as
`Latest`, so the firmware can be downloaded and smoke tested on a controlled
Mono Gateway DK first. After hardware smoke validation passes, promote the
GitHub release manually in the GitHub Web UI.

## Security Model

The workflow keeps the same CI/CD safety posture as the nightly next workflow:

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
- Release cutting refuses to overwrite an existing release branch or tag; use
  a new Mono revision such as `r2` instead.
- The release workflow requires `version_code` to match `release_tag`, and the
  image version must match the version embedded in the tag.

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

If the stable release replay conflicts, the workflow stops in the preparation
job before pushing any release branches, tags, or GitHub releases. The failed
job summary lists the conflicted files. Land the minimal compatibility fix on
the appropriate integration branch, usually `mono-oss` or `mono-ask`, then
rerun the release cut with the same upstream tag and the intended Mono revision
if it is still unused.

The preparation script has one narrow built-in resolver for the known
`v25.12.4` image makefile conflict: it preserves upstream's
`traverse_ten64_mtd` device block and inserts the Mono Gateway DK device block
before it. Any other conflict still fails closed.

Build-log artifacts include `make-toolchain-install.log` and
`ccache-stats.txt` so cache effectiveness can be checked separately from total
firmware build time. The `staging_dir/toolchain-*` cache is intentionally
disabled because release-candidate telemetry showed that an Actions cache hit
could still spend tens of minutes in `make toolchain/install`.

Do not promote the release from pre-release to full release until the hardware
smoke-test record confirms boot, management reachability, package/service
presence, route/interface behavior, relevant logs, and any in-scope ASK/CEETM
runtime checks. Build success alone is not hardware validation.
