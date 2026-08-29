# QEMU ESP/53C9x behavior — research report

Research notes for the wombat33 `rtl/ncr53c96.sv` bring-up (2026-08-28).
Tree: `~/repos/qemu` @ `3d719b7723` (v11.1.0-730). Key files:
- `hw/scsi/esp.c` (1694 lines) — all core logic
- `include/hw/scsi/esp.h`
- `hw/m68k/q800.c:461-489` — the only q800 SCSI glue (djmemc.c / iosb.c /
  q800-glue.c do **not** touch SCSI DMA at all)
- `hw/misc/mac_via.c:1144-1156` — DRQ visibility to the guest

Two global facts that shape everything:

- q800 sets `esp->dma_memory_read = NULL; esp->dma_memory_write = NULL;` and
  `esp->dma_enabled = 1` (`q800.c:467-471`). So on Quadra, **every** "DMA" code
  path in esp.c takes the *else* branch that moves bytes through the 16-byte
  FIFO (= PDMA), and the `dma_cb` deferral in `handle_ti`/`handle_satn` never
  triggers.
- There is exactly one state machine per mode: `esp_do_dma()` (esp.c:484-742)
  and `esp_do_nodma()` (esp.c:771-945), both `switch`ed on **SCSI phase first**,
  then on the *currently latched* `rregs[ESP_CMD]`.

---

## 1. Non-DMA (PIO) information transfer — `CMD_TI` without `CMD_DMA`

Entry point `handle_ti()` (esp.c:1076-1097):

```c
    } else {
        trace_esp_handle_ti(s->ti_size);
        esp_do_nodma(s);
        if (esp_get_phase(s) == STAT_DO) {
            esp_nodma_ti_dataout(s);
        }
    }
```

### Bytes per TI

| phase | bytes moved per non-DMA TI | code |
|---|---|---|
| DATA IN | **exactly 1**, and only if the FIFO is empty | esp.c:892-919 |
| DATA OUT | `MIN(async_len, ESP_FIFO_SZ=16, fifo_used)` — i.e. drains whatever the guest preloaded, capped at 16 | esp.c:744-769 |
| MESSAGE OUT | whole FIFO → cmdfifo, then forces phase to COMMAND | esp.c:817-829 |
| COMMAND | whole FIFO → cmdfifo; executes CDB when complete | esp.c:833-860 |

DATA IN (esp.c:900-919):
```c
        if (fifo8_is_empty(&s->fifo)) {
            esp_fifo_push(s, s->async_buf[0]);
            s->async_buf++;  s->async_len--;  s->ti_size--;
        }
        if (s->async_len == 0) { scsi_req_continue(s->current_req); return; }
        /* If preloading the FIFO, defer until TI command issued */
        if (s->rregs[ESP_CMD] != CMD_TI) { return; }
        s->rregs[ESP_RINTR] |= INTR_BS;
        esp_raise_irq(s);
```
Note: if the guest issues TI while a byte is still unread in the FIFO, **no new
byte is pushed but INTR_BS is still raised**.

### What re-triggers more data

- Reading the FIFO register does **not** pull more data.
  `esp_reg_read(ESP_FIFO)` is a bare `esp_fifo_pop()` (esp.c:1259-1262) — no
  state machine call.
- **Writing** the FIFO register *does* run the machine: `esp_reg_write` case
  `ESP_FIFO` → `esp_fifo_push()` then `esp_do_nodma(s)` (esp.c:1314-1319). This
  is how MESSAGE OUT / COMMAND bytes get consumed and how a DMA CDB can be
  terminated by a PIO byte (see §2).
- Otherwise only a new `CMD_TI` write advances a DATA phase.
- Late-arriving SCSI data re-enters via `esp_transfer_data()` (esp.c:1066-1073),
  which only re-runs the machine when the *latched* command is still TI:
  `if (s->rregs[ESP_CMD] == (CMD_TI|CMD_DMA)) ... else if (s->rregs[ESP_CMD] == CMD_TI) esp_do_nodma(s);`

