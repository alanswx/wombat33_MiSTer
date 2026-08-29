# Quadra 800 ROM + Apple_Driver43 — 53C96 register access patterns

Mined 2026-08-28 from `docs/quadra800-rom-disassembly.asm` and
`docs/quadra800-scsi-driver-disassembly.asm`. This is the map of what the disk
boot actually demands from the 53C96 — the "customer spec" for
`rtl/ncr53c96.sv`.

## Headline: the disk driver never touches the 53C96

`docs/quadra800-scsi-driver-disassembly.asm` contains **zero** hardware
accesses. Greps for `50f0`/`50f1`/`5001xxxx`, any absolute-long I/O address,
and any `$30(aN)`-style register offset all come back empty. Every SCSI
operation leaves via a trap:

- `$A815` `_SCSIDispatch` (original SCSI Manager) — 11 call sites, all inside
  `$00001A3A`
- `$A089` `_SCSIAtomic` (SCSI Manager 4.3 `SCSIAction`) — 10 call sites

and the driver picks between them at `$00000A5C`/`$000005E8` by comparing the
address of trap `$89` against `$9F` (unimplemented); the result is cached in
`-$8(a5)`. On a stock Q800 ROM boot there is no SCSI Manager 4.3 yet, so **the
old-API path is the live one**. Therefore all 53C96 register semantics live in
the ROM, and questions 1–4 below are answered from ROM code with the driver
supplying only the *shape* of the requests.

Address map established for the Q800 (needed throughout):

| Thing | Address | Where established |
|---|---|---|
| 53C96 base (`SCSIBase`, lowmem `$0C00`) | `$50F10000` | base-address table entry at `$408D3094` (`50 f1 00 00`); loaded `$40804112`, consumed `$4088402C`, `$408D1658` (`movea.l $40(a4),a3`) |
| register *N* | `base + N*16` | throughout |
| PDMA byte/word port | `base+$100` = `$50F10100` | `$408D1A4A`, `$408D24B8`, `$408D2572` |
| PDMA 32-bit bulk port | `base+$40000+$100` = `$50F50100` | `$408D1EC0` `adda.l #$40000,a1` then `$408D1F3A` `lea $100(a1),a1` |
| DREQ register | `$50F03A00` (VIA2/IOSB IFR image), bit index 0 | `$408D1610` `move.l #$50f03a00,$44(a4)`; `$408D160C` `clr.b $160(a4)` |
| IOSB PDMA control/status | `$50F18200`, `$50F18300`, `$50F18400` | `$408D1E0A`, `$408D2622`, `$408D26C8` |

Two 53C96 driver copies exist. `btst #5,$dd1.w` at `$4089889C` selects them:
bit clear → **`$408D1540`–`$408D28xx` (IOSB/Q800)**; bit set → `$40899xxx`
(DAFB, Q700/900, SCSI at `$50F0F000`, DREQ `$F9800024` bit 9). The `$408D1xxx`
copy is the Q800 one and is where `$408D1982` lives. A third body at
`$40807400`–`$40809xxx` is the **NCR 5380** driver (its `$30(a3)` values
`$01/$02/$03/$06/$07` are 5380 Target Command Register phase codes, not 53C96
commands) — don't confuse it.

---

## 1. Command-register (reg 3 = `$30(a3)`) values actually written

Complete set used by the Q800 path:

| Value | Meaning | Sites |
|---|---|---|
| `$00` | NOP | `$408D1DD6` |
| `$01` | Flush FIFO | ~20 sites; `$408D1934`, `$408D1A02`, `$408D1AB6`, `$408D1ECE`, `$408D1F52`, `$408D2054`, `$408D2178`, `$408D2726` … |
| `$02` | Reset device (chip) | `$408D1DD0` |
| `$03` | Reset SCSI bus | `$408D23DA` |
| `$10` | Transfer Info, **non-DMA** (FIFO PIO) | `$408D1B00`, `$408D1E58`, `$408D1E8A`, `$408D1FE8`, `$408D237A`, `$408D25A8` |
| `$11` | ICCS, **non-DMA only** | `$408D1880` (and `$40898CB0` in the DAFB copy) |
| `$12` | Message Accepted | `$408D18A6`, `$408D1B10`, `$408D1D4C` |
| `$90` | Transfer Info, **DMA** | `$408D1A10`, `$408D1F74`, `$408D20AA`, `$408D21B8`, `$408D22DE`, `$408D24AE`, `$408D254E` |
| `$C1` | **DMA \| Select w/o ATN** | `$408D1948` |
| `$C2` | **DMA \| Select with ATN** | `$408D195E` |

