# CPU performance task list and recovery record

Last updated: 2026-09-04. This is the authoritative CPU-speed queue and the
first file to read after a power loss or a new session. Measurements and
screenshots remain in `docs/PERFORMANCE_MEASUREMENTS.md`.

## Immediate answer: should area be reduced?

**Completed before a broad pipeline change.** Reducing ALM/LAB use does not
directly increase emulated CPU throughput. The FPU and two DAFB reclaim passes
lower the timing-clean design from 40,738 to 36,592 ALMs and from 4,182 to
4,080 LABs. That leaves 111 LABs free instead of nine, makes fits less
seed-sensitive, and creates useful room for predecode, bypass controls, or
another pipeline register. The endpoints use seeds 27 and 28 respectively, so
same-seed deltas are recorded for each pass below.

LAB availability remains the more urgent number. The MLAB-backed FPU register
bank recovered 1,380 ALMs but only six LABs. Explicit CPU/scanout copies of the
DAFB palette then moved the unintended 6,144-flop read mirror into three more
M10Ks, recovering another 2,833 ALMs and 77 LABs. Continue toward the initial
practical milestone of **100 LABs and 1,000 ALMs** relative to the old ADD
checkpoint, without disabling the MMU, FPU, caches, video, audio, or other
machine features. Combining the 17 DAFB timing words in one MLAB then saves 67
ALMs and 16 LABs against the same-seed palette control. The milestone is met:
the accepted seed-28 fit is 4,146 ALMs and 102 LABs below the old seed-27 ADD
checkpoint, with 111 LABs free.

The pre-reclaim seed-27 hierarchy report says where to work:

| hierarchy | fitted ALMs needed | implication |
|---|---:|---|
| complete design | 40,738--40,755 | 97%; fitting is the constraint |
| `wombat_cpu` | about 24,783 | about 61% of the whole FPGA |
| `ap040_core` | about 23,565 | primary target |
| core sequencer/decode excluding named children | about 15,947 | best first area target |
| `ap040_fpu` | about 5,209 | second target; preserve 040 behavior |
| `ap040_alu` | about 1,559 | investigate sharing after decode |
| `ap040_mmu` | about 756 | relatively small |
| `ap040_regfile` | about 436 | low priority; asynchronous ports buy speed |
| `ap040_cache` | about 366 plus M10Ks | already mostly in block RAM |

That report estimated roughly 493 CPU ALMs could be recovered by denser packing,
but also reports roughly 799 ALMs unavailable to that hierarchy. This reinforces
that routing/packing structure matters alongside raw Boolean count.

## Accepted checkpoint: preserve this

- Parent repository branch: `cpu-sdram-handoff-seed15`
- Parent remote: `https://github.com/alanswx/wombat33_MiSTer.git`
- Parent commit: `cec2f3f` (`Infer DAFB timing registers in MLAB`)
- AP68040 branch: `wombat-retained-line-fill`
- AP68040 remote: `https://github.com/alanswx/AP68040.git`
- AP68040 commit: `8231eec` (`Infer FPU register bank in MLABs`)
- Quartus seed: 28
- Exact preserved build: `/home/alans/builds/wombat33_dafb_timing_mlab_seed28_20260903`
- MiSTer RBF: `/media/fat/_Unstable/Wombat33_DAFB_timing_mlab_seed28_20260903.rbf`
- MD5: `f6db788d637aaf2baf275ef82e015c2a`
- SHA-256: `ae937e62a675a248124e2b065db984e29d16ffc916f840d8a0f6abe2c552fd01`
- Quartus: 36,592/41,910 ALMs; 4,080/4,191 LABs; zero setup/hold TNS
- Setup slack: +0.291 ns overall, +0.862 ns CPU, +0.291 ns SDRAM
- Hold slack: +0.243 ns overall, +0.254 ns CPU, +0.433 ns SDRAM
- Stable performance reference remains the unperturbed palette run: CPU 4.726,
  Graphics 5.430, Disk 0.683, Math 31.538, Old PR 6.810, New PR 2.295
- Focused `bench_loop`: 212,238 cycles
- First 100 SingleStepTests rows: 35,196,127 cycles, 1,696 field groups,
  zero real differences

