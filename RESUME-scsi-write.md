# Resume prompt — SCSI `_Write` on the Quadra 800 bench: shim shipped, awaiting hardware

Paste this whole file as the opening message of a new session.

---

## Where it stands (2026-08-27, end of session)

`SingleStepTests` boots a Quadra 800 from an HFS boot block, runs the
722-row 68040 corpus, and writes `/Results.jsonl` back over SCSI.
Everything works on the physical machine except the SCSI `_Write`,
which dies at the first 16 KB flush (~test 58) with Sad Mac
`0000000F 0000000A` = died pre-System, System Error ID 10 = **vector 11,
F-line** — raised while the ROM's own vector table is active (the
bench brackets `_Write` with `use_os_vbr()`).

Read `SingleStepTests/test-blockers.md` **finding 20** first. Summary:

- Traced the write path at instruction level (QEMU `-d in_asm`; log
  position = first-execution order = phase). The write path runs ROM
  `_BlockMove`, whose 68040 form uses `MOVE16` bursts plus a cache
  epilogue: `PTESTR`+`MOVEC MMUSR`+`CPUSHL` loop (<`$C00` bytes) or
  `CPUSHA BC` (bigger), and ~1000 blocks of `$408Dxxxx` SCSI Manager
  code `_Read` never touches.
- **But** the ROM's own boot/mount phase (which the machine survives
  every run) already executes `move16`, `ptestr`, `cpushl` and
  `pflusha` — so the real CPU handles all of those, and finding 11's
  "PFLUSHA F-lines on real silicon" blame is doubtful. The killer is
  write-only: an op in a hardware-only Turbo SCSI branch emulators
  don't steer into, an FPU instruction (no FPSP is loaded pre-System),
  or garbage execution after a pseudo-DMA recovery failure.
- The previously-proposed fix (`restore_os_traps()` + letting IRQs in)
  is ruled out: vectors 32..63 are dormant under the OS VBR, and the
  ROM masks/lowers IPL itself. IPL changes regressed twice.

## What shipped: the F-line shim

`preboot/common/runtime/fline_shim.s` (+ `fline_shim_report.c`),
installed by all three bench mains right after `install_vbr()`. It
builds a private forwarding vector table and repoints `orig_vbr` at it
(so `use_os_vbr()` activates it during I/O brackets); vector 11 goes to
the thunk, every other vector forwards through the LIVE low-mem slot at
exception time. The live table at 0 is never written: patching `$2C` in
place made MAME SysError `dsFSErr` (`0F/1B`) at the 8th flush — ROM
OS-trap code reads that slot as data (finding 20). Thunk behavior:

- `MOVE16 (A0)+,(A1)+` → emulated (4 longs, regs +16)
- CINV/CPUSH `$F4xx`, PFLUSH/PTEST `$F5xx` → skipped (PC += 2); safe
  in composition — a skipped PTESTR's stale MMUSR only feeds CPUSHLs
  that are skipped too
- anything else → **paints `FLINE OP+PC: xxxx xxxxxxxx` at row 40 and
  halts with the screen alive** (no Sad Mac)
- every hit counted; the CPU bench paints
  `shim=NNNNNNNN op=XXXX pc=XXXXXXXX` at row 40 on the DONE screen

Dormant under MAME/QEMU (they execute the full ISA — that is why no
emulator reproduces the failure).

## Next hardware run decides it — outcome matrix

Boot the new CPU disk on the Quadra:

| Screen | Meaning | Next step |
|---|---|---|
| `ALL TESTS DONE`, no shim line | writes just worked | extract + diff, done |
| `ALL TESTS DONE`, `shim=N op=F6xx/F4xx/F5xx` | shim emulated/skipped the culprit | root cause named; done |
| `FLINE OP+PC: xxxx xxxxxxxx` halt | un-emulatable op named | op `F2xx` + PC in ROM → FPU op, machine likely has no working FPU: decide emulate-vs-avoid. PC in RAM/garbage → control-flow corruption in the pseudo-DMA path: chase with BOOT_WRITE_TEST |
| Sad Mac with ID ≠ `0A` | F-line was secondary; new primary surfaced | decode ID (`docs/quadra800-rom-notes.md`), rerun |

Companion diagnostic: `BOOT_WRITE_TEST` (`--defsym BOOT_WRITE_TEST=1`
boot block, commit e565717) runs one `_Write` from the pristine boot
environment — no payload, no shim — separating "the write path is
broken everywhere" from "the payload environment matters".

## Build / verify

```sh
export RETRO68=$HOME/repos/Retro68-build/toolchain
cd SingleStepTests/preboot/supervisor_bench
# hardware image (no DTT0):
make clean && make cpu && ./build_cpu_hda.sh ~/testdisk.hda /tmp/out.hda
# emulator regression first (MANDATORY before handing over a disk):
make cpu EXTRA_ASFLAGS="--defsym BOOT_SET_DTT0=1"   # then build hda, chdman, run MAME
# MAME needs -seconds_to_run 400 for the full corpus (150 only reaches ~test 460)
```

MAME/QEMU must reach `ALL TESTS DONE`, `ioResult=0000`, **no shim
line** (shim must stay dormant), and the extracted `/Results.jsonl`
must diff clean against `results/cpu/mame_baseline_2026-06-12.json`
(717 written / 696 comparable / 667 match / 29 known corpus-portability
divergences).

## Dead ends — do not repeat

- Raw `CPUSHA`/`PFLUSHA` in our own code (use `_HwPriv` `$A198` sel 1).
- `DTT0` in the boot block on hardware (emulator-only; `BOOT_SET_DTT0`).
- Lowering IPL across `_Write` (regressed MAME and hardware).
- Removing the `use_os_vbr` bracket or the cache flush (regress MAME).
- `restore_os_traps()` around `_Write` (no-op: wrong table).
- Patching vector 11 at `$2C` in place (ROM reads it as data -> `0F/1B`).

## Working style

- In-line code comments: one line or less; rationale to
  `test-blockers.md` / commit messages.
- Commit to `main`, never push, no branches.
- Always run a candidate through MAME before handing the user a disk.
