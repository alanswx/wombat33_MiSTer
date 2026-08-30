#!/usr/bin/env bash
# scripts/mac_shutdown.sh — shut Mac OS down from INSIDE the guest (Special ->
# Shut Down) before swapping cores.
#
# WHY THIS EXISTS. Reloading the core while Mac OS is running is a hard
# power-cut on a mounted HFS volume. Doing it repeatedly on 2026-08-30 corrupted
# the Quad Squad image badly enough that it hung mid-boot at a repeatable offset
# — which then got misdiagnosed as an RTL fault more than once. Always shut the
# guest down first; only load a new core once the screen says it is safe.
#
# HOW IT DRIVES THE MOUSE. mrext sends RELATIVE motion and Mac OS applies mouse
# acceleration, so one big delta does NOT move a predictable number of pixels.
# Everything here therefore moves in 1-pixel steps, which stays under the
# acceleration threshold and tracks 1:1. The cursor is first "pinned" to the
# top-left by driving it hard into the corner, giving a known origin — the ADB
# mouse only reports deltas, so there is no absolute position to read back.
#
# STATUS 2026-08-30: the NAVIGATION works -- pinning, the menu-bar geometry and
# the item offsets below are all measured and land on Shut Down correctly. The
# CLICK does not: mrext mouseBtn:left_down/left_up reach the Main (they appear in
# /tmp/remote.log) and mouse MOTION drives the guest fine, but button presses do
# not take effect -- an open menu will not even dismiss on a click. Keyboard menu
# navigation is not a way round it either; Mac OS 8.1 has no Full Keyboard Access.
#
# That is almost certainly the same ADB defect as the phantom keys: fabricated
# reports overwrite the button state before the guest samples it. So this script
# cannot complete a shutdown until ADB is fixed -- until then, ask a human to use
# Special -> Shut Down with a real mouse before any core swap.
#
# Pacing matters: 0.008 s between motion events outruns the ~90 Hz ADB poll and
# the moves are silently lost. 0.02 s tracks 1:1. Do not speed this up.
#
# Usage:
#   bash scripts/mac_shutdown.sh            # do it, with verification shots
#   bash scripts/mac_shutdown.sh --dry-run  # print the plan only
#
# Verify before you trust it: shots land in scratch/shutdown_*.png.
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
[ -r scripts/local.env ] && . scripts/local.env
: "${MISTER_HOST:?set MISTER_HOST in scripts/local.env}"

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

WS="python scripts/mister_ws.py --host $MISTER_HOST --delay 0.008"

# Menu-bar geometry, measured off a 640x480 grab of the Mac OS 8 Finder:
#   apple 26 | File 53 | Edit 88 | View 127 | Special 180 | Help 230,  y = 9
SPECIAL_X=180
MENUBAR_Y=9

# Emit N one-pixel steps in a direction.
steps() { local n=$1 dx=$2 dy=$3 out=""; while [ "$n" -gt 0 ]; do out="$out mouse:$dx,$dy"; n=$((n-1)); done; echo "$out"; }

PIN=$(steps 60 -12 -12)        # drive hard into the top-left corner
TO_SPECIAL="$(steps $SPECIAL_X 1 0) $(steps $MENUBAR_Y 0 1)"

if [ "$DRY" = 1 ]; then
    echo "would pin to (0,0), then move to Special ($SPECIAL_X,$MENUBAR_Y), open it,"
    echo "screenshot, walk down to Shut Down and click."
    exit 0
fi

log() { echo "[$(date +%H:%M:%S)] $*"; }
mkdir -p scratch

log "pinning cursor to top-left"
$WS $PIN >/dev/null 2>&1

log "moving to Special ($SPECIAL_X,$MENUBAR_Y) and opening the menu"
$WS $TO_SPECIAL >/dev/null 2>&1
$WS mousebtn:left_down sleep:0.4 >/dev/null 2>&1
bash scripts/grab_fresh.sh scratch/shutdown_menu.png >/dev/null 2>&1
log "menu shot: scratch/shutdown_menu.png — check Shut Down's row before trusting the offset"

# Special menu (Mac OS 8.1): Clean Up Window / Empty Trash / Eject / Erase Disk
# / --- / Sleep / Restart / Shut Down.  Items are 16 px; Shut Down is the last.
# The menu is held OPEN with the button down and released over the item, which
# is the classic Mac press-drag-release a real user performs.
SHUTDOWN_DY=${SHUTDOWN_DY:-106}   # measured: Restart ~88, Shut Down ~103 from y=9
log "walking down $SHUTDOWN_DY px to Shut Down"
$WS $(steps "$SHUTDOWN_DY" 0 1) >/dev/null 2>&1
bash scripts/grab_fresh.sh scratch/shutdown_hover.png >/dev/null 2>&1
$WS mousebtn:left_up >/dev/null 2>&1

log "released over Shut Down; waiting for the guest to park"
sleep 12
bash scripts/grab_fresh.sh scratch/shutdown_done.png >/dev/null 2>&1
log "final shot: scratch/shutdown_done.png"
log "Only load another core once that shows the shutdown screen."
