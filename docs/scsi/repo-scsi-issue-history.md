# SCSI issues in wombat33_MiSTer — full catalog

Compiled 2026-08-28 from `SingleStepTests/test-blockers.md`, `preboot/iotest/`,
`rtl/iosb.sv`, git history, and the resume docs, ahead of the Problem-4 disk-
boot debugging.

Two distinct eras exist in this repo and they fail in different ways:

- **Era 1 (2026-06 → 08-28): "real Quadra 800 + real ROM SCSI driver"** — the
  bench campaign. Every issue is *software/OS-environment*, discovered on
  silicon, and almost never reproducible in an emulator.
- **Era 2 (2026-08-28, current): "our RTL 53C96 + real ROM"** — machine
  bring-up. Two issues found so far, both *register-semantics mismatches vs
  QEMU/MAME*, both found by tracing the ROM's polling loop.

The disk-boot debugging is Era 2, but Era 1's failure taxonomy is what tells
you where to look.

---

## Part A — Era 1: OS/driver-path SCSI issues (SingleStepTests/test-blockers.md)

### A1. Payload load through the 68040 caches — "works one boot in twenty" (finding 7)
`SingleStepTests/test-blockers.md:10-38`, `preboot/common/boot/boot_stub_scsi.s:34-60`

1. **Symptom (silicon):** the bench "almost never started, and only very
   occasionally got as far as painting." Non-deterministic across boots.
2. **Root cause:** `boot_stub_scsi.s` did one 256 KB `_Read` to `$40000` then
   `JMP`'d in with no cache management. On 68020/68030 (256-byte write-through
   caches) that was safe; on the 68040's 4 KB **copyback** D-cache + 4 KB
   I-cache, dirty lines from the ROM's own low-RAM use get written back *on top
   of* the transferred payload, and stale I-lines execute instead of the
   delivered bytes.
3. **Fix:** `CPUSHA BC` + `NOP` on **both** sides of `_Read` (push-and-
   invalidate deliberately, not `CINVA`, because a driver that copies via CPU
   leaves the payload dirty in D-cache). Applied to all three boot stubs. Later
   superseded by A6's `_HwPriv` call.
4. **Open:** none, but note the model was later partly invalidated (A8): Apple
   SCSI is *pseudo*-DMA, so "the DMA engine reads stale RAM" was the wrong
   mental model even though the fix was right for the I-cache half.

### A2. Results-write hang at run=58, `/Results.jsonl` all zero (2026-06-13 finding 2 + commit `b527a95`)
`test-blockers.md:1148-1160`

1. **Symptom:** froze at exactly `run=58` with an all-zero results file.
2. **Root cause (as diagnosed then):** the writer buffers 16 KB batches at
   ~281 B/line, so the **first** `_Write` ($A003) fires at ~line 58. Buffer
   filled through the copyback D-cache; "the Quadra's SCSI does DMA from
   physical RAM" so the driver read stale/zero RAM. Param block identical to
   the working `_Read`, so refnum/drive were exonerated.
3. **Fix:** `CPUSHA DC` ($F478) before every `_Write` in
   `common/runtime/jsonl_writer.c:58-68`.
4. **Open/retracted:** the *cache-coherency* attribution was later shown to be
   aimed at a nonexistent DMA engine (A8) — and the real root cause was A9
   (stack smash). The flush stayed because removing it regressed under MAME
   (A5).

**Key reusable number: test 58 = the first 16 KB flush.** Two independent
breakages both stalled there, which is how the batch arithmetic got confirmed.

### A3. `_Write` ran under the bench VBR, not the OS VBR (finding 5, commit `790970f`)
`test-blockers.md:1176-1191`, `jsonl_writer.c:24-31,70-76`

1. **Symptom:** intermittent crashes and slowness during writes.
2. **Root cause:** `_Write` goes through the ROM SCSI driver, which takes its
   own traps/faults while servicing the transfer. The bench had its **own**
   VBR installed (vectors 2..9, 11..15, 32..47 are recovery stubs), so any
   driver-internal fault hijacked `recovery_core` and longjmp'd out mid-write.
   `_Read` worked precisely because the boot block runs before `install_vbr`.
3. **Fix:** bracket every `_Write` with `use_os_vbr()` / `use_recovery_vbr()`.
   Declared weak so `iotest`/`keytest` (no recovery.o) skip it.
4. **Still-relevant note:** `common/runtime/recovery.s:83-92` records the
   *sibling* rule — autovector interrupts 25..31 are deliberately left to the
   ROM, because "the .Sony / SCSI driver's synchronous `_Write` ... **lowers
   IPL internally to wait for its completion interrupt**, and routing that IRQ
   into `recovery_core` jumped to a stale resume PC, so the write never
   returned."

