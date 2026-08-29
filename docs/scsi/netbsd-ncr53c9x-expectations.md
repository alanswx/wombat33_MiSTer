# NetBSD ncr53c9x driver — chip-behavior expectations

Research notes for the wombat33 `rtl/ncr53c96.sv` bring-up (2026-08-28).
Extracted from NetBSD trunk (fetched from GitHub):
- `sys/dev/ic/ncr53c9x.c` (rev 1.156), `ncr53c9xreg.h` (1.17), `ncr53c9xvar.h` (1.59)
- `sys/arch/mac68k/obio/esp.c` (1.66) + `espvar.h` — **the mac68k PDMA
  attachment, i.e. this exact hardware: 53C96 on Quadra with pseudo-DMA**
- `sys/arch/m68k/m68k/trap_subr.s`, `mac68k/locore.s`, `mac68k/machdep.c`,
  `mac68k/viareg.h` (the bus-error stub the PDMA depends on)

This is documentation/expectation mining: what a battle-tested driver assumes
the chip does. NetBSD has **no 53C96-specific erratum workarounds anywhere** —
the 53C96 is treated as a clean ESP200-class part (see §4).

---

# 1. PDMA on mac68k Quadra (this is the Quadra 800 path)

## 1.1 Which path a Quadra 800 takes

`espattach` dispatches on `SCSIBase - IOBase`, and Q800 is named explicitly
(esp.c:189-211):

```
	 * For Wombat, Primus and Optimus motherboards, DREQ is
	 * visible on bit 0 of the IOSB's emulated VIA2 vIFR (and
	 * the scsi registers are offset 0x1000 bytes from IOBase).
	 *
	 * For the Q700/900/950 it's at f9800024 for bus 0 and
	 * f9800028 for bus 1 (900/950).  For these machines, that is also
	 * a (12-bit) configuration register for DAFB's control of the
	 * pseudo-DMA timing.  The default value is 0x1d1.
	 */
	if (oa->oa_addr == 0) {
		switch (reg_offset) {
		case 0x10000:
			quick = 1;
			esp_have_dreq = esp_iosb_have_dreq;
```

(the comment says 0x1000, the code tests 0x10000; machdep.c:1978 sets
`case MACH_MACQ800: SCSIBase = base + 0x10000;`). So Q800 = **"quick" PDMA +
IOSB DREQ**, `sc_freq = 16500000` ("From the Q650 developer's note"),
`sc_rev = NCR_VARIANT_NCR53C96`, `sc_cfg1 = sc_id (7)`,
`sc_cfg2 = NCRCFG2_SCSI2`, `sc_cfg3 = 0`, `sc_maxxfer = 64*1024`,
`sc_minsync = 1000/16 = 62`.

Derived register programming a Verilog core will see at reset (from
`ncr53c9x_attach` + `ncr53c9x_reset`): `sc_freq` is integer-truncated to
16 MHz, so `CCF = FREQTOCCF(16) = 4`,
`NCR_TIMEOUT = (250*1000*16)/(8192*4) = 122`, `SYNCOFF = 0`, `CFG3 = 0`,
`CFG2 = 0x08`, `CFG1 = 0x07`.

## 1.2 Address map / access size

- Registers are on a **16-byte stride**: `return esc->sc_reg[reg * 16];`
  (esp.c:425). Second bus (Q900/950) is at `SCSIBase + 0x402`.
- The PDMA (DACK) window is at **register base + 0x100**, accessed as
  `volatile uint16_t *`:
  `pdma = (volatile uint16_t *)(esc->sc_reg + 0x100);` (esp.c:831).
- Bulk transfer is **exclusively 16-bit (`movw`) accesses to one fixed
  address**, unrolled 16 per iteration:

```
	cnt32 = len / 32;
	cnt2 = (len % 32) / 2;
	...
	"1:	movw %%a2@+,%%a3@; movw %%a2@+,%%a3@	\n"   (x16)
	"	movw #8704,%%sr	\n"      /* SR=0x2200 -> IPL2, let serial in */
	"	movw #9728,%%sr	\n"      /* SR=0x2600 -> IPL6 again */
	"	dbra %%d2, 1b	\n"
```

and the tail loop does the remaining whole words one `movw` at a time.
`len &= ~1;` before the loops, so the bulk path never does an odd-sized access.

The comment on the aliasing/replication (esp.c:696-707) is the load-bearing
hardware description:

```
 * Basically, the CPU acts like the DMA controller.  The DREQ/ off the
 * chip goes to a register that we've mapped at attach time (on the
 * IOSB or DAFB, depending on the machine).  Apple also provides some
 * space for which the memory controller handshakes data to/from the
 * NCR chip with the DACK/ line.  This space appears to be mapped over
 * and over, every 4 bytes, but only the lower 16 bits are valid (but
 * reading the upper 16 bits will handshake DACK/ just fine, so if you
 * read *uint16_t++ = *uint16_t++ in a loop, you'll get
 * <databyte><databyte>0xff0xff<databyte><databyte>0xff0xff...
```

Read that as: the window repeats every 4 bytes; offsets 0-1 (mod 4) return the
two data bytes, offsets 2-3 return 0xFF but **still perform a DACK handshake**
(i.e. still consume/produce chip data). The driver only ever touches offset 0 of
the replica, so a core that decodes `A[1]` and only handshakes on the low half
would still work with NetBSD, but the documented behavior is "any access in the
window handshakes".