Notes that matter for a chip model:
- The plain `$41`/`$42` select forms are **never** issued — selection is always
  the DMA form. Nor are `$43` (sel+ATN+stop), `$46` (ATN3), `$18` (transfer
  pad), `$1A/$1B` (set/reset ATN), `$44/$45` (enable/disable reselection).
- ICCS is only ever `$11`; **`$91` never appears**.
- Register 14 (`$E0`, third TC byte) is never touched, and CONFIG2 (reg 11) is
  written 0 at `$408D1DE6`, so the extended-counter feature is off.

**Both PIO and pseudo-DMA are used, and mixed inside one command.** The CDB
send is the sharpest example — `$408D1A02`:

```
408D1A02:  177c00010030   move.b #$1, $30(a3)      ; flush FIFO
408D1A08:  17470010       move.b d7, $10(a3)       ; TC hi = 0
408D1A0C:  16bc0001       move.b #$1, (a3)         ; TC lo = 1
408D1A10:  177c00900030   move.b #$90, $30(a3)     ; DMA | Transfer Info
408D1A16:  002b00800080   ori.b #$80, $80(a3)      ; CONFIG1 |= slow-cable mode
408D1A1C:  5382           subq.l #$1, d2
408D1A20:  175a0020       move.b (a2)+, $20(a3)    ; CDB bytes 0..n-2 -> FIFO (true PIO)
408D1A24:  51cafffa       dbra d2, $408d1a20
408D1A30:  721f           moveq #$1f, d1
408D1A32:  c22b0070       and.b $70(a3), d1        ; spin until FIFO drains
408D1A4A:  175a0100       move.b (a2)+, $100(a3)   ; LAST CDB byte via pseudo-DMA port
408D1A6E:  022b007f0080   andi.b #$7f, $80(a3)     ; clear slow-cable mode
```

That last byte through `$50F10100` is what satisfies the `TC=1` DMA request the
`$C1`/`$C2` select left outstanding. Any model must accept a DACK-window byte
to complete a DMA-select.

Chip init, `$408D1DD0`:
```
408D1DD0:  move.b #$2, $30(a3)      ; reset device
408D1DD6:  clr.b   $30(a3)          ; NOP
408D1DDA:  move.b #$1, $30(a3)      ; flush FIFO
408D1DE0:  move.b #$47, $80(a3)     ; CONFIG1: own ID 7, disable INT on SCSI reset
408D1DE6:  clr.b   $b0(a3)          ; CONFIG2 = 0
408D1DEA:  move.b #$4, $c0(a3)      ; CONFIG3 = 4
408D1E3C:  move.b #$5, $90(a3)      ; clock conversion = 5
408D1E42:  move.b #$a7, $50(a3)     ; select/reselect timeout = $A7
408D1E48:  clr.b   $70(a3)          ; sync offset = 0 (async only)
408D1E4C:  move.b  $50(a3), d0      ; read INT reg to clear
```

---

## 2. Data transfer: Turbo-SCSI PDMA, 32-bit, with a bus-error handler

The old-API selectors map to four routines through a table at `$a4(a4)`
(`$408D1EEE` `movea.l (a0,d4.l),a0`), installed at `$408D1584`:

| Selector | `d4` | Slot | Routine |
|---|---|---|---|
| 5 SCSIRead | `$20` | `$c4(a4)` | `$408D1F26` |
| 6 SCSIWrite | `$24` | `$c8(a4)` | `$408D205C` |
| 8 SCSIRBlind | `$28` | `$cc(a4)` | `$408D228E` |
| 9 SCSIWBlind | `$2c` | `$d0(a4)` | `$408D216C` |
| (SCSIComp, TIB op 8) | `$38` | `$dc(a4)` | `$408D2476` |

