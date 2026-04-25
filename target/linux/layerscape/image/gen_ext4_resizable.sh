#!/bin/bash
# Creates an ext4 image with resize_inode support and proper GDT reservation
# Usage: gen_ext4_resizable.sh <output> <size_bytes> <blocksize> <source_dir> [reserved_pct]
# Note: Uses mkfs.ext4 -d (e2fsprogs 1.43+) - no root required

set -e

OUTPUT="$1"
SIZE="$2"
BLOCKSIZE="$3"
SOURCE_DIR="$4"
RESERVED_PCT="${5:-0}"

TMPFILE="${OUTPUT}.tmp"

# Calculate actual content size + 50% headroom for filesystem overhead
CONTENT_SIZE=$(du -sb "$SOURCE_DIR" | cut -f1)
INITIAL_SIZE=$(( CONTENT_SIZE * 150 / 100 ))

# Minimum 128MB to ensure proper metadata allocation
MIN_SIZE=$((128 * 1024 * 1024))
if [ "$INITIAL_SIZE" -lt "$MIN_SIZE" ]; then
    INITIAL_SIZE="$MIN_SIZE"
fi

# Round up to 4K boundary
INITIAL_SIZE=$(( (INITIAL_SIZE + 4095) / 4096 * 4096 ))

truncate -s "$INITIAL_SIZE" "$TMPFILE"

# Create ext4 filesystem with:
# - resize_inode: enables online resize
# - resize=32G: reserves GDT blocks for future expansion to 32GB
# - ^has_journal: no journal (saves ~128MB, OpenWRT doesn't need it for rootfs)
fakeroot mkfs.ext4 -F -L rootfs -O resize_inode,^has_journal \
    -E resize=34359738368 \
    -b "$BLOCKSIZE" -m "$RESERVED_PCT" \
    -d "$SOURCE_DIR" \
    "$TMPFILE"

# Shrink filesystem to minimum
e2fsck -fy "$TMPFILE" >/dev/null 2>&1 || true
resize2fs -M "$TMPFILE" >/dev/null 2>&1

# Get actual filesystem size and add padding for kernel.itb (added later by mono-add-kernel)
# Need at least 32MB extra for kernel + headroom
BLOCKS=$(dumpe2fs -h "$TMPFILE" 2>/dev/null | grep "Block count:" | awk '{print $3}')
BLOCK_SIZE_ACTUAL=$(dumpe2fs -h "$TMPFILE" 2>/dev/null | grep "Block size:" | awk '{print $3}')
FS_SIZE=$(( BLOCKS * BLOCK_SIZE_ACTUAL ))
PADDING=$(( FS_SIZE * 5 / 100 ))  # 5% padding
MIN_PADDING=$((32 * 1024 * 1024))  # minimum 32MB for kernel
if [ "$PADDING" -lt "$MIN_PADDING" ]; then
    PADDING="$MIN_PADDING"
fi
FINAL_SIZE=$(( FS_SIZE + PADDING ))

# Truncate file to final size
truncate -s "$FINAL_SIZE" "$TMPFILE"

# Resize filesystem to fill the truncated file
e2fsck -fy "$TMPFILE" >/dev/null 2>&1 || true
resize2fs "$TMPFILE" >/dev/null 2>&1

mv "$TMPFILE" "$OUTPUT"