## 1.3 Byte order — which byte hits the SCSI bus first

m68k is big-endian and the source/destination pointer walks memory ascending
while the PDMA address is fixed. For `movw %a2@+,%a3@`, the byte at the lower
buffer address lands in **D15-D8**. Combined with the
"`<databyte><databyte>0xff0xff`" observation (the first data byte appears at
window offset 0, the second at offset 1), the expectation is:

- **the high byte of the 16-bit word (D15-D8) is the earlier SCSI byte; D7-D0
  is the later one**, for both directions.
- The odd trailing byte uses an 8-bit access **at the same even (4-byte
  aligned) window address**, i.e. the same upper lane:
  `*(volatile int8_t *)pdma = *c;` (write) /
  `*c = *(volatile uint8_t *)pdma;` (read), esp.c:882, 925.

## 1.4 Odd counts

`esp_quick_dma_setup` (esp.c:656-660):

```
	if (*len & 1) {
		esc->sc_pad = 1;
	} else {
		esc->sc_pad = 0;
	}
```

The bulk loops transfer `len & ~1` bytes; the leftover byte is transferred
separately, and **only after explicitly polling DREQ**, because a not-ready
single-byte access would bus-error:

```
		if (esc->sc_pad) {
			volatile uint8_t *c;
			c = (volatile uint8_t *) addr;
			/* Wait for DREQ */
			while (!esp_have_dreq(esc)) {
				if (*statreg & 0x80) {
					nofault = NULL;
					goto gotintr;
				}
			}
			*(volatile int8_t *)pdma = *c;
		}
```

Note the escape hatch: if the interrupt (STAT bit 7) appears while waiting for
DREQ, the pad byte is abandoned and the interrupt is processed.

## 1.5 The bus-error flow control mechanism

Driver-side description (esp.c:709-728):

```
 * When you're attempting to read or write memory to this DACK/ed space,
 * and the NCR is not ready for some timeout period, the system will
 * generate a bus error.  This might be for one of several reasons:
 *
 *	1) (on write) The FIFO is full and is not draining.
 *	2) (on read) The FIFO is empty and is not filling.
 *	3) An interrupt condition has occurred.
 *	4) Anything else?
 *
 * So if a bus error occurs, we first turn off the nofault bus error handler,
 * then we check for an interrupt (which would render the first two
 * possibilities moot).  If there's no interrupt, check for a DREQ/.  If we
 * have that, then attempt to resume stuffing (or unstuffing) the FIFO.  If
 * neither condition holds, pause briefly and check again.
 *
 * NOTE!!!  In order to make allowances for the hardware structure of
 *          the mac, spl values in here are hardcoded!!!!!!!!!
```

Mechanics: `nofault = &faultbuf; if (setjmp(nofault)) { ... }`, and the kernel's
bus-error stub longjmps back. The mac68k-specific hook that makes resumption
possible is in `trap_subr.s:102-122`:

```
ASGLOBAL(buserr_common)
	tstl	_C_LABEL(nofault)	| catch bus error?
	jeq	1f			| no, handle as usual
#ifdef mac68k
	/*
	 * TL;DR - mac68k SCSI DMA needs to peek under the covers
	 * here, and needs the value of %a2 when the fault occurred
	 * as well as the faulting address.
	 ...
	movl	%sp@(FR_A2+8),_C_LABEL(mac68k_a2_fromfault)
	movl	%sp@(4),_C_LABEL(m68k_fault_addr)
#endif
	movl	_C_LABEL(nofault),%sp@-	| yes,
	jbsr	_C_LABEL(longjmp)	|  longjmp(nofault)
```

