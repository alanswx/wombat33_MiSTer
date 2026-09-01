# Performance measurements — Speedometer 4.02

Three-way comparison of a **real Quadra 800**, the **Wombat33 core before the
SDRAM fast path**, and the **core with it**. Measured 2026-09-01 on hardware
(DE10-Nano + MiSTer SDRAM board), same disk image, same ROM, same Mac OS.

| | Benchmark Mix | Color QuickDraw |
|---|---|---|
| Real Quadra 800 | **1.897** | **1.283** |
| Wombat33 `20260831_2` (before) | 0.200 | 0.198 |
| Wombat33 seed 8 (after) | **0.231** | **0.219** |
| **Gain from the SDRAM work** | **+15.5 %** | **+10.6 %** |
| **Still short of real hardware by** | **8.2×** | **5.9×** |

Speedometer's ratios are against a **Quadra 605 = 1.0** (FPU against a Quadra
650). Higher is better. For the `(sec)` rows a *lower* absolute is better; for
the `/sec` rows a *higher* absolute is better.

The headline: the memory work is worth a solid, reproducible **15 %** of real
CPU throughput — and the emulated Quadra is still **roughly eight times slower
than the machine it is emulating**.

---

## 1. What was compared

| | Real Quadra 800 | Before | After |
|---|---|---|---|
| Bitstream | — | `releases/wombat33_20260831_2.rbf` | seed 8 of `cpu-speed-sdram` |
| md5 | — | `4414e7b3294b3d554a9e43faa16682bd` | `58c5b54fffb314c7e3ddcbd13a401730` |
| Provenance | photograph | commit `cc53fbd` | branch `cpu-speed-sdram`, `db174e5` |
| CPU | MC68040 | MC68040 | MC68040 |
| FPU / MMU | Integral / Integral | Integral / Integral | Integral / Integral |
| ROM | `$067C`, 1024K | `$067C`, 1024K | `$067C`, 1024K |
| Physical RAM | 122880K | 32768K | 32768K |
| Bus clock | 33.33 MHz | 33.000 MHz | 33.000 MHz |

Both Wombat33 md5s were verified **on the MiSTer after the push**, not just
locally. The guest was shut down from the Apple menu before every core swap.

Two differences from the real machine worth keeping in mind: it has 128 MB
against our 32 MB (irrelevant to these tests, which are cache- and
bandwidth-bound rather than capacity-bound), and its bus is 1 % faster.

![Real Quadra 800](perf/real_quadra800.jpg)

## 2. Benchmark Mix

Absolute values. One iteration of every test, which is what the reference
photograph used.

| Test | Real Q800 | Before | After | After vs before | After vs real |
|---|---|---|---|---|---|
| KWhetstones/sec | 1978.474 | 157.809 | 191.015 | **+21.0 %** | 10.4× slower |
| Dhrystones/sec | 24999.350 | 2033.948 | 2378.287 | **+16.9 %** | 10.5× slower |
| Towers (sec) | 0.469 | 5.048 | 4.250 | **−15.8 %** | 9.1× |
| Quick Sort (sec) | 0.532 | 3.396 | 3.015 | −11.2 % | 5.7× |
| Bubble Sort (sec) | 0.566 | 3.885 | 3.569 | −8.1 % | 6.3× |
| Queens (sec) | 0.307 | 3.047 | 2.621 | −14.0 % | 8.5× |
| Puzzle (sec) | 0.799 | 5.739 | 5.366 | −6.5 % | 6.7× |
| Permutations (sec) | 0.619 | 8.575 | 7.051 | **−17.8 %** | 11.4× |
| Int. Matrix (sec) | 0.599 | 4.766 | 4.333 | −9.1 % | 7.2× |
| Sieve (sec) | 0.974 | 5.821 | 5.187 | −10.9 % | 5.3× |
| **Average ratio** | **1.897** | **0.200** | **0.231** | **+15.5 %** | **8.2×** |

The spread across tests is itself informative. Permutations (+17.8 %) and
Towers (+15.8 %) gain most — both are pointer-chasing, cache-missing workloads
that spend their time waiting on memory. Puzzle (+6.5 %) and Bubble Sort
(+8.1 %) gain least, being tight loops that mostly stay in the '040's caches
and were never waiting on SDRAM. That is exactly the signature the change
should produce, and it is a useful sanity check that the gain is real rather
than measurement drift.

## 3. Color QuickDraw

All four depths from 1-bit to 8-bit; 16 bits/pixel is greyed out in Speedometer
on this hardware and was not run on the real machine either.

| Test | Real Q800 | Before | After | After vs before | After vs real |
|---|---|---|---|---|---|
| Monochrome (sec) | 5.356 | 36.804 | 32.935 | −10.5 % | 6.1× |
| Two Bit (sec) | 5.961 | 40.341 | 36.270 | −10.1 % | 6.1× |
| Four Bit (sec) | 6.806 | 43.115 | 39.023 | −9.5 % | 5.7× |
| Eight bit (sec) | 8.242 | 49.479 | 45.184 | −8.7 % | 5.5× |
| **Average ratio** | **1.283** | **0.198** | **0.219** | **+10.6 %** | **5.9×** |

