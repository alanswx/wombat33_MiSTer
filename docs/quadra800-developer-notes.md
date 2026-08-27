# Quadra 800 developer notes — technical findings

Source: `DeveloperNotes_Quadra800.pdf` in this folder — Apple's
*Macintosh Centris 610/650 & Macintosh Quadra 800 Developer Note*
(Final Draft, 1995-03-09, "Preliminary, Confidential"). It covers all
three machines together; everything below applies to the Quadra 800
unless noted.

This is the machine-specific reference for the bench. Generic *Inside
Macintosh* volumes do not describe the MEMC/IOSB address decode, the
NuBus-mapped built-in video, the 64 MB RAM bank layout, or the ROM's
68040 cache and exception handling — which are the parts that bite us.

## 1. Address map (ch. 2, figs. 2-4 / 2-5)

| Range | Contents |
|---|---|
| `$0000 0000` | RAM |
| `$4000 0000` | ROM |
| `$5000 0000` | I/O |
| `$6000 0000 – $EFFF FFFF` | NuBus **super** slot space (256 MB/slot) |
| `$F000 0000 – $FFFF FFFF` | NuBus **standard** slot space (16 MB/slot) |

I/O decode inside `$5000 0000`:

| Address | Device |
|---|---|
| `$5000 0000` | VIA1 (IOSB) |
| `$5000 2000` | VIA2 (IOSB) |
| `$5000 8000` | Ethernet PROM |
| `$5000 A000` | Ethernet |
| `$5000 C000` | SCC |
| `$5000 E000` | MEMC |
| `$5001 0000` | **SCSI (53C96)** |
| `$5001 2000`–`$5001 8000` | IOSB |
| `$5001 A000` | Sound (IOSB) |
| `$5001 E000` | SWIM II (IOSB) |
| `$5002 8000` | KIWI controls |
| `$5004 0000`–`$53FF FFFF` | repeated images of `$5000 0000–$5004 0000` |

Slot allocations (fig. 2-5):

| Standard slot space | Super slot space | Slot |
|---|---|---|
| `$F900 0000 – $F9FF FFFF` | `$9000 0000` | **Video slot space** |
| `$F800 0000` | `$8000 0000` | Expansion slot `$8` |
| `$FA00 0000` | `$A000 0000` | Expansion slot `$A` |
| `$FB00 0000` | `$B000 0000` | Expansion slot `$B` |
| `$FC00 0000` | `$C000 0000` | NuBus slot `$C` |
| `$FD00 0000` | `$D000 0000` | NuBus slot `$D` |
| `$FE00 0000` | `$E000 0000` | NuBus slot `$E` / PDS |

**Bench relevance.** The built-in video is a NuBus pseudo-slot, which is
why `ScrnBase` reads `$F9001000`. The *slot window* is 16 MB
(`$F900 0000–$F9FF FFFF`) but actual VRAM is only 512 KB–1 MB (§4), so
most of that window has nothing behind it. Any framebuffer write that
runs past real VRAM is an access to unoccupied slot space.

## 2. MMU (ch. 4, "Support for the Built-in MMU")

- "the MMU is set up to support **only one ROM address space and one I/O
  address space**. Actually, only one address space for each is
  necessary, and mapping one image of each address space reduces the
  size of the MMU tables."
- "…combine an MMU with built-in video using frame buffers in separate
  banks of VRAM. **The ROM software manages the address space for the
  video frame buffers separately from main memory.**"
- "The MMU operation codes on the MC68040 are different from those on
  the MC68030. For example, both microprocessors have a PTEST
  operation, but the PTEST operation code for the MC68030 generates an
  unimplemented-instruction exception on the MC68040."

**Bench relevance.** The ROM actively manages translation for the
framebuffer, separately from RAM. A boot block installing its own
transparent translation over `$F000 0000+` overrides a mapping the ROM
deliberately built — see `SingleStepTests/test-blockers.md` finding 11,
which was derived from emulator behaviour and is **not** confirmed on
hardware.

## 3. Caches (ch. 4, "Support for the New Copyback Cache Mode")

- The 68040 D-cache defaults to **CopyBack**, unlike the WriteThru
  caches of the 68020/68030. Main memory does **not** always hold the
  latest data.
- The ROM flushes the data cache to main memory after **loading a
  resource**, **moving a heap block**, and **creating a jump table** —
  i.e. after writing anything that will later be executed.
- The ROM uses **only pages marked uncacheable** when setting up
  communication areas with alternate bus masters.
- For applications: "flushing only the instruction cache … is not
  sufficient." `_FlushInstructionCache` on the 68040 **flushes both
  caches**, and doing both in one call "avoids problems in situations in
  which interrupts might occur while the caches are being flushed
  individually." See Macintosh Technical Note 261, *"Cache as Cache
  Can."*
- Explicit warning not to flush *too often* — it costs real performance.

**Bench relevance.** Independent confirmation of finding 7: loading code
and jumping to it on an 040 requires a data-cache push, not just an
I-cache invalidate. Also note the interrupt-race caveat — our boot block
brackets `_Read` with `CPUSHA BC` while at IPL 7, which is consistent
with the ROM's own reasoning.

## 4. Video / VRAM (ch. 1, ch. 4)

- **512 KB VRAM** standard, expandable to **1 MB**. 640×480 is 8 bpp at
  512 KB.
- Frame buffers are in dedicated VRAM controlled by the MEMC IC.
- The 68040 lacks the 68020/68030 **byte smearing** behaviour, so the
  ROM patches the primary init and video driver of the Macintosh II
  Video Card, Portrait Video Card and Two-Page Video Card.

