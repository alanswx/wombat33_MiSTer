# MAME NCR 53C90/94/96 + Quadra 800 Turbo SCSI — findings

Research notes for the wombat33 `rtl/ncr53c96.sv` bring-up (2026-08-28).
MAME tree at `~/repos/mame`, rev `f34f02505e32` (0.289).
Key files: `src/devices/machine/ncr53c90.cpp`, `.h`, `src/mame/apple/iosb.cpp`,
`src/mame/apple/macquadra800.cpp`, `src/mame/apple/dafb.cpp` (Q700 sibling
implementation).

---

## 1. dma16_swap / PDMA byte order — **first SCSI byte is the HIGH byte of the 16-bit word**

### The primitive
`src/devices/machine/ncr53c90.h:312-313`
```cpp
u16 dma16_swap_r() { return swapendian_int16(dma16_r()); }
void dma16_swap_w(u16 data) { return dma16_w(swapendian_int16(data)); }
```

Unswapped (little-endian, native chip order) at `ncr53c90.cpp:1326-1350`:
```cpp
u16 ncr53c94_device::dma16_r()
{
    // check fifo underflow
    if (fifo_pos < 2)
        return dma_r() | 0xff00;
    // pop two bytes from fifo
    u16 const data = fifo[0] | (fifo[1] << 8);
```
and `ncr53c90.cpp:1362-1364`:
```cpp
    // push two bytes into fifo
    fifo[fifo_pos++] = data;
    fifo[fifo_pos++] = data >> 8;
```

So natively: **FIFO byte 0 (first SCSI byte) ⇔ low byte (D7-D0)**. `dma16_swap_*`
inverts this, giving **first SCSI byte ⇔ high byte (D15-D8)**. This is symmetric —
the *same* swap is applied for read and write; there is no direction asymmetry.
The commit that introduced it (`c64e2da46de`) states: *"Use little-endian byte
order for 16-bit DMA handlers, but add alternate byte-swapping handlers for
convenient use with big-endian systems"*.

### Where Quadra 800 uses it
Q800 wires the 53C96 to IOSB: `src/mame/apple/macquadra800.cpp:234-238`
```cpp
NCR53C96(config, m_ncr1, 40_MHz_XTAL);
m_scsibus->set_external_device(7, m_ncr1);
m_ncr1->set_busmd(ncr53c96_device::BUSMD_1);   // 8-bit host, 16-bit DMA
m_ncr1->irq_handler_cb().set(m_iosb, FUNC(iosb_device::scsi_irq_w));
m_ncr1->drq_handler_cb().set(m_iosb, FUNC(iosb_device::scsi_drq_w));
```

IOSB map (`src/mame/apple/iosb.cpp:58-59`) — register window at `+0x10000` with a
4-bit-shifted register index, PDMA window at `+0x10100` (Q800 physical
`0x50010000` / `0x50010100`):
```cpp
map(0x00010000, 0x000100ff).rw(FUNC(iosb_base::turboscsi_r), FUNC(iosb_base::turboscsi_w)).mirror(0x00fc0000);
map(0x00010100, 0x00010103).rw(FUNC(iosb_base::turboscsi_dma_r), FUNC(iosb_base::turboscsi_dma_w)).select(0x00fc0000);
```
Register access is `m_ncr->read(offset>>4)` / `write(offset>>4, data)` — one NCR
register per 16 bytes (`iosb.cpp:482-495`).

### 32-bit PDMA and net byte order
`src/mame/apple/iosb.cpp:498-546` (read):
```cpp
if (mem_mask == 0xffffffff)
{
    if (!m_scsi_second_half)
    {
        m_scsi_dma_result = m_ncr->dma16_swap_r()<<16;
        m_scsi_second_half = true;
    }
    ... /* DRQ holdoff re-check */ ...
    m_scsi_second_half = false;
    m_scsi_dma_result |= m_ncr->dma16_swap_r();
}
else if (mem_mask == 0xffff0000)
{
    m_scsi_dma_result = m_ncr->dma16_swap_r()<<16;
}
```
A 32-bit read is two swapped 16-bit reads, first word → bits 31..16. Net effect
on the 68040's big-endian bus: **SCSI byte N+0 → D31-24, N+1 → D23-16, N+2 →
D15-8, N+3 → D7-0** — i.e. plain sequential byte order in memory. `mem_mask`
other than `0xffffffff`/`0xffff0000` is a `fatalerror` on reads
(`iosb.cpp:500-503`).

