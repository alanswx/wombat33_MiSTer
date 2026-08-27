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

11. **The boot block ran with the 68040 MMU on and no transparent
    translation — its screen wipe destroyed low memory. RETRACTED as a
    hardware finding; the fix is now OFF by default (2026-08-27).**

    > **This finding is emulator-only.** The `DTT0` fix below was
    > justified entirely on MAME/QEMU behaviour and never reproduced on
    > silicon. Worse, the `PFLUSHA` ($F518) it uses **F-line traps on the
    > real Quadra 800** — Sad Mac `0000000F 0000000A`, System Error ID 10
    > — which is the same class as finding 16's `CPUSHA` bus error, and
    > was itself the failure that blocked every hardware run until it was
    > removed. The block is now behind `.ifdef BOOT_SET_DTT0`, off by
    > default; build emulator images with `--defsym BOOT_SET_DTT0=1`.
    >
    > What the two emulators actually showed is that *their* page-table
    > walk does not map the DAFB aperture, so a `ScrnBase` write lands at
    > physical `$00001000`. The Developer Note (ch. 4) says the ROM
    > "manages the address space for the video frame buffers separately
    > from main memory", and hardware test T1 (finding 16) painted
    > correctly through `ScrnBase` with no `DTT0` at all — so the ROM's
    > mapping is fine and there was nothing to fix.

    Original text follows, kept for the record.

    Measured on `macqd800` at the instant the ROM jumps into the HFS
    boot block (it loads it at ~`$3FD480`):

    ```
    TC   = $0000C000     MMU translation ENABLED, 8 KB pages
    SRP  = $007FCC00     supervisor root pointer (ROM's page tables)
    ITT0 = ITT1 = DTT0 = DTT1 = $00000000    ALL transparent windows OFF
    ```

    So every access the boot block makes goes through the ROM's page
    tables, and those do not map the DAFB aperture flat. A write to
    `ScrnBase` (`$F9001000`) does **not** reach video RAM — it lands at
    physical `$00001000`. The 128 KB screen wipe at the top of
    `startup:` therefore sprays `$FFFFFFFF` over low memory
    `$1000..$21000`.

    That range contains the **drive queue**. Proven by changing the wipe
    fill to `$A5A5A5A5` and finding exactly 128 KB of it at
    `$001000..$020FFC` in RAM, with VRAM untouched. The `DrvQEl` at
    `$4700` reads `$0000A30E` before the wipe and `$FFFFFFFF` after, so
    the `DrvQHdr` walk immediately dereferences `$FFFFFFFF`, takes a
    fault, and the ROM's handler takes the machine back — the CPU
    "parked in ROM" of finding 6. Which low-memory casualty lands first
    is luck, which is why it looked intermittent on the physical Quadra.

    **Fix:** map the IO/framebuffer aperture 1:1 through `DTT0` as the
    very first thing `startup:` does, before `ScrnBase` is touched:

    ```
    move.l  #0xF00FE040, %d0    | base $F0, mask $0F, E=1, S=11, CM=10
    movec   %d0, %dtt0          | $F0000000..$FFFFFFFF, cache-inhibited
    pflusha
    nop
    ```

    Two constraints found the hard way, both by experiment:

    - **Only `DTT0`.** Forcing a blanket 1:1 over the whole address
      space (`$00FFE040` in `ITT0`+`DTT0`) makes the load fail with
      `readErr (-19)`: RAM must keep the ROM's own page-table mapping
      or the SCSI driver behind `_Read` stops working.
    - **Keep `SR = $2700`.** Re-enabling interrupts at boot-block entry
      also breaks the load.

    A TTR is a CPU register, so the mapping stays in force for the
    payload, whose entry shim paints through `ScrnBase` the same way.
    Applied to all three boot stubs (`boot_stub_scsi.s`,
    `boot_stub_floppy.s`, `boot_stub_scsi_fixed_offset.s`), same as
    finding 7, so it cannot return through another make target.

    **Why nothing caught this:** `bbsim` has no MMU and maps VRAM flat,
    so the wipe always "worked" there; MAME was believed unable to boot
    the disk at all (finding 6); and the physical Quadra could only say
    "it didn't start".

    **Independently confirmed on QEMU (2026-08-27).** Use the git-master
    build at `~/nextstep-test/qemu-src/build/qemu-system-m68k`
    (**11.1.50**), not the packaged `/usr/bin/qemu-system-m68k`
    (**8.2.2**). 8.2.2 is useless here: it aborts on its own assertion
    (`qemu_mutex_lock_iothread_impl`, `system/cpus.c:504`) or
    `DOUBLE MMU FAULT` as soon as *any* SCSI disk is attached, including
    a blank template with none of our code, on both ROM revisions and at
    every RAM size. That lock was reworked upstream (it is `bql_lock_impl`
    now), and 11.1.50 boots our disks fine.

    Run: `-M q800 -m 128 -bios <Quadra800 ROM> -display none
    -drive file=X.hda,format=raw,media=disk,if=none,id=hd0
    -device scsi-hd,drive=hd0,scsi-id=0`, ROM extracted from MAME's
    `macqd800.zip`. Screens come out via QMP `screendump`.

    On 11.1.50 the **MMU bench runs to completion — `MMU BENCH DONE`,
    ran=14, skipped=10, byte-identical to the MAME result**, painting
    legible 8 bpp at 640x480. The FPU bench runs clean too. So the DTT0
    fix is confirmed on a second, independent emulator, and QEMU's fault
    dump reports the same handoff state MAME does:

    ```
    TCR 0000c000
    DTTR0/1: 00000000/00000000   ITTR0/1: 00000000/00000000
    ```

    Two emulators sharing no MMU implementation agreeing on that is good
    evidence the state is faithful to silicon rather than a MAME artifact
    — the one assumption the `DTT0` fix rests on. In the CPU run QEMU
    also reports `D5 = e156577e`, exactly the host-computed payload
    checksum, and `DTTR0 = f00fe040`, i.e. it honoured our `MOVEC`.

