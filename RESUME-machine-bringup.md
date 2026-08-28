# Resume prompt — wombat33 machine bring-up (moved to the laptop)

Paste this whole file as the opening message of a new session on the
laptop. Repo state: everything is committed on `main` through
`930a9c9` ("Interactive-first sim"); the working tree was clean at
hand-off.

## Working rules (Dani, 2026-08-28 — binding)

- **ALWAYS run the machine sim (Vemu) interactively** — the GUI, never
  headless. Debug flags work in the GUI: `--trace-after N` turns the
  trace file on, a `--stop-at-pc lo,hi` hit pauses the sim in the UI
  (RUN unchecks) with registers live in the Machine panel. The batch
  sim040 corpus testbench (Vtb_corpus) has no GUI and stays batch.
- **Only ONE simulation at a time.** Sequence runs; don't stack
  background sims (and don't leave a GUI instance running forgotten).
- Clean up big sim logs as you go — cpu_trace.log runs grow to GBs.

## What the laptop needs

- This repo with the `rtl/ap68040` submodule (@ 3fed526) and
  `releases/quadra800.rom` (tracked). MacLC/lbmactwo checkouts are NOT
  needed — via6522/adb/framework files are copied into `rtl/` and
  `verilator/sim/`.
- Verilator **5.028 built from source** (was in `~/.local/bin`; apt's is
  too old), SDL2 dev libs, xxd. `cd verilator && PATH=$HOME/.local/bin:$PATH make`
  builds Vemu and generates `quadra800.rom.hex`.
- For oracle work (strongly recommended): QEMU git-master q800 (was at
  `~/nextstep-test/qemu-src`) and the MAME source tree (`~/repos/mame`)
  — see the memory notes `qemu-device-trace-oracle` /
  `qemu-q800-oracle`. Update those paths if they differ on the laptop.

## Where things stand (2026-08-28 evening)

The machine RTL is live end to end: AP68040 on its native 32-bit bus,
djMEMC (overlay, open-bus DRAM window, config regs), IOSB (VIA1 +
machine ID $12, pseudo-VIA, Turbo SCSI PDMA, ID reg), DAFB (640x480,
max 8bpp — the core's ceiling by decision), RTC, EASC wavetable (chime
is audible in the GUI Audio window), NCR 53C96 + disk target
(`--disk <image>` mounts on SCSI ID 0 — **untested** against the ROM),
ADB keyboard/mouse (lbmactwo lineage — untested). 32 MB RAM config
(target configs 32/48 MB; 8 MB double-faults — see rules below).

**The boot now runs ~2G cycles and paints a SAD MAC through our DAFB**
— the first real image from the machine (`verilator/screenshot_f2800.png`
at hand-off). Codes: `0000000F / 00000033`. Per
`docs/quadra800-rom-notes.md` ("The Sad Mac path"): $0F = died before
the System loaded; the second line is DSErrCode = **vector − 1**, so
$33 = vector 52 = **FPU OPERR**. An FP operand-error exception ends the
boot after the NuBus slot scan. Suspects, in order: (a) the AP68040
FPU's arithmetic-exception delivery firing despite FPCR enables being
clear (the fpu corpus passed 270/270, but through the FSAVE/pending
paths of the bench, not necessarily this shape); (b) an earlier stubbed
device feeding garbage into an FP calculation that then legitimately...
no — OPERR with exceptions disabled must NOT trap, so (a)-shaped
delivery is the prime suspect regardless of operands.

### Immediate next step (was about to run)

One interactive run:
```sh
cd verilator && PATH=$HOME/.local/bin:$PATH make
./obj_dir/Vemu --stop-at-pc 4080280e,4080281f
```
Watch the boot (chime ~1 min in sim-minutes, long RAM test, slot-scan
berrs at $FnFFFFFC are NORMAL). The sim pauses itself at the Sad Mac
entry with D6/D7 live in the Machine panel; the `[STOP] pc=.. at cycle
C` line names the cycle. Then a second interactive run
`./obj_dir/Vemu --trace-after <C-2000000> --stop-at-pc 4080280e,4080281f`
gives a cpu_trace.log window ending at the failure — the vector-52
dispatch and the FP instruction before it will be in the tail. Fix in
`rtl/ap68040/rtl/ap040_fpu.v` / `ap040_core.v` FPU-pending plumbing (a
submodule change — coordinate before touching; an iosb/machine-side fix
is preferable if the trace shows garbage operands instead).

### Also in flight at hand-off

`SingleStepTests/preboot/sim040`: the FULL 722-row cpu corpus
(finding 31) was re-running with a fresh forced rebuild
(`SIM=verilator MAXCYCLES=4000000000 CDEFS="-DLAST_TEST_INDEX=721"
./run_corpus.sh cpu`), at 1.68G cycles at hand-off. Evidence so far:
the hand-off-era build products were slow AND hung at results-row 408;
a fresh 0..430 build runs 6x faster, sails past that row, and scores
**427 rows, 0 REAL** with the new `--flat-env` scorer flag
(finding 32: 7 env-read rows classify as `envread` in the bare TB;
machine acceptance scoring stays strict). If the full run wasn't
finished/collected before the move: rerun the command above on the
laptop (~30-60 min) and score; expected 0 REAL. Update finding 31
either way.

## The acceptance gate (unchanged)

Boot a COPY of
`SingleStepTests/preboot/supervisor_bench/dist/quadra800-allinone.hda`
via `./obj_dir/Vemu --disk <copy>`, boot rows `A/D/E/C/3` paint with
`C = 862D7F48`, suites chain, extract `/Results.jsonl`, score every
suite with `gen/score_vs_oracle.py` (NO --flat-env there). The 53C96
model's shaky spots are flagged in `rtl/ncr53c96.sv` (non-DMA data
transfers minimal, PDMA byte order unverified vs MAME's dma16_swap,
DMA-select CDB unimplemented) — expect a trace→fix loop after the Sad
Mac is cleared.

## Machine rules learned the hard way (do not relearn)

- RAM space NEVER bus-errors: djMEMC acks its whole DRAM window;
  beyond installed RAM reads open-bus zeros. A berr there = the ROM's
  critical-error path (death chime → SCC monitor at $408B9886).
- Linear RAM ≥ 32 MB (bank probes land at $01000000+; 8 MB ⇒ MemTop 0
  ⇒ double fault at boot-stack setup). Real 8 MB needs bank-conf
  address decode — hardware-core work, later.
- NuBus slot probes EXPECT berr — keep it for empty spaces.
- QEMU q800 `--trace 'djmemc_*' --trace 'iosb_*' --trace 'macfb_*'` is
  the boot ground truth; QEMU `-m 32` reaches gray desktop + flashing
  floppy at 640x480 with this ROM. MAME's models differ in load-bearing
  ways (documented in the memory notes).

## Campaign rules that still bind

Commit to `main`, never push; one-line code comments, rationale to
`SingleStepTests/test-blockers.md` (findings run through 32);
corpus files change only with a stated reason; bench disks are
single-use — always run on copies; `gen/score_vs_oracle.py` remains THE
pass/fail contract (`--flat-env` for bare-TB runs ONLY).