Colour gains less than the CPU mix (~10 % against ~15 %), which fits: QuickDraw
here is drawing into **VRAM, which is on-chip BRAM**, not SDRAM. Only the
source data and the drawing code itself come through the memory path this
branch touched, so only part of the work could speed up.

## 4. FPU

Not run on the previous release (agreed to skip). Seed 8 only, for the record,
against a Quadra 650 = 1.0:

| Test | Abs. | Rat. |
|---|---|---|
| KWhetstones/sec | 827.979 | 0.159 |
| Matrix Mult. (sec) | 4.572 | 0.154 |
| Fast Fourier (sec) | 1.679 | 0.171 |
| **Average** | | **0.161** |

## 5. How much to trust these numbers

**Benchmark Mix reproduces to under 1 %.** Three independent seed-8 runs,
the last one after a clean shutdown, a flash to the previous release, and a
flash back:

| Test | run 1 | run 2 | run 3 |
|---|---|---|---|
| KWhetstones/sec | 190.959 | 191.395 | 191.015 |
| Dhrystones/sec | 2378.068 | 2379.446 | 2378.287 |
| Towers | 4.250 | 4.249 | 4.250 |
| Permutations | 7.050 | 7.048 | 7.051 |
| Sieve | 5.186 | 5.169 | 5.187 |
| **Average** | **0.231** | **0.231** | **0.231** |

The previous release was likewise run twice (average 0.200 both times, every
test within 2 %). A 0.200 → 0.231 difference is an order of magnitude larger
than that noise.

**The 8-bit colour figure is not stable and should not be quoted alone.**
Seed 8 produced 43.713, 32.440 and 45.184 seconds for the same test on three
occasions. Monochrome, 2-bit and 4-bit repeat to within 0.5 %, so the ~10 %
colour headline rests on those; the 8-bit column above uses the run consistent
with the other two samples. An earlier sweep that happened to catch the 32.4 s
outlier suggested a 22 % colour gain — that number is wrong and is recorded
here only so nobody rediscovers it and believes it. **Why 8-bit alone varies is
unexplained and worth a look.**

**A screensaver is armed on this disk** and its idle timeout sits somewhere
between 250 s and 400 s. One early run ended with it up; that run was repeated
inside a shorter window and agreed to three decimals, so it did no harm, but
any future timing work on this machine should keep runs inside ~250 s of the
last input or disable it first.

## 6. Method

Speedometer 4.02, from `Quad Squad:Utilities:`. Driven over the MiSTer remote
websocket (`scripts/mister_ws.py`); helper scripts in `scratch/perf/`.

- The guest's **Command key is PS/2 Left Alt** (`rtl/adb.sv:530` maps it to ADB
  `$37`), i.e. Linux keycode 56, so ⌘B is `down:56 raw:48 up:56`. Speedometer's
  shortcuts — ⌘B Benchmark Mix, ⌘G Color QuickDraw, ⌘F FPU — make the whole
  run keyboard-driven; only the checkboxes need the mouse.
- Navigation to the app used the Finder's **type-select + ⌘O**, which is far
  more reliable than clicking icons.
- **No screenshots were taken during a run.** The capture is an HTTP POST the
  core services, and it perturbs what is being timed.
- Mouse positioning is a closed loop, because mrext sends *relative* motion and
  Mac OS accelerates it — the event-to-pixel scale measured anywhere from 1.3
  to well over 8 px per event depending on how many events got coalesced into
  one ADB report. `scratch/perf/click.sh` pins the pointer into the top-left
  corner (the one position the screen edge makes certain) and then walks to the
  target, re-measuring the scale from a screenshot after every move.

### Screenshots

Before — `releases/wombat33_20260831_2.rbf`:

![Before](perf/wombat33_20260831_2_baseline.png)

After — seed 8 of `cpu-speed-sdram`:

![After](perf/wombat33_seed8_sdram-fastpath.png)

## 7. What this says about the SDRAM work

`docs/sdram-fast-path.md` measured the memory path in isolation with
`verilator/tb_sdram.sv`: an isolated store fell from 242 ns to 30 ns and a read
beat from 272 ns to 212 ns. This document is the end-to-end consequence of
that: **+15.5 % on the CPU mix, +10.6 % on colour**, on real silicon running
real Mac OS.

That ratio is worth understanding rather than being disappointed by. An 8×
store latency win does not become an 8× machine win because most instructions
are not stores and most stores were already overlapping with something. The
tests that gained most are the ones that miss cache most, which is the
signature of a genuine memory-path improvement.

**The gap that remains is the interesting part.** At 8.2× slower than a real
Quadra 800 on the CPU mix, the bottleneck is no longer only the platform's
memory path:

- A read beat is now 212 ns of which the SDRAM row cycle is ~81 ns; the rest is
  the two clock-domain crossings. Removing them (§1c of the speed plan) is the
  next platform item and is worth more than its position in the running order
  suggested.
- Page mode (§1d) is the structural fix and the one that reaches real-Quadra
  *bandwidth*.
- Beyond that the remaining terms are inside the CPU core — the write-through
  cache with no write buffer, and the lack of an early ack on line fills — which
  live in the `rtl/ap68040` submodule.

A useful next measurement would be the same three-way comparison after §1c and
§1d land, to see how much of the 8.2× is memory and how much is the core.
