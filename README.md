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
score into the **4.73** range, with the complete AP68040 suite, the Wombat
Verilator model, the first 100 SingleStepTests rows, Quartus timing, and a full
hardware PR run used as the acceptance gate.

The current accepted CPU checkpoint is parent commit `a267903` with AP68040
submodule commit `5aa596f`. Its seed-27 fit uses 40,738/41,910 ALMs and
4,182/4,191 LABs, so resource headroom is now as important as another local
fast path. See
[`docs/PERFORMANCE_MEASUREMENTS.md`](docs/PERFORMANCE_MEASUREMENTS.md) for
measurements and [`CPU_PERFORMANCE_TASKS.md`](CPU_PERFORMANCE_TASKS.md) for the
live, power-loss-safe work queue and exact recovery instructions.

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