### A4. IPL-lowering "fix" — a regression shipped untested (finding 18/19, commits `258a81c` then `b0ee52f`)
`test-blockers.md:414-465`

1. **Symptom/hypothesis:** first full hardware run showed writes still fail;
   theory was "the write runs at IPL 7 and the 53C96 signals completion by
   interrupt, which can never be taken while masked."
2. **Root cause:** wrong. Emulator triage table (`test-blockers.md:441-448`):

   | Variant | MAME result |
   |---|---|
   | drop IPL to 0 across `_Write` | hangs at test 58 |
   | remove `use_os_vbr()` bracket | crashes, ROM takes over |
   | remove the cache flush | hangs at test 58 |
   | flush + VBR bracket, IPL untouched | `ALL TESTS DONE`, ioResult 0 |

3. **Fix:** reverted. All three candidate levers make it worse; the shipped
   config was already correct.
4. **Lesson recorded verbatim:** "**Neither emulator can reproduce the
   hardware write failure** — both complete the corpus. So MAME and QEMU can
   only catch regressions here, never confirm a fix."

### A5. The `_Write` F-line hunt and the vector-11 low-mem trap (finding 20, commit `8a95e80`)
`test-blockers.md:476-555`

1. **Symptom:** hardware-only, write-only Sad Mac `0F/000A` (System Error 10 =
   F-line) at the first flush.
2. **Investigation:** QEMU `-d in_asm` (log order = first-execution order)
   showed the write path runs ROM `_BlockMove`'s `MOVE16 (A0)+,(A1)+` burst
   loop plus a cache epilogue (`PTESTR` + `MOVEC MMUSR` + `CPUSHL BC,(A1)` per
   line for <$C00, `CPUSHA BC` above), and **~1000 blocks of `$408Dxxxx` SCSI
   Manager code that the read path never touches**. Phase correlation killed
   the "instruction gap" theory: the ROM's own boot/mount phase already
   executes `move16`/`ptestr`/`cpushl`/`pflusha` and the machine survives it.
3. **Sub-finding worth carrying forward — never patch vector 11's low-mem slot
   in place** (`test-blockers.md:518-526`): patching `$2C` directly made MAME
   die deterministically at the **8th** flush with `0F/0000001B` = `dsFSErr`,
   stored by a `_SysError` reached from `$40809A26` inside the OS-trap
   dispatcher, **with the thunk never entered**. Some ROM OS-trap/FS code reads
   that slot as *data*.
4. **Fix/instrument:** `common/runtime/fline_shim.s` v2 — a private 256-entry
   forwarding table repointed via `recovery.s`'s `orig_vbr`, entry 11 → thunk,
   every other entry → a 6-byte stub that jumps through the **live** low-mem
   slot at exception time "so runtime vector patching by the ROM/driver (e.g.
   pseudo-DMA bus-error handlers, completion IRQs) keeps working mid-transfer."
5. **Suspects listed at the time (three of four now closed):** "an op in the
   un-decoded SCSI write machinery (a hardware-only Turbo SCSI branch the
   emulators don't steer into)", an FPU op, or "garbage execution after a
   pseudo-DMA recovery failure" — the last one was correct in spirit (A9).

### A6. `CPUSHA BC` bus-errors on real Quadra silicon (finding 16, commit `375ef05`)
`test-blockers.md:333-378`, `boot_stub_scsi.s:295-320`

1. **Symptom:** Sad Mac `0000000F 00000001` = System Error 1 = vector 2 = bus
   error.
2. **Root cause:** isolated by three halt-point boot blocks — T1 (halt before
   `CPUSHA`) runs and paints, T3 (execute one more instruction) dies, T2
   (`CPUSHA`→`NOP`) boots. **`CPUSHA BC` itself bus-errors on this silicon.**
   Both MAME and QEMU execute it happily.
3. **Fix:** all cache ops now go through the ROM's `_HwPriv` selector 1
   (`moveq #1,d0` + `.word 0xA198`), which flushes both caches; clobbers D0/A0
   so the boot block saves `%d4/%d6/%d7/%a0`.
4. **Note:** the Sad Mac ID differs from the earlier `0000000A` seen with the
   full boot block — "the fault presents differently depending on what runs
   after it."

### A7. `_Read`-path exoneration (finding 17)
`test-blockers.md:380-412` — hardware test T5 painted `A 00000008` (BootDrive
8), `D FFFFFFDF` (refnum -33), `E 00000000` (`_Read` succeeded), `C A7263EC9`
(checksum matches host). So on silicon: disk mounts, driver works, 256 KB
`_Read` transfers intact. **`~/testdisk.hda`, the `Apple_Driver43` partition
and the disk structure are all exonerated** — useful when the RTL boot fails:
the disk image is not the variable.

### A8. "Apple SCSI is pseudo-DMA and bus errors are normal" — the reframing (commit `81655b2`)
`docs/quadra800-developer-notes.md:237-288`

From NetBSD `sys/arch/mac68k/obio/esp.c`, the mac68k driver for this exact
53C96:

> "Apple 'DMA' is weird. Basically, **the CPU acts like the DMA controller**.
> The DREQ/ off the chip goes to a register that we've mapped at attach time
> (on the IOSB or DAFB...). Apple also provides some space for which the memory
> controller handshakes data to/from the NCR chip with the DACK/ line."

> "When you're attempting to read or write memory to this DACK/ed space, and
> the NCR is not ready for some timeout period, **the system will generate a
> bus error**... 1) (on write) The FIFO is full and is not draining. 2) (on
> read) The FIFO is empty and is not filling. 3) An interrupt condition has
> occurred."

