# Resume prompt — hardware write-path bisection in flight (2026-08-28 evening)

**LIVE ISSUE:** the new integration/MMU-full builds' SCSI writes fail on
the real Quadra with `ioResult=0000` and rn=0000/dr=0000/base=00000000
painted (writer saw all-zero context) while the SAME images run and
write perfectly under QEMU. Two write-relevant deltas exist vs the
hardware-proven 017acee (-27c) state: HANDOFF_ADDR $50000->$80000 and
the sliced-chunk jsonl writer. Bisection disks are with the user:
`dist/quadra800-srtest-27c-writepath.hda` (BOTH reverted, C=BC01A78F,
should write; then run `cpufpu-27c-writepath`, C=8ECF22F9) plus
single-variable controls `srtest-handoff50000` (C=A40063CB) and
`srtest-oldwriter` (C=05F86D28). All paint rn=/dr=/base= + ioResult on
the DONE screen. Every payload entry + boot stub now honors
`--defsym HANDOFF_ADDR=` (guarded defaults). Whichever variable the
bisection convicts: make its -27c value the default again and record
why $80000 (or the slicer) breaks real hardware — note the all-zeros
anomaly includes `base` (payload .data loaded from disk!), which no
handoff theory alone explains; suspect the diag values themselves or a
partial/incoherent payload load, and compare the painted C against the
expected value per disk.

---

# Previous state — SCSI `_Write`: root cause found and fixed, awaiting the confirming hardware run

Paste this whole file as the opening message of a new session.

---

## Where it stands (2026-08-27, end of session)

The hardware-only SCSI `_Write` failure (Sad Mac `0F/000A` at the first
16 KB flush, ~test 58) is **root-caused and fixed**. Read
`SingleStepTests/test-blockers.md` findings **20 and 21**.

- The F-line shim (finding 20) turned the Sad Mac into a readable
  paint. First hardware boot: `run=58 ok=58 trap=0`, then
  `FLINE OP+PC: FFFF 0000FF44` — a format-2 (unimplemented-FP-shaped)
  vector 11 with the stacked PC in **low RAM**.
- `$FF44` is ROM-boot-heap territory: the SCSI Manager 4.3 keeps its
  write-path RAM glue just below `$10000` — and the boot block's first
  act was `move.l #$10000,%sp`. Its own calls smashed that glue on
  every boot; the first `_Write` then executed the corpse. Hardware
  died (glue ~$BC below the stack top), MAME/QEMU survived (theirs
  sits ~$B38 below — never reached). `_Read` doesn't use the
  structure, which is why only writes failed. (Finding 21.)
- **Fix:** boot stubs no longer touch SP (the ROM's stack is valid);
  the payload stack moved `$100000` → `$80000` (top of our own 256 KB
  read window). Stacks only on RAM we own.

## What to expect from the next hardware boot

Boot `quadra800-cpu` from the 2026-08-27c set (or `dist/`):

| Screen | Meaning |
|---|---|
| `ALL TESTS DONE`, `ioResult=0000`, no shim line | **the expected outcome** — extract `/Results.jsonl`, diff (see below), close the campaign loop |
| `ALL TESTS DONE` + `shim=N op=…` | writes worked and the shim also had to emulate/skip something — note op/pc, still extract + diff |
| `FLINE OP+PC…` halt | a NEW fault; the screen now also paints `FV=`(frame fmt/vec) `FR=` `EA=`, `M-:`/`M+:` instruction bytes around PC, and `RA:` return addresses — one photo identifies it completely |
| Sad Mac | decode via `docs/quadra800-rom-notes.md` (`0F`/ID, ID = vector−1 or a software SysError code) |

Extract + diff:

```sh
rb-cli get IMG@1 /Results.jsonl results.jsonl
# strip NUL padding, drop trap_state rows, add "initial": {} per row, then:
SingleStepTests/gen/cpu_diff_corpus.py SingleStepTests/results/cpu/mame_baseline_2026-06-12.json results.bridged.jsonl
```

Yardstick (MAME-bench vs MAME baseline): 717 written / 696 comparable /
**667 match**; the 29 divergences are known corpus-portability
artifacts (finding 13). A QEMU-bench run scores 610/692 — that's
QEMU-vs-MAME 68040 divergence, not a bench bug.

## Build / verify

```sh
export RETRO68=$HOME/repos/Retro68-build/toolchain
cd SingleStepTests/preboot/supervisor_bench
# hardware images (no DTT0):
make clean && make cpu fpu mmu
./build_cpu_hda.sh ~/testdisk.hda dist/quadra800-cpu.hda   # + _dsk / fpu / mmu variants
# emulator regression first (MANDATORY before handing over a disk):
make clean && make cpu EXTRA_ASFLAGS="--defsym BOOT_SET_DTT0=1"
# ALWAYS make clean (or rm build/boot_stub_patch.*) when switching between
# hardware and emulator flavors: flags are not make dependencies, and the
# build_*_hda.sh scripts re-run make WITHOUT your EXTRA_ASFLAGS.
# MAME needs -seconds_to_run 400 for the full CPU corpus (150 reaches only ~test 460);
# -str auto-saves a final screenshot; -debugger none silently disables -debugscript.
```

## Dead ends — do not repeat

- Raw `CPUSHA`/`PFLUSHA` in our own code (use `_HwPriv` `$A198` sel 1).
- `DTT0` in the boot block on hardware (emulator-only; `BOOT_SET_DTT0`).
- Lowering IPL across `_Write`; removing the VBR bracket or the flush.
- `restore_os_traps()` around `_Write` (no-op: wrong table).
- Patching vector 11 at `$2C` in place (ROM reads it as data → `0F/1B`).
- Boot-block or payload stacks below `$10000` / at `$100000` — the ROM
  boot heap lives there (finding 21).

## Working style

- In-line code comments: one line or less; rationale to
  `test-blockers.md` / commit messages.
- Commit to `main`, never push, no branches.
- Always run a candidate through MAME before handing the user a disk.