(`mac68k_a2_fromfault` is declared in `mac68k/mac68k/locore.s:457`. This is why
the loops are hand-written asm: *"we need the address that we are reading from
or writing to to be in a2"*, esp.c:835-838.)

Recovery loop (esp.c:772-825), verbatim on the important parts:

```
		for (;;) {
			spl2();		/* Give serial a chance... */
			splhigh();	/* That's enough... */

			if (*statreg & 0x80) {
				goto gotintr;
			}

			if (esp_have_dreq(esc)) {
				/*
				 * Get the remaining length from the address
				 * differential.
				 */
				addr = (uint16_t *)mac68k_a2_fromfault;
				len = esc->sc_dmasize -
				    ((long)addr - (long)*esc->sc_dmaaddr);

				if (esc->sc_datain == 0) {
					/*
					 * Let the FIFO drain before we read
					 * the transfer count.
					 ...
					while (NCR_READ_REG(sc, NCR_FFLAG) & 0x1f);
					res = NCR_READ_REG(sc, NCR_TCL);
					res += NCR_READ_REG(sc, NCR_TCM) << 8;
					/* If they don't agree, adjust accordingly. */
					while (res > len) {
						len+=2; addr--;
					}
					if (res != len) {
						panic("%s: res %d != len %d", ...);
					}
				}
				break;
			}
			DELAY(1);
			if (i++ > 1000000)
				panic("%s: Bus error, but no condition!  Argh!", ...);
		}
		goto restart_dmago;
```

Expectations this places on a Verilog core + glue:
- Bus error must be raised on a PDMA-window access when the chip is not ready,
  after a bounded timeout, and it must be **restartable**: after the fault,
  `TCL/TCM` plus the FIFO count must exactly account for what the chip
  accepted, and the discrepancy versus the CPU's `%a2` must be an **even number
  of bytes** (the rewind loop steps `len += 2; addr--`), or the kernel panics.
- Priority order the driver assumes when a fault happens: interrupt pending
  (STAT bit 7) > DREQ asserted > neither (transient; retry).
- Interrupt condition must also cause the PDMA window to stop being ready
  (case 3 above), i.e. an in-flight PDMA burst is terminated by bus error when
  the chip raises INT.
- Reading `NCR_STAT` must be completely side-effect-free: it is polled in tight
  loops here, in `esp_dma_isintr`, `esp_intr`, and `esp_dualbus_intr`.
- `esp_quick_dma_go` runs at splhigh with a brief drop to IPL2 every 32 bytes;
  there is no interrupt servicing during a burst.
- On completion, if no interrupt has arrived yet, it just returns: *"If we have
  not received an interrupt yet, we should shortly, and we can't prevent it, so
  return and wait for it."* If the interrupt is already up it calls
  `ncr53c9x_intr(sc)` inline (with the MI mutex dropped/retaken, mirroring
  `ncr53c9x_poll`).

## 1.6 DREQ visibility, AV vs non-AV, IOSB

```
static int
esp_dafb_have_dreq(struct esp_softc *esc)
{
	return *esc->sc_dreqreg & 0x200;
}

static int
esp_iosb_have_dreq(struct esp_softc *esc)
{
	return via2_reg(vIFR) & V2IF_SCSIDRQ;
}
```

`V2IF_SCSIDRQ = (1 << 0)`, `V2IF_SCSIIRQ = (1 << 3)` (`viareg.h:120-133`). So
on Wombat/Q800 the DREQ line is a **live level in bit 0 of the emulated VIA2
IFR** (read repeatedly, never cleared/acknowledged by the driver), and the SCSI
IRQ is VIA2 IFR bit 3. Attach does `via2_reg(vPCR) = 0x22;
via2_reg(vIFR) = irq_mask; via2_reg(vIER) = 0x80 | irq_mask;` — only the IRQ
bit is enabled in IER; DRQ is polled, not interrupt-driven.

On DAFB Quadras the same 32-bit location is both the DREQ status (bit 9) and a
12-bit PDMA timing config written with `*esc->sc_dreqreg = 0x1d1;`.

AV (840AV, `SCSIBase = base + 0x18000`, machdep.c:2009): completely different —
real DMA through the PSC, `sc_rev = NCR_VARIANT_NCR53C94`,
`sc_cfg3 = NCRCFG3_CDB`, 20 MHz, and bounce buffers because *"PSC seems to
require that DMA buffer is (1) aligned to 16-byte boundares, and (2) multiple of
16 bytes in size"*, plus *"(A) NCR53C94/PSC do not seem to allow partial PIO.
(port-mac68k/56131) (B) Synchronous transfer fails with PIO."* Also note AV
deliberately does **not** enable DMA-select: `#if 0 ... /* This degrades
performance; FIFO is better than bounce DMA for short SCSI commands and their
responses. */ sc->sc_features |= NCR_F_DMASELECT;`.

Third path (no quick, no avdma — non-Quadra 53C9x): pure FIFO PIO,
`sc_minsync = 0` ("No synchronous xfers w/o DMA") and `sc_maxxfer = 8*1024`.

---

# 2. Select sequences

## 2.1 Which commands the driver issues

From `ncr53c9x_select` (ncr53c9x.c:669-818). On mac68k `NCR_F_DMASELECT` is
never set, so **all four select variants are FIFO-preloaded**, never the DMA
form:

| Case | Command | Preloaded into FIFO |
|---|---|---|
| REQUEST SENSE (`ECB_SENSE`) | `NCRCMD_SELNATN` (0x41) | CDB only, no IDENTIFY ("we should not send an IDENTIFY... There should be no MESSAGE IN phase") |
| normal | `NCRCMD_SELATN` (0x42) | IDENTIFY + CDB |
| sync/wide negotiation pending, or tags without SELATN3 | `NCRCMD_SELATNS` (0x43) | IDENTIFY + CDB; comment: `/* Arbitrate, select and stop after IDENTIFY message */` |
| tagged and `NCR_F_SELATN3` | `NCRCMD_SELATN3` (0x46) | IDENTIFY + 2 tag bytes + CDB, and `sc->sc_msgout = SEND_TAG; sc->sc_flags |= NCR_ATN;` |

`NCR_F_SELATN3` is set for ESP100A and everything above it, including 53C96
(fallthrough chain in `ncr53c9x_reset`), so a Quadra core must implement
SELATN3/RESEL3 *for NetBSD* (the Mac ROM never uses it).

Implication for FIFO depth: worst case preload is 3 message bytes + a 12-byte
CDB = 15 bytes, i.e. the 16-byte FIFO must hold the whole thing before the
select command is written.

Ordering before the select command: `NCR_WRITE_REG(sc, NCR_SELID, target)` then
`ncr53c9x_setsync()` (writes CFG3, SYNCOFF, SYNCTP) then `wrfifo()` then the
select command. The DMA variants (unused here) instead do `NCR_SET_COUNT();
NCRCMD(NCRCMD_NOP|NCRCMD_DMA); NCRCMD(SELxxx|NCRCMD_DMA); NCRDMA_GO();`.

## 2.2 How the interrupt is interpreted

`ncr53c9x_readregs` order matters and is a hard chip expectation
(ncr53c9x.c:566-601):

```
 * Read the NCR registers, and save their contents for later use.
 * NCR_STAT, NCR_STEP & NCR_INTR are mostly zeroed out when reading
 * NCR_INTR - so make sure it is the last read.
```

Read order: STAT, STEP (`& NCRSTEP_MASK` = 0x07), [STAT2 on FAS366], INTR last.
Phase is then
`(intr & NCRINTR_DIS) ? BUSFREE_PHASE : (stat & NCRSTAT_PHASE)`.

In state `NCR_IDLE`/`NCR_SELECTING`:

- `NCRINTR_RESEL` set → we were reselected instead; back off our own select,
  push the ECB back on the ready list, expect MESSAGE_IN and exactly 2 bytes in
  the FIFO.
- `#define NCRINTR_DONE (NCRINTR_FC | NCRINTR_BS)` and
  `if ((sc->sc_espintr & NCRINTR_DONE) == NCRINTR_DONE)` → *"Arbitration won;
  examine the `step' register to determine how far the selection could
  progress."* **Both FC and BS must be set** at select completion.
- Anything else → `"unexpected status after select: [intr %x, stat %x,
  step %x]"`, `NCRCMD_FLUSH`, `DELAY(1)`, full chip reinit.