**Width.** Bulk moves are **32-bit**, straight `move.l`, no byte swapping
anywhere:

```
408D1FB6:  24d1   move.l (a1), (a2)+     ; PDMA read, x4 = 16 bytes
408D1FB8:  24d1
408D1FBA:  24d1
408D1FBC:  24d1
```
and for writes, an unrolled `move.l (a2)+,(a1)` (`22 9a`) block entered by
`jmp $408D20D2(pc,d5.w)` / `jmp $408D2216(pc,d3.w)`. Blind writes use a
**32-entry** unrolled run (`$408D21D6`–`$408D2215`, 128 bytes per `dbra`).

Residuals and the verify path use the *other* window at 16/8 bits:
```
408D20F6:  375a0100   move.w (a2)+, $100(a3)   ; 2-byte residual
408D2100:  175a0100   move.b (a2)+, $100(a3)   ; 1-byte residual
408D24B8:  302b0100   move.w $100(a3), d0      ; SCSIComp reads 16-bit
408D26CC:  34eb0100   move.w $100(a3), (a2)+   ; bus-error recovery
```
So: **32-bit longwords go to `base+$40100`; word/byte accesses go to
`base+$100`.** A model needs both. (`$40000` is exactly one I/O image stride
per dev-note §1, so they alias in address terms but the ROM clearly treats them
as different-width ports.)

**Readiness — all three mechanisms are present, and which one applies depends
on the selector.**

*Non-blind read (`$408D1F26`) — this is the one the ROM's own boot read uses.*
TC is loaded with **16** per chunk and `$90` reissued each chunk:
```
408D1F52:  177c00010030   move.b #$1, $30(a3)     ; flush FIFO
408D1F58:  422b0010       clr.b  $10(a3)          ; TC hi = 0
408D1F5C:  16bc0010       move.b #$10, (a3)       ; TC lo = 16
408D1F74:  177c00900030   move.b #$90, $30(a3)    ; DMA transfer info
408D1F7A:  4e71           nop
408D1F7C:  082b00040040   btst.b #$4, $40(a3)     ; STATUS bit 4 = TC zero
408D1F82:  661e           bne.b  $408d1fa2
408D1F84:  082b00070040   btst.b #$7, $40(a3)     ; STATUS bit 7 = INT
408D1F8A:  66000080       bne.w  $408d200c
408D1F8E:  7a07 ca2b0040  moveq #$7,d5 / and.b $40(a3),d5   ; phase still 1?
408D1F9A:  4a13           tst.b  (a3)             ; TC low != 0
...
408D1FA2:  2a10           move.l (a0), d5         ; a0 = $13c(a4) = $50F03A00
408D1FA4:  102c0160       move.b $160(a4), d0     ; DREQ bit index (= 0)
408D1FA8:  0105           btst.l d0, d5           ; ** DREQ poll **
408D1FAA:  67d0           beq.b  $408d1f7c
408D1FAC:  082b00040070   btst.b #$4, $70(a3)     ; FIFO FLAGS bit 4 = 16 bytes present
408D1FB2:  67c8           beq.b  $408d1f7c
408D1FB4:  4e71           nop
408D1FB6:  24d1 24d1 24d1 24d1                    ; drain 16 bytes
408D1FC0:  082b00070040   btst.b #$7, $40(a3)     ; spin for INT
408D1FC6:  67f8           beq.b  $408d1fc0
408D1FC8:  1a2b0050       move.b $50(a3), d5      ; read INT reg
408D1FCC:  08050005       btst.b #$5, d5          ; bit 5 = disconnect -> error
408D1FD2:  51ccff92       dbra d4, $408d1f66
```
So a non-blind read gates on **STATUS bit 4 (TC=0) AND external DREQ AND
FIFO-flags bit 4** before every 16-byte burst, then waits for INT and reads
reg 5. Note the two `nop`s bracketing the burst — deliberate settling.

