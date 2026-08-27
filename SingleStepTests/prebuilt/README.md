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
tar xzf quadra800-cpu-2026-08-27.tgz       # -> quadra800-cpu.hda + .dsk
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

## 2026-08-27 bundles — FULL rebuild (boot block **and** payload)

**Boot these.** Two things are new. First, unlike the 2026-08-26
bundles, which were **boot-block-only** re-splices carrying the
unchanged 2026-06-13 payloads, these are **full rebuilds: the payload
was recompiled too**, so the `payload_entry_cpu.s` 8 bpp paint fix
ships in an image for the first time here.

Second, and more important: the boot block now **sets up transparent
translation (`DTT0`) for the DAFB aperture before it touches the
screen.** The ROM hands the boot block a machine with the 68040 MMU
enabled and every transparent-translation window disabled, so writes to
`ScrnBase` did not reach video RAM — they landed at physical
`$00001000`, and the 128 KB screen wipe destroyed low memory
`$1000..$21000`, drive queue included. That is the real "the bench
mostly does not start" bug (finding 11 in `../test-blockers.md`); the
2026-08-26 cache fix was necessary but not sufficient.

With it, **all four benches now boot end to end under MAME
`macqd800`** — the first time that has ever worked. The MMU bench runs
to completion; the FPU bench reaches test 266; the CPU bench reaches
test 180 and stops on a corpus row that re-enables interrupts
(finding 12), not on anything to do with booting.

| Bundle | Bench |
|---|---|
| `quadra800-cpu-2026-08-27.tgz` | 68040 integer CPU, 722 rows |
| `quadra800-fpu-2026-08-27.tgz` | 68040 FPU, 270 rows |
| `quadra800-mmu-2026-08-27.tgz` | 68040 MMU, 24 rows |
| `quadra800-cpu-nowrite-diag-2026-08-27.tgz` | CPU bench with SCSI writes stubbed out |

Both fixes are now in both halves of the image:

- **boot block** — `CPUSHA BC` either side of the payload `_Read`, and
  8 bpp diagnostics (shipped 2026-08-26, unchanged here).
- **payload entry** — `payload_entry_cpu.s` now paints 8 bpp with a
  runtime `ScrnRow` stride instead of 1 bpp. On the Quadra's DAFB the
  old code was unreadable speckle. **New in these bundles.**
- **boot block checksum** — the `C` line is sized per image from the
  `PAYLCKSZ` marker the build scripts patch.

Payload sizes (they moved, because the payload actually changed):

| Image | payload | `C` window |
|---|---|---|
| cpu | 125218 B | `0x1EA00` |
| fpu | 32442 B | `0x8000` |
| mmu | 27040 B | `0x6A00` |
| cpu-nowrite | 124938 B | `0x1EA00` |

### Reading the boot screen

Five lines appear before the bench itself starts:

```
A 00000003     boot block running; BootDrive = 3
D FFFFFFDF     driver refnum from the drive queue (negative = normal)
E 00000000     _Read ioResult -- 00000000 is noErr; anything else = load failed
C 5A9646DF     checksum of the payload as loaded into RAM
3 <block>      about to JMP into the payload
```

`C` is the diagnostic that settles whether the cache fix took. It is a
rotating 32-bit sum over the region HFS allocated to `/Payload`, taken
straight after the transfer and **before** anything else touches RAM.
Expected values, per image (**these are the 2026-08-27 rebuilds** —
every payload rebuild changes them):

| Image | expected `C` |
|---|---|
| `quadra800-cpu.hda` | `5A9646DF` |
| `quadra800-cpu.dsk` | `9C56C17C` |
| `quadra800-fpu.hda` | `AC893D41` |
| `quadra800-fpu.dsk` | `AC8933E5` |
| `quadra800-mmu.hda` | `AEF86860` |
| `quadra800-mmu.dsk` | `ECA662B7` |
| `quadra800-cpu-nowrite.hda` | `A6058355` |
| `quadra800-cpu-nowrite.dsk` | `646129EE` |

- Matches, and the bench runs → the payload arrived intact.
- **Differs, or differs between two boots of the same disk** → the
  payload is still being corrupted in transit; the cache fix is not the
  whole story. Photograph the value and the `E` line.
- `E` non-zero → the load itself failed; the block halts there and the
  code on screen is the driver's `ioResult`.

## 2026-08-26 bundles — 68040 cache fix + readable boot diagnostics

**Superseded by the 2026-08-27 bundles above.** Same bench payloads as
06-13, byte for byte; the only change is the 1024-byte HFS boot block.
The `C` values these images paint differ from the table above, because
their payloads are the older 06-13 builds.

| Bundle | Bench |
|---|---|
| `quadra800-cpu-2026-08-26.tgz` | 68040 integer CPU, 722 rows |
| `quadra800-fpu-2026-08-26.tgz` | 68040 FPU, 270 rows |
| `quadra800-mmu-2026-08-26.tgz` | 68040 MMU, 24 rows |
| `quadra800-cpu-nowrite-diag-2026-08-26.tgz` | CPU bench with SCSI writes stubbed out |

### What changed and why

Symptom on the physical Quadra 800: the bench **mostly did not start at
all**, and only very occasionally got as far as painting. The boot block
loads 256 KB of payload to `$40000` with one `_Read` and then `JMP`s
into it — with no cache management. That was safe on the 68020/68030
(256-byte write-through caches); on the 68040 it is not:

- dirty lines in the 4 KB **copyback** data cache, left over from the
  ROM's own use of low RAM, get written back **on top of** the payload
  that the SCSI transfer just delivered, and
- stale lines in the 4 KB instruction cache get executed instead of the
  bytes that actually arrived.

Whether a given boot lands the damage on code that matters or on padding
is luck, which is exactly why it looked intermittent. The boot block now
issues `CPUSHA BC` on **both** sides of the `_Read` (push *and*
invalidate — `CINVA` would throw away the payload if the driver copies
through the CPU rather than DMAing), with a `NOP` after each for
pipeline sync. Same class of bug as the `CPUSHA DC` fix for `_Write`;
the read side had simply never been covered.

The boot block's own readouts were also still painting **1 bpp** into
the Quadra's 8 bpp framebuffer — one byte per eight pixels — so the
drive number, driver refnum and `_Read` result code have been
unreadable speckle for the whole bring-up. They now paint one byte per
pixel and take the row stride from `ScrnRow` at runtime.

### Provenance

The boot block was rebuilt from
`../preboot/common/boot/boot_stub_scsi.s` and spliced into the 06-13
images; every byte outside the 1024-byte boot block is unchanged
(verified by byte-diff). It was validated before shipping by executing
the assembled block under Musashi against a simulated Quadra 800 low
memory + DAFB framebuffer: the painted screen renders legibly, the
handoff slot receives `FFDF 0003`, and the 68k checksum routine
reproduces the host-computed expectation for every image above. The
1 bpp path was re-checked the same way at stride 80 so the Mac II /
IIvi lineage is not regressed.

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
