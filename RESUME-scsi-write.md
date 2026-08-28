# Resume prompt — all-in-one disk HARDWARE-VALIDATED; next: analysis + RTL bring-up

Paste this whole file as the opening message of a new session.

---

## Where the campaign stands (2026-08-28, after the all-in-one session)

**Every bench has completed on the real Quadra 800** (see finding 26;
raw captures `SingleStepTests/results/*/hardware*2026-08-28*.jsonl`).
**The all-in-one chain disk is built and QEMU-validated end to end**
(finding 27): one `.hda` chains cpu → fpu → saverestore → mmu-full →
integration through a `$7C000` chain stub; one 1 MB `/Results.jsonl`
with per-suite regions + `.manifest.json`;
`gen/split_allinone_results.py` extracts, `gen/boot_cksum.py` computes
the boot `C` row. QEMU run: cpu 717 + fpu 270 + sr 8 + mmu-full 25 rows
(counts = the hardware singles, mmu 0 real diffs) + integration rows
1–972 before the known tail crash. Prebuilts refreshed as the
`2026-08-28b` bundle set (7 tgz + SHA256SUMS + READMEs);
`dist/quadra800-allinone.hda`, expected `C = 862D7F48`.

Chain lessons on record (finding 27): finding 24 bites `_Read` too
(slice ≤16 KB at bench time); the saverestore corpus's
`FSAVE/FRESTORE (A0)` rows scribble the `$80000` handoff — the entry
re-plants it from its entry-time copy before every hop.

**HARDWARE-VALIDATED 2026-08-28 (finding 27 close-out):** one boot ran
all five suites; splits in `results/allinone/`. saverestore + mmu-full
byte-identical to the singles; cpu/fpu differ only by constant layout
shifts (+340/+300 on recorded addresses); integration 1328/1328 with
the corrected FDBcc goldens 51/51 and the adjudicated 176 vec-11 + 16
FPIAR fails. Chain `_Read` under the ROM table proven on silicon.

## NEXT TASKS (in order)

1. **MMU diff-tool contract rework** (finding 22): `mmu_diff_corpus.py`
   scores 0/14 everywhere (harness-state expectations). Fold the safe
   rows into `gen/mmu_live_check.py` (the working model) or fix
   mmu_diff to match (finding-13 treatment: split environment fields
   from CPU behavior).
2. **CPU corpus portability debt** (finding 13): 29 rows (absolute
   `$1800/$1820`, A6-into-Dn, MOVEC harness state) — re-express
   A6-relative or mark platform-local and exclude.
3. **FPU polish**: per-row FPSR clear so AEXC doesn't stick; optional
   FPIAR probe suite (word vs long paths, FMOVEM variant) to pin the
   low-16 behavior (finding 26).
4. **Docs sweep**: finding 11's "PFLUSHA F-lines on silicon"
   attribution is disproven (f20/f22); what killed the DTT0-era boot
   block stays formally unresolved — low priority.
5. Then the point of it all: **wombat33 RTL bring-up against the
   captured oracle set** (`results/*2026-08-28*` + corrected corpora;
   `cpu_fpu/cpu_fpu_tests.v` + `sim_main.cpp` are the Verilator start).

## Know-how (do not relearn)

- Emulator roles: **QEMU git-master (`~/nextstep-test/qemu-src/build`)
  is the oracle** (MMU/FPU-shaped work; ROM from MAME's
  `roms/macqd800.zip`, file `f1a6f343.rom`); MAME `macqd800` for the
  CPU corpus only. QEMU runs the whole chain in ~30 s wall clock;
  `-d int -D log` + QMP `screendump` is the debug kit that found every
  chain bug (the ROM Sad Mac painter is the `$A05D`/`408023xx`
  cluster; the real fault is always just before it).
- Flavors: emulator disks need `EXTRA_ASFLAGS="--defsym
  BOOT_SET_DTT0=1"` and it is NOT a make dependency — `make clean`
  when switching (finding 23). `build_allinone_hda.sh` forwards
  EXTRA_ASFLAGS itself.
- Cache ops only via `_HwPriv` sel 1; grep imported code for
  `MOVEC`/`CACR` (finding 25). Stacks/buffers only on RAM we own
  (finding 21); `HANDOFF_ADDR $80000`, `--defsym`-overridable.
- ALL pre-System driver requests ≤16 KB — writes AND reads
  (findings 24/27).
- Bench mains RETURN to the entry shim now (DONE + hang or chain);
  per-suite disks paint an extra DONE row over the "Power off" text —
  cosmetic. The fpu bench's own wipe is 1-bpp sized, so the ROM's gray
  happy-Mac screen stays below row ~128 on its DONE screen —
  pre-existing, cosmetic.
- Working style: one-line comments; rationale to test-blockers.md;
  commit to `main`, never push; run candidates through an emulator
  before handing over a disk; corpus files change only with a stated
  reason.

## Build quick-reference

```sh
export RETRO68=$HOME/repos/Retro68-build/toolchain
cd SingleStepTests/preboot/supervisor_bench
make clean && make cpu fpu mmu mmu_full cpu_fpu cpu_fpu_save_restore   # hardware flavor
./build_allinone_hda.sh ~/testdisk.hda dist/quadra800-allinone.hda     # all-in-one (+manifest)
python3 ../../gen/boot_cksum.py dist/quadra800-allinone.hda            # expected C row
# emulator flavor: make clean first, then EXTRA_ASFLAGS="--defsym BOOT_SET_DTT0=1"
# QEMU: qemu-system-m68k -M q800 -m 128 -bios f1a6f343.rom -display none \
#   -drive file=X.hda,format=raw,media=disk,if=none,id=hd0 -device scsi-hd,drive=hd0,scsi-id=0
python3 gen/split_allinone_results.py <manifest.json> <Results.jsonl> outdir/  # from SingleStepTests/
```