The palette checkpoint remains the closest known-good fallback at parent
`3a960b5`, AP68040 `8231eec`, exact build
`/home/alans/builds/wombat33_dafb_palette_m10k_seed27_20260903`, and MiSTer RBF
`Wombat33_DAFB_palette_m10k_seed27_20260903.rbf` (MD5
`c43a310d2c39171e4be7f781904405c4`). Do not overwrite either checkpoint.
Experiments use the disposable remote tree and a separately named RBF. The
disposable Mac disk is always restored from the compressed golden after a safe
guest shutdown.

## Completed 2026-09-03: DAFB palette in explicit M10K mirrors

The DAFB palette formerly presented one write port plus independent CPU and
scanout read ports through three arrays. Quartus inferred one 6,144-bit M10K
copy and implemented the second read view as 6,144 flip-flops. The candidate
uses explicit CPU and video mirrors, writes both, and registers the three video
outputs in their own `clk_vid` process. Quartus now infers six simple-dual-port
M10Ks while preserving the existing one-pixel registered lookup.

- Local/remote `rtl/dafb.sv` MD5: `6cea7041a458c2627d26e710ebb17f59`
- Focused independent-clock palette readback/scanout test: pass
- Full-machine Verilator build: pass
- First 100 SingleStepTests rows: 35,196,127 cycles, 1,696 matching field
  groups, zero real differences
- Seed-27 fit: 36,525 ALMs, 4,099/4,191 LABs, 24,187 registers, 428 M10Ks,
  zero setup/hold TNS
- Change from the FPU-MLAB checkpoint: -2,833 ALMs, -77 LABs, -6,056
  registers, +3 M10Ks, +6,144 block-memory bits
- Cumulative change from the old ADD checkpoint: -4,213 ALMs and -83 LABs;
  17 more LABs remain to the 100-LAB milestone
- Setup: +0.447 ns overall, +0.587 ns CPU, +0.552 ns SDRAM
- Hold: +0.244 ns overall, +0.251 ns CPU, +0.442 ns SDRAM
- Exact preserved build:
  `/home/alans/builds/wombat33_dafb_palette_m10k_seed27_20260903`
- RBF: `/media/fat/_Unstable/Wombat33_DAFB_palette_m10k_seed27_20260903.rbf`
- RBF MD5: `c43a310d2c39171e4be7f781904405c4`
- RBF SHA-256:
  `6dbbd34b30d767a32255049cb0e2dad3a9f75dc6454344ac24da9c881d29037c`
- Hardware: Mac OS and full-color video boot correctly. Speedometer 3.23
  `Run ALL Tests` completed: CPU 4.726, Graphics 5.430, Disk 0.683, Math
  31.538, Old PR 6.810, New PR 2.295, FPU average 2.446, and Color average
  1.618. This is no measurable throughput change, as expected for area-only
  work.
- Mac OS reached the safe shutdown screen, the MiSTer returned to its menu,
  and both disposable and pristine disks matched MD5
  `0c4f774b4a2eccd5656e92f16119875f` after the golden restore.

## Completed 2026-09-04: DAFB timing registers in one MLAB

The ten `hparam` and seven `vparam` words are now one power-of-two 32x12
MLAB-backed array. Register selectors `$09` through `$19` retain the same bus
addresses and map contiguously into it. Against the palette-only seed-28
control, synthesis falls 319 cells and the fit saves 67 ALMs, 16 LABs, and 197
registers for 384 additional MLAB bits. The accepted fit is 36,592 ALMs,
4,080/4,191 LABs, 23,944 registers, 428 M10Ks, and 1,664 MLAB bits.

Seed 28 is timing-clean at +0.291 ns setup overall (+0.862 ns CPU/+0.291 ns
SDRAM) and +0.243 ns hold overall (+0.254 ns CPU/+0.433 ns SDRAM), with zero
TNS. Seed 27 is rejected despite its smaller 36,463-ALM/4,070-LAB fit because
SDRAM setup is -0.453 ns with -0.692 ns TNS.

