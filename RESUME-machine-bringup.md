# Resume prompt — wombat33 machine bring-up (AP68040 + Quadra 800 hardware)

Paste this whole file as the opening message of a new session.

---

## Where the project stands (2026-08-28, end of the oracle+CPU campaign)

The **CPU question is settled**: AP68040 (`rtl/ap68040` submodule,
github.com/apolkosnik/AP68040 @ 3fed526, GPL-3) scores **0 REAL diffs
against the real Quadra 800 on every suite** — saverestore 8/8, fpu
270/270 (traps exactly where 040-lite silicon traps), integration
1328/1328 (including the emulator-fatal FDBcc tail and the FPIAR
low-16 quirk), mmu 24/24 with live translation (stale-ATC retention,
MMUSR flag ground truth, vec-2 fault recovery). Findings 26–30 in
`SingleStepTests/test-blockers.md` carry the whole trail; RTL results
in `SingleStepTests/results/ap68040/`. The full 722-row cpu corpus run
was in flight at hand-off — check
`SingleStepTests/preboot/sim040/build/run_cpu.log` /
`results_cpu.jsonl`, or just rerun:
`cd SingleStepTests/preboot/sim040 && SIM=verilator ./run_corpus.sh cpu`
(its 10-row smoke was already 0 REAL).

In place and committed:
- **MiSTer core scaffold** from Template_MiSTer: `wombat33.sv` (emu),
  `sys/`, `files.qip` (already pulls `rtl/ap68040/rtl/ap040.qip`),
  qsf/qpf/sdc, GPL-3.
- **GUI Verilator sim** at `/verilator` — the MacLC-style ImGui+SDL2
  framework (`make && ./obj_dir/Vemu`; `--headless --screenshot N
  --stop-at-frame M` for scripted runs). `sim.v` is the simulation
  `emu`; today it wraps the template pattern core and stubs
  `debug_pc/opcode/...` taps for the machine.
- **Batch corpus harness** at `SingleStepTests/preboot/sim040` (flat-RAM
  TB + `SIM=verilator ./run_corpus.sh <suite>`), scored by
  `gen/score_vs_oracle.py` — THE pass/fail contract vs the silicon
  captures (`results/*2026-08-28*`).
- **Boot media**: `preboot/supervisor_bench/dist/quadra800-allinone.hda`
  (silicon-validated all-suite chain disk, expected boot `C = 862D7F48`)
  + per-suite disks; `releases/quadra800.rom` (1 MB, the f1a6f343 image
  everything has run on — if untracked, the user commits it:
  `git add -f releases/quadra800.rom`).

## THE TASK: machine bring-up

Wire AP68040 + the Quadra 800 hardware into the `emu` top and the GUI
sim. **The acceptance test is already built**: this machine must boot
`quadra800-allinone.hda` from its own SCSI and produce a
`/Results.jsonl` that `score_vs_oracle.py` passes against the silicon
captures — the entire oracle campaign becomes the machine's test suite,
long before a System 7 boot is attempted.

### The machine (read `MacQuadra800_HardwareConfig.md` first — it is the map)

Quadra 800 = 68040 @ 33 MHz on a flat 32-bit bus + TWO ASICs:
- **djMEMC** — memory controller + **DAFB II** video (ScrnBase
  `$F9001000`, boots 640×480@8bpp; the benches REQUIRE that mode).
- **IOSB** — everything else: VIA1 + pseudo-VIA, **NCR 53C96** SCSI
  (not the 5380!), SCC, SWIM II floppy, ASC audio, **Cuda** ADB.
- SONIC Ethernet (skip), NuBus (skip initially).
- ROM 1 MB at `$40800000` with reset overlay at 0; RAM from 0.

References, in authority order: the real captures; MAME
`src/mame/apple/{macquadra800,djmemc,iosb,dafb,cuda}.cpp` (~/repos/mame);
QEMU `hw/m68k/q800.c` (~/nextstep-test/qemu-src); the ROM disassembly
notes already in `verilator/sim/` (`quadra800-rom-notes.md`,
`quadra800-rom-disassembly.asm`, `quadra800-scsi-driver-disassembly.asm`,
`quadra800-developer-notes.md`, DAFB/boot behavior in
`docs/` + `QUADRA800_TESTBENCH.md`).

