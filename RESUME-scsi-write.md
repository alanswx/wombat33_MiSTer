# Resume prompt — fix the SCSI `_Write` on the Quadra 800 bench

Paste this whole file as the opening message of a new session.

---

## The task

`SingleStepTests` is a 68040 testbench that boots a Macintosh Quadra 800
straight from an HFS boot block (no System), runs a 722-row CPU corpus,
and writes `/Results.jsonl` back to the same disk so it can be diffed
against a MAME baseline.

**Everything works on real hardware except the SCSI write.** Fix that.

Repo `/home/dani/repos/wombat33_MiSTer`, branch `main`, nothing pushed.
Read `SingleStepTests/test-blockers.md` findings 11–19 and
`docs/quadra800-developer-notes.md` before changing anything.

## Where it stands on real hardware

| Thing | Status on the physical Quadra 800 |
|---|---|
| Boot block | **proven good.** Prints `A 00000008` / `D FFFFFFDF` / `E 00000000` / `C 1D983A3F` — drive 8, refnum −33, `_Read` succeeded, 256 KB payload loaded byte-perfect |
| Payload, display, recovery harness, 68040 | **proven good** |
| Full 722-row corpus | **completes** using `quadra800-cpu-nowrite.hda` (writes compiled out), ~10 traps, which is expected — the corpus has 21 `EXC:` rows that trap deliberately |
| SCSI `_Write` | **fails.** Sad Mac `0000000F 0000000A`, nothing written |

Decoding that Sad Mac (traced through the ROM, see
`docs/quadra800-rom-notes.md`): the first word is a constant `$0F`
meaning "died before the System loaded"; the second is the **Macintosh
System Error ID**, which is `vector − 1`. So `$0A` = ID 10 = **vector 11
= F-line**.

Results buffer in 16 KB batches at ~281 bytes/line, so **the first
`_Write` fires around test 58**, not at the end. A crash there leaves
`/Results.jsonl` untouched — which is exactly what the machine shows.

## The lead to act on: NetBSD says Apple SCSI is pseudo-DMA

From `sys/arch/mac68k/obio/esp.c` (NetBSD's driver for this exact 53C96;
fetch with `curl -sSL https://raw.githubusercontent.com/NetBSD/src/trunk/sys/arch/mac68k/obio/esp.c`):

> "Apple 'DMA' is weird. Basically, **the CPU acts like the DMA
> controller**."

> "When you're attempting to read or write memory to this DACK/ed space,
> and the NCR is not ready for some timeout period, **the system will
> generate a bus error**… 1) (on write) **The FIFO is full and is not
> draining.** … 3) An interrupt condition has occurred."

> "**NOTE!!! spl values in here are hardcoded!!!** This is done to
> **allow serial interrupts to get in during scsi transfers.**"

Its bus-error recovery loop drops to `spl2()` then back to `splhigh()`
specifically so interrupts can land mid-transfer.

**Three consequences:**

1. There is **no DMA engine** reading our buffer. "Flush the cache so the
   DMA sees our data" is the wrong model — several hours were wasted on
   it. Don't go back there.
2. **A bus error mid-transfer is normal.** The driver installs a
   temporary bus-error handler and resumes. Anything that disturbs
   bus-error handling during `_Write` breaks the driver's own recovery.
3. **Interrupts must be able to get in.** The bench writes at IPL 7.

