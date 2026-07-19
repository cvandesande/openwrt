# Persistent CMM Hardware Upload Shaper

## Purpose

`ask-cmm` provides a persisted OpenWrt control path for the CEETM hardware
egress shaper. It is for upload-side shaping of traffic that uses the NXP fast
path; upstream SQM, CAKE, and qosify do not control those offloaded flows.

The supported control path is:

```text
/etc/config/cmmqos -> /etc/init.d/cmmqos reload -> cmm reload qm-config
                       -> running CMM daemon -> CEETM/QM hardware
```

There is no second daemon or polling process. CMM restores the configured state
when it starts, and the one-shot `cmmqos` init script reloads it after a UCI
change.

## Supported Scope

- One port-shaper section, named `wan` by the shipped configuration.
- A physical CMM/QM port only. For the validated PPPoE-over-VLAN WAN, use
  `eth4`, not `eth4.10` or `pppoe-wan`.
- Fixed CMM CLI channel 1 (FPP/CDX channel index 0). CEETM channels are shared
  across ports; the loader must fail if another port owns that channel rather
  than silently selecting or reassigning a channel.
- Upload-side hardware shaping only. This is not a CAKE/FQ-CoDel equivalent,
  download-side latency control, or a general-purpose QoS framework.

Multi-port configuration, user-selectable channels, and a LuCI frontend are
not part of this validated backend scope.

## Configuration

The package ships a disabled, sysupgrade-preserved configuration:

```uci
config shaper 'wan'
	option enabled '0'
	option device 'eth4'
	option rate '107000'
	option bucketsize '8192'
```

Enable or change it on the router:

```sh
uci set cmmqos.wan.enabled='1'
uci set cmmqos.wan.device='eth4'
uci set cmmqos.wan.rate='107000'
uci set cmmqos.wan.bucketsize='8192'
uci commit cmmqos
/etc/init.d/cmmqos reload
```

The reload assigns channel 1 before enabling QoS and programs the port shaper.
Applying it can briefly disrupt fast-path forwarding and established streams;
use a maintenance window when that disruption matters.

To disable the CMM-managed QoS state:

```sh
uci set cmmqos.wan.enabled='0'
uci commit cmmqos
/etc/init.d/cmmqos reload
```

This is the preferred rollback. Do not restart netifd or repeatedly reload the
network solely to change this shaper.

## Validation and Observability

The implementation is in owned `ask-cmm` commit
`81f1aa40badc7114551d95049907181f45b93ca5`; OpenWrt package
`ask-cmm-17.03.1-r27` pins that revision. The package was built in the normal
`mono-ask-25.12` checkout, installed on the Mono Gateway router, rebooted, and
enabled on `eth4` at 107000 Kbps with an 8192-byte bucket. Router traffic was
confirmed working by the operator.

`cmm -c "query qm interface eth4"` is the direct QM-state diagnostic, but it
can interrupt established streams on this platform. Run it only in an approved
maintenance window; normal traffic validation is the non-disruptive check.

Build or installed-package state alone is not hardware proof. Further changes
to rate, channel ownership, CMM restart behavior, or SELinux mode require
separate validation and should be recorded with their router scope.