Write side (`iosb.cpp:548-592`) mirrors it, plus a byte case:
```cpp
if (mem_mask == 0xffffffff) { ... dma16_swap_w(data>>16); ... dma16_swap_w(data & 0xffff); }
else if (mem_mask == 0xffff0000) { m_ncr->dma16_swap_w(data >> 16); }
else if (mem_mask == 0xff000000) { m_ncr->dma_w(data >> 24); }
else fatalerror("IOSB: turboscsi_dma_w unhandled mask %08x\n", mem_mask);
```
Only the MSB lane byte write is supported; other byte lanes fatalerror.

Residual/odd-byte path inside the device: `dma16_r()` with `fifo_pos < 2`
returns `dma_r() | 0xff00`; after the swap, the real byte lands in the **high**
half and `0xff` in the low half — consistent with "first byte = high byte".
`dma16_w()` with `fifo_pos > 14 || tcounter == 1` does `dma_w(data & 0x00ff)`,
which after the caller's swap is the CPU-side **high** byte, i.e. the first
bus-order byte. Both residual paths preserve the same convention.

### DRQ / DTACK hold-off model
`src/mame/apple/iosb.cpp:510-518` (and repeated at 529-536 mid-longword,
557-562 and 571-576 on writes):
```cpp
if (!m_drq)
{
    // The real DAFB simply holds off /DTACK here, we simulate that
    // by rewinding and repeating the instruction until DRQ is asserted.
    m_maincpu->restart_this_instruction();
    m_maincpu->spin_until_time(attotime::from_usec(50));
    return 0xffff;
}
```
Notes:
- The hold-off is checked **before the first halfword and again between the two
  halves** of a 32-bit access. `m_scsi_second_half` (`iosb.h:101`) is the latch
  that survives the instruction restart so the first halfword is not re-fetched
  from the FIFO.
- **IOSB's hold-off is unconditional.** The DAFB (Q700) version gates it on
  control-register bits: `dafb.cpp:1003` `if (BIT(m_scsi_ctrl[bus], 7))` for
  reads and `dafb.cpp:1042` `if (BIT(m_scsi_ctrl[bus], 8))` for writes,
  documented at `dafb.cpp:486-487`: *"bit 7 = DRQ Check Read (PDMA reads wait if
  DRQ isn't set and bus error on timeout) / bit 8 = DRQ Check Write"*. MAME never
  models the bus-error-on-timeout, only the stall.
- Cycle-stealing wait states are modeled via
  `m_maincpu->adjust_icount(-m_scsi_dma_read_cycles)`, applied only when
  `BIT(offset << 1, 18)` (`iosb.cpp:504-508`, `548-552`) — i.e. a particular
  address alias within the `select(0x00fc0000)` region gets the penalty and the
  other doesn't. (Because IOSB's handler is 32-bit and DAFB's is 16-bit, the same
  `BIT(offset<<1,18)` expression tests a different physical address bit in each —
  worth being aware of if you're matching aliases.)
- Timings come from IOSB register 2 (`iosb.cpp:606-618`):
  `const int times[4] = { 5, 5, 4, 3 };` indexed by `(m_iosb_regs[2]>>8)&3`
  (DMA read) and `(m_iosb_regs[2]>>11)&3` (DMA write). Non-DMA register
  read/write cycles default to 3 (`iosb.cpp:144-147`).
- DRQ is also exposed to software: `iosb_base::scsi_drq_w` (`iosb.cpp:594-599`)
  forwards to the pseudo-VIA, which sets IFR bit 0
  (`src/devices/machine/pseudovia.cpp:162-171`, `m_pseudovia_regs[3] |= 0x01`).

---

## 2. Select with/without ATN (0x41 / 0x42 / 0x43) — full sequence and RSEQ

Command dispatch, `ncr53c90.cpp:978-990`:
```cpp
case CD_SELECT:
case CD_SELECT_ATN:
case CD_SELECT_ATN_STOP:
    seq = 0;
    state = DISC_SEL_ARBITRATION_INIT;
    dma_set(dma_command ? DMA_OUT : DMA_NONE);
    arbitrate();
```
`start_command` first does `dma_command = command[0] & 0x80;` and either
`load_tcounter()` or `tcounter = 0` (`ncr53c90.cpp:940-948`).