**The bench's write path is the one place it both replaces the vector
table and masks interrupts** — exactly the combination this driver cannot
tolerate. That is almost certainly the bug, and it explains why `_Read`
works (boot block: ROM's own vectors, nothing of ours installed) while
`_Write` does not (payload: our VBR, our vector 2, IPL 7).

## The change to make

`SingleStepTests/preboot/common/runtime/jsonl_writer.c`,
`driver_write_sector()`. Today it calls only `use_os_vbr()` around the
trap. Give the ROM the **whole** fault environment:

- `use_os_vbr()` **and** `restore_os_traps()` before the trap
  (`recovery.s` exports both; vectors 32–63 are swapped separately from
  the VBR, and only the VBR is currently restored)
- let interrupts in across the trap so the driver's completion IRQ and
  bus-error recovery can run
- re-arm ours (`install_recovery_traps()`, `use_recovery_vbr()`) only
  after `_Write` returns

Note IPL was tried *alone* and did not fix it on hardware (T6) — the
hypothesis is that it needs the full vector restore **as well**.

## Dead ends — already ruled out, do not repeat

- **Raw cache/MMU instructions fault on this machine.** `CPUSHA BC`
  (`$F4F8`) → bus error; `PFLUSHA` (`$F518`) → F-line. All converted to
  the ROM call `_HwPriv` (`moveq #1,d0` + `$A198`), which is verified
  working on hardware. **Never reintroduce raw cache ops.**
- **The `DTT0` boot-block change was an emulator artifact** and broke
  hardware. Now behind `.ifdef BOOT_SET_DTT0`, off by default. Finding 11
  is retracted.
- **Lowering IPL alone** regressed MAME (hangs at test 58) and did not
  fix hardware.
- **Removing the VBR bracket** and **removing the cache flush** both
  regress in MAME.
- The disk's `Apple_Driver43` partition contains **no** F-line
  instructions (disassembled, 74% coverage).
- Payload `.bss` was never zeroed — fixed; disks used to be single-use.
- `ANDI.W #$F8FF,SR` is the only corpus row that lowers IPL; marked
  `hw_unsafe`.

## Emulators cannot validate a fix here

**MAME and QEMU both complete the write successfully**, so neither
reproduces this bug. They can only catch *regressions*. A regression was
shipped to hardware once by skipping that check — **always run a
candidate through MAME before handing the user a disk.**

```sh
export RETRO68=$HOME/repos/Retro68-build/toolchain
cd SingleStepTests/preboot/supervisor_bench
make clean && make cpu && ./build_cpu_hda.sh ~/testdisk.hda /tmp/out.hda

# emulator build needs the DAFB mapped:
make cpu EXTRA_ASFLAGS="--defsym BOOT_SET_DTT0=1"
chdman createhd -i /tmp/out.hda -o /tmp/out.chd -c none -f
cd ~/repos/mame && ./mame macqd800 -skip_gameinfo -nothrottle -video none \
  -sound none -seconds_to_run 140 -hard /tmp/out.chd \
  -autoboot_delay 1 -autoboot_script /tmp/inv.lua

# QEMU: use the git-master build, NOT /usr/bin (8.2.2 aborts on any SCSI disk)
~/nextstep-test/qemu-src/build/qemu-system-m68k -M q800 -m 128 \
  -bios /tmp/q800rom/f1a6f343.rom -display none \
  -drive file=X.hda,format=raw,media=disk,if=none,id=hd0 \
  -device scsi-hd,drive=hd0,scsi-id=0
```

Screens come out of MAME via a Lua framebuffer dump rendered with
`SingleStepTests/preboot/common/tools/bbsim/render_fb.py --stride 1024
--bpp 8` (note: it crops below ~row 70; read raw bytes for lower rows).

## Open question only the hardware can answer

**Does a normal System disk save a file on this Quadra?**

- yes → SCSI writes are fine, the bug is entirely our environment
- no → drive/cable/termination/BlueSCSI, and no code change helps

This has not been tested and it gates everything.

## Fallbacks if `_Write` cannot be fixed

1. **Floppy.** `quadra800-cpu.dsk` boots and reaches the `.Sony` driver
   (`BootDrive 1`, refnum −5) — the last attempt failed with `ioResult
   −72` (`badDCksum`), a media error, not a code fault. SWIM II is a
   completely different write path from the 53C96.
2. **Buffer all results in RAM** (~203 KB) and write once at the end.
3. **Skip writing entirely** — embed a 2-byte digest per expected row
   (722 × 2 = 1,444 bytes), compare on-device, and paint only the
   diverging row indices. MAME predicts ~29 divergences, all
   corpus-portability artifacts (finding 13). Twenty-nine numbers on a
   screen is a photograph, and it is the actual deliverable.

## Working style the user asked for

- In-line code comments: **one line or less.** Long rationale goes in
  `test-blockers.md` or the commit message.
- Commit to `main`, never push, don't create branches.
- Don't touch `gen/*_tests.h` or the MAME baselines without saying so.