*Non-blind write (`$408D205C`)* loads the **full count** and polls FIFO-flags
between chunks instead of DREQ:
```
408D20A2:  1684           move.b d4, (a3)         ; TC lo
408D20A6:  17440010       move.b d4, $10(a3)      ; TC hi  (after lsr.l #8)
408D20AA:  177c00900030   move.b #$90, $30(a3)
408D20D4:  082b00070040   btst.b #$7, $40(a3)     ; INT -> abort
408D20DC:  7607 c62b0040  moveq #$7,d3 / and.b $40(a3),d3   ; phase changed -> abort
408D20E4:  701f c02b0070  moveq #$1f,d0 / and.b $70(a3),d0  ; FIFO must be empty
408D20EA:  66e6           bne.b  $408d20d2
408D20EC:  51ccffda       dbra d4, $408d20c8      ; next 16 bytes
```

*Blind (`$408D216C` write, `$408D228E` read)* — **no polling at all** between
moves; 32 `move.l` per `dbra` iteration straight at the window. These rely
entirely on the hardware hold-off plus bus error.

**Bus-error retry is real and is the third mechanism.** `$408D1E9E` wraps
every PDMA routine:
```
408D1ECE:  177c00010030    move.b #$1, $30(a3)
408D1ED4:  2978000801c0    move.l $8.w, $1c0(a4)        ; save vector 2
408D1EDA:  21ec01ac0008    move.l $1ac(a4), $8.w        ; install $408D2606
408D1EE0:  08ec00070158    bset.b #$7, $158(a4)         ; "in PDMA" flag
408D1EE6:  394401bc        move.w d4, $1bc(a4)
408D1EEA:  41ec00a4        lea.l $a4(a4), a0
408D1EEE:  20704800        movea.l (a0, d4.l), a0
408D1EF2:  4e90            jsr (a0)
408D1EFA:  21ec01c00008    move.l $1c0(a4), $8.w        ; restore
```
The handler at `$408D2606`:
```
408D260C:  26780c00        movea.l $c00.w, a3           ; SCSIBase
408D2610:  41ef0024        lea.l $24(a7), a0            ; -> 68040 access-error frame
408D2614:  b9f80c0c        cmpa.l $c0c.w, a4
408D261A:  082c00070158    btst.b #$7, $158(a4)
408D2622:  43f950f18000    lea.l $50f18000.l, a1
408D2628:  082900000300    btst.b #$0, $300(a1)         ; IOSB: was this our PDMA fault?
408D262E:  6610            bne.b $408d2640
408D2634:  2f6801c00020    move.l $1c0(a0), $20(a7)     ; not ours -> chain
408D2640:  226c013c        movea.l $13c(a4), a1
408D2648:  2011 0700       move.l (a1),d0 / btst.l d3,d0 ; spin on DREQ
408D264E:  082b00070040    btst.b #$7, $40(a3)          ; ...or chip INT
408D265A:  30280012 ...    move.w $12(a0),d0 / movea.l $28(a0),a1 / move.l $2c(a0),d1
408D2666:  6100010a        bsr.w $408d2772              ; replay WB1
408D266A:  ...$10(a0)/$20(a0)/$24(a0)                   ; replay WB2
408D267A:  ...$e(a0)/$18(a0)/$1c(a0)                    ; replay WB3
```
`$408D2772` decodes the 68040 `WBxS` size field and replays the write at the
right width — `$20`→`move.b d1,(a1)`, `$40`→`move.w d1,(a1)`,
`$00`→`move.l d1,(a1)` (the long case first checks IOSB `$50F18300` bit 2 and
downgrades to a word if set). Then it rewrites the frame to a format-0 at
`+$34` and `rte`s to **re-execute the faulting instruction**. For `SCSIRBlind`
only (`cmpi.w #$28,$1bc(a4)` at `$408D2690`) it first recovers in-flight data:
```
408D26C8:  34e90400        move.w $400(a1), (a2)+       ; IOSB latch $50F18400
408D26CC:  34eb0100        move.w $100(a3), (a2)+
408D26E2:  42690300        clr.w  $300(a1)              ; clear IOSB fault latch
```
This is exactly the NetBSD description quoted in dev-notes §13, and it confirms
the bench's concern there: replacing vector 2 or presenting a non-format-`$7`
frame breaks this.

**No byte-swap logic anywhere** — lanes are handled by the IOSB, the ROM just
moves longwords.

---

## 3. Status/interrupt polling

