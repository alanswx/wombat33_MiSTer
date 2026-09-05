# CPU/area optimization handoff — 2026-09-04

Read this file first, then `CPU_PERFORMANCE_TASKS.md`. The area milestone is
complete; do not repeat either completed DAFB hardware run.

## Safe stop state

- Branch: `cpu-sdram-handoff-seed15`
- Fork remote: `https://github.com/alanswx/wombat33_MiSTer.git`
- Accepted parent RTL commit: `e3477c7` (`Advance AP68040 to DBcc refill fast path`)
- AP68040 submodule: clean at `c9ecf79` on `wombat-inline-dbcc-refill`
- MiSTer `192.168.1.75`: Mac OS was shut down through MacAtrium and the menu
  core was loaded. It is safe to deploy another RBF.
- Disposable disk currently matches MD5
  `0c4f774b4a2eccd5656e92f16119875f`.
- Golden restore source:
  `/media/fat/games/Wombat33/backup/MacAtrium-7.5.5-fullcolor_speedtest_golden_20260902.hda.gz`
- Untouched golden gzip MD5: `671894be51b1cd1e0c0c8fb4ec39173e`

## Newly accepted DAFB palette reclaim

Commit `3a960b5` replaces the unintended 6,144-register second palette read
view with explicit CPU/video M10K mirrors. It has completed every gate:

- focused independent-clock CPU readback/video scanout test: pass;
- full-machine Verilator build: pass;
- first 100 SingleStepTests CPU rows: 35,196,127 cycles, 1,696 field groups,
  zero real differences;
- seed-27 Quartus: 36,525 ALMs, 4,099/4,191 LABs, 24,187 registers, 428
  M10Ks, zero setup/hold TNS;
- setup +0.447 ns overall, +0.587 ns CPU, +0.552 ns SDRAM;
- hold +0.244 ns overall, +0.251 ns CPU, +0.442 ns SDRAM;
- Mac OS 7.5.5 full-color boot and Speedometer 3.23 `Run ALL Tests`: pass;
- safe guest shutdown, menu-core return, and golden disk restore: pass.

Speedometer PR is CPU 4.726, Graphics 5.430, Disk 0.683, Math 31.538, Old
6.810, New 2.295. FPU average is 2.446 and Color average is 1.618. This is no
measurable speed change, as expected for area-only work. The cumulative reclaim
from the old ADD checkpoint is 4,213 ALMs and 83 LABs, leaving 92 LABs free.

Preserved artifacts:

- Quartus tree: `/home/alans/builds/wombat33_dafb_palette_m10k_seed27_20260903`
- MiSTer RBF: `/media/fat/_Unstable/Wombat33_DAFB_palette_m10k_seed27_20260903.rbf`
- RBF MD5: `c43a310d2c39171e4be7f781904405c4`
- RBF SHA-256: `6dbbd34b30d767a32255049cb0e2dad3a9f75dc6454344ac24da9c881d29037c`
- Result screenshot:
  `docs/perf/wombat33_dafb_palette_seed27_speedometer323_pr.png`

## Newly accepted DAFB timing-register reclaim

Commit `cec2f3f` combines the ten 12-bit `hparam` entries and seven 12-bit
`vparam` entries into one 32x12 MLAB. Register selectors `6'h09` through
`6'h19` map to `rsel - 6'h09` for both reads and writes. Seed 28 is the
accepted default; seed 27 fails SDRAM timing.

The exact source and build are preserved remotely in:

`/home/alans/builds/wombat33_dafb_timing_mlab_seed28_20260903/rtl/dafb.sv`

The source MD5 is `c35b8c4155959511b7db06ee2bd169d9`. The focused timing and
palette test, full-machine Verilator build, and first 100 SingleStepTests rows
pass with zero real differences.

Measured same-seed comparison against palette-only seed 28:

| seed-28 metric | palette control | timing MLAB | change |
|---|---:|---:|---:|
| fitted ALMs | 36,659 | 36,592 | -67 |
| LABs used | 4,096 | 4,080 | -16 |
| registers | 24,141 | 23,944 | -197 |
| MLAB bits | 1,280 | 1,664 | +384 |
| setup overall | +0.388 ns | +0.291 ns | pass |
| setup CPU | +0.883 ns | +0.862 ns | pass |
| setup SDRAM | +0.928 ns | +0.291 ns | pass |
| hold overall | +0.241 ns | +0.243 ns | pass |

The seed-27 fit is smaller (36,463 ALMs/4,070 LABs) but has -0.453
ns SDRAM setup slack and -0.692 ns TNS, so reject that seed. The accepted
seed-28 candidate RBF already exists at:

`output_files/Wombat33_DAFB_timing_mlab_seed28_20260903.rbf`

It has MD5 `f6db788d637aaf2baf275ef82e015c2a` and SHA-256
`ae937e62a675a248124e2b065db984e29d16ffc916f840d8a0f6abe2c552fd01`.
The working-tree QSF now records seed 28. Hardware booted Mac OS 7.5.5 with
correct full-color output and completed Speedometer 3.23 `Run ALL Tests`.
Progress captures perturbed Graphics and Disk, so retain the prior unperturbed
palette scores as the performance baseline; this run is accepted as a full
functional soak. CPU remained 4.726 and the untouched later Math/FPU/Color
groups read 31.565/2.453/1.613. The guest reached the safe shutdown screen,
the menu core was loaded, and both disk copies matched the golden MD5 after
restore.

The area milestone is now complete: the timing-MLAB seed-28 fit leaves 111 LABs free. Do
not force the eight-entry ADB keyboard FIFO into two Memory LABs without first
proving a real fitted-LAB win; its two asynchronous reads make it a weak
candidate. `SUB.L Dn,Dn` decode preselection passed simulation and saved 715
cycles (0.002%) in the first 100 SingleStepTests rows, but was absent from the
focused loop and its same-seed fit missed 99 MHz SDRAM setup by 0.296 ns with
-0.324 ns TNS. It was reverted without a hardware run. `AND.L Dn,Dn` then
passed the complete AP suite but was also absent from the focused loop and
saved only 746 cycles (0.0021%) in the first 100 SingleStepTests rows, with all
1,696 field groups matching. It was rejected before fitting. `OR.L Dn,Dn` then
passed the complete AP suite but was absent from the focused loop and saved
only 39 corpus cycles (0.00011%); it too was reverted before fitting. EOR.L
produced the same 39-cycle result and was also reverted before fit.

## Newly accepted CMP decode fast path

AP68040 `d543f2d` and parent `b0e6174` preselect both register-file operands
for `CMP.L Dn,Dn` and skip only `S_PIPE_START`. Unlike the rejected opcode
families, CMP has useful coverage: the first 100 SingleStepTests rows fall from
35,196,127 to 35,168,444 cycles, saving 27,683 cycles (0.0787%), with all
1,696 architectural field groups matching. The complete AP suite,
full-machine Verilator build, and focused loop also pass; the focused loop is
unchanged at 212,238 cycles because it contains no eligible CMP.

Seed 28 fits in 36,446 ALMs and 4,063/4,191 LABs, 146 ALMs and 17 LABs below
the timing-MLAB control. It leaves 128 LABs free. Setup is +0.133 ns
overall/SDRAM and +1.192 ns CPU; hold is +0.242 ns overall and +0.245 ns CPU,
with zero TNS. The exact tree is
`/home/alans/builds/wombat33_cpu_cmpdecode_seed28_20260904` and the deployed
RBF is `/media/fat/_Unstable/Wombat33_CPU_cmpdecode_seed28_20260904.rbf`, MD5
`40ba7971e90a2af461276bee0f2159ae`, SHA-256
`44fba87ab5864a42cd4fe0ad6022c01e8f2905272fd03a9da9e4a5d673207f3e`.

