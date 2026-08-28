#!/bin/bash
# run_corpus.sh — build the CPU corpus payload, simulate it against the
# AP68040 core with iverilog, extract the JSONL results and score them
# against the Quadra 800 hardware capture.
#
#   AP68040_RTL   path to AP68040's rtl/ (default ~/repos/AP68040/rtl)
#   CDEFS         forwarded to make (e.g. -DLAST_TEST_INDEX=9 for smoke)
#   ORACLE        capture to score against (default the 2026-08-28 cpu one)
set -euo pipefail
cd "$(dirname "$0")"

RTL="${AP68040_RTL:-$(cd ../../.. && pwd)/rtl/ap68040/rtl}"
IVERILOG="${IVERILOG:-$HOME/.local/bin/iverilog}"
VVP="${VVP:-$HOME/.local/bin/vvp}"
ORACLE="${ORACLE:-../../results/cpu/hardware_quadra800_2026-08-28.jsonl}"
WORK=build

[[ -d "$RTL" ]] || { echo "AP68040 rtl not found at $RTL"; exit 1; }
# CDEFS is not a make dependency (the finding-23 footgun): always rebuild
# the corpus-bearing object so a narrowed smoke build cannot go stale.
rm -f "$WORK/bench_main.o"
make payloads CDEFS="${CDEFS:-}"

# hex image: reset vectors @0 (SP=$80000, PC=$40000), payload @$40000
python3 - "$WORK/payload_cpu_sim.bin" "$WORK/corpus.hex" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
if len(data) % 2: data += b"\0"
with open(sys.argv[2], "w") as out:
    out.write("@0\n0008 0000 0004 0000\n")          # SP $80000, PC $40000
    out.write("@20000\n")                            # word address of $40000
    for i in range(0, len(data), 2):
        out.write("%02x%02x\n" % (data[i], data[i+1]))
PY

SRC="$RTL/ap040_tg68k_compat.v $RTL/ap040_core.v $RTL/ap040_bus16_adapter.v \
     $RTL/ap040_bus_timeout.v $RTL/ap040_regfile.v $RTL/ap040_alu.v \
     $RTL/ap040_muldiv.v $RTL/ap040_mmu.v $RTL/ap040_cache.v $RTL/ap040_fpu.v \
     $RTL/ap040_walker_cdc.v $RTL/primitives/dpram.v"

"$IVERILOG" -g2012 -I "$RTL" -o "$WORK/tb_corpus.vvp" tb_corpus.v $SRC
"$VVP" "$WORK/tb_corpus.vvp" +prog="$WORK/corpus.hex" \
       +results="$WORK/results.bin" | tee "$WORK/run.log"
grep -q "CORPUS DONE" "$WORK/run.log" || { echo "simulation did not finish"; exit 1; }

python3 - "$WORK/results.bin" "$WORK/results.jsonl" <<'PY'
import sys
raw = open(sys.argv[1], "rb").read().replace(b"\0", b"")
rows = [l for l in raw.split(b"\n") if l[:1] == b"{"]
open(sys.argv[2], "wb").write(b"\n".join(rows) + (b"\n" if rows else b""))
print(f"{len(rows)} result rows")
PY

python3 ../../gen/score_vs_oracle.py cpu "$ORACLE" "$WORK/results.jsonl"