Registers read: **4 (STATUS, `$40`)**, **5 (INTERRUPT, `$50`)**, **7 (FIFO
FLAGS, `$70`)**, **3 (COMMAND readback, `$30`)**, **0/1 (TC readback,
`$00`/`$10`)**. Sequence-step (reg 6, `$60`) is **not read at all in the Q800
path** — grep for `$60(a3)` in `$408D1xxx` returns nothing. (The DAFB copy does
use it once, `$40898F6E` `move.b $60(a3),d0` + `andi #$7`, during MESSAGE-OUT;
the Q800 copy replaced that with a phase poll at `$408D1C1E`.)

STATUS bits used:
- **bits 2:0 phase** — everywhere, e.g. `$408D1F30`
  `moveq #7,d0 / and.b $40(a3),d0`, then `cmpi #1` DATA IN, `#0` DATA OUT,
  `#2` COMMAND, `#3` STATUS, `#6` MSG OUT, `#7` MSG IN. The phase dispatcher is
  `$408D1C62`–`$408D1D5A`.
- **bit 4 (TC zero)** — `$408D1F7C`, `$408D255C`, and indirectly via
  `$408D212E btst #4,d5`.
- **bit 7 (INT)** — the primary readiness test: `$408D1994`, `$408D1F84`,
  `$408D1FC0`, `$408D20D4`, `$408D243C`, `$40899708`, `$4089973C`.

INTERRUPT register (reg 5) bits:
- **bit 5 (Disconnected)** — `$408D19CC btst #5,d1` after select (→ selection
  timeout, returns 2), `$408D1FCC`, `$408D1FFE`, `$408D258C`.
- **bits 5:4 as a pair** — `$40899720 andi.b #$30,d0 / cmpi.b #$10,d0`, i.e.
  "Bus Service set, Disconnect clear".
- Reg 5 read always *also* latches reg 7: the shared wait helper `$40899704`
  (called via `bsr.l` from the Q800 code) is
```
40899704:  7a00            moveq #$0, d5
40899706:  1a2b0040        move.b $40(a3), d5     ; STATUS
4089970A:  08050007        btst.b #$7, d5         ; spin for INT
4089970E:  67f4            beq.b $40899704
40899710:  4845            swap d5
40899712:  1a2b0070        move.b $70(a3), d5     ; FIFO FLAGS
40899716:  e14d            lsl.w #$8, d5
40899718:  1a2b0050        move.b $50(a3), d5     ; INTERRUPT (clears it)
40899720:  02000030        andi.b #$30, d0
40899724:  0c000010        cmpi.b #$10, d0
```
`$4089972A` is the same with a `$B24`-derived `dbne` timeout.

Poll points:
- **after select** → `$408D1994` (see §6)
- **after each DMA burst** → `$408D1FC0` (INT) then reg 5 bit 5
- **after ICCS** → `bsr.l $40899704` at `$408D1886`, then two FIFO reads
- **before/after every phase change** → phase bits, plus reg 7 count for FIFO
  drain

FIFO FLAGS (reg 7) is polled two ways: `and.b $70(a3),d0` with `#$1f` for a
byte count (drain/empty checks at `$408D1A32`, `$408D20E6`, `$408D2152`,
`$408D2244`, `$408D270A`), and `btst #4,$70(a3)` for "16 bytes present" at
`$408D1FAC`.

---

## 4. Transfer counter

Only **regs 0 and 1** (`(a3)` and `$10(a3)`) are ever written — no third byte,
and reg 14 is untouched.

| Situation | TC loaded | Site |
|---|---|---|
| Before `$C1`/`$C2` select | **`$0001`** (`TChi = d7 = 0`, `TClo = 1`) | `$408D1940`/`$408D1956` |
| Before `$90` in SCSICmd | `$0001` | `$408D1A08` |
| Non-blind **read**, per chunk | **16** (`clr.b $10(a3)` / `move.b #$10,(a3)`) | `$408D1F58` |
| Non-blind **write** | full byte count, low 16 bits; `$10000` per outer pass | `$408D20A2` |
| **Blind** read/write | full byte count, low 16 bits; `$10000` per outer pass | `$408D21B0`, `$408D22D6` |
| SCSIComp | 16 per chunk | `$408D2540` |