- Selection timeout arrives as `NCRINTR_DIS` (handled earlier in the DIS block)
  → `XS_SELTIMEOUT`.

## 2.3 The step values 0..4 (verbatim driver semantics)

```
		case 0:
			/*
			 * The target did not respond with a
			 * message out phase - probably an old
			 * device that doesn't recognize ATN.
			 * Clear ATN and just continue, the
			 * target should be in the command
			 * phase.
			 * XXXX check for command phase?
			 */
			NCRCMD(sc, NCRCMD_RSTATN);
			break;
		case 1:
			if ((ti->flags & T_NEGOTIATE) == 0 && ecb->tag[0] == 0) {
				printf("%s: step 1 & !NEG\n", ...);  goto reset;
			}
			if (sc->sc_phase != MESSAGE_OUT_PHASE) {
				printf("%s: !MSGOUT\n", ...);  goto reset;
			}
			... schedule SEND_WDTR / SEND_SDTR / SEND_TAG ...
			sc->sc_prevphase = MESSAGE_OUT_PHASE; /* XXXX */
			break;
		case 3:
			/*
			 * Grr, this is supposed to mean
			 * "target left command phase  prematurely".
			 * It seems to happen regularly when
			 * sync mode is on.
			 * Look at FIFO to see if command went out.
			 * (Timing problems?)
			 */
		case 2:
			/* Select stuck at Command Phase */
			NCRCMD(sc, NCRCMD_FLUSH);
			break;
		case 4:
			... /* So far, everything went fine */
```

Reading that back as chip-behavior expectations:
- **step 0**: selection succeeded but the target never entered MSGOUT (ATN
  ignored). Driver clears ATN with `NCRCMD_RSTATN` (0x1b) and continues; the
  target is expected to be in COMMAND phase.
- **step 1**: stopped after sending the (first) message byte — this is the
  normal, expected result of SELATNS, and the driver *requires* the phase
  register to read MESSAGE_OUT here, otherwise it resets the chip. Step 1
  arriving when nothing was scheduled to be negotiated/tagged is treated as a
  fatal protocol error.
- **step 2**: "Select stuck at Command Phase" — chip got into command phase but
  did not transfer the CDB; driver just flushes the FIFO and proceeds to phase
  dispatch (it will re-send the CDB from COMMAND_PHASE handling).
- **step 3**: "target left command phase prematurely" — command bytes were
  *partially* sent.
- **step 4** (`NCRSTEP_DONE`, 0x04): everything went out.

The `NCR_STEP` register is read-only at 0x06 masked to 3 bits; the same
sequence-step value is also duplicated in the FIFO flags register top bits
(`#define NCRFIFO_SS 0xe0 /* Sequence Step (Dup) */`). The driver never uses
the duplicate (always masks with `NCRFIFO_FF` 0x1f), but a faithful core should
implement it.

## 2.4 What happens when the command bytes were not all sent (step 3)

```
			case 3:
				if (sc->sc_features & NCR_F_DMASELECT) {
					if (sc->sc_cmdlen == 0)
						/* Hope for the best.. */
						break;
				} else if ((NCR_READ_REG(sc, NCR_FFLAG)
				    & NCRFIFO_FF) == 0) {
					/* Hope for the best.. */
					break;
				}
				printf("(%s:%d:%d): selection failed;"
				    " %d left in FIFO "
				    "[intr %x, stat %x, step %d]\n", ...);
				NCRCMD(sc, NCRCMD_FLUSH);
				ncr53c9x_sched_msgout(SEND_ABORT);
				goto out;
```