### TC / STAT_TC during PIO

**PIO never touches the transfer counter.** `esp_set_tc()` is called only from
`esp_do_dma()`, `esp_pdma_write()`, `esp_run_cmd()` and `esp_post_load()` —
never from `esp_do_nodma()` / `esp_nodma_ti_dataout()`. Consequently:
- `rregs[ESP_TCLO/TCMID/TCHI]` keep whatever the last `CMD_DMA` command loaded
  (esp.c:1170-1180 — the reload happens **only** if `cmd & CMD_DMA`).
- `STAT_TC` is only cleared by a guest **write** to TCLO/TCMID/TCHI
  (esp.c:1307-1313: `s->rregs[ESP_RSTAT] &= ~STAT_TC;`) and only set by the
  `esp_set_tc()` non-zero→zero edge (esp.c:227-229). So after a PIO transfer
  STAT_TC is stale/whatever it was.
- The internal PIO progress counter is `s->ti_size` (signed), invisible to the
  guest; it counts *down* on DATA IN, *up* on DATA OUT.

### Interrupts / seq step in PIO

- Per-chunk completion: `INTR_BS` only (esp.c:767-768, 856-857, 917-918,
  827-828). No `INTR_FC` for plain TI chunks.
- End of the SCSI request: `esp_command_complete()` (esp.c:947-1005) zeroes
  `ESP_CMD` for TI, sets phase STATUS and raises `INTR_BS`:
  ```c
    case CMD_TI | CMD_DMA:
    case CMD_TI:
        s->rregs[ESP_CMD] = 0;
        break;
    }
    esp_set_phase(s, STAT_ST);
    s->rregs[ESP_RINTR] |= INTR_BS;
    esp_raise_irq(s);
  ```
  For a PIO DATA IN, the **last byte is deliberately left in the FIFO** —
  comment at esp.c:954-957 and 970-973 (`"Non-DMA transfers from the target
  will leave the last byte in the FIFO so don't reset ti_size"`). The guest
  reads it after the phase already shows STATUS.
- MESSAGE OUT → COMMAND transition inside PIO TI (esp.c:823-828): `"ATN remains
  asserted until FIFO empty"`, `esp_set_phase(STAT_CD); s->rregs[ESP_CMD] = 0;
  INTR_BS`.
- `RSEQ` is **not** changed by TI; it retains SEQ_MO/SEQ_CD from the select.

### Non-DMA DATA OUT: how bytes reach the target

Bytes written to the FIFO in DATA OUT phase are just accumulated —
`esp_do_nodma()` case `STAT_DO` is an explicit no-op:
```c
    case STAT_DO:
        /* Accumulate data in FIFO until non-DMA TI is executed */
        break;
```
(esp.c:888-890). They are pushed to the SCSI device only when `CMD_TI` (no DMA)
is written, via `esp_nodma_ti_dataout()` (esp.c:744-769), which pops up to 16
bytes into `async_buf`, `ti_size += len`, then either `scsi_req_continue()`
(buffer full → target consumes) or raises `INTR_BS` for the next chunk.

---

## 2. DMA select with CDB (`CMD_SEL`/`CMD_SELATN`/`CMD_SELATNS` | `CMD_DMA`)

Common prologue: `esp_run_cmd()` sets `s->dma = 1` and **latches TC from the
shadow write regs** (esp.c:1170-1180, see §4), then `esp_select()`
(esp.c:260-290) which does `s->ti_size = 0; s->rregs[ESP_RSEQ] = SEQ_0;` and
deliberately raises **no** IRQ:
```c
    /*
     * Note that we deliberately don't raise the IRQ here: this will be done
     * either in esp_transfer_data() or esp_command_complete()
     */
```

The CDB is **not** read from the 16-byte FIFO — it is DMA'd straight into the
separate 32-byte `cmdfifo` (`ESP_CMDFIFO_SZ 32`, esp.h:15). On q800
(`dma_memory_read == NULL`) the source is still the FIFO, refilled by PDMA
writes.