Arbitration/selection (`ncr53c90.cpp:341-430`): `ARB_COMPLETE → ARB_ASSERT_SEL →
ARB_SET_DEST` (asserts `S_ATN` here for 0x42/0x43 only, line 366) `→
ARB_RELEASE_BUSY → ARB_DESKEW_WAIT` → `mode = MODE_I`.

Then:

| Step | Line | Behavior |
|---|---|---|
| `DISC_SEL_ARBITRATION` | 500-519 | If FIFO empty: `seq = 1;` + `check_drq()` and stall. Comment: *"this sequence isn't documented for initiator selection, but it makes macqd700 happy"*. If FIFO non-empty, `seq` stays **0**. Branches to `DISC_SEL_WAIT_REQ` for 0x41, `DISC_SEL_ATN_WAIT_REQ` for 0x42/0x43. |
| `DISC_SEL_ATN_WAIT_REQ` | 521-532 | Waits REQ. If phase ≠ MSG OUT → `function_complete()` (I_FUNCTION only, seq unchanged). If MSG OUT: for 0x42 only, deassert ATN; `send_byte()` pops **exactly one** FIFO byte (the identify message). |
| `DISC_SEL_ATN_SEND_BYTE` | 534-541 | If cmd == 0x43 (ATN+stop): `seq = 2; function_bus_complete();` → **istatus = I_FUNCTION\|I_BUS (0x18), RSEQ = 2**, stops before CDB. Otherwise fall through to `DISC_SEL_WAIT_REQ`. |
| `DISC_SEL_WAIT_REQ` | 544-562 | Waits REQ. If phase ≠ COMMAND: `seq = ((!dma_command \|\| (status & S_TC0)) && !fifo_pos) ? 4 : 2;` then `function_bus_complete()`. If phase == COMMAND: needs `fifo_pos != 0` (else stall); `if(seq < 3) seq = 3;` then `send_byte()` — **one CDB byte per pass**. |
| `DISC_SEL_SEND_BYTE` | 564-570 | `if((!dma_command \|\| (status & S_TC0)) && !fifo_pos) seq = 4;` then back to `DISC_SEL_WAIT_REQ`. |

**Byte accounting:** identify message = exactly 1 FIFO byte (0x42/0x43 only);
CDB = however many bytes the target REQs, one FIFO pop per REQ; there is no CDB
length decode.

**End state of a full select-through-command-phase:** `RSEQ = 4`,
`istatus = I_FUNCTION | I_BUS = 0x18` via `function_bus_complete()`
(`ncr53c90.cpp:772-780`):
```cpp
void ncr53c90_device::function_bus_complete()
{
    state = IDLE;
    istatus |= I_FUNCTION|I_BUS;
    dma_set(DMA_NONE);
    check_drq(); check_irq();
}
```
Interrupt bit values (`ncr53c90.h:150-157`): `I_FUNCTION = 0x08`,
`I_BUS = 0x10`, `I_DISCONNECT = 0x20`, `I_ILLEGAL = 0x40`, `I_SCSI_RESET = 0x80`.

**Stall points that leave partial RSEQ:** RSEQ 0 (never got REQ / FIFO preloaded
and target never responded), 1 (waiting for DMA-fed FIFO), 2 (ATN-stop, or phase
left MSG-OUT/COMMAND with bytes still pending), 3 (mid-CDB), 4 (CDB fully sent).

**Selection timeout** — `ARB_TIMEOUT_BUSY`/`ARB_TIMEOUT_ABORT`,
`ncr53c90.cpp:404-430`:
```cpp
} else {
    m_scsi_bus->ctrl_w(m_scsi_refid, 0, S_ALL);
    state = IDLE;
    istatus |= I_DISCONNECT;
    reset_disconnect();
    check_irq();
}
```
→ **istatus = 0x20 (disconnect) only, RSEQ stays 0, mode returns to MODE_D,
`command_pos = 0`** (`reset_disconnect()` at 275-282). No I_FUNCTION. Note the
timeout duration is hacked: `ncr53c90.cpp:20` `#define DELAY_HACK`, and
`ncr53c90.cpp:379-386` uses `delay(1)` instead of `delay(8192*select_timeout)` —
so selection timeouts are effectively instantaneous. This matters for the ROM's
bus scan pacing.

**Select with ATN3 (0x46) is NOT implemented** — `check_valid_command` accepts
it on 53c90a+ (`ncr53c90.cpp:471`, `case 4: return mode == MODE_D && subcmd <= 6;`)
but `start_command` has no case, so it falls to
`fatalerror("...unimplemented command %02x")` at line 1055.

