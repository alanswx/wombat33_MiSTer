# Resume prompt — Quartus area reduction (fit the DE10-Nano)

Paste this file as the opening message of a new session.  Repo on `main`
through `6d79e0c` (never pushed).  Environment quirks live in the
`laptop-sim-environment` memory note.  Binding rules for THIS task:

- **Keep the FPU.**  `AP040_HAS_FPU=1` is not negotiable (Dani, explicit).
  It is only 8,396 ALUTs / 11.5% anyway — dropping it would not have fit.
- **Do not change anything in `sys/`.**  Not the files, and prefer not to
  touch its behavior.  All of `sys/` is ~10,730 ALUTs (15%); there was
  never enough there to matter.
- **Do not edit the `rtl/ap68040` submodule.**  Item 2 is fixed at project
  level instead (see below).
- Commit to `main`, never branch.
- The Windows build box tree is mounted **read-only** at
  `/Volumes/Temp/mistercore/wombat33_MiSTer` — READ the Quartus reports
  there, never write.  Its own path on Windows is
  `C:\Temp\mistercore\wombat33_MiSTer`.

## STATUS 2026-08-29 — all four items DONE, awaiting the Quartus compile

All four conversions are implemented, committed, and regression-clean:

| commit | item | sim regression |
|---|---|---|
| `ae3e81c` | 2: `rtl/dpram.v` altsyncram wrapper (ctag_ram/atc_ram) | gate identical to baseline |
| `93184c6` | 1: asc_wavetable 4x `asc_bank` + iosb `A_ASC` wait state | gate identical to baseline |
| `119aa9c` | 3: ncr53c96 `ncr_sbuf` + synth sequencer + registered reads | gate (see below) |
| `1d4cde2` | 4: rtc3430042 pram single port pair, inferred M10K | gate (see below) |
| `fcd213d` | qsf area-first knobs (the old step-1 fallback, applied) | no sim impact |
| `bcb0559` | 3-fix: io transactions complete on io_ack FALLING | gate (see below) |

The first 3+4 gate TRIPPED the Sad Mac watch and it was a real find:
buf_valid was published at io_ack RISING (= command accepted, load still
streaming), which the old asynchronous sbuf read got away with by racing
one word behind the load; the registered read served a stale byte 0 per
sector and the partition scan aborted.  `bcb0559` moves all completion
to the ack FALLING edge with an io_busy hold-off window — this was a
live hardware bug regardless (hps_io streams slower than the fill
drains), so the fit campaign flushed out a real DE10 blocker.

A fresh BASELINE gate ran first and scored exactly the recorded
acceptance (2 REAL cpu diffs, clean elsewhere), then the gate re-ran
after items 1+2 (identical scores, identical DONE instruction count
201834866) and finally after items 3+4 with the ack-fall fix —
**identical scores again** (DONE instr 201842882, +8k poll iterations
riding out the new latencies; every suite scores exactly the
acceptance record).  Diskless boots reach the flashing-? idle at
`$408014CA` after every step.  Gate runs take ~10 min wall on the
laptop; recipe unchanged (below).

**Next: compile on the Windows box** (recipe below, unchanged).  In the
reports, the four arrays now appear as explicit RAMs, so check:

- RAM Summary: `dpram:ctag_ram|altsyncram` (128x94) and
  `dpram:atc_ram|altsyncram` (32x168), four `asc_bank|altsyncram`
  (128x32), `ncr_sbuf|altsyncram` (256x16), and the inferred
  `rtc3430042 pram` (256x8) — all `M10K`.  TDP slices at x20, so
  expect ~24 M10K total (ctag 5, atc 9, asc 8, sbuf 1, pram 1);
  M10K usage ≈ 423/553.
- Entity table: `asc_wavetable`, `ncr53c96`, `rtc3430042` own-logic
  ALUTs collapse from 7,781 / 4,057 / 1,137; `ap040_cache` loses
  ctag_ram's 4,366.  Total registers ≈ 27,300 (was 62,729).