> "**In order to make allowances for the hardware structure of the mac, spl
> values in here are hardcoded!!!** ... to **allow serial interrupts to get in
> during scsi transfers.**"

Three consequences recorded (`developer-notes.md:268-287`): (1) there is no
DMA engine, so the cache-flush theories were "aimed at something that does not
exist"; (2) **a bus error mid-transfer is expected behaviour** and the driver
installs a temporary bus-error handler and resumes — anything disturbing
vector 2 during `_Write` breaks that recovery; (3) interrupts must be able to
get in during a transfer.

**This is the single most important document for the RTL debugging** — see
Part D for why our IOSB currently cannot produce that bus error.

### A9. The actual root cause: the boot block's stack smashed the SCSI Manager's write glue (finding 21, commit `ab3245d`)
`test-blockers.md:569-616`

1. **Symptom:** the F-line shim converted the Sad Mac into a readable paint:
   `run=58 ok=58 trap=0`, then `FLINE OP+PC: FFFF 0000FF44` — `FFFF` = the
   thunk's sentinel for a non-format-0 frame (a format-2 "unimplemented FP"
   frame), stacked PC `$FF44` = **low RAM**.
2. **Root cause:** the boot block's first act was `move.l #$10000,%sp`. The
   ROM boot heap keeps the **SCSI Manager 4.3 RAM glue just below `$10000`** —
   on this hardware ~`$BC` below the stack top, on MAME/QEMU ~`$B38` below
   (QEMU builds an XPT trampoline at `$F4C8`: `jsr` into the driver, return
   through `[jIODone]` at `$8FC`). Every boot-block call scribbled frames over
   it; hardware *guaranteed* the glue was dead, the emulators' allocation sat
   just deep enough to survive. `_Read` never calls this structure. The first
   `_Write` jumped into the corpse, the bytes decoded as an unimplemented-FP
   pattern → vector 11.
3. **Fix:** "park stacks only on RAM we own." All three boot stubs no longer
   touch SP at all; the payload stack moved from `$100000` to `$80000`.
4. **Every prior signature fits at once:** hardware-only, write-only,
   first-flush timing, the F-line ID, and the IPL/VBR/cache dead ends.

### A10. Pre-System driver requests must be ≤16 KB — writes AND reads (findings 24 and 27)
`test-blockers.md:741-746` and `890-896`

1. **Symptom:** a single 48 KB `_Write` (and later a single 35 KB `_Read`)
   Sad Mac'd `0F/01`, dying in the ROM `Enqueue` at `$40809948` with
   `ea=$FFFFFFFF`.
2. **Root cause:** "a single pre-System `_Write` above 16 KB drives the ROM
   Device Manager into a **queued** path whose low-mem structures are still
   boot-fill `$FFFFFFFF`". The boot block's single 256 KB `_Read` survives
   *only* in the boot-time environment.
3. **Fix:** the writer slices any batch into ≤16 KB requests; the chain stub
   slices reads the same way.
4. **Standing rule** (`RESUME-scsi-write.md:93-94`): "ALL pre-System driver
   requests ≤16 KB — writes AND reads."

### A11. HANDOFF_ADDR collisions corrupting refnum/drive (findings 10, 24, 27)
`test-blockers.md:64-76, 762-773, 897-904`

1. **Symptom:** `_Write` to refnum 0; the Device Manager walked a boot-fill
   queue pointer and Sad Mac'd. Diag row painted `rn=0000 dr=0000
   base=00000000`.
2. **Root causes (three separate detonations):** (a) `HANDOFF_ADDR=$50000` sat
   *inside* the payload; the .bss zero-loop wiped it; (b) the saverestore
   corpus's `FSAVE/FRESTORE (A0)` rows do `movea.l #$80000,a0` and write frames
   right over the handoff slot.
3. **Fix:** `HANDOFF_ADDR` moved to `$00080000` in all eight boot-stub/payload-
   entry sites in one commit; the entry re-plants the handoff from its own
   entry-time copy before every chain hop.