The focused timing/palette test, full-machine Verilator build, and first 100
SingleStepTests rows all pass; the CPU corpus remains 35,196,127 cycles with
1,696 matching field groups and zero real differences. Hardware booted Mac OS
7.5.5 in full color and completed every Speedometer 3.23 `Run ALL Tests`
category. Progress screenshots perturbed Graphics and Disk, so that run is a
functional soak rather than a controlled speed comparison; CPU remained 4.726
and the later untouched Math/FPU/Color results remained at 31.565/2.453/1.613.
Mac OS then reached the safe shutdown screen, the MiSTer returned to its menu,
and both disk copies matched `0c4f774b4a2eccd5656e92f16119875f` after restore.

## Completed 2026-09-03: first ALM/LAB reclaim pass

The accepted AP68040 commit `8231eec` contains the cumulative structural work
below. Intermediate fits are retained here so future work does not repeat the
same attractive-looking failures.

1. Reset is no longer applied to the instruction/refill payload arrays or the
   four-word MOVEM16 buffer. Their existing count/valid/state controls prevent
   consumption until the payload has been written. Quartus infers `m16buf` as
   a 4x32 simple-dual-port M10K (128 bits). The complete AP68040 suite, focused
   loop at 212,238 cycles, full-machine Verilator build, and first 100
   SingleStep rows at 35,196,127 cycles/1,696 matching field groups/zero real
   differences pass. Seed 27 with the normal speed mapper is timing-clean at
   40,730 ALMs and 4,177/4,191 LABs, only 8 ALMs and 5 LABs better than the
   old ADD checkpoint. Setup is +0.195 overall/+0.377 CPU/+0.312 SDRAM; hold
   is +0.139 overall/+0.250 CPU/+0.434 SDRAM. This is evidence, not yet an
   accepted commit.
2. The FPU now captures FPn once at command dispatch, reuses its existing
   exception shadow for later exception frames, and reuses the corresponding
   unpacked `b_*` operand through arithmetic/compare. This removes a late
   80-bit asynchronous destination-bank read. On its own this lowers the
   synthesis netlist from 80,910 to 80,688 logic cells and the FPU hierarchy
   from 8,462 to 8,226. AP tests, the 212,238-cycle focused loop, full-machine
   Verilator, first-100 CPU, all FPU, save/restore, and integration corpora all
   pass. Its seed-27 fit is timing-clean at 40,044 ALMs but still consumes
   4,189/4,191 LABs; setup is +0.166 overall/+0.742 CPU/+0.672 SDRAM and hold
   is +0.175 overall/+0.175 CPU/+0.431 SDRAM. It proves the logic reduction is
   real but does not by itself improve physical packing.
3. The next extension makes FMOVEM stores reuse the ordinary FP source-bank
   read port. `S_FPU_MVM` selects `fpu_srcr` and the existing `S_FPU_MVM2`
   setup cycle preserves the interface timing; FMOVEM loads retain the
   independent `fm_sel` write port. Exact local/remote hashes are core
   `b376c7fd9df452cce9237c6d21fbdb3c` and FPU
   `7b3bfaa98cb3e73af44ad2ac2399c31b`. Synthesis falls again to 80,475 logic
   cells and the FPU hierarchy to 8,036, respectively 435 and 426 below the
   reset-payload baseline. AP tests, focused loop, full-machine build,
   first-100 CPU (35,196,127 cycles/1,696 matches), all 270 FPU rows (5,000
   matches), all 8 save/restore rows, and all 1,328 integration rows pass with
   zero real differences. The seed-27 fit is timing-clean at 39,873 ALMs but
   still occupies 4,191/4,191 LABs. Setup is +0.091 overall/+0.673 CPU/+0.379
   SDRAM and hold is +0.254 overall/+0.264 CPU/+0.433 SDRAM. The fitter places
   40,650 physical ALMs, calls 1,912 recoverable by dense packing, and loses
   1,135 to packing constraints (115 LAB-wide signal conflicts and 1,020 LAB
   input limits). Keep this as a useful logical-area result, but it does not
   pass the physical-headroom gate by itself.
4. Adding an 8-bit validity mask after reducing the register bank to two read
   views passes every simulation corpus and lowers synthesis to 80,256 logic
   cells, with 7,354 in the FPU. Its seed-27 fit is smaller at 39,735 ALMs and
   4,185/4,191 LABs, but fails timing at -0.033 ns setup overall and -0.205 ns
   SDRAM hold. This is not the accepted form.