So on the mac68k (non-DMA-select) path the arbiter of "did the CDB actually go
out" is **the FIFO count**: FIFO empty at step 3 → assume the command was
delivered and continue as CONNECTED; FIFO non-empty → flush, assert ATN
(`ncr53c9x_sched_msgout` does `NCRCMD_SETATN` immediately) and send ABORT. This
means a core must leave un-sent command bytes visible in the FIFO count when it
aborts a select sequence mid-CDB, and must have drained the FIFO when the CDB
did go out.

Step 4 with DMA-select and non-zero residual `sc_cmdlen` only produces a
warning ("select; %lu left in DMA buffer") and continues.

After any of 0..4 that doesn't bail: `sc->sc_prevphase = INVALID_PHASE;
sc->sc_dp = ecb->daddr; sc->sc_dleft = ecb->dleft;
sc->sc_state = NCR_CONNECTED;` and then dispatch on `sc->sc_phase` read from
STAT — so the phase bits in STAT must be valid and current at the
select-complete interrupt.

## 2.5 Reselection

```
			 * The SCSI chip made a snapshot of the data bus
			 * while the reselection was being negotiated.
			 * This enables us to determine which target did
			 * the reselect.
			 */
			selid = sc->sc_selid & ~(1 << sc->sc_id);
			if (selid & (selid - 1)) { ... "reselect with invalid selid" ... }
			target = ffs(selid) - 1;
```

Two FIFO bytes are mandatory after a reselect
(`if (nfifo != 2) { "RESELECT: %d bytes in FIFO!" ; ncr53c9x_init(sc, 1); }`):
byte 0 = the data-bus snapshot containing both IDs, byte 1 = the IDENTIFY
message. Phase must be MESSAGE_IN or the driver resets ("target didn't
identify").

---

# 3. FIFO handling quirks

## 3.1 When the FIFO gets flushed

```
static void
ncr53c9x_flushfifo(struct ncr53c9x_softc *sc)
{
	NCRCMD(sc, NCRCMD_FLUSH);

	if (sc->sc_phase == COMMAND_PHASE ||
	    sc->sc_phase == MESSAGE_OUT_PHASE)
		DELAY(2);
}
```

Explicit `NCRCMD_FLUSH` sites, all of which are behavioral expectations (flush
must be instantaneous-ish and must zero the FIFO count):

- On SCSI bus reset interrupt, gross error, and illegal command — but **only if
  `FFLAG & NCRFIFO_FF` is non-zero**, then `DELAY(1)`.
- On disconnect (`NCRINTR_DIS`), if FIFO non-empty; immediately followed by
  `NCRCMD_ENSEL` with the comment *"This command must (apparently) be issued
  within 250mS of a disconnect."*
- Unconditionally before every DATA_OUT setup
  (`case DATA_OUT_PHASE: NCRCMD(sc, NCRCMD_FLUSH);`).
- Before DATA_IN **only on ESP100**
  (`if (sc->sc_rev == NCR_VARIANT_ESP100) NCRCMD(sc, NCRCMD_FLUSH);`) — a
  53C96 core is expected *not* to need this.
- On entry to COMMAND_PHASE if FIFO non-empty.
- At the start of a new MESSAGE_OUT message.
- In MESSAGE_IN on a BS interrupt, before the byte-fetch `TRANS`.
- After a tagged-queuing MESSAGE REJECT (`NCRCMD(sc, NCRCMD_FLUSH); DELAY(1);`).
- Select steps 2 and 3, and "unexpected status after select".

## 3.2 Residue from FIFO count + TC at phase change

`esp_quick_dma_intr` (esp.c:586-645) is the canonical mac68k residue
calculation:

```
	if ((sc->sc_espstat & NCRSTAT_TC) == 0) {
		if (esc->sc_datain == 0) {
			resid = NCR_READ_REG(sc, NCR_FFLAG) & 0x1f;
			... "Write FIFO residual %d bytes" ...
		}
		resid += NCR_READ_REG(sc, NCR_TCL);
		resid += NCR_READ_REG(sc, NCR_TCM) << 8;
		if (resid == 0)
			resid = 65536;
	}

	trans = esc->sc_dmasize - resid;
	if (trans < 0) {
		printf("dmaintr: trans < 0????\n");
		trans = *esc->sc_dmalen;
	}
```

Key expectations:
- If `NCRSTAT_TC` is set, residue is zero, full stop — no register reads at
  all.
- For **data-out**, bytes still sitting in the chip FIFO count as *not
  transferred* and are added to TC. This means TC is decremented when a byte is
  loaded into the FIFO (not when it reaches the bus), and the FIFO count must
  be readable and accurate after the phase change / interrupt.
- For **data-in**, the FIFO count is deliberately *not* added: the PDMA engine
  is expected to have drained everything the chip counted.
- `resid == 0` with TC clear is interpreted as 65536, i.e. a wrapped/never-
  loaded counter.
- The zero-size (`TRPAD`) case is special-cased before any of this:
  `sc->sc_espstat |= NCRSTAT_TC;` with the note *"This can happen in the case
  of a TRPAD operation / Pretend that it was complete"*, and the debug print
  computes `65536 - res`.

The MI side then sanity-checks TC (ncr53c9x.c:2212-2258): with `NCRSTAT_TC`
clear it accepts exactly three explanations — selecting (reselected mid-DMA-
select), a multi-byte MSGOUT interrupted by the target switching to MSGIN (a
REJECT), and otherwise complains `"!TC on DATA XFER"` / `"!TC on MSG OUT"`.

## 3.3 Message-in, byte at a time

```
	case MESSAGE_IN_PHASE:
msgin:
		if ((sc->sc_espintr & NCRINTR_BS) != 0) {
			if ((sc->sc_rev != NCR_VARIANT_FAS366) || ...) {
				NCRCMD(sc, NCRCMD_FLUSH);
			}
			sc->sc_flags |= NCR_WAITI;
			NCRCMD(sc, NCRCMD_TRANS);
		} else if ((sc->sc_espintr & NCRINTR_FC) != 0) {
			if ((sc->sc_flags & NCR_WAITI) == 0) {
				printf("%s: MSGIN: unexpected FC bit: ...");
			}
			sc->sc_flags &= ~NCR_WAITI;
			ncr53c9x_rdfifo(sc,
			    (sc->sc_prevphase == sc->sc_phase) ?
			    NCR_RDFIFO_CONTINUE : NCR_RDFIFO_START);
			ncr53c9x_msgin(sc);
		} else {
			printf("%s: MSGIN: weird bits: ...");
		}
		sc->sc_prevphase = MESSAGE_IN_PHASE;
		goto shortcut;	/* i.e. expect data to be ready */
```

So the exact handshake a core must produce:
1. Phase change into MESSAGE IN → **BS** interrupt (no FC).
2. Driver: FLUSH, then `NCRCMD_TRANS` (0x10, **no DMA bit**, no transfer count
   programmed) → a non-DMA Transfer Information must move **exactly one byte**
   and complete with **FC** (not BS).
3. Driver drains that one byte with `ncr53c9x_rdfifo` (which reads
   `FFLAG & 0x1f` bytes — so the count must read 1), appends to `sc_imess`, and
   then `ncr53c9x_msgin` decides.
4. Every path out of `ncr53c9x_msgin` ends in `NCRCMD(sc, NCRCMD_MSGOK)` (0x12,
   Message Accepted) — including the "incomplete message so far" path (`/* Ack
   what we have so far */`) and the drop path. If more messages are queued
   outbound, `NCRCMD_SETATN` is issued *before* MSGOK:

```
	/* if we have more messages to send set ATN */
	if (sc->sc_msgpriq)
		NCRCMD(sc, NCRCMD_SETATN);

	/* Ack last message byte */
	NCRCMD(sc, NCRCMD_MSGOK);
```

5. MSGOK releases ACK; the next byte (or phase change) produces the next BS
   interrupt, and `NCR_RDFIFO_CONTINUE` accumulates because
   `prevphase == phase`.

Multi-byte messages are validated by `__verify_msg_format` (1-byte, 2-byte,
extended with `len == p[1] + 2`), and `NCR_MAX_MSG_LEN` is 8; overrun → REJECT
+ `NCR_DROP_MSGI`.

The status-phase variant uses ICCS instead: `sc->sc_flags |= NCR_ICCS;
NCRCMD(sc, NCRCMD_ICCS);`, and on the resulting interrupt (expected `FC|BS`,
else it prints "ICCS:") it does `ncr53c9x_rdfifo(NCR_RDFIFO_START)` and takes
the **last two** bytes:

```
			ecb->stat = sc->sc_imess[sc->sc_imlen - 2];
			msg = sc->sc_imess[sc->sc_imlen - 1];
```

so ICCS must leave status byte then message byte in the FIFO
(`if (sc->sc_imlen < 2) printf("can't get status, only %d bytes")`), followed
by `NCRCMD_MSGOK`.

## 3.4 What reading the interrupt register is assumed to clear

- `NCR_INTR` (0x05, RO) read **clears the interrupt** and effectively
  snapshots/clears STAT and STEP: *"NCR_STAT, NCR_STEP & NCR_INTR are mostly
  zeroed out when reading NCR_INTR - so make sure it is the last read."*
  Corollary: STAT and STEP must hold their latched values until INTR is read.
- `NCR_STAT` (0x04, RO) read is **side-effect free**, including bit 7
  (`NCRSTAT_INT`): it is polled in `esp_dma_isintr`, `esp_intr`,
  `esp_dualbus_intr`, in the PDMA inner loop `while (!(*statreg & 0x80));`, in
  the pad-byte DREQ wait, and in `ncr53c9x_intr`'s `NCRDMA_ISINTR` gate at the
  top (which returns early without touching INTR).
- The MI code re-enters via `goto again;` in the `shortcut:` path, i.e. it will
  re-read STAT/STEP/INTR immediately after a previous read while the same
  command sequence is running; the chip must present a fresh, coherent set each
  time.
- There is an optional `gl_clear_latched_intr` hook for platforms whose glue
  latches the IRQ; mac68k sets it to `NULL`
  (`.gl_clear_latched_intr = NULL`), i.e. the IRQ level to VIA2 is expected to
  drop when INTR is read.
- The PIO (non-quick) glue reads STAT and INTR directly from the register block
  in its inner loop and reconstructs phase itself:
  `espphase = (espintr & NCRINTR_DIS) ? BUSFREE_PHASE : espstat & PHASE_MASK;`.

---

# 4. Known chip bugs / quirks, and which apply to NCR_VARIANT_NCR53C96

The MI driver's variant-conditional code is short, and this is itself the
useful finding: **there is no 53C96-specific erratum workaround anywhere in
NetBSD's MI driver.** The 53C96 is treated as a clean ESP200-class part.
Enumerated:

**ESP100 (and 53C90+86C01, which is aliased to ESP100 at attach:
`if (sc->sc_rev == NCR_VARIANT_NCR53C90_86C01) sc->sc_rev =
NCR_VARIANT_ESP100;`)**

```
			 * The C90 only inhibits FIFO writes until reselection
			 * is complete, instead of waiting until the interrupt
			 * status register has been read.  So, if the reselect
			 * happens while we were entering command bytes (for
			 * another target) some of those bytes can appear in
			 * the FIFO here, after the interrupt is taken.
			 *
			 * To remedy this situation, pull the Selection ID
			 * and Identify message from the FIFO directly, and
			 * ignore any extraneous fifo contents. Also, set
			 * a flag that allows one Illegal Command Interrupt
			 * to occur which the chip also generates as a result
			 * of writing to the FIFO during a reselect.