The 64K-chunking pattern is identical in all three bulk routines:
```
408D21A0:  2c02 4846       move.l d2,d6 / swap d6          ; d6 = count >> 16
408D21A4:  0282 0000ffff   andi.l #$ffff, d2
408D21B0:  1684            move.b d4, (a3)                 ; TC lo
408D21B2:  e08c            lsr.l #$8, d4
408D21B4:  17440010        move.b d4, $10(a3)              ; TC hi
408D21B8:  177c00900030    move.b #$90, $30(a3)
...
408D2238:  243c00010000    move.l #$10000, d2              ; 0 means 65536
408D223E:  51ceff6e        dbra d6, $408d21ae
```
For a 512-byte read the driver's TIB carries 512, and a non-blind read
therefore issues **32 separate `$90` commands with TC=16 each**; a blind read
issues **one `$90` with TC=512**.

Status/message phases use no counter at all — they go through `$11` ICCS and
two plain FIFO reads:
```
408D187A:  17 7c 00 01 00 30   move.b #$01, $30(a3)     ; flush FIFO
408D1880:  17 7c 00 11 00 30   move.b #$11, $30(a3)     ; ICCS
408D1886:  61 ff ff fc 7e a2   bsr.l   $40899704        ; wait INT
408D1892:  14 2b 00 20         move.b  $20(a3), d2      ; status byte
408D189C:  14 2b 00 20         move.b  $20(a3), d2      ; message byte
408D18A6:  17 7c 00 12 00 30   move.b #$12, $30(a3)     ; message accepted
```
(That block is inside an undecoded hex region at `$408D1842`; bytes are quoted
verbatim, decode is analysis.)

Counts the disk boot actually produces: ROM boot read = 512 bytes
(`$4080735C move.w #$200,d4`); driver reads = *n*×512
(`$00001108 moveq #$9,d0 / lsl.l d0,d1 / move.l d1,$2c(a4)` for the 4.3 path,
`$00001348` for the old path).

---

## 5. Developer note on Turbo SCSI / IOSB PDMA

`docs/quadra800-developer-notes.md` is thin on the hardware and honest about
it. §12 (from the Apple Developer Note) gives only: controller is a **53C96**;
one driver IC serves internal + external, treated as "one virtual bus with a
single set of SCSI IDs"; automatic termination is sampled **during system
reset** (so hot-changing the bus leaves a stale termination decision); the
internal cable has no terminators. §1 places SCSI at `$50010000` (i.e.
`$50F10000` in the `$50F0` image) and puts IOSB at `$50012000`–`$50018000`,
with `$50040000`–`$53FFFFFF` being repeated images of `$50000000`–`$50040000` —
which is what makes the ROM's `+$40000` PDMA alias legal.

The note contains **no** hold-off timing, byte-lane, or latency rules from
Apple. What it does have is §13, "Apple SCSI is pseudo-DMA, and bus errors are
*normal*", quoted from NetBSD `sys/arch/mac68k/obio/esp.c` rather than from
Apple: the CPU is the DMA controller; DREQ is exposed through a register mapped
on the IOSB or DAFB; the memory controller handshakes data via a DACK space;
and **a bus error is the normal signal that the FIFO stalled** (full and not
draining on write, empty and not filling on read, or an interrupt condition).
The recovery recipe it quotes — disable the nofault handler, check for
interrupt, else check DREQ, else resume stuffing — is exactly what `$408D2606`
implements, including the "spin on DREQ or chip INT" at
`$408D2648`/`$408D264E`. The note also flags that NetBSD hardcodes spl values
to let serial interrupts in during transfers.

The note's "what this does not answer" list explicitly includes "Which SCSI
commands the ROM's driver issues during mount" — that gap is closed by §6
below.

Concrete latency/width rules the ROM implies but the note does not state:
16-byte granularity on non-blind reads (FIFO depth), the two `nop`s bracketing
each burst (`$408D1F7A`, `$408D1FB4`, `$408D1FBE`, `$408D20B0`, `$408D20D2`,
`$408D22F6`), the word-vs-long window split, and the IOSB
`$50F18300`/`$50F18400` fault-status and data-latch pair.

---