5. The accepted form mirrors the 8x80 architectural FP bank into two inferred
   simple-dual-port MLAB memories, giving two asynchronous command-time reads
   and one shared synchronous write. Quartus uses exactly 1,280 MLAB bits in
   eight Memory LABs. Synthesis falls to 79,252 logic cells, 1,469 below the
   prior accepted build; the FPU falls from 8,462 logic cells/2,243 registers
   to 7,091/1,617. The seed-27 fit is timing-clean at 39,358 ALMs and
   4,176/4,191 LABs. It places 40,166 physical ALMs, estimates 1,876 recoverable
   by dense packing, and loses 1,068 to constraints (99 LAB-wide signal
   conflicts and 969 LAB input limits). Setup is +0.290 ns overall/+0.649 CPU/
   +0.591 SDRAM; hold is +0.244 overall/+0.262 CPU/+0.434 SDRAM. Exact source
   hashes are core `b376c7fd9df452cce9237c6d21fbdb3c` and FPU
   `4491c1186f6e7a09b8dbb507d0ca436d`.

   The AP suite, 212,238-cycle focused loop, full-machine Verilator build,
   first-100 CPU corpus, all 270 FPU rows, all 8 save/restore rows, and all
   1,328 integration rows pass with zero real differences. Hardware booted and
   completed Speedometer 3.23 `Run ALL Tests`; the comparable PR scores are
   4.726 CPU, 5.452 Graphics, 0.685 Disk, 31.512 Math, 6.814 Old PR, and 2.301
   New PR. This is no measurable speed change, as expected for area-only work.
   Mac OS reached the safe shutdown screen, the MiSTer returned to `MENU`, and
   the disposable and pristine disks were verified at MD5
   `0c4f774b4a2eccd5656e92f16119875f` after the golden restore.

Rejected tool and structural experiments:

- Removing reset only from `m16buf` reduces the synthesized CPU hierarchy by
  97 combinational ALUTs, but its seed-27 fit spreads 39,805 ALMs across every
  LAB (4,191/4,191) and misses HDMI setup by 0.258 ns. Reject that isolated
  form; the large fitted-ALM swing is placement, not a credible RTL delta.
- FPU-only `OPTIMIZATION_TECHNIQUE AREA` and global `OPTIMIZATION_MODE
  BALANCED` both synthesize the exact same 80,910-logic-cell netlist as the
  normal settings. Reject both as no-ops.
- Routing all 218 sequencer transitions through one explicit `state_next`
  carrier passes the AP suite, focused 212,238-cycle loop, full-machine
  Verilator build, and first 100 SingleStep rows with zero real differences.
  Reject it anyway: Quartus still does not recognize `state` as an FSM, the
  complete synthesis netlist grows by 217 logic cells, and the CPU hierarchy
  grows to 36,505 combinational ALUTs. The working tree has been restored to
  the pre-experiment payload/M10K form.
- Adding a `syn_encoding="onehot"` hint to the existing state register is not
  sufficient either. Quartus still does not extract the main FSM and the
  complete synthesis netlist grows by 61 logic cells. Reject and remove it.
- Global `OPTIMIZATION_TECHNIQUE AREA` produces a smaller synthesis netlist
  (80,166 versus 80,910 logic cells) and a 39,578-ALM fit, 1,160 below the
  accepted checkpoint. Reject it: packing worsens to 4,190/4,191 LABs and the
  seed-27 fit misses setup by 0.342 ns. CPU/SDRAM setup is +0.814/+0.109 ns and
  overall hold is +0.239 ns, but the complete design gate is not met.
- Raising `ALM_REGISTER_PACKING_EFFORT` from `MEDIUM` to `HIGH` is a complete
  no-op for this netlist and seed: 40,730 ALMs, 4,177/4,191 LABs, and every
  reported setup/hold value exactly match the normal-packing fit. Restore
  `MEDIUM`.
- Changing `QII_AUTO_PACKED_REGISTERS` from `NORMAL` to `MINIMIZE AREA` is
  likewise a complete no-op on the accepted FPU-MLAB netlist and seed 27:
  39,358 ALMs, 4,176/4,191 LABs, 30,243 registers, +0.290 ns setup, and
  +0.244 ns hold all match exactly. Restore `NORMAL`; Quartus is already
  applying the useful register packing available to this netlist.
