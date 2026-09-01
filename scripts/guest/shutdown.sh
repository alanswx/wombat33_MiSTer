#!/usr/bin/env bash
# shutdown.sh — Special -> Shut Down, from the Finder.
#
# Same job as scripts/mac_shutdown.sh, but it positions the pointer with the
# absolute closed loop in click.sh (pin to the corner, then walk while watching
# the pointer in screenshots) instead of stepping a fixed number of events onto
# the menu bar. The fixed-step version pressed the button between two titles and
# opened nothing, then walked the wrong way looking for a menu.
#
# Shut Down is the LAST item of Special, so the release condition is
# menuitem_probe reporting a highlighted row flush with the panel bottom
# (gap 0-4) -- Restart is the row directly above, so this must be exact.
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 1
. scripts/local.env
WS="python scripts/mister_ws.py --host $MISTER_HOST --delay 0.02"
P=scratch/guest

SPECIAL_X=${SPECIAL_X:-179}
TARGET_Y=${TARGET_Y:-104}   # middle of the Shut Down row
steps() { local n=$1 dx=$2 dy=$3 out=""; while [ "$n" -gt 0 ]; do out="$out mouse:$dx,$dy"; n=$((n-1)); done; echo "$out"; }
log()   { echo "[$(date +%H:%M:%S)] $*"; }

log "positioning on Special (x=$SPECIAL_X)"
bash scripts/guest/click.sh "$SPECIAL_X" 10 move || { log "could not position"; exit 3; }

$WS mousebtn:left_down sleep:0.4 >/dev/null 2>&1
bash scripts/grab_fresh.sh "$P/sd_menu.png" >/dev/null 2>&1
read -r st a b <<<"$(python scripts/menubar_probe.py "$P/sd_menu.png")"
if [ "$st" != "OPEN" ]; then
    log "no menu opened ($st) — releasing, nothing selected"
    $WS $(steps 40 0 -1) mousebtn:left_up >/dev/null 2>&1
    exit 3
fi
TL=${a#x=[}; TL=${TL%%,*}
log "menu open, title left=$TL ($b)"

# The vertical scale while dragging a menu open is much coarser than free
# movement -- measured ~7 px per event here against ~1.5 px in click.sh -- so
# 20 events lands ~140 px down, well BELOW a panel that ends at y~113. Six is
# a real undershoot; the loop closes the rest.
$WS $(steps 6 0 1) >/dev/null 2>&1
seen=0; ok=0
for attempt in $(seq 1 60); do
    bash scripts/grab_fresh.sh "$P/sd_hover.png" >/dev/null 2>&1
    probe=$(python scripts/menuitem_probe.py "$P/sd_hover.png" "$TL")
    # An open menu draws its TITLE inverted in the menu bar, and the probe
    # scores that as a highlighted band at y~0-5 -- reported as a huge gap to
    # the panel bottom, which sent the walk flying past the last row. A real
    # row is always below the 20 px menu bar, so anything above it is the
    # title and means "no row is hovered".
    case "$probe" in
        ITEM*)
            # Do NOT trust panel_bottom / gap here. With Finder windows sitting
            # behind the menu the probe locks onto a window edge instead of the
            # panel (measured panel_bottom=219 against a panel that really ends
            # at 113), so "gap" was reporting the Shut Down row as 108 px short
            # of the bottom and the walk kept stepping away from the very row
            # it was already on. The band itself is reliable, so aim at the row
            # by absolute y: in this 5-item Special menu Shut Down spans
            # roughly y=96..112.
            seen=1
            b=${probe#*band=[}; b=${b%%]*}
            y0=${b%%,*}; y1=${b##*,}
            if [ "$y0" -le "$TARGET_Y" ] && [ "$y1" -ge "$TARGET_Y" ]; then
                log "Shut Down highlighted (band=[$y0,$y1])"; ok=1; break
            fi
            mid=$(( (y0 + y1) / 2 ))
            if [ "$mid" -lt "$TARGET_Y" ]; then
                log "band=[$y0,$y1] above target $TARGET_Y — down 2"; $WS $(steps 2 0 1) >/dev/null 2>&1
            else
                log "band=[$y0,$y1] below target $TARGET_Y — up 2"; $WS $(steps 2 0 -1) >/dev/null 2>&1
            fi ;;
        NOITEM*)
            if [ "$seen" = 1 ]; then log "no row hovered — up 2"; $WS $(steps 2 0 -1) >/dev/null 2>&1
            else log "not in the panel yet — down 2"; $WS $(steps 2 0 1) >/dev/null 2>&1; fi ;;
        *) log "menu vanished ($probe)"; break ;;
    esac
done

if [ "$ok" != 1 ]; then
    log "could not confirm Shut Down — releasing on the title, nothing selected"
    $WS $(steps 60 0 -1) mousebtn:left_up >/dev/null 2>&1
    exit 3
fi

# Released in place. Do NOT nudge first: Restart is the row directly above.
$WS mousebtn:left_up >/dev/null 2>&1
log "released over Shut Down; waiting for the guest to park"
sleep 15
bash scripts/grab_fresh.sh "$P/sd_done.png" >/dev/null 2>&1
log "final shot: $P/sd_done.png"