### CMD_SEL | CMD_DMA (no ATN)
`handle_s_without_atn()` (esp.c:386-405): `esp_set_phase(STAT_CD);
s->cmdfifo_cdb_offset = 0;` then `esp_do_dma()` → `case STAT_CD`
(esp.c:546-567): pull `MIN(TC, cmdfifo_free)` bytes into cmdfifo,
`esp_set_tc(TC-len)`, `s->ti_size = 0`, and
```c
        if (esp_get_tc(s) == 0) {
            /* Command has been received */
            do_cmd(s);
        }
```
`cdb_offset == 0`, so `do_message_phase()` is a no-op and the whole DMA buffer
is the CDB. LUN stays whatever it was.

### CMD_SELATN | CMD_DMA
`handle_satn()` (esp.c:366-384): phase = MESSAGE OUT, then `esp_do_dma()` →
`case STAT_MO` (esp.c:492-520). The identify byte **and** CDB come in as one DMA
burst (`len = MIN(TC, cmdfifo_free)`, `cmdfifo_cdb_offset += len`), then:
```c
        case CMD_SELATN | CMD_DMA:
            if (fifo8_num_used(&s->cmdfifo) >= 1) {
                /* First byte received, switch to command phase */
                esp_set_phase(s, STAT_CD);
                s->rregs[ESP_RSEQ] = SEQ_CD;      /* == 4 */
                s->cmdfifo_cdb_offset = 1;
                if (fifo8_num_used(&s->cmdfifo) > 1) {
                    esp_do_dma(s);                 /* re-enter in CD phase */
                }
            }
```
The re-entry lands in `STAT_CD` with TC already 0 → `do_cmd()`.
`do_message_phase()` (esp.c:340-357) pops byte 0 as the identify message:
`s->lun = message & 7;`, and *silently drops* any further message bytes
(`"Ignore extended messages for now"`, fifo8_drop).

### CMD_SELATNS | CMD_DMA (select with ATN and stop)
`handle_satn_stop()` (esp.c:407-426): phase = MESSAGE OUT,
`cmdfifo_cdb_offset = 0`, then `esp_do_dma()` → esp.c:522-532:
```c
        case CMD_SELATNS | CMD_DMA:
            if (fifo8_num_used(&s->cmdfifo) == 1) {
                /* First byte received, stop in message out phase */
                s->rregs[ESP_RSEQ] = SEQ_MO;      /* == 1 */
                s->cmdfifo_cdb_offset = 1;
                s->rregs[ESP_RINTR] |= INTR_BS | INTR_FC;
                esp_raise_irq(s);
            }
```
Note the strict `== 1`: the trigger only fires if exactly one byte arrived.
Phase **stays MESSAGE OUT**; the guest then sends the remaining message bytes
and a TI, which is handled by esp.c:534-542:
```c
        case CMD_TI | CMD_DMA:
            /* ATN remains asserted until TC == 0 */
            if (esp_get_tc(s) == 0) {
                esp_set_phase(s, STAT_CD);
                s->rregs[ESP_CMD] = 0;
                s->rregs[ESP_RINTR] |= INTR_BS;
                esp_raise_irq(s);
            }
```
then the CDB goes over in COMMAND phase via a further TI.

### Interrupts for SEL/SELATN with CDB — all deferred
Nothing is raised at CDB-completion time. Two exits:
- Command has a data phase: `do_command_phase()` sets DI/DO and calls
  `scsi_req_continue()`; when data lands, `esp_transfer_data()`
  (esp.c:1016-1042) raises for the sequencer commands:
  ```c
        case CMD_SEL | CMD_DMA: case CMD_SEL:
        case CMD_SELATN | CMD_DMA: case CMD_SELATN:
             s->rregs[ESP_RINTR] |= INTR_BS | INTR_FC;
             s->rregs[ESP_RSEQ] = SEQ_CD;
  ```
  (SELATNS instead gets `INTR_BS` + `RSEQ = SEQ_MO`, esp.c:1033-1042.) So the
  guest's first interrupt after a DMA select shows **INTR_BS|INTR_FC, RSEQ=4,
  RSTAT phase = DATA IN/OUT**.