- Replacing reset writes to the 640-bit FP0--FP7 payload with an 8-bit valid
  mask passes the AP suite, the 212,238-cycle focused loop, full-machine
  Verilator, the first 100 CPU rows, all 270 FPU rows, all 8 save/restore rows,
  and all 1,328 CPU/FPU integration rows with zero real differences. It also
  lowers the FPU synthesis hierarchy from 8,462 to 7,835 combinational
  functions. Reject it anyway: its four validity-gated asynchronous read views
  fit at 40,986 ALMs and 4,190/4,191 LABs, versus 40,730 and 4,177 for the
  reset-payload candidate. Timing is clean (+0.147 overall/+0.664 CPU/+0.558
  SDRAM setup, +0.241 hold), but placement density is much worse. A future FP
  register-bank attempt must reduce/stage read ports, not merely remove reset.
- Removing reset from more than 1,000 validity-gated FPU command, operand,
  exception-frame, and writeback payload bits passes the complete AP suite but
  is a synthesis loss. The FPU itself falls from 7,091 to 7,021 ALUTs, while
  the complete design grows from 79,252 to 79,436 logic cells as optimization
  moves into the parent core. Reject it before fitting; removing resets is not
  automatically useful after the architectural FP bank is already in MLABs.
- Mirroring D0--D7/A0--A6 into two asynchronous 16x32 MLAB banks, while leaving
  USP/ISP/MSP in registers, passes the AP suite, full-machine Verilator build,
  the 212,238-cycle focused loop, and first 100 SingleStep rows at 35,196,127
  cycles/zero real differences. Synthesis looks attractive: 78,837 logic
  cells, 415 below the accepted checkpoint, and the register-file hierarchy
  falls from 412 ALUTs/576 registers to 137/104. Reject it after the physical
  gate: seed 27 fits at 39,312 ALMs but consumes 4,186/4,191 LABs, ten more
  than the accepted build, and misses the 99 MHz setup constraint by 0.715 ns
  with -0.965 ns TNS. The four new Memory LABs leave only five LABs free.
  Preserve the flip-flop register file unless a future design adds a staged
  read/bypass architecture and can recover the resulting cycle cost elsewhere.
- Replacing the four parallel ADD/ADDX/SUB/SUBX arithmetic results with one
  op-controlled 33-bit adder passes the AP suite, full-machine Verilator,
  first 100 SingleStep rows, and 2.08 billion cycles of an extended CPU corpus
  before that no-longer-needed run was stopped. The ALU synthesis hierarchy is
  202 ALUTs smaller and the whole netlist is 103 cells smaller, but the control
  depth moves ahead of the carry chain. Seed 27 grows to 39,402 ALMs and
  4,188/4,191 LABs and misses 99 MHz setup by 0.491 ns (-0.897 ns TNS). Reject
  the fully shared form. A narrower ADD/ADDX and SUB/SUBX pair-sharing test may
  avoid the 33-bit add/sub input inversion and is the only sensible follow-up.
- The narrower pair-sharing follow-up passes the AP suite, full-machine build,
  and first 100 SingleStep rows, and makes the ALU hierarchy 137 ALUTs smaller.
  It still grows the complete synthesis netlist by 225 cells (79,477 versus
  79,252) and the core hierarchy by 25 ALUTs as logic crosses the module
  boundary. Reject it before fitting. Keep the four parallel arithmetic
  results; Quartus packs that source structure better in this design.
- Removing reset from the core's validity- and state-gated request, decode,
  exception, effective-address, bit-field, and multicycle payload registers
  passes the complete AP suite, full-machine Verilator build, and first 100
  SingleStep rows. It removes 75 cells from the CPU hierarchy (34,852 to
  34,777), but cross-boundary optimization grows the complete netlist by 31
  cells (79,252 to 79,283). Reject it before fitting and retain the explicit
  architectural reset behavior. Future reset trimming should target one
  fitted register bank at a time and must win at the complete-design level.

## Completed 2026-09-03: narrow `ADD.L Dn,Dn` preselection