---

## 3. DMA select — yes, the CDB is fetched via DMA

`start_command` does `dma_set(dma_command ? DMA_OUT : DMA_NONE)` for all three
select commands (`ncr53c90.cpp:988`), and `load_tcounter()` reloads `tcounter`
and clears TC0 (`ncr53c90.cpp:918-925`).

The mechanism is the `seq = 1` stall at `ncr53c90.cpp:500-509`:
```cpp
case DISC_SEL_ARBITRATION:
    // wait until a command is in the fifo
    if (!fifo_pos) {
        seq = 1;
        // dma starts after bus arbitration/selection is complete
        check_drq();
        break;
    }
```
`check_drq()` with `dma_dir == DMA_OUT` asserts DRQ while
`!(status & S_TC0) && fifo_pos < 16` (53c90 base, line 1223-1224) / `< 15` for
16-bit DMA (`ncr53c94_device::check_drq`, line 1392-1394). The host then feeds
bytes through `dma_w`/`dma16_w`, each of which does `fifo_push` +
`decrement_tcounter` + `check_drq` + **`step(false)`** (`ncr53c90.cpp:1182-1189`,
`1352-1370`), and that `step()` re-enters the select state machine and drives
message-out/command-phase byte transmission. So the identify byte and CDB both
come in via DMA, one FIFO push at a time, and RSEQ advances 1 → 3 → 4 as they're
consumed. The `(!dma_command || (status & S_TC0)) && !fifo_pos` conditions at
lines 548/565 mean RSEQ only reaches 4 once TC has expired *and* the FIFO is
drained.

---

## 4. Non-DMA Transfer Information (0x10), ICCS (0x11), Message Accept (0x12)

### CI_XFER (0x10), `ncr53c90.cpp:1002-1009`
```cpp
case CI_XFER:
    state = INIT_XFR;
    xfr_phase = m_scsi_bus->ctrl_r() & S_PHASE_MASK;
    dma_set(dma_command ? ((xfr_phase & S_INP) ? DMA_IN : DMA_OUT) : DMA_NONE);
    check_drq();
    step(false);
```
The phase is **latched once** at command start into `xfr_phase`.

**Transfer counter in non-DMA mode: it does not move.** `start_command` sets
`tcounter = 0` when the DMA bit is clear (`ncr53c90.cpp:947`), and
`decrement_tcounter` bails immediately (`ncr53c90.cpp:1234-1236`):
```cpp
void ncr53c90_device::decrement_tcounter(int count)
{
    if (!dma_command)
        return;
```
Consequence: in non-DMA mode `S_TC0` is whatever it was left at; it is only
cleared by `load_tcounter()` on a DMA command.

**Bytes per command / termination** — `INIT_XFR_WAIT_REQ`,
`ncr53c90.cpp:643-664`:
```cpp
if ((dma_command && (status & S_TC0) && (dma_dir == DMA_IN || fifo_pos == 0)) // dma in/out: transfer count == 0
||  (!dma_command && (xfr_phase & S_INP) == 0 && fifo_pos == 0)      // non-dma out: fifo empty
||  (!dma_command && (xfr_phase & S_INP) == S_INP && fifo_pos == 1)) // non-dma in: every byte
    state = INIT_XFR_BUS_COMPLETE;
else
    if((ctrl & S_PHASE_MASK) != xfr_phase) {
        command_pos = 0;
        state = INIT_XFR_BUS_COMPLETE;
    } else {
        state = INIT_XFR;
    }
```
- **Non-DMA IN (data-in/status): one byte per command.** Terminates via
  `INIT_XFR_BUS_COMPLETE` → `bus_complete()` → **istatus |= I_BUS (0x10) only**
  (`ncr53c90.cpp:792-800`). Note the check is evaluated on the *next* REQ, so
  the interrupt fires when the target requests the following byte or changes
  phase.
- **Non-DMA OUT: runs until the FIFO drains,** also → `bus_complete()` / I_BUS.
- **Phase change** during the transfer: same `INIT_XFR_BUS_COMPLETE` path →
  I_BUS. RSEQ is not touched by 0x10 anywhere; it reads whatever it was (0 after
  any interrupt-register read).