The full Speedometer 3.23 run completed. Controlled PR results are CPU 4.765,
Graphics 5.394, Disk 0.676, Math 31.480, Old 6.808, and New 2.280. CPU is
0.83% above the unperturbed 4.726 control; the small non-CPU movements are run
variance. FPU averages 2.432 and Color 1.614. Mac OS reached its safe shutdown
screen, MiSTer returned to `MENU`, and the disposable disk was restored to
MD5 `0c4f774b4a2eccd5656e92f16119875f`. The golden gzip remains untouched at
MD5 `671894be51b1cd1e0c0c8fb4ec39173e`.

Return to speed work now. Use the collected full-machine profile/opcode data
to choose a higher-occupancy decode or front-end path; do not continue copying
the fast path across unranked instruction families. Keep broad pipelining as
the subsequent step after one more evidence-driven narrow target.

The next profiled experiment tested `MOVE.L Dn,Dn` decode preselection. It
passed the complete AP suite, full-machine build, and first-100 differential
corpus, saving 68,796 cycles (0.1956%) with no mismatches. A seed-30 fit closed
timing at 36,453 ALMs and 4,070 LABs (121 free), but the complete hardware run
scored CPU 4.752 versus the accepted CMP checkpoint's 4.765. Because this is
not a measurable hardware improvement and the timing-clean fit leaves seven
fewer free LABs, the RTL was reverted. The exact rejected fit remains at
`/home/alans/builds/wombat33_cpu_movedecode_seed30_20260904`; see measurement
section 25 for hashes and all scores.

That `MOVE.L (A1),(A2)+` target has now also been tested and rejected. The
candidate removed five sequencer states, passed directed write-fault restart,
the complete AP suite, full-machine Verilator, and a timing-clean seed-28 fit.
It cost 218 ALMs and 16 LABs, then scored CPU 4.726 versus the accepted 4.765
on a complete hardware run. The boot trace was real but not representative of
the timed CPU workload. RTL and directed tests were reverted; the AP submodule
is clean at accepted commit `d543f2d`. The exact rejected build is preserved at
`/home/alans/builds/wombat33_cpu_movemempostinc_seed28_20260904`; see
measurement section 26.

The Priority-3 front-end target was then implemented and accepted as the new
checkpoint described below.

The user explicitly released the earlier MiSTer reservation and authorized the
ongoing CPU plan to use the FPGA again. After the rejected copy-loop run, Mac OS
reached its safe shutdown screen, MiSTer returned to `MENU`, and both disposable
and pristine-reference disks were verified at MD5
`0c4f774b4a2eccd5656e92f16119875f`; the golden gzip remains
`671894be51b1cd1e0c0c8fb4ec39173e`.

## Newly accepted resident-opcode inline retirement

AP68040 `8ab1057` removes the standalone `S_FETCH` retirement cycle whenever
the next opcode is already resident in the prefetch queue. IRQ/trace checks and
flushes retain priority. Forwarding covers the two direct decode consumers
whose register-file writes otherwise commit one edge late: A7 for short
`BSR.B`, and USP for `MOVE USP,An`. Both hazards have permanent directed tests
which fail when their individual bypass is removed.

All pre-hardware gates pass. The focused loop falls from 212,238 to 186,380
cycles (-12.18%), and the first 100 SingleStepTests rows fall from 35,168,444
to 32,935,620 (-6.35%) with 1,696 matching field groups and zero real
differences. The complete AP suite and full-machine Verilator build pass.

Seed 28 fits at 36,704 ALMs, 4,099/4,191 LABs, 23,974 registers, and 1,664
MLAB bits. Every timing domain has zero TNS: setup is +0.208 ns overall,
+0.934 ns SDRAM, and +1.122 ns CPU; hold is +0.243 ns overall, +0.257 ns CPU,
and +0.441 ns SDRAM. This leaves 92 LABs free.