The change selects both asynchronous register-file ports in decode and enters
`S_PIPE_REGS`, bypassing only `S_PIPE_START`. It deliberately retains operand
capture and `S_EXEC`. It is accepted at AP68040 `5aa596f` and parent `a267903`.

- Local/remote core MD5: `e41babcaeec22193e03e915ea4da1c1c`
- Full AP68040 suite: pass
- Wombat full-machine Verilator build: pass
- Focused `bench_loop`: **212,238 cycles**, 5.69% below the accepted 225,036
  and 26.80% below the branch-refill baseline of 289,956
- State effect: `S_PIPE_START` falls from 25,669 to 12,868 visits;
  `S_PIPE_REGS` and `S_EXEC` are intentionally unchanged
- First 100 SingleStepTests rows: **35,196,127 cycles**, 1,696 matching field
  groups and zero real differences; 8,516 cycles below the accepted checkpoint
- Exact Quartus tree:
  `/home/alans/builds/wombat33_cpu_adddecode_seed27_20260903`
- Seed-27 Quartus result: **pass**, 40,738 ALMs, 4,182/4,191 LABs, zero TNS;
  setup +0.070 ns overall/+0.772 ns CPU/+0.070 ns SDRAM; hold +0.245 ns
  overall/+0.263 ns CPU/+0.430 ns SDRAM
- RBF: MD5 `cb83d1a71d262a61af9a5508a443506d`, SHA-256
  `512558ea68f5bc5e9dfeb79be9bd0860e44f2d2046e4909bb3c6096c6e24816a`
- Hardware: Mac OS boot and all six Speedometer categories passed; safe shutdown
  screen confirmed; disposable and pristine disks restored/verified at MD5
  `0c4f774b4a2eccd5656e92f16119875f`
- Hardware performance: all six scores are within 0.5% of the predecessor, so
  this is a focused-loop improvement and area-neutral checkpoint, **not a
  measurable Speedometer gain**

## Priority 1: reclaim placement headroom

Treat every item as a separate measured experiment. Preserve the accepted
seed-27 tree and compare both synthesis hierarchy and fitted LAB/ALM totals.

- [ ] Save a machine-readable baseline from the Fitter and Analysis & Synthesis
  resource-by-entity reports. Track ALMs, LABs, registers, recoverable packing,
  unavailable ALMs, M10Ks, DSPs, and per-clock slack after every experiment.
- [ ] Profile `ap040_core`'s self logic. The monolithic sequencer/decode is
  about 15.9k ALMs, far larger than the named ALU, MMU, cache, or register file.
  Use Quartus node/fanout and critical-path reports to rank state-decode cones,
  write-enable muxes, exception controls, EA controls, and duplicated size/mask
  logic before changing RTL.
- [ ] Factor repeated instruction decode predicates, size/byte masks, condition
  evaluation, and destination-write enables into shared controls where Quartus
  is not already sharing them. Verify the post-synthesis netlist actually gets
  smaller; cleaner source alone is not a result.
- [ ] Reduce the number of possible writers and mux inputs for wide stateful
  registers. Consider splitting the giant sequencer into localized register
  update blocks or explicit enables one register group at a time. This is high
  reward and high correctness risk because ordering currently comes from one
  sequential block.
- [ ] Experiment with a hierarchical FSM or selected state encoding. The state
  bits have very high fanout; a local substate can shrink equality decoders,
  while one-hot may trade otherwise idle flip-flops for fewer LUT levels. Keep
  only a result that reduces fitted LABs and retains timing.
- [ ] Look for constant tables or read-only decode/control data that can infer
  MLAB/M10K ROMs. Block-memory bits are only 55% used. Do not move a hot
  asynchronous path into synchronous RAM unless its added cycle is hidden or
  recovered elsewhere.
- [ ] Audit small arrays and refill/prefetch storage for RAM inference. The cache
  data/tags and MMU ATC already use M10Ks; prioritize buffers still implemented
  as scattered registers. The branch-refill sector is hot, so preserve its
  required read bandwidth and zero-extra-cycle branch behavior.
