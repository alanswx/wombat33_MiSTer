# Prebuilt Quadra 800 bench disks (committed fixtures)

Compressed, ready-to-run bootable disk images of the three 68040 benches.
Each `.tgz` holds the SCSI hard-disk image (`.hda`) and the 1.44 MB HFS
floppy (`.dsk`) for one bench. Boot a Quadra 800 (or any 68040 Mac) from
the disk and it runs the bench straight from the HFS boot block — no
System needed — painting progress on the built-in DAFB display and
writing `/Results.jsonl` back to the same disk.

> ## ⚠️ REQUIREMENT: set the display to **640×480, 256 colors**
> The bench paints the built-in DAFB at **8 bits-per-pixel** (the Quadra
> 800's boot default — the Apple 640×480 @ 67 Hz mode). If the monitor is
> in a different colour depth the on-screen text will be garbled. Set
> Monitors to **640×480, 256 Colors** before running (or just leave the
> machine at its default). The byte stride is read from the ROM at
> runtime, so other *resolutions* at 256 colors also work; the depth is
> what matters. (A `dafb1` build exists for 1 bpp / B&W screens.)

| Bundle (`2026-06-13`) | Bench | Corpus |
|---|---|---|
| `quadra800-cpu-2026-06-13.tgz` | 68040 integer CPU | 722 rows (full ISA + 040 discriminators: MOVE16, CACR/CAAR mask, RTM) |
| `quadra800-fpu-2026-06-13.tgz` | 68040 FPU | 270 rows; hardware subset executes, unimplemented ops trap (vector 11) |
| `quadra800-mmu-2026-06-13.tgz` | 68040 MMU | 24 rows; register-mask + PFLUSH run, live/fault rows skipped (see note) |
| `quadra800-cpu-nowrite-diag-2026-06-13.tgz` | CPU bench, **disk writes stubbed out** | diagnostic only — runs all 722 to confirm the freeze was the SCSI write, not a CPU hang |

## Use

```sh
tar xzf quadra800-cpu-2026-06-13.tgz       # -> quadra800-cpu.hda + .dsk
sha256sum -c SHA256SUMS                     # verify the bundles first
```
- **`.hda`** — write to a BlueSCSI / SCSI2SD / real SCSI disk, or attach
  in an emulator. APM + Apple_HFS, boots directly into the bench.
- **`.dsk`** — 1.44 MB HFS floppy; write with Disk Copy / Greaseweazle /
  `dd`, or mount in an emulator.

Run it to **"ALL TESTS DONE"**, power off, pull `/Results.jsonl`, and diff:
```sh
../gen/cpu_diff_corpus.py ../results/cpu/mame_baseline_2026-06-12.json Results.jsonl
../gen/mmu_diff_corpus.py ../results/mmu/mame_baseline_2026-06-12.json Results.jsonl
# fpu: per row, vec 11 = an unimplemented op correctly trapped; vec 0 = executed
```

## Provenance / validation (2026-06-13)

Built by `preboot/supervisor_bench/build_<bench>_<hda|dsk>.sh` from the
captured corpora (`gen/{cpu,mmu,fpu}_tests.h`) with the Retro68
`m68k-apple-macos-gcc -m68040` toolchain. The 8 bpp paint kernel was
**verified by host-rendering** the bench screen through the exact same
`display_1bpp.c` code (`-DDISPLAY_BPP8`): "SUPERVISOR CPU BENCH …" and the
`run=/ok=/trap=` tally render as clean, legible white-on-black text at
640×480×8 bpp. ScrnBase on the Quadra is `$F9001000` (DAFB VRAM); the byte
stride (1024 for 640×480) is read from the ROM's `ScrnRow` ($0106) global
at runtime.

> **Display history:** the first cut painted 1 bpp into the 8 bpp DAFB
> framebuffer → garbled characters (one font byte became one 8 bpp pixel).
> Fixed 2026-06-13 by painting one byte per pixel; hence the 640×480×256
> requirement above.
>
> **Results write-back (2026-06-13 hardware finding + fix):** on the
> first real run the bench froze at `run=58` with an all-zero
> `/Results.jsonl`. Cause: the writer buffers into 16 KB batches, so the
> first SCSI `_Write` fires only when that buffer fills (~line 58) — and
> on the 68040 the buffer was filled through the **copyback data cache**
> while the Quadra's SCSI does **DMA from physical RAM**, so the driver
> read stale RAM and wedged. (The Mac II this code came from is a 68020
> with no copyback cache, so it never hit this.) **Fix:** the writer now
> issues `CPUSHA DC` (push the data cache to RAM) before every `_Write`.
>
> If a run still freezes or `/Results.jsonl` is still empty, boot the
> **`quadra800-cpu-nowrite-diag`** disk: it stubs the SCSI write out
> entirely, so it should run all 722 tests to `ALL TESTS DONE`. If it
> does, the remaining issue is purely the write path (next stop: a
> serial-port results channel, which sidesteps SCSI/DMA). If it *still*
> freezes at the same test, the problem is that test's execution, not the
> write. Either way the on-screen `run=/ok=/trap=` tally + final
> `ioResult=` are a valid readout — photograph the screen.

## Notes

- **MMU bench:** the register-characterization + PFLUSH rows run; the
  live-translation and fault rows are emitted `skipped:"live-reloc-todo"`
  pending the private-identity-page-table relocation (port from
  `../preboot/supervisor_bench/mmu_bench_main.c.68030-reference`).
- **FPU bench:** assumes MC68040-lite + no FPSP — transcendentals are
  expected to trap (vector 11). If the core embeds a full 68882 FPU,
  those rows execute instead; that *is* the discriminator.
- Rebuild from source: `cd ../preboot/supervisor_bench && make {cpu,fpu,mmu}`
  then `./build_<bench>_<hda|dsk>.sh`. The raw images land in `dist/`
  (gitignored); these `.tgz` are the committed copies.

See [`../../QUADRA800_TESTBENCH.md`](../../QUADRA800_TESTBENCH.md) for the
full plan and [`../test-blockers.md`](../test-blockers.md) for status.