### A12. A 68020 CACR write that silently disabled the 040 caches (finding 25)
`test-blockers.md:778-812`

1. **Symptom:** integration disks ran on hardware but **wrote nothing**,
   painting `rn=0000 dr=0000 base=00000000` with `ioResult=0000`. Flawless
   under QEMU.
2. **Root cause:** `moveq #9,d0; movec d0,cacr` (a 68020 "clear+enable
   I-cache" relic) in `cpu_fpu_bench_main.c`'s `flush_icache()`. On the 040,
   `$09` **disables both caches without pushing the dirty D-cache**, so every
   global written through copyback — including the handoff refnum/drive and
   writer context — became invisible. `_Write` went to refnum 0 and "the ROM
   politely returned `noErr` while touching nothing."
3. **Fix:** the ROM `_HwPriv` call; tree-wide sweep for `MOVEC ...,CACR`.
4. **Trap to remember: `ioResult=0000` does not mean the write happened.**

### A13. Retracted: "MAME won't boot the SCSI .hda" (finding 6)
`test-blockers.md:1193-1200` — recorded as a MAME `macqd800` boot-device
quirk; **wrong**. MAME boots SCSI disks fine and does execute our HFS boot
block. The CPU parking in ROM at `$408046C6` was our own bug (finding 11).
"The diagnosis stood for ten weeks and sent verification down the offline-
harness path instead of at the real defect."

### A14. Boot-flavor footgun that silently ships the wrong boot block (finding 23)
`test-blockers.md:716-721` — `EXTRA_ASFLAGS` is not a make dependency and
`build_*_hda.sh` re-runs `make` without it. Always `make clean` when switching
hardware↔emulator flavors, "or the disk silently carries the wrong boot block
(a hardware stub under MAME shows the ROM boot-scanner screen: the finding-11
low-memory wipe)."

---

## Part B — Era 2: our RTL 53C96 (the two issues found so far)

### B1. Boot spun forever in the SCSI scan — STATUS bit 7 hardwired 0 (commit `eb3311f`, RESUME-machine-bringup.md:41-50)
1. **Symptom:** after the finding-33 VBL fix, the boot "sat at `$408D1982-98`
   polling the 53C96 for 680M+ cycles."
2. **Root cause:** the loop decodes as `btst #7` of **STATUS (reg 4)** waiting
   for INT after a SELECT. Our RTL raised `irq` on selection timeout, but
   STATUS bit 7 was hardwired 0. QEMU `esp.c` mirrors `STAT_INT 0x80` into
   RSTAT. **The ROM polls STATUS, not the VIA.**
3. **Fix:** `rtl/ncr53c96.sv:124` —
   `(rs == 4'h4) ? {irq, 1'b0, 1'b0, tc_zero, 1'b1, phase}` (was
   `{1'b0, ...}`).
4. **Result:** diskless boot now completes — slot scan → SCSI scan →
   flashing-`?` floppy idle loop at `$408014CA`, ~2.31G cycles, "first time
   the machine reached the correct diskless end state."

### B2. DAFB VBL on the wrong pseudo-VIA slot bit — a 7-bit concat (finding 33, commit `0316cb0`)
Not SCSI itself but it lives in the same IFR and it is the template for the
next bug.
1. **Symptom:** Sad Mac `0000000F/00000033` at ~2.21G cycles.
2. **False lead:** `$33` was read through the exception dispatcher's
   `ID = vector − 1` formula → vector 52 = FPU OPERR → a whole FPSP/FSAVE-frame
   theory. **The trace refuted it** — no FPSP flow anywhere near the failure.
   `$33` = 51 = **dsBadSlotInt**, an *explicit* `_SysError`, not vector−1.
3. **Root cause:** `rtl/iosb.sv` had
   `nubus_irqs = {1'b1, ~vbl_irq, 5'b11111}` — a 7-bit concat zero-extended to
   `[7:0]`, so VBL landed on **bit 5 = NuBus slot $E** (empty socket, no
   handler) instead of **bit 6 = internal video**.
4. **Fix:** `rtl/iosb.sv:335` —
   `wire [7:0] nubus_irqs = {1'b1, ~vbl_irq, 6'b111111};`
5. **Lesson recorded:** "not every Sad Mac code is vector−1" (now a section in
   `docs/quadra800-rom-notes.md`).

### B3. Declared-shaky areas (RESUME-machine-bringup.md:74-78, next task)
> "Expect a trace→fix loop on the 53C96 data-transfer paths — flagged shaky in
> `rtl/ncr53c96.sv`: **non-DMA transfers minimal, PDMA byte order unverified vs
> MAME dma16_swap, DMA-select CDB unimplemented**."

These are the author's own pre-registered suspicions and they map onto real
gaps in the code (Part D).

---

## Part C — preboot/iotest: what the probes exercise, and what their comments record

- **`iotest/scsi_probe.c`** — reads 8 controller registers as raw MMIO at
  `$50F10000 + (reg << 4)`, "bypassing every Mac OS driver layer," so the bus
  state is painted *before* a trap can Sad Mac and wipe the screen. Its
  rationale (`scsi_probe.c:4-18`): "When the FPGA's SCSI implementation
  misbehaves, the `_Read`/`_Write` traps tend to crash to a Sad Mac with
  vector 10 (line-A trap), because the `.Scsi` driver internally takes another
  A-line call that the dispatcher can't handle."
  - **Caveat: it is an NCR 5380 probe, not a 53C96 probe.** `scsi_probe.c:20-42`
    documents the 5380 register map (CDR/ICR/MR/TCR/CSR/BSR/IDR/RST) and
    Mac II's `addrDecoder.v`. The base address happens to be right for the
    Quadra (`$50F10000` mirrors to `sel_scsi`), and the 16-byte stride happens
    to match, but **the register meanings are wrong for the 53C96** — reg 4 on
    our chip is status/dest-id, reg 5 is istatus, and *reading reg 5 clears the
    interrupt* (`ncr53c96.sv:306-309`). Pointing this probe at the Quadra would
    silently eat interrupts. Update it before using it against the RTL.
- **`iotest/scsi_sense.c`** — goes around the Device Manager to the SCSI
  Manager (`_SCSIGet` → `_SCSISelect(id)` → `_SCSICmd(REQUEST SENSE)` →
  `_SCSIRBlind(18)` → `_SCSIComplete`) to recover `sense_key`/`asc`/`ascq`
  after a non-zero ioResult. **Known limitation** (`preboot/README.md:228-237`):
  these calls "hang or Sad-Mac the bench under MAME's `maciihmu` driver
  (vector 10 / Line-A trap)". SCSI ID is hardcoded to 0 (`README.md:212`,
  "hardcoded TODO"). Our RTL target is also ID 0 (`iosb.sv:386`
  `ncr53c96 #(.DISK_ID(0))`), so this path is at least aimed correctly.
