# SDRAM sharing for 1 MB of VRAM — clock/timing scoping

**Status:** analysis only. No RTL changed. Written 2026-08-30 against
`rtl/sdram.sv`, `rtl/dafb.sv`, `wombat33.sv` @ `9cfd1b3`.

**The ask:** the Quadra 800 wants **1 MB of VRAM**. That does not fit in
on-chip BRAM, so VRAM has to move into SDRAM alongside the machine's RAM.
This doc answers: what the SDRAM timing is today, what a real Q800 does,
what MAME does, and how to schedule the two masters so the video fetch
costs the CPU (almost) nothing.

---

## 0. Answers up front

| Question | Answer |
|---|---|
| **What is our SDRAM timing right now?** | Every access is a full row cycle: `ACT → NOP → RD/WR+autoprecharge → 4 idle`. **7 `clk_ram` cycles per 16-bit word**, no page hits ever. A 32-bit machine beat is two of those plus two clock-domain crossings = **8 `clk_sys` cycles ≈ 242 ns ≈ 16.5 MB/s**. |
| **What does a real Quadra 800 need?** | Not 60 ns fast-page. Apple's developer note says **80 ns VRAM** (Centris 610 = 100 ns), on a **separate VRAM data bus** (`BDb31-0`) behind its own transceivers, distinct from the RAM bus (`BDa31-0`). Real hardware has *no* RAM/VRAM contention because they are physically different buses. |
| **How does MAME do it?** | It doesn't. `dafb.cpp` is a flat `std::unique_ptr<u32[]>`; `vram_r`/`vram_w` are bounds-checked array accesses; `screen_update` walks the array directly. **Zero cycle, contention, arbitration, wait-state or refresh modelling.** MAME is useless as a timing oracle here — but it does confirm the size: `m_vram_size` is 1 MB for the MEMC/djMEMC variants. |
| **How do we steal cycles with no contention?** | `clk_ram` is exactly **3 × `clk_sys` from the same PLL**, phase-aligned. That gives 3 SDRAM command slots per machine cycle. Reserve slot 0 for the CPU and slots 1–2 for video, put VRAM in its own bank with the row held open across a scanline, and drain into a line FIFO. Video at 16 bpp needs 48.3 MB/s out of the 66 MB/s its slots provide — **contention-free by construction**, and the CPU still comes out *faster* than today. |

The headline: **you cannot bolt VRAM onto the current controller.** It tops out
at 28.3 MB/s and 8 bpp scanout alone needs 24.1 MB/s average / 33.0 MB/s peak.
But the rework that makes VRAM possible also takes RAM from 16.5 MB/s to
~33–56 MB/s. This is not a trade — it's a straight win with work attached.

---

## 1. Clock inventory

From `rtl/pll/pll_0002.v` and `wombat33.sv:143-156`:

| Clock | Freq | Period | Source | Consumers |
|---|---|---|---|---|
| `clk_sys` | 33.000 MHz | 30.303 ns | PLL `outclk_0` | machine, CPU, DAFB, dot clock, `DDRAM_CLK` |
| `clk_ram` | 99.000 MHz | 10.101 ns | PLL `outclk_1` | `sdram.sv` |
| `SDRAM_CLK` | 99.000 MHz | 10.101 ns | `altddio_out` in `sdram.sv:270` | the SDRAM chip |

Three facts that the whole design rests on:

1. **`clk_ram` = 3 × `clk_sys`, same PLL.** They are phase-aligned. Any
   fixed slot wheel built on this ratio needs no synchronisers and no FIFO
   between the machine's cycle and the SDRAM's cycle.
2. **`SDRAM_CLK` is `clk_ram` inverted** (`datain_h=0, datain_l=1`), so the
   chip's rising edge lands in the *middle* of an FPGA cycle. Commands get
   half a period (5.05 ns) of setup on the way out and read data gets half a
   period on the way back. That margin is why CL=2 works at 99 MHz.