15. **The payload never zeroed its `.bss` — the bench disks were
    single-use. FIXED 2026-08-27.** Root cause behind finding 14, the
    MAME `DAFB: Aux scanline interrupt` aborts, and any second run of a
    disk that had already been run.

    `payload.ld` declares `.bss (NOLOAD)` and nothing cleared it, so
    every C static came up as whatever the boot block's 256 KB over-read
    left at that address. The payload is ~125 KB of a 256 KB read, so
    `.bss` (`$5E938..$63384`) is filled from the disk *past* `/Payload`
    — which is `/Results.jsonl`. That is zeros exactly once: on a disk
    that has never been run. After one completed run it holds JSON text,
    so on the next boot the statics are garbage.

    The visible casualty is `display_row_bytes()`'s cached stride. It is
    non-zero garbage, so the cache hit returns it instead of reading
    `ScrnRow`, and `display_wipe(480)` computes `stride * 480` from it.
    Measured on QEMU: the wipe ran from `$F9001000` to `$F9400000` —
    ~4 MB — off the end of video RAM, taking a bus error. On MAME it
    instead reaches the DAFB registers at `$F9800000` and trips
    `Aux scanline interrupt enable not supported`, which is why that
    abort was blamed on ROM code earlier; it was our own runaway wipe.

    Proven causally: the pristine shipped image has 137054 zero bytes
    (4 non-zero) between payload end and the end of the load window and
    completes; fill just that region with `0x41` and the same image dies
    at 10 s. With the fix that doctored image completes again.

    **Fix:** `payload_entry_cpu.s` now zeroes `_payload_bss_start ..
    _payload_bss_end` before anything else — it must precede the handoff
    load, which lands in `.bss`. `payload.ld` gained the start symbol and
    a `. = ALIGN(4)` so the clear can be a long loop. All three benches
    share this shim, so all four bundles get it.

    Both emulators now run every bench end to end: MAME and QEMU each
    take the CPU corpus to `ALL TESTS DONE` with `ioResult=0000`.

14. **CPU bench dies on QEMU 11.1.50 with a null stack pointer
    (RESOLVED by finding 15).** Kept for the trail: the null `A7` was
    not a stack bug. A bus error (vector 2) from the runaway wipe hit
    `recovery_core`, which restores SP and resume-PC from slots that are
    still zero before the first test is armed — so it "recovered" into
    `SP = 0, PC = 0`. Worth noting as a latent sharp edge in
    `recovery.s`: any fault before the first armed test lands in a null
    context rather than being reported.

    Original symptom, for reference:
    Only the CPU image does; MMU and FPU are fine. `DOUBLE MMU FAULT`
    with `A7 = 00000000`, `PC = 0000000a`, faulting at `$FFFFFFFC` —
    an exception frame pushed onto a null stack. `VBR = $00062EF0` shows
    `install_vbr` had run, so it is inside `bench_main`, and it happens
    early (~3 s, before anything paints). MAME runs the same image to
    `ALL TESTS DONE`, so this is a MAME/QEMU divergence, not a known
    bench bug — but a genuinely null A7 would bite on hardware too, so
    it is worth finding which row does it before trusting a long
    hardware run. `target/m68k/op_helper.c:346` is where QEMU gives up.

