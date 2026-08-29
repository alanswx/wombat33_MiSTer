#!/bin/bash
# make-emulator-gate-disk.sh — turn a hardware-flavor bench .hda into an
# emulator/sim-bootable copy by re-blessing it with an emulator-flavor
# boot block (BOOT_SET_DTT0=1) and re-patching the stub's markers.
#
# Why: the prebuilt bench images carry the HARDWARE boot stub, which
# relies on the real ROM's page tables mapping the DAFB aperture.  Under
# the sim (and MAME/QEMU) those tables do not map it, so the stub's
# screen wipe lands on low RAM, destroys the drive queue, and the boot
# dies with Sad Mac 0F/0001 (see docs/scsi/repo-scsi-issue-history.md
# and the long comment in preboot/common/boot/boot_stub_scsi.s).  The
# payloads and manifest are flavor-independent — only the boot block
# differs — so re-blessing keeps the expected C-row checksum valid.
#
# Usage: make-emulator-gate-disk.sh <in.hda> <out.hda>
# Needs: m68k-elf binutils (Homebrew), rb-cli, jq.
set -euo pipefail

IN="$1"; OUT="$2"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
COMMON="$REPO/SingleStepTests/preboot/common"
RB="${RB:-$HOME/bin/rb-cli}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. assemble the emulator-flavor stub (dafb flags per common.mk)
m68k-elf-as -m68040 --defsym ROW_BYTES=1024 --defsym ROW_BYTES_AUTO=1 \
    --defsym DISPLAY_BPP8=1 --defsym BOOT_SET_DTT0=1 \
    -o "$TMP/stub.o" "$COMMON/boot/boot_stub_scsi.s"
m68k-elf-ld -nostdlib --no-eh-frame-hdr -T "$COMMON/runtime/boot_stub.ld" \
    -o "$TMP/stub.elf" "$TMP/stub.o"
m68k-elf-objcopy -O binary "$TMP/stub.elf" "$TMP/stub.bin"

# 2. fresh copy + verbatim boot-block install
cp -f "$IN" "$OUT"
"$RB" put --boot "$TMP/stub.bin" --quiet "$OUT@1"

# 3. patch the stub's markers (rb-cli put --boot is verbatim; the full
#    build script patches these itself, so we must too).
#    PAYLDOFF -> /Payload's partition-relative offset
#    PAYLCKSZ -> /Payload's allocation-rounded length (the C-row window)
loc=$("$RB" locate "$OUT@1" /Payload)
p_off=$(jq -r '.result.offset - .result.partition_offset' <<<"$loc")
p_len=$(jq -r '.result.length' <<<"$loc")
p_len=$(( (p_len + 511) / 512 * 512 ))

marker=$(grep -obUa "PAYLDOFF" "$OUT" | head -1 | cut -d: -f1)
[[ -n "$marker" ]] || { echo "PAYLDOFF marker not found"; exit 1; }
printf '%08x' "$p_off" | xxd -r -p | dd of="$OUT" bs=1 seek=$((marker + 8))  conv=notrunc 2>/dev/null
printf '%08x' "$p_len" | xxd -r -p | dd of="$OUT" bs=1 seek=$((marker + 20)) conv=notrunc 2>/dev/null

echo "blessed: $OUT  (/Payload rel_off=$p_off cksum_window=$p_len)"
dd if="$OUT" bs=1 skip=$marker count=24 2>/dev/null | xxd