- If the Fitter STILL fails after this, the remaining levers are the
  doc's items 2 and 3 under "If it is still over" (iosb/dafb, then the
  ap040_core sequencer with apolkosnik).

On-hardware/beyond-gate risk notes: REQUEST SENSE after an error and
true CHECK CONDITION paths get little gate coverage (same synth
mechanism as INQUIRY, which is covered); PRAM read-back timing now has
one extra core clock (invisible under the VIA bit-bang clock).

## Where we were (2026-08-29 morning)

`905d1a7` fixed the Analysis & Synthesis hang (VRAM was building 2.5 Mbit
of registers).  A&S now succeeds in ~13 min and `vram0..3` map as
`M10K block / True Dual Port / 78848 x 8`.  **The Fitter then failed on
area:**

```
Error (170012): Fitter requires 6122 LABs ... device contains only 4191
Error (11802): Can't fit design in device.
Logic utilization (in ALMs) : 59,968 / 41,910 ( 143 % )
M10K blocks                 : 399 / 553 ( 72 % )
Total DSP Blocks            : 45 / 112 ( 40 % )
Combinational ALUTs         : 72,954
Dedicated logic registers   : 62,729
```

**Must shed ~18,058 ALMs.**  Block RAM has 154 spare M10K — the fix is to
move logic INTO that spare memory, not to cut features.

ALM packing is poor as a symptom, not a cause: 72,954 ALUTs in 59,968 ALMs
= 1.22 ALUTs/ALM against an ideal 2.0, and the placement breaks down as
LUT+register 17,584 / LUT-only 28,155 / **register-only 12,009** /
memory 0.  Killing the registers below collapses most of that last group.

## Root cause: four arrays that failed to infer as RAM

Each shows **0 block memory bits** in the A&S entity table while carrying a
register count that matches its bit count almost exactly — i.e. the array
*is* the registers, plus the read muxes.

| # | array | ALUTs | Registers | array bits | wants |
|---|---|---|---|---|---|
| 1 | `asc_wavetable` `wave[0:2047]` | 7,781 | 16,621 | 16,384 | 2 M10K |
| 2 | `ap040_cache` `dpram:ctag_ram` | 4,366 | 12,126 | 12,032 | 2 M10K |
| 3 | `ncr53c96` `sbuf[0:255]x16` | 4,057 | 4,562 | 4,096 | 1 M10K |
| 4 | `rtc3430042` `pram[0:255]` | 1,137 | 2,142 | 2,048 | 1 M10K |
| | **total** | **17,341** | **35,451** | | **~6 M10K** |

17,341 ALUTs is essentially the whole overflow, bought for 6 of 154 spare
M10K blocks.  Items 1+2 alone are 12,147 ALUTs / 28,747 registers and
should get under the line on their own.

Everything below is per the reports at
`/Volumes/Temp/mistercore/wombat33_MiSTer/output_files/` from the
2026-08-29 08:22 run (`wombat33.map.rpt` section 7 "Analysis & Synthesis
Resource Utilization by Entity", section 8 "RAM Summary", and
`wombat33.fit.rpt` section 9).

---

## Item 1 — `asc_wavetable` `wave[0:2047]`  (7,781 ALUTs, 16,621 regs)

`rtl/asc_wavetable.sv:38`.  Biggest single item in the design, spent on a
boot chime.

**Why it failed:** `wave` is read **asynchronously at 8 points** — the four
voice taps `s0`-`s3` (lines 66-69, all four live every cycle) plus
`rd_byte()` called four times to build the combinational `rdata` (line 60,
one call per byte lane).  M10K has two ports and requires registered reads.

**Fix shape:** the four voice reads are bank-disjoint by construction —
voice *i* only ever reads `wave[{2'd i, phase[i][23:15]}]`, i.e. its own
512-byte bank.  So split into four independent banks of **128 x 32 bits**
(4,096 bits each, 1 M10K each):

- port B = voice *i* read, **registered**.  Word index `phase[i][23:17]`,
  byte lane `phase[i][16:15]`.  Latency is free: `tick` fires once every
  `SAMPLE_DIV = 1483` cycles, so register the address and use the previous
  cycle's sample.
