#!/usr/bin/env bash
# scripts/adb_hw_test.sh — the two ADB regressions, on hardware, as one command.
#
# 1. CLICK. Pin the cursor to the top-left, walk it onto the first desktop icon
#    and send a real mouseBtn press/release. The icon should end up selected
#    (inverted). Before the via6522 shift fix this did nothing at all, because
#    the button is bit 7 of ADB mouse Talk R0 byte 0 and every delivered byte
#    reached the driver shifted one place left -- see docs/adb-via-shift.md.
#
# 2. PHANTOM INPUT. Send 240 mouseMove messages and NOTHING else. That alone
#    used to open menus and fire keyboard shortcuts, because with the byte
#    shifted the guest read bit 6 of dy where the button belonged: any move with
#    dy >= 0 read as button-down. Afterwards the desktop must look untouched.
#
# Shots land in scratch/adbhw_*.png; read them, the script cannot judge for you.
#
# Usage: bash scripts/adb_hw_test.sh [icon_x] [icon_y]     (default 50 45)
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
[ -r scripts/local.env ] && . scripts/local.env
: "${MISTER_HOST:?set MISTER_HOST in scripts/local.env}"

ICON_X=${1:-50}
ICON_Y=${2:-45}

# 0.02 s tracks 1:1; 0.008 s outruns the ~90 Hz ADB poll and moves are dropped.
WS="python scripts/mister_ws.py --host $MISTER_HOST --delay 0.02"

steps() { local n=$1 dx=$2 dy=$3 out=""; while [ "$n" -gt 0 ]; do out="$out mouse:$dx,$dy"; n=$((n-1)); done; echo "$out"; }
shot()  { bash scripts/grab_fresh.sh "scratch/adbhw_$1.png" 2>&1 | tail -1; }

echo "== baseline =="
$WS mouse:1,0 mouse:-1,0 >/dev/null 2>&1     # wake any screensaver
sleep 2; shot 0_baseline

echo "== 1. click on the icon at ($ICON_X,$ICON_Y) =="
$WS $(steps 60 -12 -12) >/dev/null 2>&1                       # pin to (0,0)
$WS $(steps "$ICON_Y" 0 1) $(steps "$ICON_X" 1 0) >/dev/null 2>&1
sleep 1; shot 1_hover
$WS mousebtn:1 mousebtn:0 >/dev/null 2>&1
sleep 1; shot 2_clicked
echo "   -> adbhw_2_clicked.png: the icon must be SELECTED (inverted)."

echo "== 2. 240 mouseMove messages, no button, no keys =="
$WS $(steps 120 1 0) $(steps 120 -1 0) >/dev/null 2>&1
sleep 2; shot 3_afterdrag
echo "   -> adbhw_3_afterdrag.png: no menu open, no dialog, nothing typed."