## 6. ROM boot scan, around `$408D1982`

**What was issued before the poll.** `$408D1982` is inside the generic SELECT
routine, which starts at `$408D1930` and is called from `$408D177A`. The bytes
at `$408D1930`–`$408D1980` sit in an undecoded hex region; quoted raw with
decode:

```
408D1930:  17 40 00 40          move.b d0, $40(a3)       ; reg4 write = SELECT BUS ID = target
408D1934:  17 7c 00 01 00 30    move.b #$01, $30(a3)     ; flush FIFO
408D193A:  08 00 00 10          btst   #16, d0           ; ATN flag (set at $408D176A for selector 11)
408D193E:  66 16                bne.b  $408D1956
408D1940:  17 47 00 10          move.b d7, $10(a3)       ; TC hi = 0
408D1944:  16 bc 00 01          move.b #$01, (a3)        ; TC lo = 1
408D1948:  17 7c 00 c1 00 30    move.b #$C1, $30(a3)     ; DMA | Select WITHOUT ATN
408D194E:  08 ec 00 01 01 58    bset   #1, $158(a4)
408D1954:  60 14                bra.b  $408D196A
408D1956:  17 47 00 10          move.b d7, $10(a3)
408D195A:  16 bc 00 01          move.b #$01, (a3)
408D195E:  17 7c 00 c2 00 30    move.b #$C2, $30(a3)     ; DMA | Select WITH ATN
408D1964:  08 ec 00 02 01 58    bset   #2, $158(a4)
408D196A:  08 ec 00 03 01 58    bset   #3, $158(a4)
408D1970:  72 00                moveq  #0, d1
408D1972:  32 38 0b 24          move.w $b24.w, d1        ; SCSI timeout constant
408D1976:  e1 89 e3 89          lsl.l #8,d1 / lsl.l #1,d1
408D197A:  24 01 48 42          move.l d1,d2 / swap d2
```
Then the loop itself:
```
408D1982:  2a 10                move.l (a0), d5          ; a0 = $44(a4) = $50F03A00
408D1984:  10 2c 01 60          move.b $160(a4), d0      ; DREQ bit index (0)
408D1988:  01 05                btst   d0, d5            ; ** DREQ short-circuit exit **
408D198A:  66 52                bne.b  $408D19DE         ; -> return 0
408D198E:  16 2b 00 40          move.b $40(a3), d3       ; STATUS
408D1992:  10 03                move.b d3, d0
408D1994:  08 00 00 07          btst   #7, d0            ; ** INT **
408D1998:  56 c9 ff e8          dbne   d1, $408D1982
408D199C:  56 ca ff e4          dbne   d2, $408D1982
408D19A0:  67 00 00 36          beq.w  $408D19D8         ; timed out -> d2 = 3
```
So the answer to "what command preceded it": **`$C1` or `$C2` — always the DMA
form of select, with the transfer counter preloaded to exactly 1 and an empty
FIFO.** Selection is not a plain `$41`/`$42`.

**What happens right after INT asserts:**
```
408D19A4:  16 2b 00 40          move.b $40(a3), d3       ; re-read STATUS (reg 4)
408D19A8:  12 2b 00 50          move.b $50(a3), d1       ; read INTERRUPT (reg 5) - clears it
408D19AC:  19 43 01 bf          move.b d3, $1bf(a4)      ; stash status
408D19B0:  19 41 01 be          move.b d1, $1be(a4)      ; stash interrupt
408D19B4:  08 ac 00 04 01 58    bclr #4,$158(a4)
408D19BA:  08 ac 00 03 01 58    bclr #3,$158(a4)
408D19C0:  08 ac 00 02 01 58    bclr #2,$158(a4)
408D19C6:  08 ac 00 01 01 58    bclr #1,$158(a4)
408D19CC:  08 01 00 05          btst   #5, d1            ; INT bit 5 = Disconnected
408D19D0:  67 00 00 0c          beq.w  $408D19DE
408D19D4:  74 02                moveq  #2, d2            ; -> "no device" / selection timeout
408D19DE:  74 00                moveq  #0, d2            ; -> selected OK
408D19E0:  20 02 4e 75          move.l d2,d0 / rts
```
No FIFO read, no sequence-step read, no follow-up command. The next chip write
only happens when the caller invokes SCSICmd (`$408D19E4`), which waits for
phase 2 via `$408D2436` and then does the split FIFO/PDMA CDB push shown in §1.