- [ ] Audit the FPU separately. At about 5.2k ALMs it is the largest named child.
  Explore sharing normalization, rounding, shift, compare, and conversion
  hardware across multi-cycle operations. Trading extra FPU cycles for several
  hundred ALMs may be worthwhile only after measuring Speedometer Math and
  retaining the complete FPU/FPSP tests. The first pass moved FP0--FP7 into
  MLABs and removed 1,371 FPU logic cells without adding cycles; the arithmetic
  datapath remains the next target.
- [ ] Review the 436-ALM asynchronous register file only after larger targets.
  Replicated synchronous RAM could cost instruction cycles; do not sacrifice
  the two combinational read ports without an end-to-end throughput win.
- [ ] Inspect low-risk logic outside the CPU if the core alone cannot free 100
  LABs. Framework scaler/audio blocks are individually sizable, but no feature
  may be removed merely to make the utilization number smaller.
- [ ] Evaluate Quartus packing and physical-synthesis assignments on an
  unchanged netlist. Keep tool-setting changes separate from RTL changes and
  require repeatable seed results; fitter-only savings do not excuse negative
  timing slack.
- [x] Milestone gate: recover at least 1,000 ALMs and 100 LABs with all tests
  green before undertaking broader front-end/pipeline work. The accepted
  seed-28 checkpoint is 4,146 ALMs and 102 LABs below the old seed-27 ADD fit,
  leaving 111 LABs free. Same-seed deltas remain the authoritative measure for
  each individual RTL change.

## Priority 2: extend only the proven narrow fast-path pattern

- [ ] Use opcode histograms from the focused bench and a boot workload to rank
  register-register forms. Do not optimize ISA families merely because their
  decode looks similar.
- [ ] The ADD candidate passed hardware. Continue extending decode-time
  dual-register selection one family at a time: EOR, CMP, then
  address-register forms. Re-run every gate after each family. SUB.L was
  tested and rejected: it saved only 715 cycles (0.002%) in the first 100
  SingleStepTests rows, was absent from the focused loop, and its same-seed fit
  missed 99 MHz SDRAM setup by 0.296 ns with -0.324 ns TNS. AND.L was rejected
  before fitting: it was also absent from the focused loop and saved only 746
  cycles (0.0021%) in the same corpus. OR.L was likewise absent from the loop
  and saved just 39 corpus cycles (0.00011%), so it was rejected before fit.
- [ ] Evaluate byte/word register forms separately. Their merge and condition-
  code behavior differs from longword operations and can erase the simplicity
  of the ADD.L path.
- [ ] Extend acknowledgement-time retirement to non-MOVE memory-source ALU
  operations only with a staged operand/result path. Directly placing a full ALU
  and flag calculation on `d_ack` risks both a new critical path and imprecise
  fault/trace behavior.
- [ ] Investigate immediate operands already resident in the instruction queue.
  `S_IMMF` accounts for about 13.9k visits in the focused profile. A narrow
  immediate fast path must preserve extension-word PC accounting and exception
  restart state.
- [ ] Revisit DBcc only with a clearly isolated change. Its decrement state is
  already collapsed and prefetched; approximately 13.1k remaining visits are
  branch/retirement work, not the old redundant state.

## Priority 3: front-end overlap and real pipelining

The core is a correct multi-cycle sequencer, not a throughput pipeline. Narrow
state bypasses help, but reaching much closer to a real 68040 eventually needs
overlap. Start this only after area headroom exists.

- [ ] Add a predecode/dispatch record for the next queued opcode so fetch/decode
  work can overlap execution of the current instruction.
- [ ] Separate architectural retirement from execution. Exceptions, trace,
  interrupts, bus faults, and restartable write faults must remain precise; no
  later instruction may update architectural state early.
- [ ] Define hazards explicitly: register RAW/WAW, CCR dependencies, address-
  register auto-update, control-register changes, cache/MMU serialization,
  branches, and self-modifying-code flushes.
- [ ] Start with a two-stage in-order front end and only simple register ALU
  instructions. Flush on every unsupported or serializing instruction. Measure
  before widening coverage.
- [ ] Consider a small decoded micro-op queue only if one predecode register
  proves useful. Do not build a broad speculative machine; the expected win is
  hiding FETCH/DECODE occupancy, not reimplementing an out-of-order 68040.
- [ ] Revisit CPU clock frequency only after logic/routing headroom and CPI have
  improved. The 33 MHz architectural clock is authentic, and a higher clock can
  mask inefficient sequencing without fixing it or matching real bus behavior.

