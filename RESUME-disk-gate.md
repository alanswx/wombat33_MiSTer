# Resume prompt — disk-boot gate + Quartus bring-up (laptop)

Paste this file as the opening message of a new session.  Supersedes
`RESUME-machine-bringup.md` Problem 4 (that doc's Problems 1–3 remain
the record for the Sad Mac / SCSI-scan / fastboot work).  Repo on
`main` through `21f37d6` (never pushed).  Environment quirks live in
the `laptop-sim-environment` memory note.  Binding rules unchanged:
ONE Vemu at a time, always the GUI (launch with the Bash sandbox
disabled), commit to main, bench disks run as copies,
`gen/score_vs_oracle.py` is the pass/fail contract (NO `--flat-env`
for full-machine runs).

## Read first

`docs/scsi/README.md` — the research corpus (ROM access patterns =
the chip's contract, QEMU/MAME/NetBSD reference semantics, repo
issue history, the P0/P1 gap analysis).  Everything below was driven
from it.

## Solved this session (each has a commit with the full story)

1. **53C96 P0 rework** (`55df60e` + fill-cap fix): DMA-select CDB
   collection (mixed FIFO+PDMA delivery, empty FIFO at select), all
   DMA data through the 16-byte FIFO (TC0 + DREQ + FIFO=16 burst
   gating), the `$40000`-image PDMA decode + byte lanes in iosb,
   interrupt raise/read race.  Diskless regression intact
   (flashing-? at `$408014CA`, ~369M cycles fastboot).
2. **Hardware-flavor boot block Sad Macs by design** on our machine
   (ROM page tables don't map the DAFB aperture — the stub's screen
   wipe lands on low RAM and kills the DrvQEl it later walks; Sad Mac
   0F/0001).  `docs/tools/make-emulator-gate-disk.sh` re-blesses any
   prebuilt with the emulator-flavor stub (BOOT_SET_DTT0=1) AND
   patches the PAYLDOFF/PAYLCKSZ markers (`rb-cli put --boot` is
   verbatim; an unpatched PAYLDOFF = `_Read` paramErr −50 with
   `$DEADBEEF` as the offset).  **FPGA runs need this image too.**
3. **`SimBlockDevice::BeforeEval(int)` wrapped at 2^31 half-cycles**
   (`e3f37dc`) — the boot guard then disabled the disk forever,
   mid-write, at exactly cycle 2.1476G.  Any long disk-I/O sim run
   ever made hit this (desktop corpus runs included).
4. **PIO data-out never terminated** (`ea7a4e1`): the ROM's
   byte-at-a-time write loop exits on the phase bits flipping to
   STATUS; we never flipped, so one 16KB WRITE(10) at Results.jsonl
   streamed forever (one `cdb 2a` in the log, io_wr lba marching
   1398→16503).  Fixed: the sector flush that exhausts `blocks_left`
   sets `PH_STAT`.
5. **Quartus/MiSTer top wired** (`e25be50`, `45184cf`, `a93c407`):
   see below.
6. Mouse: clicks on the VGA image drive the ADB mouse closed-loop
   against RawMouse (`d2016d2`).  sim_main also gained the [STOP]
   register/DSErrCode/DrvQ dump and RAM watchpoints.

## GATE RESULT — ACCEPTANCE PASSED (pristine ROM confirmed identical)

THE gate ran on BOTH ROMs (fastboot, then the pristine acceptance
run) with identical scores and byte-identical result sizes:

The full chain ran end to end: boot → mount → payload → all FIVE
suites chained → results written (write path live for the first time
ever after `21f37d6`) → bench parked at its DONE point (CPU frozen at
`$400FA` after a clean final ICCS/msgacc — that's completion, not a
hang).  Scored vs the REAL-SILICON oracles
(`results/allinone/*_hardware_quadra800_2026-08-28.jsonl`):

| suite | rows | verdict |
|---|---|---|
| cpu | 717 | **2 REAL diffs** / 13,585 field-groups |
| fpu | 270 | clean |
| saverestore | 8 | clean |
| integration | 1328 | clean |
| mmu_full | 24 | clean (env 25 / frame 2 classified) |

Both cpu diffs are one family — 68040 memory-indirect modes
(`MOVE.L ([bd.W,A6]),D1` and postindexed) take vec 4 on AP68040 where
silicon executes.  CPU-core decode gap → the apolkosnik/finding-31
thread, NOT disk/SCSI.  Scoring recipe: dd the 1 MB at sector 1398 →
`gen/split_allinone_results.py <manifest> <blob> <outdir>` →
`gen/score_vs_oracle.py {suite} <oracle> <split>` (mmu_full scores as
`mmu`; NO `--flat-env`).  Pristine-ROM acceptance was launched at
session end — if it wasn't scored, repeat the recipe on its disk copy.

## The gate run mechanics (for reruns)

Running at session end: fastboot ROM + freshly blessed copy,
monitored.  To reproduce:

```sh
cd verilator
docs/tools/make-emulator-gate-disk.sh \
    ../SingleStepTests/prebuilt/quadra800-allinone.hda-extract  <scratch>/gate.hda
./obj_dir/Vemu +rom=quadra800-fastboot.rom.hex --disk <scratch>/gate.hda \
    --stop-at-pc 4080280e,4080281f          # Sad Mac tripwire, parks RUN
```

Milestones observed so far: scan → mount → driver → boot block →
payload `_Read` noErr → cpu suite executing → **first results write
reached** (that's where fixes 3 and 4 landed).  Still to verify:

- Results actually land at lba 1398+ (`dd if=gate.hda bs=512
  skip=1398 count=8 | strings`).  The zeros puzzle is SOLVED
  (`21f37d6`): `commandArgsPlusMatch` returns "" (never NULL) when
  the plusarg is absent, so the `!ptr` guard in sim_blkdevice.cpp
  discarded EVERY disk write the sim has ever done.  Post-fix runs
  should show jsonl text at 1398; if not, reopen the sbuf/pump
  interplay theory.
- Suites chain (5 of them, manifest in the extract; expected
  `C=862D7F48` on the boot row), then score:
  `gen/score_vs_oracle.py` per suite, NO `--flat-env`.
- THE acceptance gate re-runs all of it on the PRISTINE ROM
  (`+rom=quadra800.rom.hex`), ~4.5 min to SCSI instead of 47 s.
- The write path is byte-at-a-time PIO ($10 per byte, ~366 cyc/byte
  ≈ 6M cycles per 16KB batch) — the driver takes the slow path,
  likely an odd-aligned buffer.  Works, but if gate wall-time hurts,
  finding out why the blind/DMA write path isn't chosen is the lever.

## Debug tooling now in the tree

- **NCR taps** (VERILATOR-gated `$display` in rtl/ncr53c96.sv):
  every command write with full engine state, executed CDBs, INT
  edges, io_rd/io_wr/io_ack edges.  This found bugs 3 and 4 in
  minutes each.  Grep `[NCR`.
- **[STOP] dump** (`--stop-at-pc lo,hi`): D0-7/A0-7, DSErrCode from
  RAM, and a Drive Queue walk.  `--stop-at-pc 4080280e,4080281f` is
  the standing Sad Mac tripwire.
- **RAM watchpoints** in sim_main.cpp (currently `$308/$30C` +
  `$B948-$B95F`): old→new + PC per change.  Retarget by editing
  `watch_addr[]`.
- Units: `[HB] cycle=` and `--max-cycles` count HALF-cycles;
  `dbg_cyc` in NCR taps counts machine cycles (= half/2).  2^31
  half-cycles ≈ 1.07G machine cycles was the old blkdev cliff.
- Run from `verilator/` (ROM hex path is cwd-relative).  A backgrounded
  `cd` does not persist — every launch needs the explicit cd.

## Quartus (fit check wired, not yet compiled)

`wombat33.sv` is the real machine now: RAM 32MB + ROM 1MB in DDR3
behind an ack bridge (posted writes, ROM-write discard, big-endian
lane convention documented in-file); VRAM = **308KB BRAM advertised
as 512KB** (window aliases mod 512K for the size probe; unbacked
308K..512K folds down 204KB so probe readbacks succeed; 308KB per the
MacIIvi_MiSTer 2026-08-10 hardware finding — driver framebuffer base
offset, and 320KB broke their scaler timing).  boot.rom via ioctl;
SCSI disk = OSD `S0` mount; PLL 20→33.33MHz; `rtl/pll.qip` and
ap68040's `primitives/dpram.v` added to files.qip (both were missing
= elaboration failures).  Lints clean under Verilator with stubs
(scratchpad lint/ dir); the 12 warnings are pre-existing ap040_alu
latches (upstream, apolkosnik thread).

To build: open `wombat33.qpf` in Quartus 17.0.2, compile, read the
fitter summary.  Knobs if it fails: VRAM_WORDS (don't grow past
308KB casually — see comment), then the DDR bridge.  On hardware:
pristine 1MB ROM as `boot.rom`, mount a make-emulator-gate-disk.sh
image.  Note the fastboot ROM is sim-only by policy.

**Sim/hardware divergence to remember:** verilator/sim.v still backs
VRAM with a flat 1MB and no fold — mirror the fold into sim.v before
chasing any hardware-only video bug.

## P1 backlog (docs/scsi/rtl-gap-analysis.md has the details)

- Hold-off bus error: a wedged PDMA beat should bus-error after a
  timeout (the blind driver path RELIES on it: ROM handler
  `$408D2606`, IOSB fault regs `$50F18300/$400` unimplemented).  No
  timeout exists in quadra800.sv today — a wedge hangs forever.
- VIA2 IFR bit 0 (DREQ) is edge-follow latched; verify a write-1-to-
  clear can't wedge it low while DRQ is high (ROM polls it live).
- Partial-sector trailing writes flush stale sbuf tail bytes.
- NetBSD-only select variants ($43/$46, seq-step semantics) — only
  if NetBSD boot ever becomes a goal.