```

Inverted, this is a **positive statement about the 53C96**: a post-ESP100 chip
must inhibit FIFO writes from reselection until the **interrupt status register
has been read**, and must not produce the spurious Illegal Command interrupt.
The matching workaround flag `NCR_EXPECT_ILLCMD` / `"ESP100 work-around
activated"` is only armed under `if (sc->sc_rev == NCR_VARIANT_ESP100)`.

- ESP100 also needs a FIFO flush before DATA_IN
  (`if (sc->sc_rev == NCR_VARIANT_ESP100) NCRCMD(sc, NCRCMD_FLUSH);`) — 53C96
  does not.
- ESP100 has no CFG2/CFG3 (reset fallthrough), and per the register header
  `NCR_TCH 0x0e /* NOT on 53C90 */`, `/* Config #3 only on 53C9X */`.

**Applies to 53C96 (variant 4):** in `ncr53c9x_reset` it falls into the
`NCR53C94/NCR53C96/ESP200` arm, so it gets `NCR_F_HASCFG3` (CFG3 written), then
falls through to the ESP100A arm giving `NCR_F_SELATN3` (CFG2 written), then
ESP100 (CFG1, CCF, SYNCOFF=0, TIMEOUT). It does **not** get `NCR_F_FASTSCSI`
from the MI reset (only FAS366 does), and `sc_cfg3_fscsi` stays 0 — so no Fast
SCSI, and the `ti->period <= 50` fast-mode branch never fires on a Quadra.

**ATN behavior quirk (all variants, matters a lot for a Verilog sequencer):**

```
	 * XXX - the NCR_ATN flag is not in sync with the actual ATN
	 *	 condition on the SCSI bus. The 53c9x chip
	 *	 automatically turns off ATN before sending the
	 *	 message byte.
```

and

```
			 * We normally do not get here, since the chip
			 * automatically turns off ATN before the last
			 * byte of a message is sent to the target.
			 * However, if the target rejects our (multi-byte)
			 * message early by switching to MSG IN phase
			 * ATN remains on, so the target may return to
			 * MSG OUT phase. If there are no scheduled messages
			 * left we send a NO-OP.
```

So: the chip auto-deasserts ATN before the *last* byte of a message-out
transfer, and leaves ATN asserted if the transfer was cut short by a phase
change.

**Timing/parameter quirks in the register header:**
- `NCR_CCF 0x09 /* 0 = 35.01 - 40MHz / NEVER SET TO 1 / 2 = 10MHz ... */`, and
  the driver enforces it: `/* The value *must not* be == 1. Make it 2 */`, then
  `sc->sc_ccf &= 7;` with `/* CCF register only has 3 bits; 0 is actually 8 */`.
- `NCR_SYNCTP 0x06 /* WO - Synch Transfer Period. Default 5 (53C9X) */`, and
  mac68k: *"the NCR register 'SYNCTP' is programmed in 'clocks per byte', and
  has a minimum value of 4."*
- Select/reselect timeout formula:
  `(timeout period) x (CLK frequency) / (8192 x CCF)`, *"generally computes to
  the constant of 153"* (122 on the 16.5 MHz Quadra).
- `NCRCMD_RSTCHIP` is followed by `NCRCMD_NOP` and `DELAY(500)` before any
  config register is written.
- Gross Error (`NCRSTAT_GE`) is treated as fatal-for-the-command: flush FIFO,
  `XS_TIMEOUT`, `/* Gross Error; no target ? */`.

**mac68k-glue quirks (not chip errata, but they shape what the core sees):**
- PIO (non-quick, non-AV) glue rewrites commands: `if (reg == NCR_CMD && v ==
  (NCRCMD_TRANS|NCRCMD_DMA)) { v = NCRCMD_TRANS; }` — strips the DMA bit. The
  quick/AV paths install `esp_dma_write_reg`, which passes everything through
  unmodified, so a Quadra core *does* see `TRANS|DMA` (0x90), `NOP|DMA` (0x80)
  and `TRPAD|DMA` (0x98).
- `case MACH_MACQ630: /* XXX on LC630 64k xfer causes timeout error */
  sc->sc_maxxfer = 63 * 1024;`
