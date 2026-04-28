# MAYA-W2 Wi-Fi Build Support

This fork has first-pass optional build support for the u-blox M2-MAYA-W271 /
MAYA-W2 Wi-Fi card on Mono Gateway DK.

The support is intentionally limited:

- build-supported only; no MAYA-W2 card has been available for runtime
  validation
- Wi-Fi only
- no Bluetooth enablement
- no 802.15.4, Thread, or Zigbee enablement
- no DTS, power, reset, wake, UART mux, network default, fastpath, ASK, CMM,
  CDX, CEETM, FMAN, or DPAA changes

## Packages

Select these packages explicitly when building an image or test rootfs:

- `CONFIG_PACKAGE_nxp-maya-w2-firmware=y`
- `CONFIG_PACKAGE_kmod-nxp-mxm-wifi=y`
- `CONFIG_PACKAGE_maya-w2-wifi-diag=y`

The Mono Gateway DK seed includes these packages for lab hardware validation
images. Remove them from `config/mono_gateway-dk.seed` for production images
that do not need MAYA-W2 first-card bring-up coverage.

`nxp-maya-w2-firmware` fetches NXP `imx-firmware` during the OpenWrt build and
installs the IW612 SDIO firmware under `/lib/firmware/nxp/`. Firmware blobs are
not committed to this repository.

`kmod-nxp-mxm-wifi` fetches NXP's out-of-tree MXM Wi-Fi driver and builds the
external `mlan.ko` and `moal.ko` modules. It does not replace or modify
OpenWrt's upstream `kmod-mwifiex-*` packages. The packaged module autoloads
`moal` with `mod_para=nxp/wifi_mod_para.conf`, matching the NXP README pattern.

## Pinned Sources

- Firmware: `https://github.com/nxp-imx/imx-firmware.git`,
  `lf-6.12.49_2.2.0` branch tip pinned as
  `8c9b278016c97527b285f2fcbe53c2d428eb171d`
- Driver: `https://github.com/nxp-imx/mwifiex.git`,
  `lf-6.12.49_2.2.0` branch tip pinned as
  `84ca65c9ff935d7f2999af100a82531c22c65234`

## First Hardware Validation

On a router with the card installed, collect non-invasive state first:

```sh
maya-w2-wifi-diag
dmesg | grep -Ei 'moal|mlan|firmware|mmc|sdio|nxp|mwifiex|wlan_sdio'
ls -la /sys/bus/sdio/devices
lsmod | grep -E '^(mlan|moal)'
iw dev
iw phy
find /proc/mwlan /proc/net/mwlan -name info -type f -exec cat {} \; 2>/dev/null
```

Treat any DTS, SDIO power/reset/wake sequencing, or mux requirement as new
hardware evidence to analyze separately before changing target files.

## Board-Level Notes

The Mono hardware documentation lists the u-blox M2-MAYA-W271-00B as a
tri-radio card for the `M2_1` connector. For that connector, Wi-Fi is wired over
1.8 V SDIO, while Bluetooth uses UART and 802.15.4 uses SPI. The same pinout
also lists `M2_3R_RESET` and `M2_3R_nENABLE` as card reset and power-down
signals.

The older vendor OpenWRT-ASK tree was checked for MAYA-W2-specific support. Its
Mono Gateway DK DTS uses the same GPIO hog states that are present here for
`2r-enable`, `3r-enable`, and `uart-mux`. It also documents the UART mux
direction with a comment: `output-high` for `2R`, `output-low` for `3R`, and it
adds an NXP Bluetooth child on `duart1`. It does not add a Wi-Fi SDIO
`mmc-pwrseq-simple` node, a MAYA-specific SDIO child node, or a separate SDIO
host description.

For first-card testing, this means the current image is still best treated as a
package/firmware/driver validation image. If `/sys/bus/sdio/devices` remains
empty with a card fitted in `M2_1`, the next likely investigation is board-level
SDIO enumeration: slot power, `M2_3R_RESET`, `M2_3R_nENABLE`, SDIO muxing, and
whether Linux has visibility of the SDIO host used by the M.2 connector. Do not
flip reset, enable, or mux GPIO polarity without matching schematic or probe
evidence.
