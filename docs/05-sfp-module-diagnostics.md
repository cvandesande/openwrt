# SFP Module Diagnostics (i2csfp)

This page documents on-device diagnostics for the two SFP+ cages on the Mono
Gateway (`eth3`/`eth4`). It exists because the usual tools do not work on this
driver stack, and because direct module access is the only visibility into
copper link state when a copper (10GBASE-T) module is fitted.

## Why ethtool Does Not Work Here

The 10G ports are driven by the NXP SDK DPAA stack (`sdk_dpaa`), which does
not implement phylink. Consequences:

- `ethtool -m` (module EEPROM/DDM) reports "Not supported" and always will:
  the kernel serves it through phylink's SFP-bus attachment, which this MAC
  driver never makes. The DTS `sfp = <&sfp_xfi0/1>` handles are not consumed
  by the MAC driver.
- The MACs use `fixed-link`, so `/sys/class/net/eth3|eth4/carrier` is
  **always 1**. The kernel is structurally blind to copper-side link drops
  and retrains.
- `/sys/kernel/debug/sfp-xfi0|1/state` shows `tx_disable: 1` forever. This
  is expected under `fixed-link` and is not a fault.

For MAC/packet-level state use `ip -s link` and the FMan MAC counters. For
module and copper-link state, use `i2csfp` as described below.

## Tools And Bus Map

`i2c-tools` and `i2csfp` ship in the default image
(`config/mono_gateway-dk.seed`). The I2C mux layout on `mono-gateway-dk`:

| Bus | Device |
|-----|--------|
| 4   | DS100DF410 retimer at 0x18 (no driver; runs on power-on defaults) |
| 5/6 | tmp431 temperature sensors |
| 7   | emc2305 fan controller |
| 8   | `sfp-xfi0` cage = `eth3` |
| 9   | `sfp-xfi1` cage = `eth4` |

`i2csfp` accepts the bus as `/dev/i2c-8` / `/dev/i2c-9` (shared access with
the cage driver) or `sfp-X` for exclusive access — if you use the exclusive
form, run `i2csfp sfp-X restore` when done. `i2csfp <bus> listsfps` lists
active cages.

## Module Identification And EEPROM

```sh
i2csfp /dev/i2c-9 eepromdump        # full EEPROM incl. pages at 0x51
i2csfp /dev/i2c-9 i2cdump 0x50      # base identification page only
```

DDM support is advertised at EEPROM byte 92. Note the FS SFP-10GM-T-30
copper module has **no DDM** (byte 92 = 0): there are no
temperature/voltage/power diagnostics to read on that module by any method.

## Copper Module PHY Access (Rollball Protocol)

Copper SFP+ modules contain their own PHY, and under `fixed-link` the real
rate negotiation with the link partner happens entirely inside it. The FS
SFP-10GM-T-30's internal PHY (Marvell Alaska X 10GBASE-T family, ID
`0x002b09ab`) answers only the Rollball MDIO-over-I2C protocol:

```sh
i2csfp /dev/i2c-9 rollball read <devad> <reg>
i2csfp /dev/i2c-9 rollball write <devad> <reg> <value>
```

Plain `c45`/`c22` access at 0x56 returns `0xffff` on this module — only
`rollball` works. The required password is auto-extracted from the EEPROM
(`rbpassword` shows it explicitly).

### Register Quick Reference (Marvell Alaska X)

| Register | Meaning |
|----------|---------|
| `1.1` | PMA status; bit 2 = copper link up |
| `3.0x8008` | Marvell copper status; bit 11 = speed resolved; low nibble `0x0` = 10G, `0x8` = 5G |
| `7.32` | Multi-gig advertisement; bit 12 = 10G, bit 8 = 5G, bit 7 = 2.5G |
| `7.33` | Link-partner abilities |
| `7.0` = `0x3200` | Restart autonegotiation |

### Worked Examples

Watch copper link state at 1 Hz (the only way to see drops/retrains — the
kernel carrier will not move):

```sh
while sleep 1; do
    i2csfp /dev/i2c-9 rollball read 1 1
done
```

Check the trained speed after link-up:

```sh
i2csfp /dev/i2c-9 rollball read 3 0x8008
```

Cap the advertisement to 5G/2.5G (e.g. to hold a stable link over cable not
rated for 10GBASE-T), then restart autoneg:

```sh
i2csfp /dev/i2c-9 rollball write 7 32 0x0181
i2csfp /dev/i2c-9 rollball write 7 0 0x3200
```

Restore the full advertisement (10G/5G/2.5G):

```sh
i2csfp /dev/i2c-9 rollball write 7 32 0x1181
i2csfp /dev/i2c-9 rollball write 7 0 0x3200
```

A helper wrapping the 5G/2.5G cap exists on deployed routers as
`/etc/sfp10g-limit-rate` (router filesystem only, not part of the image).

## Case Study

This tooling exists because of a real incident: a production PPPoE-over-10G
WAN dropped every 1-3 minutes with `No response to 5 echo-requests`. The
copper link to the ONT was retraining ~4 times/minute at 10G over a Cat5e
patch lead (not rated for 10GBASE-T) — each multi-second 10GBASE-T retrain
starved pppd's LCP echoes, and ~7% of received frames failed FCS. None of
this was visible to the kernel: carrier stayed 1 throughout. Watching the
PMA link bit via `rollball read 1 1` diagnosed it in minutes; replacing the
lead with Cat6 fixed it. Prefer checking the trained rate and PMA link
stability with this tooling before suspecting drivers, ports, or modules.
