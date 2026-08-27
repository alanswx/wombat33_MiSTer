# SingleStepTests — Status & Blockers (Macintosh Quadra 800 / 68040)

Ported 2026-06-12 from `MacIIvi_MiSTer` (68030) with the FPU material
re-imported from `lbmactwo_MiSTer` (68020) — the Quadra 800's MC68040 has
an on-chip FPU. Lineage: 68020 → 68030 → **68040**. Master plan:
[`QUADRA800_TESTBENCH.md`](../QUADRA800_TESTBENCH.md).

## Hardware bring-up findings (2026-08-26)

7. **Boot block loaded the payload through the 68040 caches with no
   coherency — the "mostly doesn't reach the bench" bug. FIXED.**
   Reported symptom on the physical Quadra 800: the bench almost never
   started, and only very occasionally got as far as painting.

   `common/boot/boot_stub_scsi.s` reads 256 KB of payload to `$40000`
   with a single `_Read` and then `JMP`s into it, with no cache
   management at all. On the 68020 (Mac II) and 68030 (IIvi) that was
   safe — 256-byte, write-through caches. On the 68040 it is not:

   - dirty lines in the 4 KB **copyback** data cache, left over from the
     ROM's own boot-time use of low RAM, are written back **on top of**
     the payload the SCSI transfer just delivered; and
   - stale lines in the 4 KB instruction cache are executed instead of
     the bytes that actually arrived.

   Both are non-deterministic — whether the damage lands on code that
   matters or on padding depends on what the ROM happened to touch —
   which is exactly why it presented as "works one boot in twenty".

   **Fix:** `CPUSHA BC` ($F4F8) + `NOP` on **both** sides of the
   `_Read`. `CPUSHA` (push *and* invalidate) rather than `CINVA`
   (invalidate only) deliberately: post-transfer, a driver that copies
   through the CPU instead of DMAing leaves the payload dirty in the
   D-cache, and `CINVA` would discard it. Applied to all three boot
   stubs (`boot_stub_scsi.s`, `boot_stub_floppy.s`,
   `boot_stub_scsi_fixed_offset.s`) so the hazard can't return through
   another make target. This is the read-side twin of finding 2's
   `CPUSHA DC` fix for `_Write`.

8. **Boot-block diagnostics were painting 1 bpp on an 8 bpp screen —
   FIXED.** Finding 1 fixed the *C* paint kernel for the Quadra's
   640x480x8bpp DAFB, but the **assembly** painters were missed: the
   boot block's readouts (drive number, driver refnum, `_Read`
   ioResult) and `payload_entry_cpu.s`'s "CPU BENCH" banner still wrote
   one byte per *eight* pixels, so they rendered as unreadable speckle.
   That is why the whole bring-up has been blind at exactly the stage
   that was failing. Both now paint one byte per pixel and read the row
   stride from `ScrnRow` ($0106) at runtime. `common/make/common.mk`
   translates each `-DFOO` in `CDEFS_VIDEO` into `--defsym FOO=1` so the
   display variant reaches gas as well as the C compiler — the root
   cause of the two halves drifting apart.

9. **Boot block now paints a payload checksum ('C' row).** A rotating
   32-bit sum over the region HFS allocated to `/Payload`, computed
   straight after the transfer and before anything else touches RAM, so
   a corrupted load is visible on screen instead of being inferred from
   a crash. The window length is patched per image via a `PAYLCKSZ`
   marker (same mechanism as `PAYLDOFF`) set to
   `results_offset - payload_offset` — a fixed window would have covered
   `/Results.jsonl` on the FPU and MMU disks, whose payloads are only
   32 KB / 27 KB, and the checksum would then change every run.
   Expected values per image are tabulated in `prebuilt/README.md`.