- **MSG IN is special** (`ncr53c90.cpp:625`):
  `state = (xfr_phase == S_PHASE_MSG_IN && (!dma_command || tcounter == 1)) ? INIT_XFR_RECV_BYTE_NACK : INIT_XFR_RECV_BYTE_ACK;`
  — the last message byte leaves ACK **asserted** and terminates with
  `function_complete()` → **istatus |= I_FUNCTION (0x08)**, not I_BUS
  (`ncr53c90.cpp:667-670, 782-790`).
- FIFO full (`fifo_pos == 16`) blocks receive; FIFO empty blocks send
  (`ncr53c90.cpp:606-609, 620-622`).

**FIFO refill model (non-DMA):** the host writes register 2; `fifo_w` pushes and
then calls `step(false)` explicitly (`ncr53c90.cpp:866-875`), which is what
un-stalls a send that was waiting on an empty FIFO. `fifo_r` pops and calls
`check_drq()` but **not** `step()` (`ncr53c90.cpp:851-864`) — a non-DMA read
drain does not by itself advance the machine; the next REQ transition does, via
`scsi_ctrl_changed()` (`ncr53c90.cpp:283-293`). `fifo_flags_r` returns raw
`fifo_pos` with no top bits (`ncr53c90.cpp:1140-1143`).

Also, ATN auto-deassert on the last MSG-OUT byte (`ncr53c90.cpp:611-618`):
```cpp
int remaining_bytes = fifo_pos + (dma_command ? tcounter : 0);
if (xfr_phase == S_PHASE_MSG_OUT && remaining_bytes == 1)
    m_scsi_bus->ctrl_w(m_scsi_refid, 0, S_ATN);
```

### CI_COMPLETE / ICCS (0x11), `ncr53c90.cpp:1011-1016`
```cpp
case CI_COMPLETE:
    state = INIT_CPT_RECV_BYTE_ACK;
    dma_set(dma_command ? DMA_IN : DMA_NONE);
    recv_byte();
```
Then `ncr53c90.cpp:572-593`:
- Receives the **status byte** into the FIFO, deasserts ACK, →
  `INIT_CPT_RECV_WAIT_REQ`.
- Waits REQ. If phase ≠ MSG IN → `command_pos = 0; bus_complete();` →
  **I_BUS (0x10)** only.
- If MSG IN → `INIT_CPT_RECV_BYTE_NACK`, receives the **message byte** (ACK
  stays asserted, NACK path) → `function_complete()` → **I_FUNCTION (0x08)**.

So a normal ICCS pushes **2 bytes** (status, then message) into the FIFO, leaves
ACK asserted on the message byte, and raises Function Complete. It does **not**
set `seq`.

### CI_MSG_ACCEPT (0x12), `ncr53c90.cpp:1018-1030`
```cpp
case CI_MSG_ACCEPT:
    state = INIT_MSG_WAIT_REQ;
    // It's undocumented what the sequence register should contain after a message accept
    // command, but the InterPro boot code expects it to be non-zero; setting it to an
    // arbirary 1 here makes InterPro happy. Also in the InterPro case (perhaps typical),
    // after ACK is asserted the device disconnects and the INIT_MSG_WAIT_REQ state is never
    // entered, meaning we end up with I_DISCONNECT instead of I_BUS interrupt status.
    seq = 2;
    m_scsi_bus->ctrl_w(m_scsi_refid, 0, S_ACK);
    step(false);
```
(Note the comment says "1" but the code sets `seq = 2` — the comment is stale.)
Pushes/clears nothing in the FIFO; it only **deasserts ACK**. Outcomes:
- Target drops BSY (command complete disconnect) → top of `step()` at
  `ncr53c90.cpp:313-318`: `state = IDLE; istatus |= I_DISCONNECT;
  reset_disconnect();` → **I_DISCONNECT (0x20)**, mode back to MODE_D.
- Target stays connected and asserts REQ for a new phase → `INIT_MSG_WAIT_REQ`
  (`ncr53c90.cpp:595-599`): `if((ctrl & (S_REQ|S_BSY)) == S_BSY) break;
  bus_complete();` → **I_BUS (0x10)**, RSEQ = 2.

---

## 5. Status register (RSTAT) semantics