The complete hardware run scores CPU 4.985, Graphics 5.818, Disk 0.687, Math
33.079, Old PR 7.185, and New PR 2.348. Against the CMP checkpoint, CPU rises
4.62% and Old PR rises 5.54%. FPU averages 2.664 and Color averages 1.707.
This is the new accepted speed checkpoint.

Preserved artifacts:

- Quartus tree:
  `/home/alans/builds/wombat33_cpu_inlinefetch_wb_seed28_20260904`
- MiSTer RBF:
  `/media/fat/_Unstable/Wombat33_CPU_inlinefetch_wb_seed28_20260904.rbf`
- RBF MD5: `73568cd19f467334e149a77b3b6c9ecd`
- RBF SHA-256:
  `d82388d8b4f71dc42c8cb188befc3998f3cadda21e1e37ef3e375d5dfe020f13`
- Result captures:
  `docs/perf/wombat33_cpu_inlinefetch_wb_seed28_speedometer323_pr.png` and
  `docs/perf/wombat33_cpu_inlinefetch_wb_seed28_speedometer323_detail.png`

Mac OS reached the safe shutdown screen after the measurement, MiSTer returned
to `MENU`, and both disk copies match MD5
`0c4f774b4a2eccd5656e92f16119875f`. FPGA use remains authorized for the
continuing CPU plan until the user revokes it.

## Newly accepted resident-immediate consumption

AP68040 RTL commit `0a84732` makes decode consume immediate extension words
that are already resident in the prefetch queue. Commit `c897d77` adds the
submodule documentation, and parent `9a81035` records that submodule head. The
fast path is deliberately decode-only, refuses both an outstanding prefetch
and a same-edge `mem_ack`, and marks the port claimed so a new speculative fill
cannot begin on the pop edge. All other `immf` callers retain `S_IMMF`.

The first broad version exposed two useful failures: exception test 136 lost a
phase-0 timing boundary, and the first translated MOVE after enabling the MMU
let the page-table walker and 16-bit CPU bus run together. The ownership guards
above fix both. An earlier attempt to retire directly from the `epf_fwd` bus
forward had zero dynamic coverage in the focused loop and was reverted.

Every acceptance gate passes:

- complete AP68040 suite, including all three memory phases: pass;
- full-machine Wombat Verilator build: pass;
- focused phase-1 loop: 186,380 to 173,718 cycles, -12,662 or -6.79%;
- first 100 SingleStepTests rows: 32,935,620 to 32,841,873 cycles, -93,747 or
  -0.285%, with all 1,696 field groups matching and zero real differences;
- cumulative from CMP: focused loop -18.15%, first-100 corpus -6.62%;
- seed-28 Quartus fit: 36,937 ALMs, 4,092/4,191 LABs, 23,943 registers, 1,664
  MLAB bits, and zero setup/hold TNS;
- setup +0.342 ns overall, +1.267 ns CPU, +0.357 ns SDRAM;
- hold +0.249 ns overall, +0.256 ns CPU, +0.442 ns SDRAM.

The complete Speedometer 3.23 run scores CPU 5.088, Graphics 5.718, Disk
0.686, Math 33.133, Old PR 7.201, and New PR 2.349. CPU rises 2.07% from the
resident-opcode checkpoint. CPU benchmark average is 13.239, FPU average
2.673, and Color average 1.718. The Graphics decline is treated as run
variance: it is outside the CPU change, while the CPU result agrees with the
simulation direction and the remaining categories are stable.

Preserved artifacts:

- Quartus tree:
  `/home/alans/builds/wombat33_cpu_inlineimm_seed28_20260904`
- MiSTer RBF:
  `/media/fat/_Unstable/Wombat33_CPU_inlineimm_seed28_20260904.rbf`
- RBF MD5: `396140cb1b45c213022ff64d8954e140`
- RBF SHA-256:
  `bccbaec9d1956eeccd651a9001316117c2165c2390455ccc0e997fd1436cb076`
