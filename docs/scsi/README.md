# docs/scsi — 53C96 bring-up research corpus

Research pass run 2026-08-28, ahead of Problem 4 in `RESUME-machine-bringup.md`
(the acceptance-gate disk boot). Five sources were mined in parallel; each doc
preserves the full findings with file:line / address citations so nothing has
to be re-derived.

**Start here → [`rtl-gap-analysis.md`](rtl-gap-analysis.md)** — the synthesis:
prioritized P0/P1/P2 fix list for `rtl/ncr53c96.sv` + `rtl/iosb.sv`, the
compressed "what the ROM demands" contract, and expected hang signatures.

| Doc | Source | One-line takeaway |
|---|---|---|
| [`rom-driver-scsi-access-patterns.md`](rom-driver-scsi-access-patterns.md) | our ROM + Apple_Driver43 disassemblies | **The customer spec.** The disk driver never touches hardware (all via `_SCSIDispatch`); the ROM does everything: `$C1`/`$C2` DMA selects with TC=1 + empty FIFO, split FIFO/PDMA CDB delivery, `$90` with TC=16 per 16-byte burst gated on TC0+DREQ+FIFO=16, 32-bit bulk port at `base+$40100`, `$11`/`$12` for status, bus-error retry handler at `$408D2606`. Seq-step is never read. |
| [`qemu-esp-behavior.md`](qemu-esp-behavior.md) | `~/repos/qemu` hw/scsi/esp.c @ v11.1 | The behavior oracle: non-DMA TI = 1 byte (in), select interrupts deferred to BS\|FC at data-ready, INTR read preserves phase/TC0/RSEQ, DRQ = live function of FIFO occupancy with 2-byte threshold, end-of-DMA INT = TC0 && FIFO<2; plus 4 years of Mac-boot regression fixes and two upstream slips not to copy. |
| [`mame-ncr53c90-quadra-pdma.md`](mame-ncr53c90-quadra-pdma.md) | `~/repos/mame` ncr53c90.cpp + apple/iosb.cpp | **PDMA byte order verified**: first SCSI byte = high byte (D15-8 / D31-24), both directions, residuals included. Full select/RSEQ state table, DMA-select CDB feed via DRQ-paced FIFO pushes, IOSB hold-off re-checked mid-longword, TC decrements on DACK for writes ("68040 Macs require it"). |
| [`netbsd-ncr53c9x-expectations.md`](netbsd-ncr53c9x-expectations.md) | NetBSD trunk ncr53c9x + mac68k esp.c | What a real driver on this exact hardware assumes: restartable bus-error flow control with TC+FIFO accounting, live DREQ in VIA2 IFR bit 0, STAT reads side-effect-free / STAT+STEP latched until INTR read, seq-step 0..4 dispatch, `NOP\|DMA` latches the count, 0=65536, TCH unused on Quadra. No 53C96 errata anywhere. |
| [`repo-scsi-issue-history.md`](repo-scsi-issue-history.md) | this repo | Every SCSI issue to date, both eras: the Era-1 bench campaign (caches, VBR, stack smash, ≤16KB rule — environment, not hardware) and the Era-2 RTL bugs (both register-semantics mismatches found by tracing ROM poll loops), plus latent RTL/IOSB traps and distilled "check first" patterns. |

Related, elsewhere in `docs/`: `quadra800-rom-notes.md` (Sad Mac decoding),
`quadra800-developer-notes.md` §13 (pseudo-DMA / "bus errors are normal"),
`quadra800-ram-test.md` + `tools/make-fastboot-rom.sh` (47 s boot laps for the
fix iteration loop).
