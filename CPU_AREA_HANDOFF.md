# CPU/area optimization handoff — 2026-09-04

Read this file first, then `CPU_PERFORMANCE_TASKS.md`. The area milestone is
complete; do not repeat either completed DAFB hardware run.

## Safe stop state

- Branch: `cpu-sdram-handoff-seed15`
- Fork remote: `https://github.com/alanswx/wombat33_MiSTer.git`
- Accepted parent RTL commit: `cec2f3f` (`Infer DAFB timing registers in MLAB`)
- AP68040 submodule: clean at `8231eec` on `wombat-retained-line-fill`
- MiSTer `192.168.1.75`: Mac OS was shut down through MacAtrium and the menu
  core was loaded. It is safe to deploy another RBF.
- Disposable disk and untouched pristine reference both currently match MD5
  `0c4f774b4a2eccd5656e92f16119875f`.
- Golden restore source:
  `/media/fat/games/Wombat33/backup/MacAtrium-7.5.5-fullcolor_speedtest_golden_20260902.hda.gz`

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

The area milestone is now complete: the seed-28 fit leaves 111 LABs free. Do
not force the eight-entry ADB keyboard FIFO into two Memory LABs without first
proving a real fitted-LAB win; its two asynchronous reads make it a weak
candidate. `SUB.L Dn,Dn` decode preselection passed simulation and saved 715
cycles (0.002%) in the first 100 SingleStepTests rows, but was absent from the
focused loop and its same-seed fit missed 99 MHz SDRAM setup by 0.296 ns with
-0.324 ns TNS. It was reverted without a hardware run. The next action is to
profile and test `AND.L Dn,Dn` as the next isolated family; reject it before
hardware unless its dynamic benefit and physical fit justify carrying it.
Do not start broad pipelining yet.

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
`docs/PERFORMANCE_MEASUREMENTS.md`, this handoff, and the named timing-MLAB
performance screenshots belong in the documentation checkpoint following
`cec2f3f`.

There is no `CLAUDE.md` in this repository or its git history at this stop.
