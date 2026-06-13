# SingleStepTests — Status & Blockers (Macintosh Quadra 800 / 68040)

Ported 2026-06-12 from `MacIIvi_MiSTer` (68030) with the FPU material
re-imported from `lbmactwo_MiSTer` (68020) — the Quadra 800's MC68040 has
an on-chip FPU. Lineage: 68020 → 68030 → **68040**. Master plan:
[`QUADRA800_TESTBENCH.md`](../QUADRA800_TESTBENCH.md).

## Hardware bring-up findings (2026-06-13)

First real-Quadra-800 run surfaced two display/IO issues:

1. **Display depth — FIXED.** The Quadra 800 ROM boots the built-in DAFB
   at **640×480 @ 8 bpp (256 colors)**, not the NuBus-era 1 bpp default.
   The bench was painting 1 bit-per-pixel into the 8 bpp framebuffer, so
   each font byte became a single 8 bpp pixel → garbled speckle (confirmed
   by reconstructing a MAME VRAM dump). Fixed: `display_1bpp.c` now has an
   8 bpp paint path (`-DDISPLAY_BPP8`, one byte/pixel, bg `0xFF`/fg `0x00`)
   selected by `VIDEO_VARIANT=dafb` (the default). Verified by host-
   rendering the paint kernel to a legible image. **Requirement: run the
   display at 640×480, 256 colors** (other 256-color resolutions also work
   — the byte stride is read from ScrnRow `$0106` at runtime; only the
   depth is fixed). `dafb1` variant keeps 1 bpp for B&W screens.

2. **Froze at `run=58`, `/Results.jsonl` all-zero — FIX shipped, awaiting
   re-test.** The writer buffers 16 KB batches, so the first `_Write`
   ($A003) fires only when the buffer fills (~line 58 at ~280 B/line) —
   exactly where it froze. Root cause: the 16 KB buffer is filled through
   the 68040 **copyback data cache**, but the Quadra's SCSI does **DMA
   from physical RAM**, so the driver read stale/zero RAM and wedged.
   (`_Write`'s param block is identical to the boot block's `_Read` that
   succeeds, so refnum/drive are fine — it's cache coherency, a 68040-only
   issue the 68020 Mac II never had.) **Fix:** `jsonl_writer.c` now does
   `CPUSHA DC` ($F478) before every `_Write`. If it still fails, boot the
   `quadra800-cpu-nowrite-diag` disk (`-DJW_NO_WRITE`, via `make cpu
   CDEFS=-DJW_NO_WRITE`) to confirm write-vs-CPU-hang, then move the
   results channel to the SCC serial port (polled, no DMA/cache/IRQ).

3. **CACR-write + MOVE16 discriminators wedged the bench at test 191 —
   FIXED (marked hw_unsafe).** With the write fix in place, the CPU run
   reached test 191 = `MOVEC.L D0,CACR; CACR,D1 write all-ones`, which
   RE-ENABLES the 68040 data cache (DE) without a preceding CINV. The
   bench's own next instructions then read stale cache lines → corruption
   → intermittent hang/crash (sometimes a reboot to the Happy Mac). The
   neighboring `CACR write 0` (190) and `MOVE16` (192, also alignment-/
   burst-sensitive) have the same hazard. These three rows now carry
   `hw_unsafe` so the live bench skips them (like STOP/RESET); their MAME
   goldens remain for offline adjudication. General rule: a test that
   writes global CPU state the bench depends on (CACR, VBR, MMU) must be
   `hw_unsafe` unless the runner save/restores that state. (SR-write tests
   are fine — the runner re-masks SR after every test.)