3. Real Q800 bus clock is **33.33 MHz** (dev note ch. 2, "Processor Clock
   Speeds"). We run 33.000. Within 1%.

**Not a clock, but relevant:** `dafb.sv` scans out 640×480 inside an 800×525
frame at one pixel per `clk_sys`, i.e. a 33 MHz dot clock → **78.57 Hz**. Real
13" Mac timing is a 30.24 MHz dot clock in 864×525 → 66.67 Hz. We are asking
for **18% more video bandwidth than the real machine does.** If the video path
is being touched anyway, moving to the authentic dot clock is free bandwidth
(see §7).

---

## 2. What the SDRAM controller does today

`rtl/sdram.sv` is Sorgelig's NeoGeo controller. Mode register
(`sdram.sv:71-76`): `CAS_LATENCY=2`, `BURST_LENGTH=4`, `NO_WRITE_BURST=1`.

Address mapping (`sdram.sv:222`) — note `A10=1` on every RD/WR, i.e.
**auto-precharge on every access**:

```
{cas_addr[12:9], SDRAM_BA, SDRAM_A, cas_addr[8:0]} <= {~wr ? 2'b00 : ~bs, 1'b1, addr[25:1]};
                                                        \_ DQM _/   \_A10_/
  row  = addr[22:10]      bank = addr[24:23]      col = {addr[25], addr[9:1]}
```

### 2.1 One 16-bit access — 7 `clk_ram` cycles

Outputs are registered, so a command assigned in state *N* appears on the pins
one cycle later.

```
clk_ram cycle    0     1     2     3     4     5     6     7     8     9    10
                _|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__

state           IDLE  WAIT   RW   ID4   ID3   ID2   ID1  IDLE  WAIT   RW   ID4
                  |                                        \___ next access
cmd on pins      --   ACT   NOP    RD   NOP   NOP   NOP   NOP   ACT   NOP    RD
A10                     -     -     1                             -     -     1
                      |<-tRCD->|                                |<-tRCD->|
                       20.2 ns                                   20.2 ns

DQ (chip drives)                        ····<d0><d1><d2><d3>····
                                            |    \___\___\___ discarded
                                       CL=2 |
dout (registered)                       ---------< d0 >-------------------
ready           ‾‾‾‾‾‾‾‾‾‾\_______________________/‾‾‾‾‾\_________________

                |<--------- 7 cycles = 70.71 ns --------->|
                |<-------------- tRC (>= 60 ns) OK ------>|
```

Three things worth naming:

- **`BURST_LENGTH=4` is already in the mode register, so every READ already
  returns 4 words — 3 of them are thrown away.** Eight bytes per row cycle are
  being fetched and 6 discarded, today, for free. Capturing them is the
  cheapest possible bandwidth win in this file.
- **ACT-to-ACT is 70.71 ns.** `tRC` for a -6/-7 grade part is 60–70 ns, so the
  current design sits *exactly* on the edge for a 70 ns part. Any future
  scheduler must keep same-bank ACT-to-ACT ≥ 7 cycles (or ≥ 6 for a 60 ns
  part) — this is the constraint that makes single-access-per-row so costly
  and bank interleaving so valuable.
- **No page hits, ever.** Auto-precharge closes the row after every single
  word. Sequential access pays the full `tRCD` + `tRC` every time.

Ceiling: 1 word / 7 cycles = 14.14 M words/s = **28.3 MB/s**, before any CDC.

### 2.2 One 32-bit machine beat — 8 `clk_sys` cycles

`wombat33.sv:341-395` splits a beat into two 16-bit accesses and crosses two
clock domains with toggle handshakes.

```
clk_sys        0        1        2        3        4        5        6        7        8
             __|‾‾|_____|‾‾|_____|‾‾|_____|‾‾|_____|‾‾|_____|‾‾|_____|‾‾|_____|‾‾|_____|
clk_ram       0  1  2 | 3  4  5 | 6  7  8 | 9 10 11 |12 13 14 |15 16 17 |18 19 20 |21 22 23

sdr_req_tgl  _/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
req_sync[0]  ______/‾‾‾‾‾‾‾‾‾‾‾‾‾‾   \                                    2-FF sync in
req_sync[1]  _________/‾‾‾‾‾‾‾‾‾‾‾    +-- 2 clk_ram
sdr_busy_r   ____________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\____________

cmd on pins   .  .  .  .  A  .  R  .  .  .  .  A  .  R  .  .  .  .  .
                          C     D           C     D
                          T                 T
              |<-- sync ->|<- half 0: 7 ->|<- half 1: 7 ->|
                                                          |
sdr_ack_tgl  ______________________________________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
ack_sync[0]  __________________________________________________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾
ack_sync[1]  ___________________________________________________________________/‾‾‾‾‾
mem_ack      ________________________________________________________________________/‾‾\
                                                          |<-- 2-FF sync out (clk_sys) -->|

              |<----------------- 8 clk_sys = 24 clk_ram = 242.4 ns ------------------->|
```

Budget: **2 clk_ram in, 14 clk_ram of SDRAM, ~8 clk_ram (2–3 `clk_sys`) out.**
The crossings are 41% of the beat. The machine's mem port is fully serialised
(one beat outstanding), so:

> **Current RAM throughput: 4 bytes / 242.4 ns = 16.5 MB/s.**

For scale, a real Q800 doing a 68040 burst line fill out of 80 ns page-mode
DRAM on a 33 MHz bus lands somewhere around 45–50 MB/s (estimate — the
developer note does not publish the RAM state machine). We are roughly 3×
slower than the machine we are emulating, and the 68040 caches are doing the
hiding.

### 2.3 Refresh

`wombat33.sv:334-340` toggles `sdr_refresh` every 772 `clk_ram` cycles (7.8 µs).
`STATE_IDLE`→`STATE_RFSH` issues AUTO REFRESH to both chip halves and burns
**7 cycles every 772 = 0.9%**. Correct for 8192 rows / 64 ms. Keep this budget;
nothing below changes it materially.

---

## 3. What a real Quadra 800 does

From `docs/DeveloperNotes_Quadra800.pdf` (Final Draft, 1995):

- **ch. 1, p.10:** *"The VRAM in the Macintosh Centris 610 computer uses 100-ns
  devices; the VRAM in the Macintosh Centris 650, and Macintosh Quadra 800
  computers uses **80-ns** devices. The video controller … has been programmed
  to take advantage of the faster VRAM, speeding up video performance by as
  much as 20 percent compared to that of the Macintosh Quadra 700."*
- **ch. 1, p.10:** 512 KB standard, sockets to expand to 1 MB.
- **ch. 2, fig. 2-1 (block diagram):** the CPU bus fans out through **two
  independent sets of bidirectional transceivers** — `BDa31-0` to ROM SIMM +
  RAM SIMMs, and **`BDb31-0` to the VRAM / VRAM SIMM.** Both are driven by MEMC.
- **ch. 2, p.16:** *"The MEMC provides the control and timing signals for the
  ROM, RAM, and VRAM. It also includes … the frame buffer controller that
  provides the video timing and control signals."*

**So the user's "60 ns fast page RAM" guess is close but off on two counts:
it's 80 ns, and it's VRAM on its own bus, not main-RAM DRAM.**

What 1 MB actually buys, from Table 1-4 (byte arithmetic checked against each
row, since the OCR misaligns the monitor-type column):

| Display | 512 KB VRAM | 1 MB VRAM | bytes @ 16 bpp |
|---|---|---|---|
| 13" colour, 640×480 | 8 bpp | **16 bpp** | 614,400 |
| 16" colour, 832×624 | 8 bpp | 16 bpp | 1,038,336 |
| 21", 1152×870 | 4 bpp | 8 bpp | — |

`dafb.sv` hardwires the monitor sense to 13" 640×480 (`dafb.sv:145-147`), so
**1 MB = "Thousands" in the Monitors control panel**. That is the feature.

### 3.1 The architectural lesson

```
              REAL Q800: one scanline, ~29.6 us at 66.67 Hz
              |<------------------------------------------------------>|

  VRAM random   [CPU][CPU][CPU][CPU][CPU]  X  [CPU][CPU][CPU] ... [CPU]
  port (DRAM)    QuickDraw has the port essentially 100% of the line
                                           |
                                           +-- ONE row->SAM transfer cycle
                                               loads the next whole line

  VRAM serial   ###### shift register clocks pixels out on the dot clock ######
  port (SAM)    costs the DRAM port nothing at all
```

Apple's parts are *VRAM* — dual-ported video DRAM with a serial access port —
which is the standard architecture for this era and is consistent with the note
crediting the 80 ns speed grade with *"speeding up video performance"* (on a
Mac that means QuickDraw, i.e. **CPU writes** through the random port). The
developer note does not spell out the transfer-cycle scheme, so treat the SAM
detail as period-standard inference; what *is* documented and what actually
matters for us is the separate bus.

**The design instruction we take from this: the line buffer *is* the SAM.**
A real Q800 pays one row-transfer cycle per scanline and nothing else. Our job
is to make our SDRAM cost the CPU about that much.

---

## 4. What MAME does

Verified against `mamedev/mame` `src/mame/apple/dafb.cpp` (fetched 2026-08-30):

```cpp
m_vram_size(0x200000),                       // 2 MB base; 1 MB for MEMC/MEMCjr
m_vram = std::make_unique<u32[]>(m_vram_size);

u32 dafb_base::vram_r(offs_t offset) {
    if (offset >= (m_vram_size>>2)) return 0;
    return m_vram[offset];
}
void dafb_base::vram_w(offs_t offset, u32 data, u32 mem_mask) {
    if (offset >= (m_vram_size >> 2)) return;
    COMBINE_DATA(&m_vram[offset]);
}
// screen_update:
auto const vram8 = util::big_endian_cast<u8 const>(&m_vram[0]) + m_base;
```

**There is no timing model whatsoever** — no cycle counting, no wait states, no
bus arbitration, no refresh, no CPU stall on VRAM access. MAME models the DAFB
*registers* and the VBL/cursor scanline timers, and nothing else.

Two takeaways:

1. **Do not look to MAME for the arbitration answer.** It has none. Everything
   in §5–6 has to be derived from first principles + the SDRAM datasheet.
2. **MAME does confirm the size target.** `dafb.cpp` drops `m_vram_size` to
   **1 MB** for the MEMC/MEMCjr (djMEMC = Q800) variants, matching
   `rtl/quadra800.sv:16`'s *"$F9000000-$F91FFFFF DAFB VRAM (1 MB mirrored)"*.

---

## 5. The bandwidth problem, stated numerically

### 5.1 What the scanout demands

`dafb.sv` fetches one 32-bit word every `pix_per_word` pixels; 640×480 active
in an 800×525 frame at 33 MHz = 78.57 fps, 73.1% active duty.

| Depth | px/word | words/frame | **avg MB/s** | **peak MB/s** (during active) |
|---|---|---|---|---|
| 1 bpp | 32 | 9,600 | 3.0 | 4.1 |
| 2 bpp | 16 | 19,200 | 6.0 | 8.3 |
| 4 bpp | 8 | 38,400 | 12.1 | 16.5 |
| **8 bpp** | 4 | 76,800 | **24.1** | **33.0** |
| **16 bpp** | 2 | 153,600 | **48.3** | **66.0** |

### 5.2 Against what the controller supplies

```
                         0        25       50       75      100      125 MB/s
                         |---------|--------|--------|--------|--------|
  today's SDRAM ceiling  |#########|###|                        28.3       (1 word / 7 clk)
  today's RAM path       |#####|                                16.5       (incl. both CDCs)
  8 bpp video, average   |#########|##|                         24.1
  8 bpp video, peak      |#########|#####|                      33.0   <-- already over
  16 bpp video, average  |#########|#########|####|             48.3   <-- 1.7x over
  16 bpp video, peak     |#########|#########|#########|#####|  66.0   <-- 2.3x over
  page-mode ceiling      |#########|#########|#########|#########|#########|... 198
```

**Conclusion: the current controller cannot host VRAM at any usable depth, at
any arbitration scheme, with zero CPU traffic.** There is no cycle-stealing
trick that rescues it. The controller has to learn page mode.

---

## 6. Proposed design

Four pieces. Each is independently useful; (a) and (b) are worth doing even if
VRAM never moves.

### (a) Page mode — keep the row open, drop auto-precharge

With the row already open, a 32-bit beat is **2 command slots and 2 data
slots**:

```
clk_ram        0     1     2     3     4     5
cmd           RD    RD    --    --    --    --        row already open (page hit)
DQ                       ····<d0>·<d1>····
                        |<CL=2>|
                                       ^ 32 bits complete, 4 cycles latency,
                                         2 cycles of bus occupancy
```

Row miss in the same bank:

```
clk_ram        0     1     2     3     4     5     6     7     8
cmd           PRE   --    ACT   --    RD    RD    --    --    --
                   |<tRP>|     |<tRCD>|          ····<d0>·<d1>····
              |<-------- 8 cycles, 4 command slots -------->|
```

Row miss in a *different* bank (nothing to precharge — the other row stays
open):

```
clk_ram        0     1     2     3     4     5     6
cmd           ACT   --    RD    RD    --    --    --
              |<tRCD>|                ····<d0>·<d1>····
              |<----- 6 cycles, 3 command slots ----->|
```

68040 access has strong locality (cache line fills, sequential code), so most
CPU beats become page hits. Even assuming *every* beat is a different-bank
miss at 6 cycles, that is **16.5 M beats/s = 66 MB/s — 4× today.**

`tRAS(min)` (42–45 ns = 5 cycles) and `tRC` (60–70 ns = 6–7 cycles) still bound
same-bank ACT→ACT; the scheduler must track per-bank open row + last-ACT time.
That's the main new state.

### (b) Kill or hide the CDC

The two toggle handshakes cost 8 of the 24 `clk_ram` cycles in a beat. Because
`clk_ram` is exactly 3× `clk_sys` **from the same PLL and phase-aligned**, the
synchronisers are not needed at all — a `clk_sys`-edge strobe can be derived
inside the `clk_ram` domain with a divide-by-3 phase counter and a single
registered handoff. Saves ~80 ns per beat on its own.

*(Caveat: the `.qsf` already notes hold-slack on `clk_ram` swinging with
placement at 82% ALM utilisation. Removing synchronisers tightens that
domain. Budget a fitter-seed hunt, and see §8.)*

### (c) VRAM in its own bank, row held open across a scanline

The ROM programs a **1024-byte row pitch** (confirmed on hardware and by the
sim's `[DAFB]` tap, `wombat33.sv:443-447`). An SDRAM row on a 32 MB part is
512 columns × 16 bits = **1024 bytes**.

> **One DAFB scanline = exactly one SDRAM row.**

So a whole line fetch is: ACT once, stream reads, PRE once. On a 64 MB part
(1024 columns = 2048 B/row) it is one ACT per *two* scanlines.

```
    line fetch, row open, pipelined single reads (BL=1 or BL=2)

clk_ram    0    1    2    3    4    5    6    7    8   ...   n   n+1  n+2
cmd       ACT   --   RD   RD   RD   RD   RD   RD   RD  ...  RD   PRE   --
          |<tRCD>|
DQ                       ····<w0><w1><w2><w3><w4><w5>·······<wN>····
                        |<CL=2>|
                                 ^ one 16-bit word EVERY clk_ram = 198 MB/s
```

Cost of a full line, including ACT/PRE/CL drain:

| Depth | bytes/line | words | cycles | of 2400 (`clk_ram`/line) |
|---|---|---|---|---|
| 8 bpp | 640 | 320 | ~326 | **13.6%** |
| 16 bpp | 1280 | 640 | ~646 | **26.9%** |

Plus refresh: 3.1 auto-refreshes per scanline × 7 cycles = **0.9%**. Note that
AUTO REFRESH requires *all* banks precharged, so the video row must be closed
and reopened around each one — cheapest done in a reserved window at the top of
hblank (4 refreshes × 9 cycles = 36 of the 480 hblank cycles).

**CPU keeps ~85% of the SDRAM at 8 bpp, ~72% at 16 bpp.**

### (d) The slot wheel — "no contention" by construction

This is the direct answer to *"how can we steal cycles so there is no
contention."* Because `clk_ram` is exactly 3× `clk_sys`, every machine cycle
contains exactly three SDRAM command slots. Hard-assign them:

```
   clk_sys       |<----- N ----->|<---- N+1 ---->|<---- N+2 ---->|
   clk_ram        0    1    2      3    4    5      6    7    8
   slot          [C]  [V]  [*]    [C]  [V]  [*]    [C]  [V]  [*]
                  |    |    |
                  |    |    +--- spare: refresh, ACT/PRE, 2nd video word
                  |    +-------- VIDEO  1 word/clk_sys = 66.0 MB/s ceiling
                  +------------- CPU    1 word/clk_sys = 66.0 MB/s ceiling
                                        (2 words/beat -> 8.25 M beats/s = 33 MB/s)
```

- Video at 16 bpp needs **48.3 MB/s of its 66.0 MB/s** allocation. Fits, with
  26% headroom, *without ever looking at what the CPU is doing.*
- CPU gets a guaranteed **33 MB/s of 32-bit beats — double today's 16.5 MB/s**,
  with a hard bound of 3 `clk_ram` (30 ns) before its next slot comes round.
- The spare slot absorbs refresh (0.9%) and row management.

**Nothing can starve anything. No arbiter, no priority inversion, no worst-case
analysis.** That is the version to build first, because it is trivially
provable.

**Then, if more CPU throughput is wanted:** replace the fixed wheel with demand
arbitration — video is lowest priority *except* when its line FIFO drops below
threshold. Averaged over a line the video only actually wants 13.6% (8 bpp) or
26.9% (16 bpp), so the CPU picks up most of the difference. Size the FIFO to a
full line (320–640 words ≈ 1–2 M10K blocks) and prefetch a line ahead, and the
worst case is provably absorbed regardless of what the CPU does.

### (e) Line-level picture

```
   frame time ------------------------------------------------------------>

   scanout        |=== line N visible (640 clk_sys) ===|== hblank (160) ==|
   line FIFO A    |>>>>>>>>> draining to the CLUT >>>>>>|      (idle)      |
   line FIFO B    |<<<<< filling with line N+1 from SDRAM <<<<|   (full)   |
   SDRAM          |  paced video reads, ~14-27% duty   |RRR| video reads   |
                                                        ^^^
                                                   refresh window
   CPU            |  every remaining slot, bounded 30 ns wait               |
```

The prefetch runs a full line (~24 µs) ahead of the beam, so SDRAM latency is
irrelevant to the video — only average bandwidth matters. This is the same
decoupling a real VRAM SAM provides, done with 2.5 KB of BRAM.

### (f) Where does 1 MB actually live?

The controller supports up to 128 MB via `addr[26]` → `SDRAM_nCS`
(`sdram.sv:225`).

| Module | Row size | Bank size | Recommended split |
|---|---|---|---|
| 32 MB | 1024 B | 8 MB | RAM 16 MB (banks 0–1) + VRAM in bank 3. **RAM regresses from 32→16 MB.** |
| 64 MB | 2048 B | 16 MB | RAM 32 MB (banks 0–1) + VRAM in bank 3. Clean; 1 ACT per 2 scanlines. |
| 128 MB | 2048 B | 16 MB ×2 chips | **VRAM on the far side of `addr[26]`** — separate `nCS`, so the two chips never share row state. Closest analogue to the real Q800's separate VRAM bus. Costs a DQ bus-turnaround when switching chips; budget 1–2 cycles. |

The 32 MB case is the awkward one: banks are 8 MB, RAM sizes are powers of two
(`wombat33.sv:236`), so hosting VRAM costs half the RAM. Worth deciding early
whether 32 MB modules stay supported at 1 MB VRAM, or fall back to the existing
BRAM path at 512 KB.

---

## 7. Two things that fall out for free

**Delete the stride compaction.** `wombat33.sv:449-485` is a whole address
remapper — `vram_map()`, `VRAM_FOLD`, `VRAM_TAIL`, the shared-scratch tail
block and its "only software genuinely storing data in the pitch padding of two
different rows at once would notice" caveat — that exists solely because 512 KB
does not fit in BRAM. With SDRAM behind it, **VRAM becomes a flat linear
window** and all of that, plus its aliasing caveat and its adder chain in the
`clk_sys` critical path, goes away.

**Reclaim 2.6 Mbit of BRAM.** Current fit:

```
Total block memory bits : 3,120,549 / 5,662,720 ( 55 % )
Total RAM Blocks        :       417 /       553 ( 75 % )
Logic utilization (ALMs):    34,280 /    41,910 ( 82 % )
```

VRAM is `82,016 words × 32 bits = 2,624,512 bits` — **84% of all block memory
in use**, roughly 260 of the 417 RAM blocks. Moving it to SDRAM and replacing
it with a 2.5 KB double line buffer frees essentially all of it.

**And consider fixing the dot clock while you're in there.** 33 MHz / 800×525 =
78.57 Hz is 18% more bandwidth than the authentic 30.24 MHz / 864×525 =
66.67 Hz. Dropping to the real timing cuts 16 bpp from 48.3 to 40.9 MB/s and
makes the video slot budget in §6(d) comfortable rather than merely sufficient.
It also makes the display correct.

---

## 8. Risks and open questions

1. **Timing closure on `clk_ram`.** The `.qsf` already records hold-slack on
   this domain swinging ±0.4 ns with the fitter seed at 82% ALM. A page-mode
   scheduler adds per-bank open-row/`tRAS`/`tRC` state at 99 MHz. Mitigations:
   the 2.6 Mbit of freed BRAM and the deleted `vram_map()` adder chain both
   pull the other way; keep the scheduler's decision logic one pipeline stage
   ahead of the command register.
2. **Write coherency.** RAM writes are currently *non-posted*
   (`wombat33.sv:615-617` — deliberate, the controller has no write queue). If
   VRAM writes get posted for QuickDraw speed, the line-fetch read path must
   either drain the queue or bypass it. Do not post writes in the first cut.
3. **Tearing is authentic, not a bug.** Prefetching a line ahead means a CPU
   write to the line currently in the FIFO lands too late. Real hardware has no
   snooping either. Don't build a coherency mechanism for this.
4. **Does the ROM's VRAM sizing probe pass?** It currently sees a 512 KB wrap
   (`wombat33.sv:437-439`). Moving to a genuine 1 MB linear window changes what
   the probe finds; check the driver picks up 16 bpp rather than just seeing
   more of the same. Bench with `docs/quadra800-ram-test.md`'s fast-boot ROM.
5. **`dafb.sv` has no real 16 bpp path.** `mode == 3'd4` is a stub
   (`dafb.sv:207`, `dafb.sv:250-253`); 16 bpp is direct-colour (RGB555), not
   CLUT-indexed, so the scanout needs a separate pixel path. **1 MB of VRAM is
   necessary but not sufficient for "Thousands" — this is a second work item.**
6. **80 ns vs our 10 ns.** Nothing we do needs to be *slower* to be accurate;
   the real machine's 80 ns VRAM is a floor we clear by 8×. Fidelity risk here
   is zero. The only authenticity question is the dot clock (§7).

---

## 9. Suggested staging

| Stage | Work | Unblocks |
|---|---|---|
| 0 | Capture all 4 words of the existing BL=4 read | 4× on sequential SDRAM reads, ~1 day, no arch change |
| 1 | Page-mode scheduler + per-bank row tracking, RAM only | RAM 16.5 → ~50 MB/s; proves the timing closes |
| 2 | Drop the CDC synchronisers (§6b) | another ~80 ns/beat |
| 3 | Line FIFO + `dafb.sv` fetch decoupling, still BRAM-backed | de-risks the video side alone |
| 4 | Move VRAM to SDRAM on the fixed slot wheel (§6d), 8 bpp | **1 MB VRAM, 512 KB→1 MB advertised** |
| 5 | Demand arbitration; delete `vram_map()` | CPU picks up the video's unused share |
| 6 | Authentic 30.24 MHz dot clock; 16 bpp pixel path in `dafb.sv` | "Thousands" |

Stages 0–2 are pure wins with no VRAM involvement and are worth doing first
regardless of whether the VRAM move happens.

---

## Sources

- `docs/DeveloperNotes_Quadra800.pdf` — ch. 1 pp. 9–10 (VRAM size, 80 ns
  devices, Table 1-4 pixel depths), ch. 2 fig. 2-1 (block diagram, separate
  `BDa`/`BDb` buses), ch. 2 p. 16 (MEMC function), ch. 2 p. 16 (33.33 MHz bus
  clock).
- `mamedev/mame` `src/mame/apple/dafb.cpp` (fetched 2026-08-30) — VRAM storage,
  `vram_r`/`vram_w`, `screen_update`, absence of any timing model,
  `m_vram_size` = 1 MB for MEMC variants.
- This repo @ `9cfd1b3`: `rtl/sdram.sv`, `rtl/dafb.sv`, `rtl/quadra800.sv`,
  `wombat33.sv`, `wombat33.qsf`, `output_files/*.fit.summary`.
- SDRAM AC parameters are the -6A/-7E grades common to the MiSTer modules
  (`tRCD`/`tRP` 18–20 ns, `tRAS(min)` 42–45 ns, `tRC` 60–70 ns, `tRRD` 14 ns,
  CL2 ≤ 100 MHz). **Confirm against the specific module before committing to
  cycle counts** — the 7-cycle ACT-to-ACT in §2.1 has no margin on a 70 ns part.