**The boot-scan sequence itself.** Two ROM callers drive it, both through
`_SCSIDispatch`:

*Bus probe*, `$40815C7A` (hex region, decoded):
```
40815C7A:  42 a7 42 a7          clr.l -(a7) / clr.l -(a7)     ; 8 zero bytes = TEST UNIT READY CDB
40815C7E:  3f 3c 00 01          move.w #$1, -(a7)             ; SCSIGet
40815C82:  a8 15                _SCSIDispatch
40815C88:  10 38 0c 2f          move.b $c2f.w, d0             ; target ID
40815C8C:  02 00 00 07          andi.b #$7, d0
40815C92:  3f 3c 00 02          move.w #$2, -(a7)             ; SCSISelect
40815C96:  a8 15                _SCSIDispatch
40815CA4:  48 6f 00 02          pea $2(a7)                    ; -> the zeroed CDB
40815CA8:  3f 3c 00 06          move.w #$6, -(a7)             ; CDB length 6
40815CAC:  3f 3c 00 03          move.w #$3, -(a7)             ; SCSICmd
40815CB0:  a8 15                _SCSIDispatch
40815CBA:  70 3c 2f 00          moveq #$3c,d0 / move.l d0,-(a7) ; 60 ticks
40815CC0:  3f 3c 00 04          move.w #$4, -(a7)             ; SCSIComplete
40815CC4:  a8 15                _SCSIDispatch
```
i.e. **SCSIGet → SCSISelect(id) → SCSICmd(TEST UNIT READY, 6 bytes) →
SCSIComplete(60 ticks)**, with a nonexistent target detected purely by INT reg
bit 5 after the `$C1` select.

*Block read* used for the partition map / driver / boot blocks, `$4080738A`:
```
40807392:  41f809fa             lea.l  $9fa.w, a0            ; CDB scratch in low memory
40807396:  10fc0008             move.b #$8, (a0)+            ; ** READ(6) **
4080739C:  0203001f             andi.b #$1f, d3              ; LBA bits 20:16
408073A0:  10c3 4843 30c3       ...                          ; LBA low 16
408073AA:  10c4 4218            ...                          ; block count, control = 0
408073B8:  3f 3c 00 01  a8 15   SCSIGet
408073C2:  3f 05 3f 3c 00 02  a8 15   SCSISelect(d5 = id)
408073CE:  48 78 09 fa  3f 3c 00 06  3f 3c 00 03  a8 15   SCSICmd($9FA, 6)
408073E0:  30 fc 00 01  20 ca  20 c4  30 bc 00 07   TIB = {scInc, buf, len}, {scStop}
408073EE:  2f 06  3f 3c 00 05  a8 15   ** SCSIRead - selector 5, NON-BLIND **
408073F8:  48 78 09 fa  48 78 09 fc  2f 3c 00 00 00 3c  3f 3c 00 04  a8 15   SCSIComplete
```
Caller `$4080735A` sets `moveq #1,d2` / `move.w #$200,d4` — one 512-byte block
per call — and then checks `'PM'` at `(a2)` and `"Apple_HFS"` at `$30(a2)`.

**Bottom line for the bench.** The ROM's disk boot exercises: `$01` flush,
`$C1` select-with-TC=1, FIFO PIO for the CDB with the final byte through
`$50F10100`, `$90` DMA transfer-info with **TC=16 per burst**, DREQ + STATUS
bit 4 + FIFO-flags-bit-4 gating, four `move.l` from `$50F50100`, `$11` ICCS,
two FIFO reads, `$12` message-accepted. Once `Apple_Driver43` takes over it
switches to READ(10)/WRITE(10) (`$28`/`$2A`, built at `$000012C2` and
`$000010EE`) and may additionally take the **blind** path (`$00001936` sets
`-$14(a5)` from a per-drive capability mask), which selects the unrolled
no-poll routines at `$408D228E`/`$408D216C` — those are the ones that will
fault into `$408D2606` if the window ever stalls.