12. **CPU bench wedges at test 180, `ANDI.W #$F8FF,SR` (not a boot
    bug).** With finding 11 fixed the CPU bench boots and runs, then
    stops at test 180 with `run=179 ok=179 trap=0`. That row clears the
    SR interrupt mask to IPL 0 — re-enabling interrupts inside the
    bench's own environment — and control is lost to `$0007FFxx`. Same
    class as the `hw_unsafe` CACR/MOVE16 rows that wedged the 040 at
    test 191. The FPU bench reaches test 266 and the MMU bench runs to
    completion (`MMU BENCH DONE`, ran=14, skipped=10).

    **FIXED 2026-08-27:** marked `hw_unsafe` so the Mac bench skips it,
    in `gen/mame_cpu_capture.lua` (the generator, so a re-capture keeps
    it) and in the generated `gen/cpu_tests.h`. The instruction itself is
    fine and MAME's captured golden still adjudicates it offline
    (`sr $2704 -> $2004`); it is the bench's environment that cannot
    survive handing the machine back to ROM interrupt handlers. With it
    skipped the CPU bench completes all 722 rows — see finding 13.

13. **First full end-to-end CPU run, and what it says about the corpus
    (2026-08-27).** With finding 11 fixed and row 179 skipped as a local
    experiment, the CPU bench ran all 722 rows to `ALL TESTS DONE`,
    wrote `/Results.jsonl` over SCSI with `ioResult=0000`, and the file
    was extracted from the disk and diffed against
    `results/cpu/mame_baseline_2026-06-12.json`. That is the first time
    the loop has ever closed. **717 rows written; 696 comparable;
    667 exact match; 29 divergent; 0 of the 29 are CPU differences.**

    Every divergence is a harness or corpus-portability artifact:

    | n | cause |
    |---|---|
    | 9 | memory-indirect (`([bd,A6],...)`) via an **absolute** pointer stored in scratch |
    | 8 | A6 (the scratch base) copied into a **data** register (`EXG`, `PEA`, `MOVE.L A6,D0`) |
    | 5 | absolute address baked into the test bytes (`(xxx).W`/`(xxx).L` = `$1804`/`$1820`) |
    | 4 | control-register harness state (`MOVEC` `SFC`/`DFC`/`VBR`/`CACR`) |
    | 2 | address register stored to scratch (`MOVEM`) |
    | 1 | absolute preload compared against an A6-relative value (`CMPA.L`) |

    The mechanism, measured: the MAME capture harness puts scratch at
    **A6 = `$1800`**; the Mac bench puts it at **A6 = `$00062D3A`**. On
    the Quadra, absolute `$1800`, `$1804`, `$1810` and `$1820` all read
    `$40809AE6` (ROM-pointer filler in low memory) — and `$40809AE6` is
    exactly the value every affected row reported. So those rows are not
    comparing an instruction, they are comparing where scratch happens
    to live.

    This violates the corpus's own stated invariant, from the header of
    `gen/mame_cpu_capture.lua`: *"Test instruction bytes must be
    IDENTICAL between MAME and the Mac OS bench, so any test that
    touches memory uses (A6) / d16(A6) addressing with A6 pre-loaded by
    the harness to a platform-specific scratch base."* The `(xxx).W` /
    `(xxx).L` rows and the A6-into-Dn rows break it by construction, and
    no amount of silicon will make them agree.

    The four `MOVEC` rows are a different flavour: the capture script
    zeroes `SFC`/`DFC`/`CACR` before each row, the Mac bench does not, so
    those rows compare harness state. Worth noting that
    `MOVEC.L CACR,D0` reads **`$80008000`** on the bench — DE+IE, the
    *correct* real-68040 mask, against a baseline of `0`. That is MAME
    quirk 4 showing up from the other side.

    Exception rows are healthy: 21 rows record a trap vector instead of
    a register snapshot, 18 of them name their expected vector, and all
    18 match (`DIVS`->5, `CHK`->6, `ILLEGAL`->4, odd `JMP`->3,
    `CALLM`->4 on the 040, ...).

    **So: the emulator is not failing the CPU suite.** MAME's 68040
    matches on every row that is actually comparable. The ~29 rows are a
    corpus-portability debt, and they will diverge identically on real
    silicon — they are not a Quadra finding waiting to happen. Fixing
    them means either re-expressing them A6-relative, or marking them
    platform-local and excluding them from the diff — still open, and a
    corpus decision rather than a boot one.

    The row-179 `hw_unsafe` flag was made permanent (finding 12) and the
    shipped `2026-08-27` CPU bundles rebuilt with it. Re-verified end to
    end on the shipped image: same 717 / 696 / **667 match** split, and
    the only rows the bench now skips are the four long-standing
    `hw_unsafe` / Line-A rows plus row 179.

