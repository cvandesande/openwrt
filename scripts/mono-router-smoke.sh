#!/usr/bin/env bash
set -euo pipefail

ROUTER="${1:-root@openwrt}"

ssh "$ROUTER" '
set -eu
echo "== identity =="
uname -a
cat /etc/openwrt_release 2>/dev/null || true

echo "== packages =="
apk list --installed 2>/dev/null | grep -E "ask-cmm|ask-dpa-app|ask-fci|ask-cdx|libfci" || true
opkg list-installed 2>/dev/null | grep -E "ask-cmm|ask-dpa-app|ask-fci|ask-cdx|libfci" || true

echo "== services/modules =="
ls -l /etc/init.d/cdx /etc/init.d/fci /etc/init.d/cmm 2>/dev/null || true
lsmod | grep -E "^(cdx|fci)" || true
pgrep -a cmm || true

echo "== network =="
ip -br link
ip route

echo "== cmm =="
cmm -c "show pppoe" 2>/dev/null || true
cmm -c "query route" 2>/dev/null || true
cmm -c "show connections" 2>/dev/null | sed -n "1,80p" || true

echo "== recent relevant logs =="
logread 2>/dev/null | grep -Ei "ask|cdx|cmm|fci|dpaa|fman|ceetm|error|fail|warn" | tail -80 || true
dmesg 2>/dev/null | grep -Ei "ask|cdx|cmm|fci|dpaa|fman|ceetm|error|fail|warn" | tail -80 || true
'
