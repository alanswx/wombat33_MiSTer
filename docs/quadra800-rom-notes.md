# Quadra 800 ROM — disassembly and exception/Sad Mac path

`quadra800-rom-disassembly.asm` — **every byte of the 1 MB ROM is
accounted for**, verified programmatically:

| | bytes | share |
|---|---|---|
| decoded as verified code | 502,606 | 47.9% |
| emitted as data hex dump | 545,970 | 52.1% |
| **unaccounted** | **0** | **0%** |

154,144 instructions. Data regions are printed as hex + ASCII rather
than silently skipped, so nothing in the image is missing from the
listing.

```sh
python3 tools/m68k_rdisasm.py f1a6f343.rom --base 0x40800000 \
    --scan-pointers --scan-prologues \
    --entry 0x40800000 --entry 0x408026A0 --entry 0x40802310 \
    --entry 0x4080280E --entry 0x408099B0 --entry 0x4088D9FE \
    --out quadra800-rom-disassembly.asm
```

**Why 47.9% code and not more.** Much of a Mac ROM is genuinely data —
resources, the declaration ROM, fonts, icon bitmaps, dispatch tables.
The harder limit is that almost everything is entered through the A-trap
dispatch tables, which are built in RAM at boot, so a static walk cannot
follow them. Coverage by seeding strategy:

| seeds | code coverage |
|---|---|
| exception vector handlers only | 1.3% |
| + `LINK A6` / `MOVEM.L -(SP)` / post-`RTS` prologues | 43.6% |
| + every longword holding an in-image address (jump tables) | **47.9%** |

Confidence is not uniform. Code reached from a vector handler is
certain; prologue- and pointer-seeded code is heuristic — a seed only
survives if it decodes cleanly, but false starts are possible. A linear
sweep would report "100% code" and be lying, since it decodes data as
garbage instructions and loses sync for pages afterwards.

## The SCSI driver on our disks

`quadra800-scsi-driver-disassembly.asm` — the `Apple_Driver43` partition
from a bench image (LBA 64, `pmBootSize` 9392), disassembled from its
entry point. Also 100% accounted: 6,948 bytes code (74.0%), 2,444 bytes
data (26.0%), 0 missing.

Partition entry as built by `rb-cli mac-scsi-bless`:

| Field | Value |
|---|---|
| `pmPartName` / `pmParType` | `Macintosh` / `Apple_Driver43` |
| `pmPartStatus` | `$0000007F` |
| `pmBootSize` | 9392 |
| `pmBootAddr` / `pmBootEntry` | `$00000000` / `$00000000` |
| `pmBootCksum` | `$0000F624` |
| `pmProcessor` | `68000` |

Offset 0 is `6000 03d2` — `BRA.W $3D4`, the driver entry.

**The driver contains no F-line instructions at all.** No 68030 MMU ops
(`PMOVE`/`PTEST`/`PFLUSH`), and no `CPUSH`/`CINV`/`MOVE16` either, in any
decoded code. A raw word scan of the image finds `$F4D8`, `$F494`,
`$F024` and several `$F6xx` words, but every one of them falls in a data
region — a word scan cannot tell opcodes from data, and here it is
misleading.

That **rules out** the hypothesis that the ROM F-line traps while
executing a 68030-era driver off our disk during mount.

ROM image `f1a6f343.rom` is the 1 MB Quadra 800 ROM, extracted from
MAME's `roms/macqd800.zip`. **Base address `$40800000`** — confirmed two
ways: ROM offset 0 contains the longword `f1a6f343`, the ROM's own
checksum and its MAME filename, and `$408046C6` (an address MAME
repeatedly parked at) lands on real code.

It is a *linear* disassembly, so data regions decode as nonsense
instructions and objdump loses sync after them. When examining a
specific routine, re-run objdump with `--start-address` at that routine
so it syncs correctly — several addresses below look like garbage in the
linear dump and are fine when forced.

## Exception vector table (read from a running machine)

Dumped from MAME at `VBR = $00046A10`, after the ROM had built its table:

| Vec | Handler | Meaning |
|---|---|---|
| 2 | `$408026F0` | bus error / access fault |
| 3 | `$408026F2` | address error |
| 4 | `$408026F4` | illegal instruction |
| 5 | `$408026F6` | zero divide |
| 6 | `$408026F8` | CHK |
| 7 | `$408026FA` | TRAPV |
| 8 | `$408026FC` | privilege violation |
| 9 | `$408026FE` | trace |
| 10 | `$408099B0` | **Line A** — the A-trap dispatcher |
| 11 | `$4088D9FE` | **Line F** — FPSP entry |
| 12–63 | `$40802704` | catch-all (except FP vectors below) |
| 25–30 | `$40809B00`–`$4080A1B0` | autovector IRQ1–IRQ6 |
| 31 | `$4080270A` | NMI |
| 48, 51–55 | `$4088D252`–`$4088DAB0` | FP exceptions |

Note vectors 2–9 point at **consecutive 2-byte entries**. Each is a
`BSR.S $408026A0`, so the return address the BSR pushes encodes which
vector fired.

## The dispatcher — `$408026A0`

