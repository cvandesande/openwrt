### Notable Changes

- Based on the official OpenWrt `v25.12.4` release, with the Mono Gateway DK
  board support and ASK integration stack rebased on top.
- Adds SELinux support to the normal Mono Gateway DK image seed. The image
  includes SELinux, audit tooling, and Mono policy patches, but still boots
  permissive by default while policy coverage is validated.
- Preserves SELinux security labels in the generated ext4 rootfs image when
  security labels are enabled, including boot artifacts added during image
  assembly.
- Includes the current lab-driven SELinux policy allowances for observed Mono
  Gateway paths, including odhcpd/rpcd lease handling, htop sensor/sysfs reads,
  ucode transitions to iproute2 and WireGuard tooling, and selected board
  detection/storage utilities.
- Carries the current ASK dataplane hardening, source pins, CEETM egress
  shaping baseline, and IPv4 tunnel-mode IPsec SEC-offload integration from the
  Mono ASK branch.

### SELinux Scope

SELinux in this release should be treated as policy-validation support, not a
completed enforcing-mode product profile. The default is intentionally
permissive so AVCs can be collected without creating recovery risk during early
router testing.
