# Resume prompt — build the all-in-one bench disk; finish analysis + bundles

Paste this whole file as the opening message of a new session.

---

## Where the campaign stands (2026-08-28, end of session)

**Every bench has completed on the real Quadra 800 with results
captured and committed.** CPU (722), FPU (270), MMU-safe (24),
MMU-full (24, live translation), CPU+FPU integration (1328 — first
machine ever to run the corpus tail), FSAVE/FRESTORE (8/8). Raw
captures: `SingleStepTests/results/{cpu,fpu,mmu,cpu_fpu}/hardware*2026-08-28*.jsonl`.
Read `SingleStepTests/test-blockers.md` findings **20–26** for the
full trail. Silicon adjudications on record: undefined CCR bits +
RTM (f22), FSGL*/FINT classification + AEXC/FPIAR/NaN-init MAME gaps
(f22), ROM hands off with TTRs programmed (f22), PFLUSH(An) executes
(f22), FDBcc golden inversion fixed + validated 80/80 by hardware
(f26), FPIAR keeps low 16 bits of an FMOVE.L write (f26), silicon
holds stale ATC entries — MAME's no-ATC model is wrong (f26), MMUSR
ground truth `$58001/$58005` (f26), MOVES user-fc does not trip
S-pages (f26).

**Effective integration scorecard vs corrected goldens: 1136/1328
pass; 176 FINT/FINTRZ vector-11 traps (expected 040 behavior); 16
FPIAR rows (silicon ground truth).**

## PRIMARY TASK: one disk that runs EVERYTHING (no more swapping)

Build a chained all-in-one `.hda`. Design already worked out — follow
it, it keeps every hardware-validated payload essentially byte-intact:

- **Chain-loader, not a mega-payload.** The suites' payloads sum to
  ~315 KB of text+rodata, past the 256 KB read window — do NOT grow
  the window. Instead: one disk carries all payloads at known
  partition offsets; each payload, at its DONE point (replacing the
  final infinite hang), jumps to a small chain stub that `_Read`s the
  next payload over `$40000` and JMPs to it — the boot block's own
  load step, repeated. Cache-flush both sides of that `_Read` via
  `_HwPriv` sel 1 (finding 7; NEVER raw CPUSHA — findings 16/25).
  The chain stub must live OUTSIDE the read window it overwrites
  (e.g. copied to a slot just below `$80000`, or above it in the
  region the stack never reaches) — it cannot run from `$4xxxx`
  while `_Read` replaces `$4xxxx`.
- **Per-payload patch markers**: each payload already carries
  `RJSNLTAG` (results base). Add `NEXTPAYL` (partition offset + length
  of the next payload; zero = last suite, hang with a grand-total
  screen). The build script computes cumulative results offsets so all
  suites append into ONE `/Results.jsonl` with per-suite regions.
- **Results file: preallocate 1 MB** (user approved growing past
  409600). Totals ≈ cpu 205K + fpu 136K + integration 157K + sr 1K +
  mmu-full 25K ≈ 525 KB. Keep `g_results_max_bytes` per suite sized to
  its own region so an overrun cannot cross into the next suite's.
  The all-in-one is `.hda`-only; per-suite floppies stay as they are.
- **Suite ORDER matters for emulator validation:** cpu → fpu →
  saverestore → mmu-full → **integration LAST**, because both
  emulators die in the integration tail (MAME fatal on FDBcc class,
  QEMU core-dump ~row 972 — finding 23). QEMU (the oracle: MAME can't
  host mmu-full either, finding 24) then validates the whole chain
  through suite 4 plus integration rows 1–972; the tail is
  hardware-only, as already established.
- **What carries across chains for free:** handoff at `$80000`
  survives (each entry re-reads it; chain stub must not clobber it);
  each payload re-zeroes its own `.bss` and reinstalls VBR + fline
  shim; the MMU payload keeps its `recovery_mmu.o` linking; every
  bench already restores machine state (MMU regs incl. TTRs) before
  its final flush.