- Command with no data (TEST UNIT READY etc.): `esp_command_complete()`
  esp.c:976-998 sets `INTR_BS|INTR_FC`, `RSEQ = SEQ_CD`, then phase STATUS and
  ORs `INTR_BS` again → guest sees BS|FC with phase = STATUS.

### Seq step 3 vs 4
QEMU only ever writes **0 (`SEQ_0`), 1 (`SEQ_MO`), 4 (`SEQ_CD`)** — grep of
`ESP_RSEQ` assignments: esp.c:267, 315, 512, 525, 789, 808, 986, 1029, 1040,
1213. It **never emits 3**. Per the 53C9x datasheet (and Linux `esp_scsi.h`
naming), step 3 = "partial command bytes transferred" (target changed phase
mid-CDB) and step 4 = "command transferred OK"; QEMU's model always completes
the CDB atomically, so only the success value 4 appears. If the Verilog can
stall mid-CDB it would need step 3, but no QEMU-tested guest depends on it.

The reason RSEQ semantics matter is documented in commit
`af947a3d85`/`b6f5c02f5f` *"esp: only set ESP_RSEQ at the start of the select
sequence"*: the old Linux 2.6 driver checks the seq step even on success and
spews `"esp0: STEP_ASEL for tgt 0"` if step/phase disagree. That's why
`ESP_RSEQ` is **not** cleared on RINTR read (see §4).

⚠️ **Likely upstream bug worth not copying**: `esp_cdb_ready()` (esp.c:448-473)
now compares *total* cmdfifo occupancy against the CDB length:
```c
    int len = fifo8_num_used(&s->cmdfifo);
    ...
    cdblen = scsi_cdb_length((uint8_t *)&pbuf[s->cmdfifo_cdb_offset]);
    return cdblen < 0 ? false : (len >= cdblen);
```
Before commit `36ec1a829a` (2025-09-25) `len` was
`fifo8_num_used(&s->cmdfifo) - s->cmdfifo_cdb_offset`. With an identify byte
present (`cmdfifo_cdb_offset == 1`) the "CDB ready" test now fires one byte
early on the byte-at-a-time PIO/TI COMMAND-phase path (esp.c:845). Use
`used - cdb_offset >= cdblen` in an implementation.

---

## 3. PDMA on the Quadra 800

### Wiring
`q800.c:463-487`: `TYPE_SYSBUS_ESP`, `it_shift = 4` (registers 16 bytes apart,
base `0x50010000`), PDMA window at `ESP_PDMA = 0x50010100`. The PDMA
MemoryRegion is only **4 bytes** wide (`esp.c:1605-1606`,
`memory_region_init_io(..., "esp-pdma", 4)`). Two sysbus IRQ lines: 0 =
`s->irq` (VIA2 CB2 / `VIA2_IRQ_SCSI_BIT`), 1 = `s->drq_irq` (VIA2 CA2 /
`VIA2_IRQ_SCSI_DATA_BIT`), both **inverted** because "SCSI and SCSI data IRQs
are negative edge triggered" (`q800.c:475-483`).

The guest sees DRQ by polling VIA2 IFR; `mac_via.c:1144-1155` makes that bit
live rather than latched:
```c
        /*
         * ... The expectation of most OSs is that the DRQ bit is live,
         * rather than latched as it would be on a real VIA so do the same here.
         * Note: DRQ is negative edge triggered
         */
        val &= ~VIA2_IRQ_SCSI_DATA;
        val |= (~ms->last_irq_levels & VIA2_IRQ_SCSI_DATA);
```