10. **Latent: `HANDOFF_ADDR` ($50000) sits inside the Quadra payload.**
    The boot block writes `(refnum, drive)` there *after* loading the
    payload, and the Quadra 800 CPU-bench payload spans
    `$40000..$5E8C0` — so those 4 bytes land 64 KB into the image. They
    currently fall in a zero gap in the captured corpus, so it is
    harmless **today**, but any change to payload layout turns it into
    silent corruption. Not moved yet because the address is duplicated
    across seven files (every bench's `payload_entry*.s` reads it as a
    hard-coded literal) and a boot block and payload that disagree hand
    the bench a garbage refnum. `$00080000` — the first byte past the
    256 KB read window — is the right value; change all seven in one
    commit. `--defsym HANDOFF_ADDR=...` exists to rebuild a boot block
    against an already-built payload meanwhile.

### Offline verification harness (new)

Findings 7-9 were validated without hardware and without MAME (the local
MAME binary has no Apple drivers built in): the assembled boot block is
executed under **Musashi** against a simulated Quadra 800 low memory +
DAFB framebuffer, and the resulting framebuffer is rendered to a PNG.
That confirmed the painted screen is legible at both 8 bpp/stride 1024
and 1 bpp/stride 80, that the handoff slot receives `FFDF 0003`, and
that the 68k checksum routine reproduces the host-computed value for all
eight shipped images. The homebrew `m68k-elf-binutils` reproduce the
Retro68 boot block byte-for-byte, so boot-block-only changes can be
built and shipped **without the Retro68 toolchain** — which is how the
`2026-08-26` bundles were produced.

### Findings 7-9 now ship in the payloads too (2026-08-27)

The `2026-08-26` bundles were **boot-block-only** re-splices: pure
assembly, built without Retro68 and dropped into the 2026-06-13 images,
whose payloads were left untouched. So finding 8's *other* half — the
`payload_entry_cpu.s` 8 bpp paint fix — was fixed in the source but
present in **no shipped image**.

The `2026-08-27` bundles are **full rebuilds on a machine with Retro68**:
boot block *and* payload recompiled from source, so findings 7, 8 and 9
are now in both halves of every image. Payloads moved accordingly
(cpu 125142 -> 125218 B, fpu 32442 B, mmu 27040 B, cpu-nowrite
124938 B), which is why every expected `C` value in
`prebuilt/README.md` changed.

Re-verified for the new payloads: all four are contiguous on disk
(`rb-cli locate` reports `fragmented: false`, so the boot block's single
`_Read` still gets the whole image), and finding 10's `HANDOFF_ADDR`
($50000, payload offset `0x10000`) still lands in a **zero gap** in all
four — the latent hazard has not detonated, but it remains latent.

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

5. **SCSI `_Write` ran with the bench VBR (not the OS VBR) — FIXED, the
   real supervisor-environment bug.** The `_Write` ($A003) goes through
   the ROM's SCSI driver, which takes its own traps/faults while servicing
   the interrupt-driven DMA. But the bench runs with its OWN VBR
   (vectors 2..9, 11..15, 32..47 are recovery stubs), so any trap/fault
   the driver took mid-write hijacked `recovery_core` and longjmp'd out —
   corrupting the write (the intermittent crashes / slowness). The boot
   block's `_Read` works precisely because it runs in the ROM's VBR
   (before `install_vbr`). Fix: `jsonl_writer.c` now brackets each
   `_Write` with `use_os_vbr()` / `use_recovery_vbr()` (the I/O-bracket
   machinery built for the Amiga port but never wired into the Mac path),
   so the driver runs in the OS/ROM environment. IPL is left at the
   bench's level (the `_Read` runs masked and works — the driver polls or
   lowers IPL itself); if the write is still unreliable, lowering IPL
   around the bracket is the next lever. (`use_os_vbr`/`use_recovery_vbr`
   declared weak so iotest/keytest, which don't link recovery.o, skip it.)

6. **MAME won't boot the SCSI `.hda`** (CPU stays in ROM at `$408046C8`,
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