- **`iotest/diskio_main.c:184-195`** — the sub-block rule: "Raw block-driver
  transfers must be whole 512-byte sectors: the Device Manager `.Disk`/SCSI
  driver does NO sub-block buffering... Issuing a sub-sector `ioReqCount` like
  1 byte drives the NCR5380 + DMA path into a transfer it can't satisfy —
  **fatal on real hardware (hard reset, no Sad Mac)** and a no-op/loop under
  MAME's more forgiving SCSI model." `sector_round_up()` rounds every request.
- **`iotest/drive_enum.c:1-58`** — Drive Queue / VCB walk; the topology
  painter. Relevant because the boot block's `A`/`D` rows come from the same
  globals (`BootDrive $0210`, `DrvQEl`), and finding 11 showed a bad
  low-memory write kills exactly this.
- **`iotest/diskio_main.c:387-416`** — the Mac OS error mnemonic table for
  triage (`-36 ioErr` "most common SCSI fail", `-56 nsDrvErr`, `-64 lastDsk`
  "drive timeout (old SCSI)", `-65 offLine`).
- Notably `iotest`/`keytest` do **not** link `recovery.o`, so they skip the
  VBR bracket entirely — which is exactly why "iotest never installed these
  and writes fine; that was the tell" (`recovery.s:91-92`).

---

## Part D — How the 53C96 is wired in `rtl/iosb.sv` (quoted), plus latent traps

### Decode and register stride
```systemverilog
// rtl/iosb.sv:368-369
wire sel_scsi   = in_low && (addr[19:8] == 12'h100);   // 53C96 regs, 16-byte strides
wire sel_sdma   = in_low && (addr[19:8] == 12'h101);   // Turbo SCSI pseudo-DMA
```
`in_low` is only `addr[27:24] == 4'h0` (`iosb.sv:362`), so `$50F10000` /
`$50F10100` alias onto `$50010000`/`$50010100` — the ROM uses the `$50F1xxxx`
mirror, and that works. `rs` comes from `addr[7:4]` (`iosb.sv:393`), giving the
16-byte stride; the 16 registers exactly fill the `$100` window.

### Register strobe and byte lane
```systemverilog
// rtl/iosb.sv:376
wire scsi_strobe = ce && (astate == A_IDLE) && sel && !ack && sel_scsi;
// rtl/iosb.sv:440-442
wire [7:0] wbyte = be[3] ? wdata[31:24] :
                   be[2] ? wdata[23:16] :
                   be[1] ? wdata[15:8]  : wdata[7:0];
// rtl/iosb.sv:527
else if (sel_scsi) rdata <= {4{ncr_rdata}};  // scsi_strobe fires
```