Reuse inventory (adapt, don't fork blindly): `~/repos/MacLC_MiSTer/rtl`
has `via6522.sv`, `scc.v`, `asc.sv`, `adb.sv`, `ps2_kbd/mouse`,
`cuda_maclc.sv` (check Cuda vs Egret fit), swim/floppy;
`~/repos/lbmactwo_MiSTer` the Mac II lineage. NOT reusable as-is: their
`ncr5380` (Quadra needs 53C96), V8/VASP video (Quadra is DAFB), 16-bit
bus glue (Quadra is flat 32-bit — consider AP68040's native port rather
than the tg68k_compat 16-bit shim; the compat top's `busstate` bus is
what the sim TBs speak today, but djMEMC deserves the 32-bit path —
decide early, it shapes everything).

### Staged plan (testbench-first, milestone per stage)

1. **ROM executes**: sim.v `emu` = AP68040 + RAM + ROM (ioctl download
   of `quadra800.rom`, reset overlay) — no devices. Milestone: ROM
   start-up code runs to its first device probe; instruction trace via
   the debug taps + `sim/m68kdasm.c` (the MacLC cpu_trace pattern).
2. **DAFB enough to see**: framebuffer window in the GUI sim (the
   gray screen / Sad Mac / happy Mac ARE the milestones — the ROM
   paints diagnostics before any OS). VIA1/pseudo-VIA timers +
   interrupts as the ROM demands them; Cuda handshake enough for the
   boot to proceed (MAME `cuda.cpp` is the protocol reference).
3. **SCSI 53C96 + sim_blkdevice**: mount `quadra800-allinone.hda` via
   the framework's block device (`sim_blkdevice.cpp`, ported from
   MacLC's SCSI wiring). Milestone: the boot block's `A/D/E/C/3` rows
   paint, `C = 862D7F48`, then the suites chain — extract
   `/Results.jsonl` from the image and score every suite. **This is
   the machine's pass/fail gate.**
4. Keyboard/mouse via Cuda ADB, ASC audio, System 7.x boot, then the
   Quartus build for real MiSTer hardware.

## Know-how (do not relearn)

- **Scoring**: `python3 SingleStepTests/gen/score_vs_oracle.py <suite>
  <silicon capture> <run.jsonl>` — exit 0 = match modulo classified
  classes (layout/reloc/env/frame/golden/fp-policy/fpiar/ccr/aexc,
  all documented in the tool). All-in-one results split with
  `gen/split_allinone_results.py` + the .hda's manifest; boot checksum
  via `gen/boot_cksum.py`.
- **Verilator**: 5.028 in `~/.local/bin` (built from source, with
  iverilog 12 + vasm). Gotchas already paid for: verilator skips
  writing identical outputs (the /verilator Makefile touches VOUT and
  evicts stale user objects — keep that); Verilog unsized literals are
  32-bit (`64'd...` for big constants); `--timing` is on for the GUI
  sim (sim_lfsr.v models the template's free-running lcell ring).
- **sim040 TB facts**: corpus rows that write TC **enable translation**
  — any bare-RTL environment needs the identity world
  (`SIM_MMU_WORLD`, 8K-page tables at RAM top) exactly because the
  Quadra ROM hands off with valid tables (finding 22/30). The cpu
  suite needs a >2G cycle guard (heavy per-row JSON).
- **Emulator debug kit**: QEMU git-master q800 (`-d int -D log` + QMP
  screendump) — the ROM's Sad Mac painter is the `$A05D/408023xx`
  cluster, the real fault is just before it; MAME `macqd800` for
  side-by-side ROM behavior. ROM also in MAME's `roms/macqd800.zip`
  (`f1a6f343.rom`).
- **Campaign rules that still bind**: cache ops in bench code only via
  `_HwPriv` sel 1 on Mac / raw CPUSHA on bare-metal (`AMIGA_BENCH`);
  corpus files change only with a stated reason; one-line code
  comments, rationale to test-blockers.md; commit to `main`, never
  push; emulator-validate anything user-facing before handing it over.
- The bench disks' on-screen contract (per-suite DONE screens, the
  boot `A/D/E/C/3` rows) is documented in
  `preboot/supervisor_bench/dist/README.md` — the GUI sim's screen
  should reproduce it verbatim when the machine is right.

## Quick commands

```sh
# GUI sim (template core today; the machine as it grows):
cd verilator && make && ./obj_dir/Vemu           # or --headless --screenshot N
# CPU-vs-silicon regression (any suite, ~minutes under verilator):
cd SingleStepTests/preboot/sim040 && SIM=verilator ./run_corpus.sh integration
# AP68040's own self-tests (iverilog + vasm):
cd rtl/ap68040/tb && PATH=$HOME/.local/bin:$PATH ./run_tests.sh
# QEMU reference boot of the acceptance disk:
~/nextstep-test/qemu-src/build/qemu-system-m68k -M q800 -m 128 \
  -bios releases/quadra800.rom -display none \
  -drive file=<copy of dist/quadra800-allinone.hda>,format=raw,media=disk,if=none,id=hd0 \
  -device scsi-hd,drive=hd0,scsi-id=0
```