### Access sizes and byte order
`sysbus_esp_pdma_ops` (esp.c:1551-1559): `valid.min/max = 1/4`,
`impl.min/max = 1/2`, `DEVICE_NATIVE_ENDIAN` (m68k → big endian). So a 32-bit
access is split by the memory core into two 16-bit ops. The 16-bit ops are
literally two FIFO bytes, **first byte = most significant** (esp.c:1512-1515,
1533-1536):
```c
    case 2:
        esp_pdma_write(s, val >> 8);
        esp_pdma_write(s, val);
    ...
    case 2:
        val = esp_pdma_read(s);
        val = (val << 8) | esp_pdma_read(s);
```
i.e. plain sequential byte order on a big-endian bus. Note both
`sysbus_esp_pdma_read()` and `..._write()` unconditionally call `esp_do_dma(s)`
afterwards — that is what re-fills/drains the FIFO from/to the SCSI layer.

### TC accounting is asymmetric
- **Write (DATA OUT)**: TC is decremented **per byte in `esp_pdma_write()`**,
  and only if DRQ is currently asserted (esp.c:248-258):
  ```c
    uint32_t dmalen = esp_get_tc(s);
    esp_fifo_push(s, val);
    if (dmalen && s->drq_state) { dmalen--; esp_set_tc(s, dmalen); }
  ```
  (`drq_state` is re-evaluated by the push, so a byte that fills the FIFO to <2
  free does not decrement TC.) `esp_do_dma()`'s DATA OUT PDMA branch does
  **not** touch TC and does **not** bound by TC — it copies
  `MIN(async_len, 16, fifo_used)` regardless (esp.c:588-593).
- **Read (DATA IN)**: `esp_pdma_read()` is a bare `esp_fifo_pop()` — no TC
  change (esp.c:243-246). TC is decremented in `esp_do_dma()` when the FIFO is
  *re-filled* from the target: `len = MIN(len, fifo8_num_free(&s->fifo));
  esp_fifo_push_buf(...); ... esp_set_tc(s, esp_get_tc(s) - len);`
  (esp.c:643-651).