- Result captures:
  `docs/perf/wombat33_cpu_inlineimm_seed28_speedometer323_pr.png` and
  `docs/perf/wombat33_cpu_inlineimm_seed28_speedometer323_detail.png`

Mac OS was shut down safely, MiSTer is at `MENU`, and the disposable and
pristine-reference disks both match MD5
`0c4f774b4a2eccd5656e92f16119875f`. The untouched golden gzip remains MD5
`671894be51b1cd1e0c0c8fb4ec39173e`. FPGA use is authorized for the next CPU
experiment until the user revokes it.

## Newly accepted DBcc branch-refill fast path

The generic `go_pc` branch-refill bypass proved a 7.17% focused-loop cycle
reduction and +1.18% hardware CPU PR, but was rejected because it added 1,222
ALMs and 33 LABs. Source-state profiling showed all 12,462 useful focused hits
came from `S_DBCC1`. AP68040 commit `c9ecf79` therefore limits direct target
dispatch to DBcc and reuses `issue_ifetch` for queue seeding.

Every pre-hardware gate passes: the complete AP68040 suite, full-machine
Verilator build, and first 100 SingleStepTests rows. The focused loop falls
from 173,718 to 161,256 cycles (-7.17%); the first-100 corpus is 32,841,589
cycles with all 1,696 field groups matching and zero real differences. The
controlled Speedometer 3.23 run scores CPU 5.133, Graphics 5.792, Disk 0.688,
Math 33.051, Old PR 7.234, and New PR 2.363. CPU is 0.88% above the resident-
immediate checkpoint.

Seed 28 passed with only +0.016 ns SDRAM setup margin and seed 29 failed by
0.436 ns. Seed 30 is the accepted placement: 37,063 ALMs, 4,122/4,191 LABs,
23,929 registers, and zero setup/hold TNS. Setup is +0.512 ns overall, +1.510
ns CPU, and +0.778 ns SDRAM; hold is +0.207 ns overall, +0.260 ns CPU, and
+0.397 ns SDRAM.

Preserved artifacts:

- AP68040 branch/commit: `wombat-inline-dbcc-refill` / `c9ecf79`
- parent pointer/seed commit: `e3477c7`
- Quartus tree:
  `/home/alans/builds/wombat33_cpu_dbccbrf_reuse_seed30_20260904`
- MiSTer RBF:
  `/media/fat/_Unstable/Wombat33_CPU_dbccbrf_reuse_seed30_20260904.rbf`
- RBF MD5: `f6aa3aad50c283b884132dffd4d7e157`
- RBF SHA-256:
  `db6e2243c81710bcda96479058e72301fb323370e125f724b273618f00c60b99`

The exact seed-30 RBF smoke-booted to full-color MacAtrium and shut down
cleanly. MiSTer is back at `MENU`; the disposable and pristine-reference disks
match MD5 `0c4f774b4a2eccd5656e92f16119875f`, and the golden gzip matches
`671894be51b1cd1e0c0c8fb4ec39173e`. The next active performance task is a
measured one-entry, two-stage in-order front end for simple register ALU
instructions. Do not spend the remaining 69 LABs on more unranked state
bypasses.

## Working-tree ownership

These pre-existing changes are user-owned and were deliberately not staged,
rewritten, cleaned, or deleted:

- `docs/sdram-vram-sharing.md`
- `verilator/sim.v`
- `verilator/sim_main.cpp`
- `RESUME-vram-1mb.md`
- `docs/cpu-memory-speedup.md`
- `docs/vram-1mb-decision.md`
- generated `verilator/obj_dir_tb_*` directories

Only `README.md`, `CPU_PERFORMANCE_TASKS.md`,
`docs/PERFORMANCE_MEASUREMENTS.md`, this handoff, and the named performance
screenshots belong in the documentation checkpoint following parent RTL
commit `e3477c7`.

There is no `CLAUDE.md` in this repository or its git history at this stop.
