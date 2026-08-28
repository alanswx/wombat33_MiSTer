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

**RESOLVED on the laptop (2026-08-28, finding 33).** The Sad Mac
`0000000F / 00000033` was NOT FPU OPERR — the `vector − 1` reading was
wrong. The trace showed an explicit `_SysError($33)` = **dsBadSlotInt**:
the DAFB VBL arrived on pseudo-VIA slot bit 5 (empty NuBus slot $E)
instead of bit 6 (internal video) because `nubus_irqs` in `rtl/iosb.sv`
was a 7-bit concat zero-extended. One-bit fix, committed. The boot now
runs past 2.22G cycles into the SCSI boot-device scan ($408D19xx
polling the 53C96). See finding 33 in `SingleStepTests/test-blockers.md`
and the new "not every Sad Mac code is vector−1" section in
`docs/quadra800-rom-notes.md`.

Side discovery recorded in finding 33 for upstream AP68040 work (real
bugs, not this Sad Mac): the core's FSAVE $30/$60 frame payloads sit
one longword low vs the real 040 layout the ROM FPSP addresses, and
both frames write/pop 4 bytes more than their architected sizes.

### Immediate next step

Diskless boot now heads for the flashing-? floppy. The acceptance gate
below is the live target: mount a COPY of the all-in-one bench disk via
`--disk` and walk the 53C96 model through the real boot (its flagged
shaky spots — non-DMA transfers, PDMA byte order — are now actually
exercised by the ROM's scan).

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