4. **MAME won't boot the SCSI `.hda`** (CPU stays in ROM at `$408046C8`,
   our boot block's screen-wipe never runs) — a MAME `macqd800` boot-
   device quirk; the disk attaches and is read, but the ROM doesn't
   execute the HFS boot block. Real hardware DOES boot it (the bench
   painted characters on Dani's Quadra). So end-to-end boot+results can't
   be MAME-validated; the paint kernel was verified by host render instead.

## What is DONE and VERIFIED (against MAME `macqd800`, 2026-06-12)

- **CPU corpus** captured: 722 rows, `results/cpu/mame_baseline_2026-06-12.json`.
  `make cpu` builds the runner (`-m68040`, 125K payload).
- **MMU corpus** captured: 24 rows with live translation (U/M writeback),
  remap, ATC flush, and format-$7 fault frames (vector 2). `make mmu` builds.
- **FPU corpus** classified execute-vs-trap (270 rows, 142 trap). `make fpu`
  builds; the runner records the taken vector.
- All three payloads link with the Retro68 `m68k-apple-macos-gcc -m68040`.

## MAME 68040 quirks found (silicon adjudicates — flag where it disagrees)

1. **PTEST not implemented.** The single-word 68040 PTEST (`$F548`/`$F568`)
   hits MAME's "unknown PMMU instruction group" default (`m68kmmu.h`) — no
   MMUSR update, no fault. The MMU PTEST rows are placeholders carrying the
   right test bytes; capture real goldens on the Quadra 800.
2. **MMUSR impoverished.** Even via the 030-style two-word PTEST path,
   MAME's 040 MMUSR composition (`m68kmmu.h` ~858) uses a logical-OR, so
   only the R/W bits are meaningful (no physical address, no M/S/G/U).
3. **TC writable mask over-wide.** MAME's 040 stores all 32 TC bits; real
   silicon implements only E (15) + P (14) → reads back `$C000`.
4. **CACR writable mask over-wide.** `MOVEC #$FFFFFFFF,CACR` reads back
   `$FFFFFFF3` in MAME; real 68040 CACR is DE (31) + IE (15) → `$80008000`.
   The CPU corpus row name records the silicon expectation.
5. **CAAR still accepted.** The 68040 removed CAAR; MAME still round-trips
   MOVEC to/from `$802`. Adjudicate on HW.
6. **RTM no-ops.** MAME wires RTM (`$06C0`) into the 030/040 decode as a
   logerror no-op instead of the vector-4 illegal trap. The CPU corpus row
   is named "MAME golden known-bad" — a core that traps RTM correctly will
   FAIL this row against MAME, which is the correct behaviour.
7. **FPU executes everything.** MAME's 68040 executes the transcendentals
   (FSIN/FCOS/…) instead of taking the vector-11 unimplemented-FP trap. So
   MAME is NOT the FPU oracle — `gen_fpu.c` (host IEEE) is, and the TRAP
   rows expect vector 11 from the 68040 manual.

## Open work (hardware-iterated)

- **MMU live/fault runner.** `mmu_bench_main.c` runs the register-mask +
  PFLUSH rows; the live-translation and fault rows are emitted
  `skipped:"live-reloc-todo"`. Port the private-identity-page-table install
  + descriptor/address relocation from `mmu_bench_main.c.68030-reference`
  (it solved the equivalent 030 problem against live ROM low memory).
- **68040 FSAVE/FRESTORE frames.** The carried cpSAVE/cpRESTORE corpus uses
  68881/68882 frame formats. The 68040 frames differ ($00 null / $30 idle /
  $60 busy). Regenerate before using those rows.
- **build_prebuilts.sh** still bundles the `cpu`/`mmu` variants only and
  defaults to the old fixed-stride names; add the `dafb` (auto-stride) and
  `fpu` payloads when packaging release images. `make cpu/fpu/mmu` already
  produce the payloads directly.
- **Musashi** (`~/repos/Musashi`) not checked out — needed only for the
  alternate CPU generator `gen/gen.c` (MAME `macqd800` is the canonical
  CPU oracle). **verilator** not installed — the `fpu/`, `cpu_fpu/`
  verilator harnesses await it plus a 68040 / 68881-fpga-lite DUT.

## Decisions on record

- **FPU = MC68040-lite + FPSP-trap** (Dani, 2026-06-12): the bench expects
  the hardware arithmetic subset to execute and the transcendental/extended
  ops to trap to vector 11. If the FPGA core embeds a full 68882 FPU
  instead, move those opmodes into `HW_OPMODES` (gen_fpu_header.py) /
  the execute lists (gen_fpu.c) to flip the expectation.
- **MAME usage minimal** (Dani, 2026-06-12): capture starting baselines,
  then adjudicate on real Quadra 800 silicon.