- AV: PSC 16-byte alignment/size constraints and *"We must start a DMA before
  the device is ready to transfer data or the DMA engine gets confused and
  thinks it has to do a write when it should really do a read."*

---

# 5. Transfer counter

## 5.1 Loading it — the "NOP with DMA bit latches the count" idiom

```
#define NCR_SET_COUNT(sc, size) do { \
		NCR_WRITE_REG((sc), NCR_TCL, (size));			\
		NCR_WRITE_REG((sc), NCR_TCM, (size) >> 8);		\
		if ((sc->sc_cfg2 & NCRCFG2_FE) ||			\
		    (sc->sc_rev == NCR_VARIANT_FAS366)) {		\
			NCR_WRITE_REG((sc), NCR_TCH, (size) >> 16);	\
		}							\
		if (sc->sc_rev == NCR_VARIANT_FAS366) {			\
			NCR_WRITE_REG(sc, NCR_RCH, 0);			\
		}							\
} while (0)
```

and every user follows it with an explicitly commented latch step:

```
		/* Program the SCSI counter */
		NCR_SET_COUNT(sc, size);

		/* load the count in */
		NCRCMD(sc, NCRCMD_NOP | NCRCMD_DMA);

		NCRCMD(sc, (size == 0 ? NCRCMD_TRPAD : NCRCMD_TRANS) | NCRCMD_DMA);
		NCRDMA_GO(sc);
```

(identical pattern in `ncr53c9x_msgout`, in COMMAND_PHASE with DMA-select, in
the data-phase `setup_xfer:` label, and in `ncr53c9x_select`'s DMA variants).
The behavioral expectation: **writes to TCL/TCM/TCH go into a holding latch;
issuing any command with the DMA bit set (0x80) transfers the latch into the
active counter and clears STAT.TC.** The driver relies on the `NOP|DMA` doing
that separately from the transfer command — a core that only latched on
`TRANS|DMA` would still work here, but one that latched on nothing would break.

## 5.2 Zero == 65536

Stated three times:

```
		 * Note that if `size' is 0, we've already transceived
		 * all the bytes we want but we're still in DATA PHASE.
		 * Apparently, the device needs padding. Also, a
		 * transfer size of 0 means "maximum" to the chip
		 * DMA logic.
```

```
		if (resid == 0)
			resid = 65536;
```

```
			printf("dmaintr: DMA xfer of zero xferred %d\n", 65536 - res);
```

And the zero-size case is exactly what triggers `NCRCMD_TRPAD | NCRCMD_DMA`
(transfer pad), which both mac68k backends special-case (`esp_quick_dma_intr`
fakes `NCRSTAT_TC`; `esp_av_dma_setup`/`_go` skip DMA entirely with `/* No DMA
transfer in Transfer Pad operation */`).

## 5.3 Reading it back mid-transfer

Three places read the counter, and **all three read only TCL and TCM**:

- `esp_quick_dma_intr`: at interrupt time, `resid += NCR_READ_REG(sc, NCR_TCL);
  resid += NCR_READ_REG(sc, NCR_TCM) << 8;`
- `esp_quick_dma_go`'s bus-error recovery: **truly mid-transfer, chip still
  active** — it first spins `while (NCR_READ_REG(sc, NCR_FFLAG) & 0x1f);`
  (`/* Let the FIFO drain before we read the transfer count. Do we need to do
  this? Can we do this? */`) and then reads TCL/TCM and requires them to agree
  with the CPU pointer to within an even byte count, panicking otherwise.
- `esp_av_dma_intr` debug: `tc_size = NCR_READ_REG(sc, NCR_TCM);
  tc_size <<= 8; tc_size |= NCR_READ_REG(sc, NCR_TCL);`

So: the counter must be readable at any time (not only when idle), must read as
*bytes remaining*, and reads of TCL and TCM in either order must be consistent
(there is no latch-on-read-low protocol in this driver).

## 5.4 The third byte (TCH) on the 53C96 — is it used?

`NCR_TCH 0x0e /* RW - Transfer Count High, NOT on 53C90 */` exists, and
`NCR_SET_COUNT` will write it, but **only when `sc_cfg2 & NCRCFG2_FE` (Features
Enable, 0x40) is set, or on FAS366.**

The mac68k front-end sets `sc->sc_cfg2 = NCRCFG2_SCSI2;` (0x08) and never sets
`NCRCFG2_FE`. Therefore:

- **On the Quadra the counter is effectively 16-bit; TCH is never written and
  never read.**
- The driver caps transfers accordingly: `/* We need this to fit into the
  TCR... */ sc->sc_maxxfer = 64 * 1024;` and every data phase does
  `size = uimin(sc->sc_dleft, sc->sc_maxxfer);`.
- Residue arithmetic is 16-bit-only with the 65536 wrap rule; a core that
  decremented a 24-bit counter with a nonzero TCH would still be consistent
  with this driver, but nothing exercises TCH.

For a 53C96 core targeting this driver, the practical requirements are: TCH
must exist as a readable/writable register at 0x0e (harmless), CFG2 bit 6 (FE)
must be writable and readable (`ncr53c9x_reset` writes CFG2 and the driver
later tests its own shadow copy, not the chip), and the 16-bit counter path
must be exact — including that `TC` status asserts precisely at zero and that
TCL/TCM read back the true remaining count when TC is clear.