### The pseudo-DMA path — /DTACK holdoff
```systemverilog
// rtl/iosb.sv:528-540
else if (sel_sdma) begin
    // pseudo-DMA beat: hold off the ack until the chip has
    // moved every byte (the real IOSB holds /DTACK on !DRQ;
    // a wedged transfer ends in the CPU watchdog's berr)
    ack        <= 0;
    sdma_word2 <= !(be == 4'b1111);
    sdma_left  <= (be == 4'b1111) ? 3'd4 : 3'd2;
    sdma_shift <= wdata;
    sdma_wbyte <= wdata[31:24];
    sdma_rd    <= ~write;
    sdma_wr    <=  write;
    astate     <= A_SDMA;
end
```
```systemverilog
// rtl/iosb.sv:556-570
A_SDMA: if (sdma_valid) begin
    if (sdma_left == 3'd1) begin
        sdma_rd <= 0;
        sdma_wr <= 0;
        ack     <= 1;
        rdata   <= sdma_word2 ? {sdma_shift[7:0], sdma_rbyte, 16'h0}
                              : {sdma_shift[23:0], sdma_rbyte};
        astate  <= A_IDLE;
    end
    else begin
        sdma_shift <= {sdma_shift[23:0], sdma_rbyte};
        sdma_wbyte <=  sdma_shift[23:16];
        sdma_left  <=  sdma_left - 1'b1;
    end
end
```

### Interrupt / DRQ wiring into the pseudo-VIA
```systemverilog
// rtl/iosb.sv:329-331 (comment)
// IFR bits: 0 SCSI DRQ, 1 any-slot (VBL/NuBus/SONIC via nubus_irqs), 3 SCSI IRQ, 4 ASC (latched).
// rtl/iosb.sv:339-342
wire       via2_active = |(via2_ifr[6:0] & via2_ier[6:0] & 7'h1b);
wire [7:0] via2_ifr_r  = {via2_active, via2_ifr[6:0]};
wire scsi_irq_i = scsi_irq | ncr_irq;
wire scsi_drq_i = scsi_drq | ncr_drq;
// rtl/iosb.sv:472-473  (edge-latched, level-following)
if (scsi_irq_i != scsi_d) via2_ifr[3] <= scsi_irq_i;
if (scsi_drq_i != drq_d)  via2_ifr[0] <= scsi_drq_i;
```
(`rtl/quadra800.sv:206-207` ties the external `.scsi_irq`/`.scsi_drq` inputs to
`1'b0`; only `ncr_irq`/`ncr_drq` are live.)

### 16-bit ↔ 8-bit byte order (the whole chain, all consistent big-endian)
```systemverilog
// rtl/ncr53c96.sv:101   16-bit block-device read port
assign sd_buff_din = sbuf[sd_buff_addr];
// rtl/ncr53c96.sv:113-114   even byte index = HIGH half of the word
wire [7:0] sbuf_byte = sbuf_pos[0] ? sbuf[sbuf_pos[9:1]][7:0]
                                   : sbuf[sbuf_pos[9:1]][15:8];
// rtl/ncr53c96.sv:159-162   synthesized data, same convention
task set_byte(input [9:0] idx, input [7:0] b);
    if (idx[0]) sbuf[idx[9:1]][7:0]  <= b;
    else        sbuf[idx[9:1]][15:8] <= b;
// rtl/ncr53c96.sv:192
if (sd_buff_wr) sbuf[sd_buff_addr] <= sd_buff_dout;
```
`verilator/sim/sim_blkdevice.cpp:100-103` packs `(byte1 << 8) | byte2` with
byte1 read first, so file byte 0 → word bits [15:8] → `sbuf_pos=0` → first PDMA
byte → `rdata[31:24]`. **The end-to-end order is self-consistent.** The
longword-level convention matches MAME `dma16_swap` (first SCSI byte in
D31-24) — see `mame-ncr53c90-quadra-pdma.md`.

### Latent traps found while reading (not recorded findings yet)

1. **`sel_sdma` byte-lane handling is longword-only.** `sdma_left` is `4` for
   `be==4'b1111` and **`2` for everything else, including a single-byte
   access**, and both the read result (`{…, 16'h0}` at bits 31:16) and the
   write source (`wdata[31:24]`) are hardwired to the **upper** half. A word
   access at `$50F10102` (`be==4'b0011`) would write the wrong bytes and return
   data in the wrong lanes; a byte access would move two bytes. The ROM *does*
   use single-byte PDMA accesses (CDB last byte, residuals). `iosb.sv:534-536,
   561-562`.