- port A = CPU read/write with byte enables.  A CPU longword is aligned and
  banks are 512-byte aligned, so all four bytes of an access land in ONE
  bank — one 32-bit port A access serves it.

**The one real obstacle** is the CPU readback path.  `iosb` samples
`asc_rdata` *combinationally* in its ack cycle (`rtl/iosb.sv:530`,
`else if (sel_asc) rdata <= asc_rdata;`), and `asc_wavetable` has no `ack`
of its own.  Options, in order of preference:

1. Give `sel_asc` reads one extra cycle in the `iosb` `astate` FSM (add an
   `A_ASC` state next to the existing `A_VIA`), so a registered port A read
   has a cycle to land.  Cleanest, keeps readback exact.
2. Keep the small register file (`mode`/`control`/`volume`/`phase`/`incr`)
   combinational — it is tiny — and only make the **sample-RAM** region's
   readback registered.
3. Return 0 for sample-RAM reads.  `RESUME-machine-bringup.md` records
   audio as scope-only and the chime as an optional feature, and the ROM
   almost certainly never reads its samples back — but this is a real
   behavior change, so take it only if 1 and 2 prove awkward.

**Risk:** low.  Audio is not part of any acceptance gate today.

---

## Item 2 — `ap040_cache` `dpram:ctag_ram`  (4,366 ALUTs, 12,126 regs)

**Do this one first — it is the cleanest and the CPU core's own author
documented it as the expected integration.**

`rtl/ap68040/rtl/ap040_cache.v:119`, `dpram #(7, ROWW) ctag_ram` where
`ROWW = 2 + 4 + 4*TAGW = 94` (line 90), so 128 x 94 = 12,032 bits.

**Why it failed:** the comment at `ap040_cache.v:83-86` says the row is
*"carried by the project's true-dual-port dpram (rtl/bram.vhd ->
altsyncram) ... inferring a second write port from a bare array does NOT
map to M10K and costs ~3000 ALMs instead."*  Minimig-AGA ships that
`bram.vhd` (an explicit `altsyncram`).  This project instead wired up the
submodule's stub `rtl/ap68040/rtl/primitives/dpram.v`, which is a plain
inferred array — and it hit exactly the penalty the comment predicts.

`ctag_ram` has genuine writes on **both** ports (lookup/fill on A,
store-invalidate on B).  The stub's `q_a <= mem[address_a]` after both
writes implies mixed-port *old data*, which cannot map to M10K without an
explicit don't-care.  Note `dpram:atc_ram` (`ap040_mmu.v:305`, same module,
32 x 168) **did** infer — that one has a single write port.

**Fix shape — no submodule edit:** the AP68040 README explicitly sanctions
this: *"`dpram` is a plain inferred true-dual-port RAM. Replace it with a
vendor macro (altsyncram, XPM) if your flow needs one; the ports are
`clock, address_a, data_a, wren_a, q_a, address_b, data_b, wren_b, q_b`
with `AW`/`DW` parameters."*

1. Add `rtl/dpram.v` at project level with the identical port list, wrapping
   an explicit `altsyncram` (`operation_mode = "BIDIR_DUAL_PORT"`,
   `read_during_write_mode_mixed_ports = "DONT_CARE"`,
   `ram_block_type = "M10K"`, widths from `AW`/`DW`).
2. In `files.qip`, replace
   `set_global_assignment -name VERILOG_FILE rtl/ap68040/rtl/primitives/dpram.v`
   with the new `rtl/dpram.v`.  Quartus resolves `dpram` by module name, so
   nothing inside the submodule changes.

**Verify before shipping:** `DONT_CARE` differs from the stub's old-data
semantics when port A reads the same row port B is invalidating in the same
cycle.  Check `ap040_cache.v`'s use of `tag_q` against a concurrent
`inv_we`/`inv_wren` — if the lookup can observe a row being invalidated,
the invalidate must be allowed to win or be held off.  Minimig runs this
configuration on real DE10-Nano hardware, so the shape is proven; confirm
the reasoning rather than assuming.