- Validate: QEMU full chain (expect clean DONE screens per suite, one
  combined results file, then the known tail crash in suite 5 with
  rows 1–972 flushed); extract and check per-suite row counts match
  the singles. Then build the hardware flavor (`make clean`, no
  `BOOT_SET_DTT0` — and remember `EXTRA_ASFLAGS` is not a make
  dependency: always `make clean` when switching flavors, finding 23).
  Compute the `C` checksum (host rotating-sum over the PAYLCKSZ
  window; the C row covers payload#1 only — fine) and per-suite
  expected screens for the README.

## Remaining analysis / updates (in rough priority)

1. **Prebuilt refresh**: full bundle set on the current tree (all six
   suites + all-in-one + bootwritetest probe), new `C` table,
   SHA256SUMS, README section; mark the `-28` integration bundles
   superseded (they carry the CACR relic and inverted FDBcc goldens).
2. **MMU diff-tool contract rework** (finding 22): `mmu_diff_corpus.py`
   scores 0/14 for *every* environment (harness-state expectations).
   Give it the finding-13 treatment: separate environment fields from
   CPU behavior; `gen/mmu_live_check.py` (new, working) is the model —
   fold the safe rows into it or fix mmu_diff to match.
3. **CPU corpus portability debt** (finding 13): the 29 known rows
   (absolute `$1800/$1820`, A6-into-Dn, MOVEC harness state) — decide:
   re-express A6-relative or mark platform-local and exclude.
4. **FPU polish**: per-row FPSR clear in the bench so AEXC doesn't
   stick (cleaner rows; MAME's missing AEXC accrual already recorded);
   optionally a small FPIAR probe suite to pin down the low-16
   behavior (word vs long paths, FMOVEM variant).
5. **Docs sweep**: finding 11's leftover "PFLUSHA F-lines on silicon"
   attribution is disproven (f20/f22 TTR adjudication explains the
   emulator behavior; what killed the DTT0-era boot block remains
   formally unresolved — low priority).
6. Then the actual point of it all: **wombat33 RTL bring-up against
   the captured oracle set** (`results/*2026-08-28*` + the corrected
   corpora are the ground truth; `cpu_fpu/cpu_fpu_tests.v` and
   `sim_main.cpp` exist as the Verilator-side start).

## Know-how (hard-won — do not relearn)

- Emulator roles: **QEMU git-master (`~/nextstep-test/qemu-src/build`)
  is the oracle** for MMU/FPU-shaped work; MAME `macqd800` is fine for
  the CPU corpus only (no ATC, no FPIAR, no AEXC, fatal on FDBcc
  class, unhandled-PFLUSHA storms). MAME needs `-seconds_to_run 400`
  for the CPU corpus; `-str` auto-saves a final screenshot;
  `-debugger none` silently disables `-debugscript` (use the default
  debugger; `wpset/bpset` + `logerror` works). QEMU: `-d int,cpu`
  dumps registers per exception; QMP `pmemsave`/`screendump` for
  post-mortems.
- Device results files: strip NULs; CPU-corpus rows need the bridge
  (drop `trap_state` rows, add `"initial": {}`) before
  `cpu_diff_corpus.py`; MAME-bench yardstick 667/696, QEMU-bench
  610/692 (cross-emulator divergence, not a bug).
- Cache rule (findings 16/25): every cache op via `_HwPriv` sel 1
  (`moveq #1,d0; $A198`). Grep any newly imported code for
  `MOVEC`/`CACR` before first hardware run — the 68020 idiom disables
  both 040 caches.
- Memory ownership (findings 21/24): stacks and buffers only on RAM we
  own; boot block inherits the ROM SP; payload SP `$80000`;
  `HANDOFF_ADDR $80000` (guarded, `--defsym`-overridable everywhere);
  `.bss` growth must never cross a fixed-address slot.
- Writes: batches slice to ≤16 KB driver requests (a pre-System
  `_Write` >16 KB Enqueues through uninitialized low-mem, finding 24);
  the fline shim's forwarding table stays (never patch `$2C` in place,
  finding 20).
- Working style: in-line comments one line or less; rationale to
  test-blockers.md/commits; commit to `main`, never push; ALWAYS run a
  candidate through an emulator before handing over a disk; corpus
  files (`gen/*_tests.h`, goldens) only change with a stated reason.

## Build quick-reference

```sh
export RETRO68=$HOME/repos/Retro68-build/toolchain
cd SingleStepTests/preboot/supervisor_bench
make clean && make cpu fpu mmu mmu_full cpu_fpu cpu_fpu_save_restore   # hardware flavor
# emulator flavor: append EXTRA_ASFLAGS="--defsym BOOT_SET_DTT0=1" (make clean first!)
./build_cpu_hda.sh ~/testdisk.hda dist/quadra800-cpu.hda               # per-suite hda builders
MMU_PAYLOAD=build/payload_mmu_full_scsi.bin ./build_mmu_hda.sh ~/testdisk.hda dist/quadra800-mmu-full.hda
python3 gen/mmu_live_check.py results/mmu/mame_baseline_2026-06-12.json <device.jsonl>   # from SingleStepTests/
```
