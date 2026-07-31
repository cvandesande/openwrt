#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="root@openwrt"
SSH_CONFIG="/dev/null"
REDACT=0
FULL=0

usage() {
  cat <<'EOF'
Usage: scripts/mono-ipsec-hw-snapshot.sh [options]

Collect a read-only IPsec hardware/offload snapshot from the router.
Output includes raw sections plus machine-readable lines:
  counter name=value

Options:
  --host HOST        SSH host. Default: root@openwrt.
  --ssh-config FILE  SSH config file. Default: /dev/null.
  --full             Include larger connection dumps.
  --redact           Redact IPs, MACs, SPIs, and handles in output.
  -h, --help         Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    --ssh-config)
      SSH_CONFIG="$2"
      shift 2
      ;;
    --full)
      FULL=1
      shift
      ;;
    --redact)
      REDACT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

collect() {
  ssh -F "$SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=10 "$HOST" \
    "FULL=$FULL sh -s" <<'REMOTE'
set +e

section() {
  printf '\n### %s\n' "$*"
}

run() {
  section "$*"
  "$@" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || echo "status=$rc"
}

cmm_cmd() {
  section "cmm -c \"$1\""
  cmm -c "$1" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || echo "status=$rc"
}

counter() {
  echo "counter $1=$2"
}

count_dmesg() {
  name="$1"
  pattern="$2"
  value="$(dmesg 2>/dev/null | grep -ciE "$pattern")"
  counter "dmesg.$name" "${value:-0}"
}

section meta
date -Iseconds 2>/dev/null || date
uname -a

section board
ubus call system board 2>/dev/null || true

section packages
opkg list-installed 2>/dev/null | grep -Ei 'ask-cmm|ask-cdx|ask-fci|libfci|strongswan|ip-full|ip-tiny|tcpdump|ethtool|ripgrep|coreutils-timeout' || true

section processes
ps w 2>/dev/null | grep -E '[c]mm|[c]haron|[s]wanctl' || true

section xfrm
if command -v ip >/dev/null 2>&1; then
  ip xfrm state 2>&1 || true
  ip -s xfrm state 2>&1 || true
  ip xfrm policy 2>&1 || true
  ip -s xfrm policy 2>&1 || true
else
  echo "ip command not available"
fi

section swanctl
swanctl --list-sas 2>&1 || true
swanctl --list-pols 2>&1 || true

section cmm
cmm_cmd "query sa"
cmm_cmd "show stat ipsec query"
cmm_cmd "query qmsecrate stats"
cmm_cmd "query secfailstats"
if [ "${FULL:-0}" = "1" ]; then
  cmm_cmd "query connections"
else
  section "cmm show connections ipsec-filtered"
  cmm -c "show connections" 2>&1 | grep -Ei 'ipsec|sagd|sa handle|sa_handle|fEntry.*SA|handle' || true
fi

section ethtool-ipsec-counters
if command -v ethtool >/dev/null 2>&1; then
  for path in /sys/class/net/*; do
    dev="${path##*/}"
    case "$dev" in
      eth*|pppoe*|br-*|wan*|lan*)
        ethtool -S "$dev" 2>/dev/null |
        awk -v dev="$dev" '
          BEGIN { printed = 0 }
          /ipsec|toenc|todec|caam|sec|bpderr|drop|err|compat/ {
            printed = 1
            line = $0
            print line
            key = $1
            gsub(/:/, "", key)
            val = $NF
            if (val ~ /^-?[0-9]+$/) {
              clean = key
              gsub(/[^A-Za-z0-9_.-]/, "_", clean)
              printf "counter ethtool.%s.%s=%s\n", dev, clean, val
            }
          }
          END {
            if (!printed)
              printf "# %s: no matching ethtool counters\n", dev
          }
        '
        ;;
    esac
  done
else
  echo "ethtool not available"
fi

section bman-bpid35
bman_file="/sys/kernel/debug/bman/query_bp_state"
if [ -r "$bman_file" ]; then
  block="$(sed -n '32,38p' "$bman_file" 2>/dev/null)"
  printf '%s\n' "$block"
  free="$(printf '%s\n' "$block" | awk '/free_buffers_avail/ { print $NF; exit }')"
  depleted="$(printf '%s\n' "$block" | awk '/bp_depleted/ { print $NF; exit }')"
  case "$free" in
    yes) counter "bman.bpid35.free_buffers_avail" 1 ;;
    no) counter "bman.bpid35.free_buffers_avail" 0 ;;
  esac
  case "$depleted" in
    yes) counter "bman.bpid35.depleted" 1 ;;
    no) counter "bman.bpid35.depleted" 0 ;;
  esac
else
  echo "bman debugfs state not readable"
fi

section xfrm-stat
cat /proc/net/xfrm_stat 2>/dev/null || true

section hardware-error-counts
count_dmesg "IPSEC_COMPAT" 'IPSEC_COMPAT'
count_dmesg "status_50000008" '50000008'
count_dmesg "compound_ext_copy_failed" 'compound-ext-copy-failed'
count_dmesg "unwrap_failed" 'unwrap-failed'
count_dmesg "bpderr_drop" 'bpderr-drop'
count_dmesg "enobufs" 'ENOBUFS|err=-105'
count_dmesg "caam_sec_errors" 'caam|sec|qman|bman|fsl_dpa'

section dmesg-filtered-tail
dmesg 2>/dev/null | grep -Ei 'IPSEC_COMPAT|ASK-IPSEC|bpderr|50000008|compound-ext-copy-failed|unwrap-failed|ENOBUFS|err=-105|caam|sec|qman|bman|fsl_dpa|oops|panic|unable to handle|segfault' | tail -n 160 || true

section logread-filtered-tail
logread 2>/dev/null | grep -Ei 'IPSEC_COMPAT|ASK-IPSEC|bpderr|50000008|compound-ext-copy-failed|unwrap-failed|ENOBUFS|err=-105|caam|sec|qman|bman|fsl_dpa|cmm|cdx|ipsec|xfrm|oops|panic|segfault' | tail -n 160 || true
REMOTE
}

if [[ "$REDACT" -eq 1 ]]; then
  collect | "$ROOT/scripts/mono-redact-lab-output.sh"
else
  collect
fi