Base 53C90 (`ncr53c90.cpp:1088-1095`):
```cpp
uint8_t ncr53c90_device::status_r()
{
    uint32_t ctrl = m_scsi_bus->ctrl_r();
    uint8_t res = status | (ctrl & S_MSG ? 4 : 0) | (ctrl & S_CTL ? 2 : 0) | (ctrl & S_INP ? 1 : 0);
    return res;
}
```
53C90A/94/96 override (`ncr53c90.cpp:1288-1296`):
```cpp
uint8_t ncr53c90a_device::status_r()
{
    uint32_t ctrl = m_scsi_bus->ctrl_r();
    uint8_t res = (irq ? S_INTERRUPT : 0) | status | (ctrl & S_MSG ? 4 : 0) | (ctrl & S_CTL ? 2 : 0) | (ctrl & S_INP ? 1 : 0);
    if (irq && !machine().side_effects_disabled())
        status &= ~(S_GROSS_ERROR | S_PARITY | S_TCC);
    return res;
}
```
- **Phase bits 2:0 are read live from the SCSI bus every read** (MSG→b2,
  C/D→b1, I/O→b0). They are *not* latched at command time (LSP in config2 is
  stored but not acted on).
- **Bit 7 does mirror the interrupt line** on 53c90a/94/96
  (`S_INTERRUPT = 0x80`, `ncr53c90.h:265`); the plain 53c90 has no such bit.
  `irq` is simply `istatus != 0` (`check_irq`, `ncr53c90.cpp:1079-1086`).
- **Bit 4 = TC0 (`S_TC0 = 0x10`)**: set by `decrement_tcounter` when `tcounter`
  reaches 0 (`ncr53c90.cpp:1234-1251`), cleared by `load_tcounter()` at the
  start of any DMA-bit command (`ncr53c90.cpp:918-925`). It never changes in
  non-DMA mode.
- **Bit 3 = `S_TCC` (0x08) is never set anywhere** in the file — only cleared.
  Bit 6 `S_GROSS_ERROR` is set only on a 3-deep command-register push
  (`ncr53c90.cpp:889-893`). Bit 5 `S_PARITY` is never set.
- **Read side effect:** on 53c90a+, reading status while IRQ is pending clears
  GROSS_ERROR/PARITY/TCC. The base 53c90 `status_r` has no side effects.

**Interrupt register read side effects** (`ncr53c90.cpp:1103-1123`):
```cpp
uint8_t ncr53c90_device::istatus_r()
{
    uint8_t res = istatus;
    if (!machine().side_effects_disabled())
    {
        if (irq)
        {
            status &= ~(S_GROSS_ERROR | S_PARITY | S_TCC);
            istatus = 0;
            seq = 0;
        }
        check_irq();
        if(res)
            command_pop_and_chain();
    }
    return res;
}
```
So reading RINTR: returns latched `istatus`, then (only if IRQ was asserted)
clears `istatus`, **zeroes RSEQ**, clears the same three status bits, drops IRQ,
and pops/starts the next queued command from the two-deep command register
(`command_pop_and_chain`, `ncr53c90.cpp:901-910`). **RSEQ must be read before
RINTR.**

---

## 6. 53C94 vs 53C96, and Quadra-800-specific handling

### 53C94 vs 53C96 in MAME: **no functional difference at all.**
`ncr53c90.cpp:191-194`:
```cpp
ncr53c96_device::ncr53c96_device(const machine_config &mconfig, const char *tag, device_t *owner, uint32_t clock)
    : ncr53c94_device(mconfig, NCR53C96, tag, owner, clock)
{
}
```
Only the device type/name string differs. Same 16-byte FIFO
(`uint8_t fifo[16]`, `ncr53c90.h:206`), same registers.

What the 53c94 layer *does* add over 53c90a (`ncr53c90.cpp:100-121`,
`.h:280-322`):
- **CONFIG3 at register 0x0C** (`conf3_r`/`conf3_w`), and a write-only **FIFO
  alignment register at 0x0F** (`fifo_align_w` — stored, never used).
- Only CONFIG3 bit 2 (`LBTM`, "last byte transfer mode") has behavior, in
  `ncr53c94_device::check_drq` (`ncr53c90.cpp:1374-1400`):
```cpp
case DMA_IN: // device to memory (optionally save last remaining byte for processor)
    if (sync_offset == 0)
        drq_state = fifo_pos > (BIT(config3, 2) || !(status & S_TC0) ? 1 : 0);
    else
        drq_state = !(status & S_TC0) && fifo_pos > 1;
    break;
case DMA_OUT: // memory to device
    drq_state = !(status & S_TC0) && fifo_pos < 15;
```
  i.e. 16-bit DRQ requires 2 bytes in/room for 2 out; with TC0 set and LBTM
  clear, a final single byte will still raise DRQ. Bits BS8/MDM are declared but
  unused.