```
408026a0:  movew #$2700,%sr           ; mask interrupts
408026a4:  tstb  0x0bff               ; already in the handler?
408026a8:  bmis  $408026b0
408026aa:  moveml %d0-%sp,0x0c30      ; save all 16 registers to $0C30
408026b0:  lea   %pc@($408026f0),%a0  ; a0 = base of the BSR table
408026b4:  movel %sp@+,%d0            ; d0 = the BSR return address
408026b6:  subl  %a0,%d0
408026b8:  lsrw  #1,%d0               ; d0 = (ret - $408026F0) / 2
```

So **`D0` = the Macintosh System Error ID**, and because the entry for
vector *V* sits at `$408026F0 + (V-2)*2` with the BSR pushing `entry+2`:

```
System Error ID = vector - 1
```

The dispatcher then stores it:

```
40802786:  movew %d0,0x0af0           ; DSErrCode
```

`$0AF0` is the documented low-memory global `DSErrCode`.

## The Sad Mac path — `$4080280E`

```
4080280e:  movew #$2500,%sr
40802812:  moveq #0,%d6
40802814:  movew 0x0af0,%d6           ; d6 = DSErrCode
40802818:  movel 0x02ba,%d7           ; d7 = DSAlertTab
4080281c:  bnes  $4080282a            ; alert table present -> normal bomb box
4080281e:  moveq #15,%d7              ; <-- no System yet: d7 = $0F
40802820:  lea   0xfffffaf0,%a0
40802826:  jmp   %pc@($40802820,%a0:l) ; -> $40802310, the Sad Mac drawer
```

`$40802310` saves the registers again to `$0C30` and runs the boot-time
diagnostic display.

**Therefore the two numbers on a Sad Mac are:**

| Line | Register | Meaning |
|---|---|---|
| first | `D7` | `$0000000F` — the constant set at `$4080281E`, meaning "no `DSAlertTab` yet", i.e. failure before the System loaded |
| second | `D6` | `DSErrCode` — the **System Error ID**, which is `vector - 1` |

## Decoding `0000000F 0000000A`

The first line is *not* an error class; it is the fixed `$0F` marker for
"died before the System was up". The second line is the System Error ID.

`$0A` = **10**, and ID = vector − 1, so this is **vector 11 — the Line F
(1111 emulator) trap**, i.e. an **unimplemented `$Fxxx` instruction**.

This matches the classic Macintosh System Error ID table:

| ID | Vector | Meaning |
|---|---|---|
| 1 | 2 | bus error |
| 2 | 3 | address error |
| 3 | 4 | illegal instruction |
| 4 | 5 | zero divide |
| 5 | 6 | CHK |
| 6 | 7 | TRAPV |
| 7 | 8 | privilege violation |
| 8 | 9 | trace |
| 9 | 10 | Line 1010 (A-line) |
| **10** | **11** | **Line 1111 (F-line)** |
| 11 | — | miscellaneous hardware exception |
| 12 | — | unimplemented core routine |
| 13 | 24 | spurious interrupt |

### Correction

An earlier reading of this failure took the `$0A` as *vector* 10 and
concluded Line A, on the strength of a comment in
`preboot/iotest/scsi_probe.c` that mentions "vector 10 (line-A trap)".
That comment is about a vector number; the Sad Mac prints a **System
Error ID**, which is one less. `0000000A` is an **F-line** trap, not
Line A. `SingleStepTests/test-blockers.md` should be read with that in
mind.

## Why F-line matters here

`$Fxxx` opcodes on the 68040 are the coprocessor/cache/MMU space. Two
sources of an unimplemented-`$Fxxx` exception are live for this project:

1. **Our own boot block** uses `CPUSHA BC` = `$F4F8`, and the DTT0
   variants additionally use `PFLUSHA` = `$F518`. Both are legal
   supervisor 68040 instructions, so they should not trap — but they are
   the only `$Fxxx` opcodes we issue, and a variant with `PFLUSHA`
   removed still produced this Sad Mac, which leaves `CPUSHA`.

2. **Code the ROM loads off the disk.** The Developer Note is explicit:
   "the `PTEST` operation code for the MC68030 generates an
   unimplemented-instruction exception on the MC68040." A disk driver
   built for the 68020/68030 that contains 030-era MMU opcodes will
   F-line trap the moment the ROM executes it — which happens during
   *mount*, before any boot block runs. That fits a failure where
   nothing is painted on screen.

**(2) is now ruled out** — see the driver section above; the
`Apple_Driver43` image contains no F-line instructions in any decoded
code.

That leaves **(1), our own boot block**, as the remaining candidate for
the F-line trap. The only `$Fxxx` opcode it issues once the `DTT0`
variants are excluded is `CPUSHA BC` (`$F4F8`), which finding 7 added on
both sides of the payload `_Read`. It is a legal supervisor 68040
instruction and should not trap — but it is the last `$Fxxx` we execute,
and a variant with `PFLUSHA` removed still produced the same Sad Mac.
The obvious experiment is a boot block with the `CPUSHA` pair removed.

## Useful low-memory globals seen in this path

| Address | Name | Use |
|---|---|---|
| `$02BA` | `DSAlertTab` | system-error alert table; zero before the System loads |
| `$0AF0` | `DSErrCode` | last system error ID |
| `$0BFF` | — | "already inside the handler" flag, bit 7 |
| `$0C30` | — | 16-register save area used by the dispatcher |
| `$0C6C`/`$0C70`/`$0C74` | — | saved SP / PC / SR |
