# CPU/area optimization handoff — 2026-09-03

Read this file first, then `CPU_PERFORMANCE_TASKS.md`. Work stopped here to
preserve usage; do not start a fresh investigation or repeat the completed
hardware run.

## Safe stop state

- Branch: `cpu-sdram-handoff-seed15`
- Fork remote: `https://github.com/alanswx/wombat33_MiSTer.git`
- Accepted parent RTL commit: `3a960b5` (`Infer DAFB palette mirrors in M10Ks`)
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

## Next prepared change: DAFB timing registers in one MLAB

This is the next action. Do not redo its discovery or seed sweep. Combine the
ten 12-bit `hparam` entries and seven 12-bit `vparam` entries in `rtl/dafb.sv`
into one `(* ramstyle = "MLAB, no_rw_check" *) reg [11:0]
crtc_param[0:31]`. Map register selectors `6'h09` through `6'h19` to index
`rsel - 6'h09` for both reads and writes. Use seed 28 for the accepted build;
seed 27 fails SDRAM timing.

The exact candidate source is preserved remotely in:

`/home/alans/builds/wombat33_dafb_timing_mlab_seed28_20260903/rtl/dafb.sv`

Its MD5 is `c35b8c4155959511b7db06ee2bd169d9`. A local scratch copy may still be at
`/private/tmp/dafb_timing_candidate.sv`, but the preserved remote tree is the
authority. The candidate's focused first/boundary/last timing-register test and
palette test already pass.

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

The seed-27 candidate fit is smaller (36,463 ALMs/4,070 LABs) but has -0.453
ns SDRAM setup slack and -0.692 ns TNS, so reject that seed. The accepted
seed-28 candidate RBF already exists at:

`output_files/Wombat33_DAFB_timing_mlab_seed28_20260903.rbf`

It has MD5 `f6db788d637aaf2baf275ef82e015c2a` and SHA-256
`ae937e62a675a248124e2b065db984e29d16ffc916f840d8a0f6abe2c552fd01`.
The preserved Quartus fitter report records seed 28 even though the saved QSF
may still name seed 27; change the working-tree QSF seed to 28 when accepting
the candidate so a default rebuild is reproducible.

Next-session sequence:

1. Confirm this documentation/handoff commit is pushed and the user-owned dirty
   files below are untouched.
2. Recover the candidate `dafb.sv` from the preserved remote tree, review its
   diff against `3a960b5`, apply only the timing-array change, and set the QSF
   seed to 28.
3. Run `make -C verilator -j8`; rerun the focused timing/palette test and first
   100 SingleStepTests rows. The timing change is outside AP68040, but keep the
   same acceptance gate.
4. Deploy the already timing-clean seed-28 RBF, boot the disposable disk, and
   check video modes plus a full Speedometer `Run ALL Tests` pass.
5. Shut down through MacAtrium, wait for the safe screen, load
   `/media/fat/menu.rbf`, restore only the disposable disk from the golden, and
   verify both disk MD5s again before committing the timing change.

That timing-array pass gives 111 free LABs in its seed-28 fit and clears the
100-LAB headroom milestone. Afterward, either test the small eight-entry ADB
keyboard FIFO as explicit mirrored MLAB read views (small, hardware-sensitive
area experiment) or return to CPU speed work. The preferred CPU experiment is
to extend the proven decode-time dual-register selection from `ADD.L Dn,Dn` to
`SUB.L Dn,Dn`, one opcode family at a time. Do not start broad pipelining yet.

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
screenshot belong in the documentation checkpoint following `3a960b5`.

There is no `CLAUDE.md` in this repository or its git history at this stop.
