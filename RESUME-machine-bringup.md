# Resume prompt — wombat33 machine bring-up (laptop, post-Sad-Mac)

Paste this file as the opening message of a new session. Repo state:
clean tree, committed on `main` through `b62e32c` (never pushed).
Environment quirks (GUI launch needs the sandbox disabled, speeds,
qemu/mame paths, no lldb-attach on a running Vemu) live in the
`laptop-sim-environment` memory note. Binding rules unchanged: ONE
Vemu at a time, always the GUI, commit to main, clean big trace logs,
bench disks run as copies, `gen/score_vs_oracle.py` is the pass/fail
contract (`--flat-env` for bare-TB runs only).

## Problem 1 — Sad Mac 0000000F/00000033 at ~2.21G cycles: SOLVED

The hand-off read `$33` as System Error `vector − 1` = vector 52 =
FPU OPERR and queued an FPU exception-delivery hunt.

Tried, in order:
- **Static FPSP analysis** (before tracing): mapped the ROM's FP vector
  installer at `$4088D200` (vector 52 → `$4088D28C`), decoded that
  handler as a compacted Motorola `x_operr` port, fetched fpsp.h
  equates for the frame offsets it reads. Built a whole theory about
  AP68040 FSAVE frames. **The trace refuted the FPU theory outright**
  — no FPSP flow anywhere near the failure.
- **Side discovery kept for upstream (real bugs, wrong culprit)**: the
  AP68040's FSAVE $30/$60 frame payloads sit one longword low vs the
  real 040 layout, both frames write/pop 4 bytes more than architected
  (13/25 longs). Detailed in finding 33's side note in
  `SingleStepTests/test-blockers.md`. Not yet fixed; coordinate with
  apolkosnik (Dani has an active DM thread).
- **`--trace-after` + `--stop-at-pc 4080280e,4080281f`** (the working
  method): the tail showed an explicit `_SysError($33)` =
  **dsBadSlotInt** from the slot-interrupt service at `$4088BC56` —
  NOT a vector-52 exception. See the new "not every Sad Mac code is
  vector−1" section in `docs/quadra800-rom-notes.md`.
- **Root cause & fix** (`rtl/iosb.sv`, commit `0316cb0`):
  `nubus_irqs = {1'b1, ~vbl_irq, 5'b11111}` is a 7-bit concat
  zero-extended to 8, so DAFB VBL landed on bit 5 (= empty NuBus slot
  $E, no handler → SysError 51) instead of bit 6 (= internal video,
  QEMU `VIA2_NUBUS_IRQ_INTVIDEO`). Fix: `6'b111111`. Finding 33.

## Problem 2 — post-fix boot spun forever in the SCSI scan: SOLVED

Boot then sat at `$408D1982-98` polling the 53C96 for 680M+ cycles.
Decoded the loop: `btst #7` of STATUS (reg 4) waiting for INT after a
SELECT. Our `rtl/ncr53c96.sv` raised `irq` on selection timeout but
STATUS bit 7 was hardwired 0 (QEMU esp.c: `STAT_INT 0x80` mirrors into
RSTAT). Fix: bit 7 = `irq` (commit `eb3311f`). Diskless boot now
completes: slot scan → SCSI scan → **flashing-? floppy idle loop at
`$408014CA`, ~2.31G cycles** — first time the machine reached the
correct diskless end state.

## Problem 3 — 4.5-minute boot iterations (RAM test = 70%): SOLVED

- The pre-existing `+warmstart` plusarg (seeds 'WLSC' at `$CFC`) never
  helped: the RAM test has its OWN gate — `cmpi.l #'WLSC',(-4,a6)` at
  `$4084733C`, magic at **table−4 = `$01FFFFA0`**, the stamp a passing
  test leaves at top-of-RAM; zeroed sim RAM is always "cold".
- **Patch-only attempt failed**: NOP the gate branch (file offset
  `$47344`, `6606`→`4E71`) → death chime → SCC monitor at cycle 53M.
  That identified the 40M–80M boot phase as the **ROM checksum**
  (32-bit sum of big-endian words over [4,end), stored at offset 0).
- **Working solution**: patch + checksum fixup =
  `docs/tools/make-fastboot-rom.sh`, `make fastboot`, run with
  `+rom=quadra800-fastboot.rom.hex`. Diskless boot: 2.31G → **420M
  cycles (~47 s), 5.5x**. Full reverse engineering in
  `docs/quadra800-ram-test.md`. Sim-only; pristine ROM for acceptance.

## Problem 4 — the acceptance gate disk boot: NOT STARTED (next step)

Boot a COPY of the all-in-one bench disk via `--disk` (extract fresh
from `SingleStepTests/prebuilt/quadra800-allinone-2026-08-28b.tgz`;
manifest: 5 suites, Results.jsonl at abs offset 715776, expected
`C=862D7F48`). Boot rows `A/D/E/C/3` must paint, suites chain, then
score every suite with `gen/score_vs_oracle.py` (NO `--flat-env`).
Expect a trace→fix loop on the 53C96 data-transfer paths — flagged
shaky in `rtl/ncr53c96.sv`: non-DMA transfers minimal, PDMA byte order
unverified vs MAME dma16_swap, DMA-select CDB unimplemented. Iterate
with the fastboot ROM (47 s/lap); run THE gate on the pristine ROM.

```sh
cd verilator && make fastboot
cp <fresh-extracted>.hda /tmp/gate.hda
./obj_dir/Vemu +rom=quadra800-fastboot.rom.hex --disk /tmp/gate.hda
```
`--stop-at-pc` is now resumable in the GUI (stop parks RUN; re-check
RUN to continue) and flushes cpu_trace.log at the stop.

## Open threads

- Desktop (via screen share) was still grinding the finding-31 full
  cpu corpus rerun at 0.71 Mcyc/s — collect/score it or rerun here
  (this laptop is ~13x faster); update finding 31 either way.
- AP68040 FSAVE frame fix (see Problem 1 side discovery) — upstream
  coordination, then the `saverestore` bench suite becomes meaningful.
- Audio is scope-only (no SDL playback anywhere in sim_audio) — the
  "chime" was always the waveform plot. Optional small feature.