### DREQ gating — 2-byte threshold
`esp_update_drq()` (esp.c:127-167) is called from every FIFO push/pop; DRQ is
*only* meaningful while `s->dma` is set (a CMD_DMA command is latched), else it
is forced low:
```c
    if (s->dma) {
        if (to_device) {
            if (fifo8_num_free(&s->fifo) < 2) esp_lower_drq(s); else esp_raise_drq(s);
        } else {
            if (fifo8_num_used(&s->fifo) < 2) esp_lower_drq(s); else esp_raise_drq(s);
        }
    } else {
        esp_lower_drq(s);
    }
```
`to_device` = phases MO/CD/DO; `from device` = DI/ST/MI. The **2-byte**
threshold exists because the Mac does 16-bit PDMA; the last odd byte of a
transfer therefore never raises DRQ, which is exactly why the MacOS ROM falls
back to non-DMA TI for the first/last byte of an unaligned transfer (commit
`1b9e48a5bd`, *"esp: implement non-DMA transfers in PDMA mode … MacOS toolbox
ROM uses non-DMA TI commands to handle the first/last byte of an unaligned
16-bit transfer"*).

### Transfer-count-zero mid-PDMA
`esp_dma_ti_check()` (esp.c:476-482) is the single "end of DMA chunk" rule:
```c
    if (esp_get_tc(s) == 0 && fifo8_num_used(&s->fifo) < 2) {
        s->rregs[ESP_RINTR] |= INTR_BS;
        esp_raise_irq(s);
    }
```
So the interrupt fires when TC == 0 **and** the FIFO has drained below 2 bytes —
the guest is allowed to keep PDMA-reading residue after TC hits zero. DATA IN
with TC == 0 simply transfers nothing more (`len = esp_get_tc()` = 0), and DRQ
drops as the FIFO empties.

Guest **underflow** of TC (asks for more than the target has) is handled
explicitly (esp.c:667-671):
```c
        if (s->async_len == 0 && s->ti_size == 0 && esp_get_tc(s)) {
            /* If the guest underflows TC then terminate SCSI request */
            scsi_req_continue(s->current_req);
            return;
        }
```
→ leads to `esp_command_complete()`, phase STATUS, `INTR_BS`. Commit
`02a3ce56a7` notes this is what makes EMILE boot on m68k. There is a matching
residue path in `esp_do_dma()` `case STAT_ST` default (esp.c:707-713): "Consume
remaining data if the guest underflows TC" → `INTR_BS` when FIFO < 2.

---

## 4. Register semantics drivers depend on

**RSTAT (0x04, read)** — `esp_set_phase()`/`esp_get_phase()` (esp.c:87-98) own
bits 2:0 only. STAT_INT (0x80) is set/cleared strictly inside
`esp_raise_irq()`/`esp_lower_irq()` (esp.c:46-62) and is edge-guarded (a second
raise while already set does nothing). STAT_TC (0x10) is set only on the TC
non-zero→zero transition inside `esp_set_tc()` (esp.c:227-229) and cleared only
by a guest write to TCLO/TCMID/TCHI (esp.c:1307-1313). Phase progression for a
normal read command: `DATA IN` (set in `do_command_phase`, esp.c:330-334) →
`STATUS` (`esp_command_complete`, esp.c:996) → `MESSAGE IN` (only after
`CMD_ICCS`, esp.c:698 / 925).

**RINTR (0x05, read)** — esp.c:1263-1281:
```c
        val = s->rregs[ESP_RINTR];
        s->rregs[ESP_RINTR] = 0;
        esp_lower_irq(s);
        s->rregs[ESP_RSTAT] &= STAT_TC | 7;
        /* According to the datasheet ESP_RSEQ should be cleared, but as the
         * emulation currently defers information transfers to the next TI
         * command leave it for now ... s->rregs[ESP_RSEQ] = SEQ_0; */
```
So a RINTR read clears: the whole interrupt register, STAT_INT, STAT_PE, STAT_GE
— **preserving STAT_TC and the 3 phase bits** — and lowers the IRQ line. It does
**not** clear RSEQ and does **not** clear the FIFO flags. Order matters:
`esp_lower_irq()` must run *before* RSTAT is masked (commit `d294b77a95`), and
the phase must survive (commit `d68212cdb1`, *"otherwise the current SCSI phase
is lost when clearing an end-of-transfer interrupt"*).

**RSEQ (0x06)** — set to `SEQ_0` at select (esp.c:267) and on "no such LUN"
(esp.c:315); `SEQ_MO`(1) for SELATNS; `SEQ_CD`(4) once the CDB has been
accepted / at the deferred BS|FC interrupt; zeroed by `CMD_MSGACC`. Never
cleared by RINTR read.

**RFLAGS (0x07, read)** — esp.c:1290-1293: returns **only**
`fifo8_num_used(&s->fifo)`. The upper (sequence-step / capacity) bits are always
0. It is not cleared at end of DMA (commit `942ee6c83f`, *"The internal state of
the ESP sequencer is not affected when raising an interrupt to indicate the end
of a DMA transfer"*), and is only zeroed by `CMD_MSGACC` (esp.c:1214).

**TC latch timing** — writes to TCLO/TCMID/TCHI go to `wregs` only
(`esp_reg_write` falls through to `s->wregs[saddr] = val;` at esp.c:1342) and
just clear STAT_TC. The visible/working counter `rregs[TCLO/MID/HI]` is loaded
**only when a command with the CMD_DMA bit is written** (esp.c:1170-1180):
```c
    if (cmd & CMD_DMA) {
        s->dma = 1;
        /* Reload DMA counter.  */
        if (esp_get_stc(s) == 0) { esp_set_tc(s, 0x10000); }
        else                     { esp_set_tc(s, esp_get_stc(s)); }
    } else { s->dma = 0; }
```
Note the 0 → 0x10000 special case (24-bit counter, but only 16 bits' worth of
"0 means 64K"). Reads of TCLO/TCMID return the live decrementing counter; TCHI
returns `chip_id` until it has ever been written (`s->tchi_written`,
esp.c:1282-1289) — q800/sysbus sets `chip_id = TCHI_FAS100A` = 0x4
(esp.c:1601).

**CMD_ICCS (0x11)** — `write_response()` → esp.c:682-740 (DMA) / 921-943
(non-DMA). Non-DMA: pushes the **status byte** to the FIFO, sets phase MESSAGE
IN, recurses and pushes a **0 message byte**, then raises `INTR_FC` only:
```c
    case STAT_ST:
        case CMD_ICCS:
            esp_fifo_push(s, s->status);
            esp_set_phase(s, STAT_MI);
            esp_do_nodma(s);   /* pushes 0, raises INTR_FC */
```
DMA/PDMA: same two bytes but each consumes 1 from TC, and the MI byte (and thus
`INTR_FC`) is only produced if TC is still > 0 after the status byte — with
`TC == 1` you get status only and **no INTR_FC**. Commit `0ee71db4fc` made both
paths agree on "only INTR_FC is asserted".

**CMD_MSGACC (0x12)** — esp.c:1209-1216:
```c
        s->asc_mode = ESP_ASC_MODE_DIS;
        s->rregs[ESP_RINTR] |= INTR_DC;
        s->rregs[ESP_RSEQ] = 0;
        s->rregs[ESP_RFLAGS] = 0;
        esp_raise_irq(s);
```
i.e. disconnect interrupt, RSEQ and RFLAGS cleared, chip returns to disconnected
mode. Phase bits are **not** touched.

**Selection timeout / no device** — `esp_select()` esp.c:274-282:
```c
    if (!s->current_dev) {
        s->rregs[ESP_RSTAT] = 0;          /* phase bits + everything cleared */
        s->asc_mode = ESP_ASC_MODE_DIS;
        s->rregs[ESP_RINTR] = INTR_DC;    /* assignment, not |= */
        esp_raise_irq(s);  return -1;
```
So RSTAT reads back as 0x80 (STAT_INT only, phase = DATA OUT/0), RINTR = INTR_DC
(0x20), RSEQ = SEQ_0 (set just above at esp.c:267). Same shape for a missing LUN
in `do_command_phase()` (esp.c:311-317), which additionally sets
`RSEQ = SEQ_0`.

**Misc commands** — `CMD_FLUSH` resets the data FIFO only (not cmdfifo, not TC,
esp.c:1187); `CMD_RESET` → `esp_soft_reset()` → `esp_hard_reset()` which zeroes
all r/w regs, both FIFOs, `dma`, sets `asc_mode = DIS` and `rregs[ESP_CFG1] = 7`
(esp.c:1099-1113); `CMD_ENSEL` sets `RINTR = 0` silently, `CMD_DISSEL` sets
`RINTR = 0` **and raises an IRQ** (esp.c:1239-1247) — i.e. an interrupt with an
empty interrupt register.

**Mode/command validity** — new in 2025 (`ab1207401e`, `6f8ce26bb0`):
`asc_mode` ∈ {DIS, INI, TGT}; commands are grouped by `cmd & 0x70` and rejected
if they don't match the mode (esp.c:1134-1164). Watch out for the rejection
action (esp.c:1322-1325):
```c
        if (!esp_cmd_is_valid(s, s->rregs[saddr])) {
            s->rregs[ESP_RSTAT] |= INTR_IL;
            esp_raise_irq(s);
```
It ORs `INTR_IL` (0x40) into **RSTAT**, where 0x40 is `STAT_GE`, not into RINTR.
That looks like an upstream slip; real silicon sets the illegal-command bit in
the *interrupt* register. Don't mirror it blindly.

---

## 5. What emulated-driver authors get wrong — condensed history (2021→2025)

The whole device was rewritten by Mark Cave-Ayland in a huge Jan-2024 series
(`514425-*` message IDs) plus a Mar-2024 DRQ series; nearly every patch is a
real guest bug. The ones that matter for a register-accurate 53C96:

**Deferred interrupts (the single biggest trap).** A select-with-CDB does
**not** interrupt when the CDB is consumed. The BS|FC interrupt is deferred
until the SCSI layer returns data (`esp_transfer_data`) or completes
(`esp_command_complete`) — `4e78f3bf35`, `c90b279229` (*"ensures that the guest
visible function complete interrupt is only set once the SCSI layer has
returned"*), `1fa3812ee8`. Interrupt bits are **latched by OR**, never assigned
(`cf47a41e05`, *"esp: latch individual bits in ESP_RINTR register"*).

**RINTR read must not destroy phase or RSEQ.** `d68212cdb1` (phase),
`d294b77a95` (lower IRQ before masking RSTAT), `af947a3d85`/`b6f5c02f5f` (don't
clear RSEQ — old Linux 2.6 prints `STEP_ASEL` spam otherwise).

**Zero ESP_CMD when a TI ends because the phase changed** — `cb22ce5038`
(*"This is the behaviour documented in the datasheet and allows the state
machine to correctly process multiple consecutive TI commands"*). See
esp.c:538, 826, 991, 1051.

**FIFO under/overflow and residue.** `02a3ce56a7` (TC underflow terminates the
SCSI request; fixes EMILE boot); `dfaf55a19a` 2024-07 (removing the
transfer-size check so a DMA TI with nothing left to transfer doesn't assert —
gitlab #2415); `5a50644e47` (don't assert if the FIFO is empty on non-DMA
SELATNS); `esp_fifo_pop()` returns 0 on empty rather than faulting
(esp.c:186-198); `esp_fifo_push()` silently drops on overrun with
`trace_esp_error_fifo_overrun()`.

**Mixed DMA/PIO within one command is real and must work.** `8ba3204893`:
*"Certain versions of MacOS send the first 5 bytes of the CDB using DMA and then
send the last byte of the CDB by writing to the FIFO"* → esp.c:862-874.
`1b9e48a5bd`: MacOS ROM uses non-DMA TI for the first/last byte of an unaligned
16-bit PDMA transfer. `41f157e50f`: the FIFO must stay readable even during
DMA.

**Don't raise INTR_BS while the guest is pre-loading the FIFO in DATA IN.**
`9655f72c20` — *"the host may preload the FIFO with unaligned bytes before
issuing the main DMA transfer … needed to prevent the MacOS Disk Utility from
failing"* (esp.c:912-915).

**Byte-at-a-time CDB via repeated TI.** `5d02add4d7` — *"NextSTEP uses multiple
TI commands to transfer the CDB one byte at a time (as opposed to loading the
FIFO and using a single TI command)"*; hence `esp_cdb_ready()` /
`scsi_cdb_length()` inference of CDB length from the group code. Security
hardening followed in `3cc70889a3` and `36ec1a829a` (see the off-by-offset
caveat in §2).

**DRQ must be a continuously-evaluated function of FIFO occupancy, not manually
pulsed.** `743d873645` + `ffa3a5f2be` + `60c572502c` + `d7fe931818` (which
resolved gitlab issues #611 and #1831) moved DRQ into `esp_update_drq()` called
from every FIFO access, and `442de89a93` made it edge-detected.

**Removed hacks worth knowing** (they were symptoms of the above being wrong):
`a1ccceb9c4` removed the "MacOS TI workaround that pads FIFO transfers to
ESP_FIFO_SZ"; `e7a661d117` removed manual TC/RSEQ resets when executing a SCSI
command; `f0a24eeed9`/`0c5ae734c2` removed manual STAT_TC pokes in favour of the
single `esp_set_tc()` edge; `a034765161` made MESSAGE OUT and COMMAND phases
decrement TC too, "to ensure that STAT_TC is triggered during the right parts
of the transfer".

**Also implemented, if the target needs it:** `CMD_PAD` (0x18) with DMA for both
data directions — drops TC bytes on DATA IN, injects zero bytes on DATA OUT
(esp.c:600-612, 654-664; commit `a6cad7cd39`, used by NeXTcube).