16. **`CPUSHA BC` ($F4F8) bus-errors on real Quadra 800 silicon.
    FIXED 2026-08-27 — first bug in this project found on hardware
    rather than in an emulator.**

    Bisected on the machine with three boot blocks that halt at chosen
    points, so the screen stays up to read:

    | Test | Boot block | Result on hardware |
    |---|---|---|
    | T1 | halt *before* the first `CPUSHA` | **`A 00000008` / `D FFFFFFDF`** — runs, paints, DrvQ walk OK |
    | T3 | execute `CPUSHA`, then halt before `_Read` | **Sad Mac `0000000F 00000001`** |
    | T2 | both `CPUSHA` replaced with `NOP` | **boots; payload runs and paints its banner** |

    T1 proves the boot block, the 8 bpp paint, the drive-queue walk, the
    disk structure and the driver are all fine. T3 executes exactly one
    more instruction than T1 and dies, and its Sad Mac decodes (per
    `docs/quadra800-rom-notes.md`) to System Error ID **1 = vector 2 =
    bus error**, raised by `CPUSHA` itself. T2 removes it and the machine
    boots. Three tests, one instruction isolated.

    Note the ID differs from the original `0000000A` (ID 10, F-line) seen
    with the full boot block; the fault presents differently depending on
    what runs after it. ID 1 from T3 is the clean measurement, because
    nothing executes after the `CPUSHA` except `BRA.S *`.

    **Fix:** stop issuing raw cache instructions and use the ROM's own
    call — `_HwPriv` selector 1 (`moveq #1,d0` + `$A198`). The Developer
    Note, ch. 4: `_FlushInstructionCache` on the 68040 "is to flush both
    the instruction and data caches", deliberately in one call to "avoid
    problems in situations in which interrupts might occur while the
    caches are being flushed individually". That is exactly what finding
    7 wants, done the supported way, and it lets the ROM do whatever this
    silicon actually needs. It clobbers D0/A0, so the boot block saves
    `%d4/%d6/%d7/%a0` around it.

    Applied to `common/boot/boot_stub_scsi.s` and to `flush_icache()` in
    `bench_main.c`, `fpu_bench_main.c` and `mmu_bench_main.c`. Verified:
    full 722-row CPU corpus to `ALL TESTS DONE` with `ioResult=0000`
    under MAME, and bbsim reproduces the new checksum.

    **This invalidates the emulator-only reasoning that produced finding
    11.** Both MAME and QEMU execute `CPUSHA BC` happily, so no amount of
    emulator work could have found this. Finding 11's `DTT0` change was
    justified entirely on emulator behaviour and is still unproven on
    hardware — T1 and T2 are built without it and the machine got further
    than it ever had.