## Priority 4: remaining memory/cache ideas

The integrated path already measures 52.4 MB/s sequentially and a 304 ns line
fill, inside the real Quadra 800 bandwidth range. CPU sequencing now dominates,
so these are secondary unless profiling moves the bottleneck back to memory.

- [ ] Reduce cache-miss critical-word latency without reviving combinational
  direct acknowledgement. Two broader direct-ack variants froze during the
  hardware Disk test.
- [ ] Evaluate a safe early cache-fill acknowledgement only if subsequent words
  can complete coherently while the CPU continues and redirects/faults remain
  correct.
- [ ] Improve D-cache hit/lookup overlap if profiles show `S_MRD` is waiting on
  internal cache states rather than external SDRAM.
- [ ] Consider copyback only with a real dirty-line snoop/writeback design.
  External DMA and the MMU walker's U/M-bit writes must not invalidate and lose
  dirty CPU data.
- [ ] Preserve the passing registered RAM completion path for Disk, ROM, VRAM,
  IOSB, DAFB, and open-bus accesses.

## Rejected paths: do not rediscover these blindly

- A broad direct register-register ALU retirement change combined with further
  DBcc collapsing passed simulation and Quartus timing but froze at the Happy
  Mac. It is rejected. Bisect one opcode family and one removed state at a time.
- Broad direct memory acknowledgement froze during Speedometer Disk even when
  the pre-adapter retained-line bypass was disabled. Preserve registered
  completion and adapter ownership/order checks.
- Quartus placement is highly seed-sensitive. A new failure on an unrelated
  HDMI, SDRAM, or `ir`/exception path is not proof the RTL idea is bad. Record
  the path, walk a small seed set, and accept only a zero-TNS fit.
- Do not disable the MMU, FPU, caches, scaler, audio, or machine peripherals to
  claim an area or speed win. Feature removal is not optimization.
- Do not compare Speedometer 3.23 PR ratios directly with the published
  Speedometer 4.02 real-Quadra Benchmark Mix. Use the same application version,
  disk image, ROM, iteration count, and restored starting image.

## Validation gate for every CPU change

Run in this order so inexpensive failures stop the experiment early:

```sh
cd rtl/ap68040/tb
bash run_tests.sh

vvp build/tb_prog.vvp +prog=build/bench_loop.hex +prof +memlat

cd ../../../verilator
make -j8

cd ../SingleStepTests/preboot/sim040
CDEFS='-DLAST_TEST_INDEX=99' SIM=verilator \
  VERILATOR=/opt/homebrew/bin/verilator ./run_corpus.sh cpu
```

Then compile on `alans@cottageubuntu` with the candidate source hash and seed
recorded. Require zero setup and hold TNS; record overall, 33 MHz CPU, and 99
MHz SDRAM setup/hold margins plus ALMs/LABs. Preserve timing-clean RBFs with
unique names.

Finally boot the disposable disk on the MiSTer at `192.168.1.75`, run all six
Speedometer 3.23 PR categories, shut down from Mac OS, wait for the safe screen,
return the MiSTer to its menu, and restore:

- disposable: `/media/fat/games/Wombat33/QuadSquad8.hda`
- golden: `/media/fat/games/Wombat33/backup/MacAtrium-7.5.5-fullcolor_speedtest_golden_20260902.hda.gz`
- pristine reference: `/media/fat/games/MacIIvi/MacAtrium-7.5.5-fullcolor_speedtest.hda`
- required restored MD5: `0c4f774b4a2eccd5656e92f16119875f`

Never load a core while the guest is booting or running. It hard-resets the
FPGA while HFS is mounted writable.

## Working-tree cautions

The parent worktree contains unrelated user work in
`docs/sdram-vram-sharing.md`, `verilator/sim.v`, `verilator/sim_main.cpp`, and
the VRAM/resume documents, plus generated Verilator directories. Do not stage,
rewrite, clean, or delete those files as part of CPU work. The profiler changes
in the two Verilator source files are useful but remain user-owned until handled
separately.

There is no `CLAUDE.md` in this repository or its git history as of this
checkpoint. Do not assume instructions were loaded from one unless it is
restored later.