**Risk:** low-to-moderate, entirely in that read-during-write corner.
Regression: the diskless boot must still reach the flashing-? idle loop at
`$408014CA`, and THE gate must still score clean.

---

## Item 3 — `ncr53c96` `sbuf[0:255]`  (4,057 ALUTs, 4,562 regs)

`rtl/ncr53c96.sv:125`.  **Highest risk of the four** — this is the SCSI
path that only just started working (`21f37d6`, `ea7a4e1`), so regress it
against THE gate, not just a diskless boot.

**Why it failed, three separate reasons:**

1. `assign sd_buff_din = sbuf[sd_buff_addr];` (line 134) — asynchronous
   read port for the HPS block device.
2. `sbuf_byte` (lines 145-146) — a second asynchronous read.
3. `for` loops writing 9 / 18 / 6 entries **in a single cycle** (lines 624,
   633, 647, in REQUEST SENSE / INQUIRY / MODE SENSE(6)).  That asks for 18
   write ports.

**Fix shape:**

- Replace the `for`-loop clears with a small init sequencer: one word per
  cycle, walking `sbuf[0..N-1]`, before `buf_valid` is raised.  The ROM
  waits on the phase change, so 18 extra cycles are free.  Careful: the
  loops are *clears* that `set_byte()` calls then overwrite in the same
  cycle — sequence the clear first, then apply the literal bytes, or fold
  the constants directly into the sequencer's data.
- `sd_buff_din` must become a registered read of `sd_buff_addr`.  This is
  the normal MiSTer pattern (hps_io samples it a cycle later, and every
  core that backs `sd_buff_din` with block RAM does exactly this) — but
  confirm against `sys/hps_io.sv` timing rather than assuming.
- Register `sbuf_byte` (add a cycle to the FIFO push path, or pre-read at
  `sbuf_pos`).

**Regression:** run THE gate.  `docs/tools/make-emulator-gate-disk.sh` on a
fresh extract, boot with the fastboot ROM, and score all five suites with
`gen/score_vs_oracle.py` (NO `--flat-env`).  Expect the same 2 REAL cpu
diffs (AP68040 memory-indirect) and clean everywhere else.

---

## Item 4 — `rtc3430042` `pram[0:255]`  (1,137 ALUTs, 2,142 regs)

`rtl/rtc3430042.sv:30`.  Smallest of the four; do it last.

**Why it failed:** the reads at lines 110 and 143-144 are already
*registered* (`data_byte <= pram[...]` inside the clocked block), which is
good — but there are **three different read address expressions**
(`{cmd[2:0], b[6:2]}` at 110, `{3'b000, b[6:2]}` at 143 and 144) and three
write sites (`pram[xpaddr]` at 117, `pram[{3'b000, r}]` at 126 and 128),
which asks for more ports than an M10K has.  `initial for (i = 0; i < 256;
i = i + 1) pram[i] = 8'h00;` at line 52 compounds it.

**Fix shape:** funnel everything through one port pair.  Compute
`pram_raddr` / `pram_waddr` / `pram_we` / `pram_din` combinationally from
the FSM state, then one clean always block does the array:

```systemverilog
(* ramstyle = "M10K, no_rw_check" *) reg [7:0] pram [0:255];
always @(posedge clk) begin
    if (pram_we) pram[pram_waddr] <= pram_din;
    pram_q <= pram[pram_raddr];
end
```

and have the FSM consume `pram_q`.  Drop the `initial` loop (M10K powers up
zeroed on this device; if a defined value is genuinely needed, use a MIF).
The write sites at 126/128 are mutually exclusive case branches, so they
mux onto the single write port cleanly.

**Risk:** low, but PRAM holds the boot-device and monitor-sense settings —
check the machine still boots to the same place rather than into a
different startup disk search.

---

## Build + measure recipe (Windows box)