- `set_busmd()` gates all of this: with `BUSMD_0` the 53c94 `check_drq` falls
  straight through to the 8-bit base version (`ncr53c90.cpp:1376`, `1402-1404`).
  Q800 sets `BUSMD_1` (8-bit host regs, 16-bit DMA).
- 53c90a additions used here: CONFIG2 at 0x0B, status bit 7 = interrupt,
  `CI_RESET_ATN` (0x1B), and a wider valid-command table
  (`ncr53c90.cpp:468-478`). CONFIG2 `SBO` ("select byte order", bit 5) is
  *declared* in `ncr53c90.h:271` but **never read** — MAME does not implement
  the chip's own byte-order bit; the Mac glue does the swap externally.
- 53CF94/96 are the ones that add tcounter bit 16-23, CONFIG4, and the
  family/revision ID readback (`ncr53c90.cpp:1422-1447`) — not used by the
  Quadra.

### Quadra-800-specific quirks / ROM-scan comments
- `src/mame/apple/macquadra800.cpp:13-16` is the only architectural comment:
  *"These second-generation 68040 machines shrunk the huge mass of separate
  chips ... down to a pair of ASICs, djMEMC ... and IOSB (I/O bus adaptor with
  integrated VIAs, audio, "Turbo SCSI", and SWIM2 floppy)."* There is **no**
  comment in the Q800 driver about the ROM's SCSI scan, hold-off timing, or any
  workaround.
- `src/mame/apple/iosb.cpp:15` confirms the logic is lifted wholesale: *"The
  'Turbo SCSI' logic from the standalone versions of DAFB and DAFB II"*;
  `src/mame/apple/djmemc.cpp:10`: *"DAFB II video, minus the 'Turbo SCSI'
  feature, which has moved to IOSB"*.
- The only Mac-ROM-driven quirk in the NCR device itself is the select `seq = 1`
  hack, and it names the Quadra 700 rather than the 800 —
  `ncr53c90.cpp:502-506`:
```cpp
// this sequence isn't documented for initiator selection, but
// it makes macqd700 happy and may be consistent with target
// selection sequences
seq = 1;
```
  This is the one that directly stresses the boot-time bus scan: the ROM issues
  a DMA select to each ID, and the ROM reads RSEQ expecting a non-zero value
  while the DMA-fed FIFO is still being filled.
- Related upstream fix that the Quadra ROMs forced, commit `48f836e5c08`:
  *"Don't subtract FIFO contents from transfer count when DMA is started. The
  5390/5394/5396 manuals all agree transfer count only decrements on DACK in DMA
  write mode, and 68040 Macs require it."* That is the
  `if (sync_offset != 0) || (phase != DATA_IN)` guard in `dma_r`/`dma16_r`
  (`ncr53c90.cpp:1197-1200`, `1338-1342`) and the async-data-in
  `decrement_tcounter()` inside `RECV_WAIT_SETTLE` (`ncr53c90.cpp:470-480`).
- Nearest analogous ROM-behavior comment elsewhere in the tree, for context on
  how the Mac ROM polls DRQ: `src/mame/apple/macscsi.cpp:10` *"For SCSIRead and
  SCSIWrite, the CPU polls DRQ before it reads or..."* (that's the 5380-based
  path, not the Quadra).

---

## Summary of the two flags in RESUME-machine-bringup.md

1. **PDMA byte order is verified**: with `dma16_swap_*`, the **first SCSI byte
   is the high byte (D15-D8)** of the 16-bit word, and the first SCSI byte of a
   32-bit PDMA access is D31-D24. Same convention both directions.
   Residual/odd-byte paths agree (`dma_r()|0xff00` after swap → real byte high;
   `dma16_w` last-byte path uses `data & 0xff` of the already-swapped word = the
   CPU's high byte).
2. **The hold-off** on Q800/IOSB is unconditional in MAME (no control-register
   gate, unlike DAFB bits 7/8), is re-evaluated **mid-longword** between the two
   halfwords of a 32-bit PDMA access, and is modeled as instruction restart +
   50 µs spin rather than a real /DTACK stretch. Any residual-word latch
   (`m_scsi_second_half`) must survive the restart.
