# Resume prompt — wombat33 machine bring-up (AP68040 + Quadra 800 hardware)

Paste this whole file as the opening message of a new session.

---

## Where the project stands (2026-08-28, end of the first machine-RTL day)

The **machine exists and executes the ROM**. `rtl/` now holds the full
first-cut Quadra 800: `wombat_cpu.sv` (AP68040 core+MMU+cache on its
native 32-bit post-cache bus — the 16-bit tg68k shim is NOT used),
`wombat_bus32.sv` (transaction→aligned-beat splitter, big-endian byte
lanes), `quadra800.sv` (boot overlay, decode, walker/CPU arbiter, VGA +
block-device + audio + ps2 surfaces), `iosb.sv` (VIA1 with machine ID
$12, quadra pseudo-VIA, IOSB + djMEMC config regs, Turbo SCSI PDMA, ID
$A55A2BAD, 3-level IPL), `dafb.sv` (640x480 fixed scanout, 1/2/4/8bpp —
**the core's display ceiling is 640x480@256 colors by user decision**),
`rtc3430042.sv`, `asc_wavetable.sv` (boot chime audio), `ncr53c96.sv`
(SCSI + integrated disk target on the MiSTer sd/img interface, ID 0),
`adb.sv` + the lbmactwo via6522 (keyboard/mouse over the ADB modem).
All are in files.qip; wombat33.sv (the Quartus top) still carries the
template — stage 4 wires it.

Boot progress on the Verilator sim (32 MB RAM config): overlay clears at
13k cycles, machine ID matches, RTC bit-bang runs, boot chime plays
(audible — Audio window), the REAL RAM test runs ~100-450M cycles, SCC
init, NuBus slot probes (clean caught berrs at $FnFFFFFC descending).
Last verified milestone before hand-off: a full-length run
(`--max-cycles 4200000000`, screenshots armed) was in flight — check
`scratchpad/boot_full.log` / `verilator/screenshot_f*.png`. The gray
desktop has NOT yet been observed; the run before it (pre-ADB binary)
double-faulted at boot-stack setup only when RAM was 8 MB (fixed by
32 MB — see the hard rules below).

**Two hard-won machine rules (do not relearn):**
- **RAM space never bus-errors.** djMEMC acks its whole DRAM window;
  probes beyond installed RAM read open-bus zeros. A berr there sends
  the ROM to its critical-error path ($4084A60C → death chime → SCC
  serial monitor at $408B9886 polling RR0 forever). QEMU never executes
  $408B98xx on a good boot.
- **Linear RAM must be ≥32 MB** (bank-conf probes land at $01000000+;
  8 MB linear ⇒ MemTop 0 ⇒ double fault). Target configs: 32 and 48 MB.
  Real 8 MB needs bank-conf-driven decode (hardware-core work, later).

**Ground truth technique:** QEMU q800 with device traces
(`--trace 'djmemc_*' --trace 'iosb_*' --trace 'macfb_*'`) is the boot
oracle — its device set is the proven minimum and it DISAGREES with MAME
(djMEMC regs at $5000E000 with readback, IOSB_CONFIG resets to 1, DAFB
VBL status sets regardless of mask, SCC read base $C020). QEMU -m 32
boots this ROM to gray desktop + flashing floppy at 640x480
(`scratchpad/q32.png` was the reference shot).

## THE TASK (unchanged): the acceptance gate

Boot `preboot/supervisor_bench/dist/quadra800-allinone.hda` (run on a
COPY — bench disks are single-use) from the machine's own SCSI via
`--disk <copy>`, watch the boot block's `A/D/E/C/3` rows paint with
`C = 862D7F48`, let the suites chain, extract `/Results.jsonl`, score
with `gen/score_vs_oracle.py` against the silicon captures. The 53C96
model is UNTESTED against the ROM — expect an iteration loop (trace →
fix chip model → rerun). Known-shaky spots are flagged in ncr53c96.sv:
non-DMA data transfers are minimal, PDMA byte order unverified
(MAME's dma16_swap suggests the driver may expect swapped 16-bit reads),
SELECT-with-DMA-CDB unimplemented.

## Verilator sim quick reference

```sh
cd verilator && make            # needs PATH=$HOME/.local/bin for verilator 5.028
./obj_dir/Vemu                  # GUI: Machine panel, Debug log, Audio, VGA
./obj_dir/Vemu --headless --no-cpu-trace --max-cycles N \
    [--screenshot F1,F2] [--stop-at-pc lo,hi] [--trace-after N] [--hist] \
    [--disk path.hda] [+warmstart] [+rom=file.hex]
```
- cpu_trace.log is written headless only (a GUI run once filled the
  disk); `--trace-after` + `--stop-at-pc` carve windows out of long
  boots; heartbeat prints pc/a3/d7 every 10M cycles.
- The per-instruction trace reads the core's `pc_i` via
  `rootp->emu->__PVT__machine__DOT__cpu__DOT__core__DOT__pc_i`;
  memories are `rootp->emu->ram/rom/vram` (verilator public).
- `+warmstart` preloads 'WLSC' at $CFC but does NOT yet skip the RAM
  test (the ROM checks more — second copy lives at MemTop-4).
- Cycle counts in --max-cycles/heartbeats are HALF-cycles (2 per clk).

## Open items, in order

1. **Gray screen**: finish the full-length boot run on the current
   binary; iterate whatever blocks after the slot scan (candidates: ADB
   init handshake, SWIM2 probe, SCC — all currently inert-or-new).
2. **SCSI gate**: --disk boot of the all-in-one copy (see above).
3. **Finding 31 (test-blockers.md): full cpu corpus hangs at results-row
   408**, state-dependent (405-420 slice alone passes; 0..430
   reproduction was in flight — check
   `preboot/sim040/build/run_cpu.log`). Once reproduced, bisect the
   prefix, then trace the hang (tb_corpus dbg_pc heartbeats name it).
   Other suites remain 0 REAL vs silicon.
4. ADB liveness: keyboard/mouse events into the booted machine (adb.sv
   is wired but untested; the GUI already feeds ps2_key/ps2_mouse).
5. Stage 4: wombat33.sv Quartus top — replace the template with
   quadra800 + framework glue (hps_io ioctl ROM download, sd/img block
   device, SDRAM/DDR for RAM+VRAM, ce pacing at 33 MHz).

## Campaign rules that still bind

Commit to `main`, never push; one-line code comments, rationale to
test-blockers.md; corpus files change only with a stated reason;
emulator-validate anything user-facing; bench disks: work on copies;
clean up big sim logs as you go (the disk sits near-full).
`gen/score_vs_oracle.py` remains THE pass/fail contract.
