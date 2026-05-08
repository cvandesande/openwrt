# Mono Release Workflow

The `Mono ASK Release Build` workflow builds an already cut, annotated Mono ASK
release tag and publishes the successful CI output as a GitHub pre-release.
The first intended use is:

```text
release_tag:    mono-ask-v25.12.3-r1
version_number: 25.12.3-mono1
version_code:   mono-ask-v25.12.3-r1
```

The workflow deliberately does not create a full stable release. The GitHub
release is marked as a pre-release and explicitly not marked as `Latest`, so
the firmware can be downloaded and smoke tested on a controlled Mono Gateway DK
first. After hardware smoke validation passes, run `Promote Mono ASK Release`
with the same tag to clear the pre-release flag and mark it as `Latest`.

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
- The release workflow requires `version_code` to match `release_tag`, and the
  image version must match the version embedded in the tag.

## Validation

The build job verifies:

- the input is an annotated `mono-ask-*` tag,
- the checked-out commit matches the tag target,
- Mono vendor source hashes match the checked-in package hashes,
- restored cache state is reported in the GitHub step summary,
- `make toolchain/install` accepts or rebuilds the restored toolchain before
  the firmware build,
- `make download` and the full firmware build complete,
- output filenames use the `mono-openwrt-<version>` prefix,
- `config.buildinfo`, `profiles.json`, `/etc/openwrt_release`,
  `/usr/lib/os-release`, and `/etc/openwrt_version` report the expected Mono
  release identity.

Build-log artifacts include `make-toolchain-install.log` and
`ccache-stats.txt` so cache effectiveness can be checked separately from total
firmware build time.

Do not promote the release from pre-release to full release until the hardware
smoke-test record confirms boot, management reachability, package/service
presence, route/interface behavior, relevant logs, and any in-scope ASK/CEETM
runtime checks. Build success alone is not hardware validation.