2. **The "CPU watchdog's berr" in the comment at `iosb.sv:530-531` does not
   exist.** `rtl/quadra800.sv:398` is `S_IOSB: if (iosb_ack)` with no timeout,
   and `S_BERR` (`quadra800.sv:382,422-425`) is reached only from address
   decode. So a PDMA beat where DRQ never comes back **hangs the machine
   forever** instead of taking a bus error. Per A8, the real driver *depends*
   on that bus error to run its recovery path ("the FIFO is full and is not
   draining"). This is the most likely shape of a disk-boot hang: no Sad Mac,
   no trace movement, PC parked on one `$50F101xx` access.
3. **Lost-interrupt race on ISR read.** `raise()` (`ncr53c96.sv:153-156`) does
   `istatus <= istatus | bits; irq <= 1;` in the target FSM at
   `ncr53c96.sv:221-278`, while the register block *later in the same
   `always`* does `4'h5: begin istatus <= 0; irq <= 0; end`
   (`ncr53c96.sv:306-309`). Same-cycle raise + ISR read ⇒ the raise is silently
   dropped. Given B1 showed the ROM spins on an INT bit, a dropped interrupt is
   an infinite poll.
4. **`ce` gating asymmetry.** `dma_valid` is generated in a block that is
   **not** `ce`-gated (`ncr53c96.sv:184,205-218`), but `A_SDMA: if (sdma_valid)`
   in the IOSB only evaluates when `ce` is high (`iosb.sv:466,556`). Harmless
   in the Verilator sim (`verilator/sim.v:103` passes `.ce(1'b1)`), but a hang
   on any build where `ce` is not every cycle.
5. **DMA-select is not decoded.** `exec_command` masks the DMA bit off
   (`op = c[6:0]`, `ncr53c96.sv:327`) and `run_cdb` always pulls the CDB **out
   of the FIFO** (`ncr53c96.sv:425-433`). The ROM issues *only* DMA selects
   (`$C1`/`$C2`) with an **empty FIFO** — so `opc` reads `8'h00` and the target
   silently executes **TEST UNIT READY** instead of the real command. Also
   `$43` (select with ATN and stop) falls into `default: raise(I_ILL)`
   (`ncr53c96.sv:396`).
6. **Non-DMA data-out has no path at all.** `fill_fifo_from_buf`
   (`ncr53c96.sv:403-419`) only handles non-DMA data-**in**;
   `if (!dma && data_dir_in)` at `ncr53c96.sv:365`. A polled/FIFO write would
   go nowhere.
7. **Reading ISR does not reset `seq_step`** (`ncr53c96.sv:306-309` clears
   `istatus`/`irq` only), unlike the real chip. If the driver reads ISR then
   re-reads seq-step to decide how far selection got, it sees a stale `3'd4`.
8. **Header comment is stale**: `iosb.sv:9-10` still says
   "SWIM2/ASC/SCC/**SCSI**/SONIC decode as present-but-inert" — SCSI is live
   now.

---

## Part E — Commit list

**`git log --oneline --all -- rtl/ncr53c96.sv rtl/iosb.sv`**

| Commit | What it did |
|---|---|
| `eb3311f` | 53C96 STATUS bit 7 mirrors INT (B1) — 1 line, unblocked the SCSI scan |
| `0316cb0` | Finding 33: `nubus_irqs` 7-bit concat, VBL on the wrong slot bit (B2) |
| `8685a7c` | Finding 31 (doc only, touched iosb incidentally) |
| `a7ec62c` | ADB modem path (keyboard/mouse) |
| `2579b29` | **Stage 3 groundwork: NCR 53C96 + Turbo SCSI + block-device plumbing** — the whole SCSI RTL; ends "Untested against the ROM yet — the current boot run hasn't reached SCSI" |
| `8a5a0ed`, `a920edb`, `f7da16d` | EASC / RTC+djMEMC / IOSB+VIA1 stages |

**`git log --grep` (case-insensitive) for scsi/53c96** — the software era,
chronologically:

| Commit | Date | What it fixed |
|---|---|---|
| `b527a95` | 06-13 | `CPUSHA DC` before `_Write` (A2) |
| `790970f` | 06-13 | `_Write` under the OS VBR (A3) |
| `375ef05` | 08-27 | Raw `CPUSHA BC` → ROM `_HwPriv` sel 1 (A6) |
| `258a81c` | 08-27 | First full hardware run; lowered IPL across `_Write` — **a regression** (A4) |
| `b0ee52f` | 08-27 | Reverted the IPL change; the emulator triage table (A4) |
| `81655b2` | 08-27 | Documented NetBSD pseudo-DMA + "bus errors are normal" (A8) |
| `8a95e80` | 08-27 | The F-line shim; the "never patch `$2C` in place" sub-finding (A5) |
| `ab3245d` | 08-27 | **The real fix**: stack off the ROM boot heap (A9) |
| `fede23b` | 08-28 | First full hardware capture |
| `d84a985`, `14d8629` | 08-27 | ROM + `Apple_Driver43` disassembly, 100% of bytes accounted; **the driver contains no F-line instructions at all** (`docs/quadra800-rom-notes.md:62-70`) |
| `f990bba`, `a8e96d8`, `2ac78ba` | — | Resume docs |

---

## Part F — Distilled lessons: what to check FIRST when the 53C96 disk-boot debugging starts

**Recurring failure pattern #1 — status/interrupt-bit semantics vs QEMU/MAME.**
This is the *only* class that has bitten the RTL so far, and it bit twice (B1,
B2), both times as an infinite poll or a bogus SysError.
- Diff every register-read expression in `ncr53c96.sv:120-132` against QEMU
  `esp.c` bit-by-bit, not just field-by-field. `STAT_INT 0x80`, `STAT_TC 0x10`,
  phase in `[2:0]`, VGC in bit 3.
- Verify ISR read-clear semantics against QEMU including `seq_step`, and fix
  the same-cycle raise/clear race (D3).
- The ROM polls the *chip*, not the VIA. Assume any "waiting forever" is a chip
  status bit, not an interrupt-delivery problem, until the trace says
  otherwise.

**Recurring failure pattern #2 — concat/width/lane arithmetic.** Finding 33 was
a 7-bit concat zero-extended to 8. Finding 30 recorded "Verilog unsized
literals are 32-bit: `maxcycles = 2500000000` went negative." Check D1 (PDMA
byte lanes) and every `{...}` in the SCSI path for implied width.

