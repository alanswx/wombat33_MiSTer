# wombat33_MiSTer — Macintosh Quadra 800 (MC68040)

A MiSTer FPGA core for the Apple **Macintosh Quadra 800** (codename
*Wombat*): MC68040 @ 33 MHz, djMEMC memory controller with integrated
DAFB II built-in video, IOSB I/O. The repository holds the RTL core
(`wombat33.sv` + `rtl/`), the Verilator testbench it is brought up
against (`verilator/`), and the **verification testbench suite**
(`SingleStepTests/`) that gates the CPU against MAME and real hardware.

## Building & deploying

**Read [`BUILD.md`](BUILD.md)** — the scripted CLI flow (Quartus compile,
status summary, push-and-launch on a MiSTer, screenshot grabs).

```sh
bash scripts/setup_env.sh           # once per machine: creates scripts/local.env
bash scripts/build_only.sh --check  # ~4 min Analysis & Synthesis sanity check
bash scripts/build_only.sh          # full compile -> output_files/wombat33.rbf
bash scripts/deploy_screenshot.sh   # push + seed boot.rom/SCSI mount + launch
```

The core mounts its boot ROM from `games/Wombat33/boot.rom` and its main
SCSI disk from OSD slot `S0`; `BUILD.md` covers seeding both.

## Performance work

The memory path now measures **52.4 MB/s** for sequential integrated reads and
**304 ns** for a 16-byte fill, putting bandwidth inside the real Quadra 800's
50--65 MB/s range. CPU-side work has since raised the Speedometer 3.23 CPU PR
score to **5.195**, with the complete AP68040 suite, the Wombat Verilator
model, the first 100 SingleStepTests rows, Quartus timing, and a full hardware
PR run used as the acceptance gate.

The current accepted RTL checkpoint is parent commit `f846901` with AP68040
submodule commit `8951fd2`. Moving the two-read-port FPU register bank into
mirrored MLABs, then replacing the DAFB palette's unintended 6,144-register
read mirror with explicit M10K views, and finally consolidating DAFB's 17
timing words in one MLAB, created the room needed for CPU work. Decode-time
operand selection for `CMP.L Dn,Dn` then cut the timing-clean fit further,
from 40,738 to 36,446 ALMs and from 4,182 to 4,063 of 4,191 LABs. That leaves
128 LABs free for CPU fast paths and later pipelining. The accepted front end
now retires a resident queued opcode directly into decode, consumes resident
immediate words there when bus ownership is unambiguous, and dispatches a
resident DBcc target without the generic refill boundary. Together these steps
cut the focused loop by 24.02% and the first-100 differential corpus by 6.62%.
A one-longword sequential I-cache lookahead now serves the next instruction
directly when it is in the same 16-byte cache line. It covers 64.48% of dynamic
dispatches in the measured Speedometer CPU interval and raises the hardware CPU
benchmark average from 13.230 to **13.588** (+2.71%). The final seed-32 fit uses
37,357 ALMs and 4,152 LABs (39 free), closes every timing domain with +0.115 ns
worst setup and +0.213 ns worst hold slack, and raises controlled hardware CPU
PR from 5.133 to **5.195** (+1.21%). See
[`docs/PERFORMANCE_MEASUREMENTS.md`](docs/PERFORMANCE_MEASUREMENTS.md) for
measurements and [`CPU_PERFORMANCE_TASKS.md`](CPU_PERFORMANCE_TASKS.md) for the
live, power-loss-safe work queue and exact recovery instructions.

A subsequent one-entry `ADD.L Dn,Dn` predecode experiment was timing-clean and
cut the focused synthetic loop by another 8.06%, but improved the controlled
hardware CPU average by only 0.18% while consuming 271 ALMs and 23 LABs. It is
preserved for analysis but rejected. Profiling the real Speedometer interval led
instead to the accepted I-cache lookahead above. The next active target is the
remaining data-side `S_MRD`/`S_MWR` occupancy: measure internal cache-hit delay
separately from external SDRAM misses, then prototype a bounded D-cache
request/lookup overlap without weakening registered bus completion or precise
fault behavior.

## Testbench (`SingleStepTests/`)

Per-instruction CPU / FPU / MMU benches captured against MAME's
`macquadra800` driver as the oracle, designed to also run on real Quadra
800 hardware (boot the payload, collect `/Results.jsonl`, diff offline).
Lineage: ported from the 68020 Mac II bench (`../lbmactwo_MiSTer`) via the
68030 Macintosh IIvi bench (`../MacIIvi_MiSTer`), with the FPU material
re-imported (the 040 has an on-chip FPU).

**Read [`QUADRA800_TESTBENCH.md`](QUADRA800_TESTBENCH.md) first** — the
master plan, with the verified machine facts, the 040-lite FPU
execute-vs-trap model, the 68040 MMU corpus design, and the hardware
campaign. Status & quirks: [`SingleStepTests/test-blockers.md`](SingleStepTests/test-blockers.md).

### Quick start

```sh
# Build the bootable bench payloads (Retro68 toolchain, -m68040):
cd SingleStepTests/preboot/supervisor_bench
make cpu        # 68040 integer corpus  (722 rows)
make fpu        # 68040 FPU corpus       (execute-vs-trap, vector 11)
make mmu        # 68040 MMU corpus       (MOVEC regs, live walk, format-$7)

# Re-capture the MAME baselines (needs ~/repos/mame built with the driver):
cd ~/repos/mame
./mame macqd800 -skip_gameinfo -nothrottle -video none -sound none \
   -seconds_to_run 200 -autoboot_delay 1 \
   -autoboot_script <repo>/SingleStepTests/gen/mame_cpu_capture.lua

# Diff a hardware run against the baseline:
SingleStepTests/gen/cpu_diff_corpus.py \
   SingleStepTests/results/cpu/mame_baseline_2026-06-12.json /path/to/Results.jsonl
```

### What's verified (2026-06-12)

- CPU + MMU corpora captured from MAME `macqd800`; all three payloads build.
- MMU bench exercises live 68040 translation (U/M writeback), remap, ATC
  flush, and format-$7 access faults (vector 2).
- FPU bench distinguishes the 040 hardware subset (executes) from the
  unimplemented ops (vector-11 trap) — the FPGA-lite-FPU discriminator.

Display uses the built-in DAFB at `$F9000000`, 1 bpp, with the row stride
read from the ROM's `ScrnRow`/`ScrnBase` globals at runtime (the correct
Quadra 800 built-in mechanism — the stride is software-programmed).
