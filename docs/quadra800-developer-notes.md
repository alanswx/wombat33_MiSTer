# Quadra 800 developer notes — technical findings

Source: `DeveloperNotes_Quadra800.pdf` in this folder — Apple's
*Macintosh Centris 610/650 & Macintosh Quadra 800 Developer Note*
(Final Draft, 1995-03-09, "Preliminary, Confidential"). It covers all
three machines together; everything below applies to the Quadra 800
unless noted.

This is the machine-specific reference for the bench. Generic *Inside
Macintosh* volumes do not describe the MEMC/IOSB memory decode, the
NuBus-mapped built-in video, or the 64 MB RAM bank layout, which are the
parts that actually bite us.

## Address map (ch. 2, "Address Maps", fig. 2-4)

| Range | Contents |
|---|---|
| `$0000 0000` | RAM |
| `$4000 0000` | ROM |
| `$5000 0000` | I/O |
| `$6000 0000` | NuBus super slot space |
| `$F000 0000 – $FFFF FFFF` | **NuBus standard slot space** |

I/O device decode inside `$5000 0000`:

| Address | Device |
|---|---|
| `$5000 0000` | VIA1 (IOSB) |
| `$5000 2000` | VIA2 (IOSB) |
| `$5000 8000` | Ethernet PROM |
| `$5000 A000` | Ethernet |
| `$5000 C000` | SCC |
| `$5000 E000` | MEMC |
| `$5001 0000` | **SCSI** |
| `$5001 2000`–`$5001 8000` | IOSB |
| `$5001 A000` | Sound (IOSB) |
| `$5001 E000` | SWIM II (IOSB) |
| `$5002 8000` | KIWI controls |
| `$5004 0000`–`$53FF FFFF` | repeated images of `$5000 0000–$5004 0000` |

**Why this matters to us:** the built-in video is addressed as a NuBus
pseudo-slot, which is why `ScrnBase` reads `$F9001000` — slot `$9`
inside NuBus standard slot space, *not* a flat framebuffer aperture in
main memory. Anything the boot block or payload writes through
`ScrnBase` is going out into slot space.

## MMU (ch. 4, "Support for the Built-in MMU")

Direct quotes, because the details are load-bearing:

- "In the Macintosh Centris 610, Macintosh Centris 650, and Macintosh
  Quadra 800 computers, the MMU is set up to support **only one ROM
  address space and one I/O address space**. Actually, only one address
  space for each is necessary, and mapping one image of each address
  space reduces the size of the MMU tables."
- "…combine an MMU with built-in video using frame buffers in separate
  banks of VRAM. **The ROM software manages the address space for the
  video frame buffers separately from main memory.**"
- "The MMU operation codes on the MC68040 are different from those on
  the MC68030. For example, both microprocessors have a PTEST
  operation, but the PTEST operation code for the MC68030 generates an
  unimplemented-instruction exception on the MC68040."

**Why this matters to us:** the ROM is actively managing translation for
the framebuffer address space, separately from RAM. A boot block that
installs its own transparent translation over `$F000 0000–$FFFF FFFF`
is overriding a mapping the ROM deliberately set up — see
`SingleStepTests/test-blockers.md` finding 11, which was derived from
emulator behaviour and has **not** been confirmed on hardware.

## RAM banks (ch. 4, "Support for Memory on 64 MB Boundaries")

- "Main RAM … consists of from one to ten banks that begin on **64 MB
  boundaries**. At startup time, the ROM software determines the amount
  of RAM installed in each bank and stores the actual bank sizes in
  registers in the MEMC IC. Using those bank sizes, **the MEMC IC decodes
  bus addresses so that the installed banks of RAM occupy contiguous
  addresses in physical memory space**."
- Quadra 800: 8 MB minimum (4 SIMMs), **136 MB maximum**.

So "contiguous RAM" is a hardware decode done by MEMC from bank-size
registers, not an MMU mapping — worth remembering when reasoning about
physical addresses on a heavily-populated machine.

## Video / VRAM (ch. 1 and ch. 4)

- Ships with **512 KB VRAM**, expandable to **1 MB**.
- Frame buffers live in dedicated VRAM controlled by the MEMC IC.
- Up to 16 bpp depending on VRAM and monitor; 640×480 is 8 bpp at
  512 KB.
- The MC68040 lacks the 68020/68030 "byte smearing" behaviour, so the
  ROM patches older Apple video cards' primary init and video driver.

## Startup sequence (ch. 4, table 4-1)

| Stage | Location of code | Executed by |
|---|---|---|
| Diagnostics | ROM | ROM |
| **Boot blocks** | **Disk** | **ROM** |
| Startup arbitration | `'boot' 2` resource | System |
| Startup code | `'boot' 3` resource | System, ROM, or enabler |

Confirms the mechanism the bench relies on: the ROM itself reads and
executes the disk's boot blocks, before any System software is involved.
A bench that lives entirely in the boot block plus a payload is using
the sanctioned path, not a trick.

## ROM (ch. 4, "ROM Software", fig. 4-1)

- 1 MB ROM. First half is an overpatch of the 512 KB Macintosh II-family
  ROM; second half is new MC68040 support code.
- Based on the Macintosh IIci ROM, preserving as much of the original
  image as possible.
- Startup diagnostics sit at the end of the code section; the
  declaration ROM is always at the highest addresses.

## SCSI (ch. 2)

- Controller is the **53C96**.
- Quadra 800 has space for three internal SCSI devices plus a floppy;
  supports up to four internal SCSI devices.
- **Automatic termination:** when no external device is connected,
  circuitry on the logic board terminates the bus near the external
  connector. When an external device is present, the circuitry detects
  its termination during **system reset** and disconnects the logic-board
  termination.
- The device at the end of the internal cable must be terminated; all
  other internal devices must have their terminators removed.

Note the automatic termination is sampled **at system reset** — relevant
when hot-plugging or changing what is on the bus without a power cycle.

## Custom ICs (ch. 2)

- **MEMC** — control and timing for ROM, RAM and VRAM; system bus
  arbitration; frame buffer controller (video timing/control).
- **IOSB** — VIA1, VIA2, SWIM II, ADB, sound, SCC glue.
- **KIWI** — NuBus controller.

## Open questions this document does *not* answer

- The exact boot-block validity checks the ROM applies before executing
  a boot block (`bbID`/`bbEntry`/`bbVersion`), and what it does on
  failure.
- Which startup-diagnostic failures produce which Sad Mac codes.
- Whether the ROM validates `pmBootCksum` in the Apple Partition Map
  before loading a disk's driver.

For those, the 1 MB ROM image itself is the authority — disassembling
its mount and boot-block path is more reliable than any secondary
source.