17. **Boot block proven healthy on hardware; last raw cache op removed
    (2026-08-27).** Test T5 (halt at the `JMP` into the payload) on the
    real Quadra 800 painted all five lines:

    ```
    A 00000008     BootDrive 8
    D FFFFFFDF     driver refnum -33
    E 00000000     _Read succeeded
    C A7263EC9     matches the host-computed checksum exactly
    3 <block>
    ```

    So on silicon: the disk mounts, the driver works, `_Read` transfers
    256 KB intact, the 8 bpp paint is correct, and **both `_HwPriv` cache
    flushes execute fine** (T4 had already isolated that one). Everything
    up to entering the payload is healthy. The disk image, the rebuilt
    `~/testdisk.hda` template and the `Apple_Driver43` partition are all
    exonerated.

    That leaves the payload. `common/runtime/jsonl_writer.c` still issued
    a raw `CPUSHA DC` ($F478) before `_Write` (finding 2's fix), the last
    raw cache instruction anywhere in the shipped code. Converted to the
    ROM call, which hardware has now verified. `cpu`, `fpu` and
    `cpu-nowrite` payloads are now free of raw cache opcodes entirely.

    The `PFLUSHA` remaining in the MMU payload is **corpus test data**,
    not code — the MMU bench deliberately executes `PFLUSH` rows inside
    its recovery harness, so a fault there is recorded as a trap rather
    than crashing. Prefer the CPU image for hardware bring-up.

    `cpu-nowrite`'s checksum is unchanged by this commit, which is the
    expected cross-check: `JW_NO_WRITE` stubs out the write path, so that
    `CPUSHA` was never compiled into it.

18. **FIRST FULL HARDWARE RUN of the CPU corpus (2026-08-27), and the
    SCSI write is the last bug.** `quadra800-cpu-nowrite.hda` ran all
    722 rows to completion on the physical Quadra 800, with ~10 traps
    (expected: the corpus has 21 `EXC:` rows that deliberately trap to
    verify vectors). Writes are compiled out in that build.

    So on real silicon the boot block, payload, 8 bpp display, recovery
    harness, corpus and the 68040 itself all work. The one remaining
    failure is the SCSI `_Write` path: the write-enabled image runs, then
    Sad Macs with **no results written at all**.

    The timing corroborates it. Results are buffered in 16 KB batches and
    result lines average 281 bytes, so the **first `_Write` fires around
    test 58** — not at the end. A crash during that first flush leaves
    `/Results.jsonl` untouched, which is exactly what the machine shows.

    Suspect, and the reason finding 5 already flagged it: the write runs
    at **IPL 7**. The Quadra's **53C96** signals transfer completion by
    interrupt, which can never be taken while masked. `_Read` in the boot
    block survives masked because the driver polls on that path. Fix
    under test: drop to IPL 0 across the `_Write` trap only, which is
    safe because `use_os_vbr()` has already installed the ROM's vector
    table so the ROM services the interrupt.

19. **Emulator triage of the write path: my IPL change was a
    regression, and the other two levers are both required
    (2026-08-27).** With `BOOT_SET_DTT0=1` (emulator images need the DAFB
    mapped), three variants of `driver_write_sector` under MAME:

    | Variant | MAME result |
    |---|---|
    | drop IPL to 0 across `_Write` (finding 18's fix) | **hangs at test 58** |
    | remove the `use_os_vbr()` bracket | **crashes, ROM takes over** |
    | remove the cache flush | **hangs at test 58** |
    | flush + VBR bracket, IPL untouched | **`ALL TESTS DONE`, ioResult 0** |

    So the shipped configuration was already correct and all three of my
    candidate "fixes" make it worse. The IPL change was committed in
    258a81c and shipped as T6 before being tested in emulation; it is now
    reverted. T7 and T8 were built and offered for hardware testing —
    both are regressions and should not be run.

    Note test 58 recurs exactly as predicted: results buffer in 16 KB
    batches at ~281 bytes per line, so the first `_Write` lands there.
    Two independent breakages both stall at that row, which is good
    evidence the arithmetic is right and that the first flush is the
    trigger.

    **Neither emulator can reproduce the hardware write failure** — both
    complete the corpus and write `/Results.jsonl` successfully. So MAME
    and QEMU can only catch regressions here, never confirm a fix. That
    is exactly what they did.

    Open lead for the hardware bug, from the Developer Note ch. 4: "the
    ROM software uses **only pages marked uncacheable** when setting up
    communication areas with alternate bus masters", and
    `LockMemory` / `LockMemoryContiguous` "can change the attributes of
    individual pages in the absence of VM". The bench's write buffer is
    ordinary cacheable RAM handed to a 53C96 DMA engine. A flush before
    the transfer is not the same as marking the page uncacheable, and the
    note is explicit that Apple does the latter.

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

6. ~~**MAME won't boot the SCSI `.hda`**~~ — **WRONG, retracted
   2026-08-27.** This was recorded as a MAME `macqd800` boot-device
   quirk. It is not. MAME boots SCSI disks fine (an unrelated System
   7.5.5 disk boots on `macqd800`), and the ROM *does* execute our HFS
   boot block. The CPU parking in ROM at `$408046C6` was **our own bug**
   — see finding 11. With that fixed, all four benches boot end to end
   under MAME. The diagnosis stood for ten weeks and sent verification
   down the offline-harness path instead of at the real defect.

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