**Recurring failure pattern #3 — the byte-order chain.** It is currently
self-consistent end to end (Part D), and now verified against MAME's
`dma16_swap` at the longword level. A byte-swapped read produces a
*plausible-looking* boot block that fails its checksum — the boot block's `C`
row (`prebuilt` expected `C=862D7F48` for the all-in-one) is the free oracle.
`A`/`D`/`E` rows painting but `C` wrong = data path, not control path.

**Recurring failure pattern #4 — polling loops that never end because a
handshake never completes.** The IOSB withholds `ack` on `!DRQ` deliberately,
but there is **no timeout anywhere** (D2), while the real driver's design
*assumes* a bus error and recovers from it (A8). Symptom to expect: total
freeze with the PC on a `$50F101xx` access and zero trace progress. Instrument
this first — a cycle counter on `astate == A_SDMA` is worth more than any
amount of ROM reading.

**Recurring failure pattern #5 — "the emulators can only catch regressions
here."** Stated twice in the record (A4, finding 23). MAME/QEMU model no
caches, no ROM-heap layout, and a more forgiving SCSI. For this RTL work the
polarity flips: **QEMU git-master is the oracle for what the ROM expects the
chip to do** (it is the reference the two fixes so far were derived from) but
it cannot tell you what our RTL does wrong.
Trace-and-decode-the-ROM-loop is the method that has actually worked, twice.

**Specific first-hour checklist:**
1. Confirm the ROM's SCSI-scan path completes: it did as of `eb3311f`
   (diskless reaches `$408014CA`). Any regression there is a register-read
   bug.
2. Trace which command opcodes the ROM writes to reg 3 during mount. (Now
   known — see `rom-driver-scsi-access-patterns.md`: always `$C1`/`$C2` DMA
   selects, `$90` DMA transfer-info, `$10` PIO transfer-info, `$11` ICCS,
   `$12` message-accept, `$01` flush.)
3. Confirm the CDB arrives correctly given the ROM's split delivery (FIFO PIO
   for bytes 0..n−2, final byte via the PDMA port).
4. Watch `blocks_left`/`lba` and the `T_FETCH`/`T_XFER`/`T_FLUSH` transitions
   (`ncr53c96.sv:221-278`) against `io_rd`/`io_ack` from `sim_blkdevice`. Note
   `run_cdb` sets `blocks_left <= 0` for WRITE(6)/(10) (`ncr53c96.sv:495-504`)
   — writes rely entirely on `sbuf_pos == 512` and `tc_zero`.
5. Only then look at PDMA byte order — and check the `C` checksum row rather
   than eyeballing bytes.
6. Iterate with the fastboot ROM (`verilator && make fastboot`, ~47 s/lap,
   `docs/tools/make-fastboot-rom.sh`); run the acceptance gate on the pristine
   ROM.

**Two "do not repeat" entries:**
- Do not ship a candidate fix to the acceptance gate without running it in the
  sim first — that mistake cost three hardware trips (A4, `b0ee52f`: "three I
  should not have offered").
- Do not read a Sad Mac code as `vector − 1` by reflex. `$33` was
  `dsBadSlotInt` from an explicit `_SysError`, and the vector−1 reading burned
  a day on a nonexistent FPU bug (B2, `docs/quadra800-rom-notes.md`).