## 5. Exception handling (ch. 4, "New Exception Handlers")

- "Unlike the previous processors in the 68000 family, the MC68040
  handles exceptions by the method called **instruction restart**."
- "the MC68040 creates some **new exception stack frames**, including
  those for its version of bus errors, which are called **access
  errors**."
- "Exception handlers, **particularly bus error handlers**, are affected
  by these differences. The ROM software includes appropriate changes to
  the universal startup code and **modified bus error handlers for the
  Slot Manager and the Memory Manager**."

**Bench relevance.** Two things. First, `recovery.s` installs its own
vector 2 handler and must cope with the 68040 access-error frame
(format `$7`, 60 bytes), not a 68020/030 bus-error frame. Second, the
ROM's *Slot Manager* bus-error handler is the mechanism by which the Mac
safely probes non-responding slot addresses — which is exactly the class
of access a framebuffer overrun produces.

## 6. FPU (ch. 4, "Support for the Built-in FPU")

- The 68040 FPU "does not handle all the instructions and data types
  that the MC68881 and MC68882 handle, so the ROM software includes new
  code to deal with those instructions and data types. For example,
  **the exception vector table has a new exception vector to software
  that handles data types not supported by the FPU**."
- FPU detection differs from earlier ROMs; applications still use
  Gestalt/SysEnvirons.
- Floating-point ROM code includes ΩSANE, speeding SANE calls made via
  A-traps.
- The Centris 610 and some Centris 650 configurations use the
  **MC68LC040**, which has no FPU.

**Bench relevance.** Supports the 040-lite decision: unimplemented FP
operations are expected to vector to software, not execute.

## 7. RAM (ch. 2 "RAM"; ch. 4 "Support for Memory on 64 MB Boundaries")

- Quadra 800: **8 MB minimum**, four 72-pin SIMM slots, **132 MB max**
  (4 MB on logic board) or **136 MB max** (8 MB on logic board).
- "Main RAM … consists of from one to ten banks that begin on **64 MB
  boundaries**. At startup time, the ROM software determines the amount
  of RAM installed in each bank and stores the actual bank sizes in
  registers in the MEMC IC. Using those bank sizes, **the MEMC IC
  decodes bus addresses so that the installed banks of RAM occupy
  contiguous addresses in physical memory space**."

So contiguous RAM is a *hardware* decode by MEMC from bank-size
registers, not an MMU mapping.

## 8. Virtual memory / page attributes (ch. 4)

- `LockMemory`, `LockMemoryContiguous`, `UnlockMemory` can change the
  attributes of individual pages **even without VM running**.
- New calls `ProtectMemory` / `UnprotectMemory` add page write
  protection.
- Communication buffers shared with alternate bus masters must be marked
  uncacheable; turning the whole cache off (acceptable on 020/030) would
  cost too much on an 040.

## 9. MOVE16 (ch. 4, "An Enhanced BlockMove Routine")

- The ROM's `BlockMove` uses `MOVE16` on the 040.
- **Warning, verbatim:** "If you plan to use the `MOVE16` instruction in
  code you are writing, you should be aware that there are limitations
  on its use. For more information, refer to the latest MC68040 errata
  sheet from Motorola."

**Bench relevance.** Apple themselves flag `MOVE16` as errata-encumbered
— consistent with our corpus marking the `MOVE16` row `hw_unsafe`.

## 10. Startup sequence (ch. 4, table 4-1)

| Stage | Location of code | Executed by |
|---|---|---|
| Diagnostics | ROM | ROM |
| **Boot blocks** | **Disk** | **ROM** |
| Startup arbitration | `'boot' 2` resource | System |
| Startup code | `'boot' 3` resource | System, ROM, or enabler |

Confirms the bench's mechanism: the ROM itself reads and executes the
disk's boot blocks before any System software is involved.

## 11. ROM (ch. 4, "ROM Software", fig. 4-1)

- 1 MB ROM, same as Quadra 700/900. Supports 68020, 68030 and 68040.
- Based on the **Macintosh IIci** ROM, preserving as much of the
  original image as possible; the first half is an overpatch of the
  512 KB Macintosh II-family ROM.
- Layout: ROM code → overpatch area → ROM resources → free space → new
  ROM resources → **declaration ROM always at the highest addresses**.
- **Startup diagnostics sit at the end of the code section.**

## 12. SCSI (ch. 2, "SCSI Bus and Termination")

- Controller: **53C96**. Quadra 800 supports up to four internal SCSI
  devices plus a floppy.
- One SCSI driver IC serves both internal and external devices; the
  software "treats the two hardware buses as one virtual bus with a
  single set of SCSI ID numbers."
- **Automatic termination:** with no external device, logic-board
  circuitry terminates the bus near the external connector. With an
  external device present, the circuitry detects its termination
  **during system reset** and disconnects the logic-board termination.
- The **internal cable has no built-in terminators**; the internal device
  at the end of the cable must include them, and all other internal
  devices must have theirs removed.

**Bench relevance.** Termination state is sampled **at system reset**,
so changing what is on the bus without a power cycle leaves the machine
with a stale termination decision.

## What this note does *not* answer

- The boot-block validity checks the ROM applies (`bbID` / `bbEntry` /
  `bbVersion`) and its behaviour on failure.
- The Sad Mac code table — which startup diagnostic maps to which code.
- Whether the ROM validates `pmBootCksum` in the Apple Partition Map
  before loading a disk's driver.
- Which SCSI commands the ROM's driver issues during mount.

For all four, the 1 MB ROM image is the authority. Disassembling its
mount and boot-block path is more reliable than any secondary source.
