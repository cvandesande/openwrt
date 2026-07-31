#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$ROOT/bin/targets/layerscape/armv8_64b"
PROFILE="mono_gateway-dk"
IMAGE=""
STRICT_BIN=0

usage() {
  cat <<'EOF'
Usage: scripts/mono-ipsec-artifact-check.sh [options]

Check that the intended sysupgrade .bin.gz artifact is internally coherent:
compressed file hash, uncompressed hash, profiles.json hash, and sha256sums.

Options:
  --target-dir DIR   Target artifact directory.
  --profile NAME     Profile name fragment. Default: mono_gateway-dk.
  --image PATH       Exact .bin.gz image to check.
  --strict-bin       Also fail if sibling uncompressed .bin is stale.
  -h, --help         Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --image)
      IMAGE="$2"
      shift 2
      ;;
    --strict-bin)
      STRICT_BIN=1
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

if [[ -z "$IMAGE" ]]; then
  mapfile -t images < <(find "$TARGET_DIR" -maxdepth 1 -type f \
    -name "*${PROFILE}*sysupgrade*.bin.gz" -printf '%T@ %p\n' 2>/dev/null |
    sort -nr | awk '{ $1=""; sub(/^ /, ""); print }')
  if [[ ${#images[@]} -eq 0 ]]; then
    echo "No sysupgrade .bin.gz image found for profile fragment '$PROFILE' in $TARGET_DIR" >&2
    exit 1
  fi
  IMAGE="${images[0]}"
fi

if [[ ! -f "$IMAGE" ]]; then
  echo "Image not found: $IMAGE" >&2
  exit 1
fi

TARGET_DIR="$(cd "$(dirname "$IMAGE")" && pwd)"
IMAGE_BASENAME="$(basename "$IMAGE")"
PROFILE_IMAGE_BASENAME="${IMAGE_BASENAME%.gz}"
PROFILES_JSON="$TARGET_DIR/profiles.json"
SHA256SUMS="$TARGET_DIR/sha256sums"
SIBLING_BIN="${IMAGE%.gz}"
fail=0

compressed_sha="$(sha256sum "$IMAGE" | awk '{ print $1 }')"
uncompressed_sha="$(gzip -dc "$IMAGE" | sha256sum | awk '{ print $1 }')"

profiles_sha=""
if [[ -f "$PROFILES_JSON" ]]; then
  profiles_sha="$(python3 - "$PROFILES_JSON" "$PROFILE_IMAGE_BASENAME" "$IMAGE_BASENAME" <<'PY'
import json
import sys

profiles, image_name, compressed_name = sys.argv[1], sys.argv[2], sys.argv[3]
with open(profiles, "r", encoding="utf-8") as f:
    data = json.load(f)

matches = []

def walk(obj):
    if isinstance(obj, dict):
        if obj.get("name") in (image_name, compressed_name) and "sha256" in obj:
            matches.append(obj["sha256"])
        for value in obj.values():
            walk(value)
    elif isinstance(obj, list):
        for value in obj:
            walk(value)

walk(data)
print(matches[0] if matches else "")
PY
)"
fi

sha256sums_entry=""
if [[ -f "$SHA256SUMS" ]]; then
  sha256sums_entry="$(awk -v f="$IMAGE_BASENAME" '{ name=$2; sub(/^\*/, "", name); if (name == f) { print $1; found=1 } } END { if (!found) exit 0 }' "$SHA256SUMS")"
fi

printf 'image=%s\n' "$IMAGE"
printf 'sha256.bin_gz=%s\n' "$compressed_sha"
printf 'sha256.zcat_bin=%s\n' "$uncompressed_sha"

if [[ -n "$profiles_sha" ]]; then
  printf 'profiles.sysupgrade.sha256=%s\n' "$profiles_sha"
  if [[ "$profiles_sha" == "$uncompressed_sha" ]]; then
    echo "profiles_match=YES"
  else
    echo "profiles_match=NO"
    fail=1
  fi
else
  echo "profiles_match=UNKNOWN"
  [[ -f "$PROFILES_JSON" ]] || echo "profiles_json_missing=$PROFILES_JSON"
fi

if [[ -n "$sha256sums_entry" ]]; then
  printf 'sha256sums.bin_gz=%s\n' "$sha256sums_entry"
  if [[ "$sha256sums_entry" == "$compressed_sha" ]]; then
    echo "sha256sums_bin_gz_match=YES"
  else
    echo "sha256sums_bin_gz_match=NO"
    fail=1
  fi
else
  echo "sha256sums_bin_gz_match=UNKNOWN"
  [[ -f "$SHA256SUMS" ]] || echo "sha256sums_missing=$SHA256SUMS"
fi

if [[ -f "$SIBLING_BIN" ]]; then
  sibling_sha="$(sha256sum "$SIBLING_BIN" | awk '{ print $1 }')"
  printf 'sha256.sibling_bin=%s\n' "$sibling_sha"
  if [[ "$sibling_sha" == "$uncompressed_sha" ]]; then
    echo "sibling_bin_matches_gz_payload=YES"
  else
    echo "sibling_bin_matches_gz_payload=NO"
    echo "warning=sibling .bin appears stale relative to .bin.gz payload"
    [[ "$STRICT_BIN" -eq 0 ]] || fail=1
  fi
fi

exit "$fail"