```powershell
$env:QUARTUS_ROOTDIR = "C:\intelfpga_lite\17.0\quartus"
$env:PATH = "$env:QUARTUS_ROOTDIR\bin64;$env:PATH"
cd C:\Temp\mistercore\wombat33_MiSTer

# A&S only, ~13 min, enough to confirm the arrays now infer
quartus_sh --flow analysis_and_synthesis wombat33 > quartus_build_map.log 2>&1
type output_files\wombat33.map.summary

# full compile, fitter is the gate, ~30 min
quartus_sh --flow compile wombat33 > quartus_build.log 2>&1
type output_files\wombat33.fit.summary
```

Then read the reports from the Mac at
`/Volumes/Temp/mistercore/wombat33_MiSTer/output_files/`:

```sh
i=$(grep -n "^; Analysis & Synthesis RAM Summary" wombat33.map.rpt | cut -d: -f1)
sed -n "${i},$((i+45))p" wombat33.map.rpt      # every array + its Type
```

**The check that matters:** all four arrays must appear in the RAM Summary
with `Type = M10K block` (or `AUTO`), and their entities must show non-zero
"Block Memory Bits" in the entity table.  `Total registers` should fall
from 63,484 to roughly 28,000.

## Acceptance

- `Logic utilization (in ALMs)` **< 41,910** and the Fitter reports
  `Successful`.
- `output_files\wombat33.rbf` produced (`GENERATE_RBF_FILE ON`).
- Timing: check `wombat33.sta.rpt` closes at 33.000 MHz (PLL retuned from
  33.333 on 2026-08-29 — exact real-Quadra rate; every time-anchored
  divider assumes it).  `wombat33.sdc` has
  only `derive_pll_clocks` / `derive_clock_uncertainty` today.
- Sim regressions unchanged: diskless boot reaches flashing-? at
  `$408014CA`; THE gate scores 2 REAL cpu diffs and clean elsewhere.

## If it is still over after all four

In order, none of which touch `sys/` files or the FPU:

1. **qsf area settings** (`wombat33.qsf`, no design change):
   `OPTIMIZATION_TECHNIQUE AREA`, `OPTIMIZATION_MODE "AGGRESSIVE AREA"`,
   `ALM_REGISTER_PACKING_EFFORT HIGH`, and turn OFF
   `ROUTER_LCELL_INSERTION_AND_LOGIC_DUPLICATION` and
   `PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION` / `_RETIMING` (those trade area
   for Fmax, and we only need 33.33 MHz).  Note the box runs Quartus
   **Lite**, where the `PHYSICAL_SYNTHESIS_*` assignments are likely
   ignored anyway — `OPTIMIZATION_*` and `ALM_REGISTER_PACKING_EFFORT` do
   work there.
2. `iosb` own logic is 6,404 ALUTs and `dafb` 3,466 ALUTs / 6,690 regs,
   both larger than they look for what they do — the peripheral read mux
   and `dafb`'s scanout are the next places to look.
3. `ap040_core` own logic is 17,880 ALUTs (the sequencer/decode).  Upstream;
   coordinate with apolkosnik (Dani has an active DM thread) rather than
   forking.

## Gotchas carried forward

- `wombat33.srf` suppresses RAM-inference messages wholesale (IDs `276020`
  and `276027` with a `*` wildcard, last lines of the file).  **Never trust
  the absence of an inference warning** — read the RAM Summary table and the
  Block Memory Bits column instead.
- The build box runs Quartus Prime **17.0.2 Lite**, while `wombat33.qsf`
  declares `LAST_QUARTUS_VERSION "17.0.2 Standard Edition"`.  Benign, but if
  Standard is available it is the better fitter for a design this close to
  the edge.
- `quartus_map` standalone skips the pre-flow script (`sys/sys.tcl:216`)
  that generates `build_id.v`, which `wombat33.sv:61` includes.  Go through
  `quartus_sh --flow`, or run
  `quartus_sh -t sys/build_id.tcl compile wombat33 wombat33` first.
- `verilator/sim.v:163` still backs VRAM with a flat 1 MB and no fold, so
  the fold in `wombat33.sv` has never executed in sim.  Mirror it before
  chasing any hardware-only video bug.
