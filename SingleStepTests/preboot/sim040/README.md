# preboot/sim040 — the bench corpora against an RTL 68040 core

Runs the wombat33 SingleStepTests bench payloads against a simulated
68040 core and scores the output against the Quadra 800 hardware
captures — RTL-vs-silicon, using the same shared bench code every other
platform runs. First target: **AP68040** (`~/repos/AP68040`), whose
TG68K-shaped top (`ap040_tg68k_compat`) the testbench instantiates.

```sh
./run_corpus.sh                              # full 722-row CPU corpus
CDEFS="-DLAST_TEST_INDEX=9" ./run_corpus.sh  # 10-row smoke (~2 min)
```

Needs iverilog (a from-source build in `~/.local` works: gperf, then
Icarus v12) and the repo's Retro68 m68k GCC. `AP68040_RTL` overrides
the core location; `ORACLE` the capture to score against.

## How it works

- The payload is the shared `bench_main.c` linked at `$40000` by the
  common `payload.ld`, with a three-file platform layer:
  `payload_entry_sim.s` (reset entry: SP `$80000`, .bss zero, dummy
  framebuffer, doorbell write at DONE), `jsonl_sim.c` (the JsonlWriter
  backend memcpys batches to RAM `$100000`), and the Amiga eject stub.
  Compile flags are the Amiga trio (`DISPLAY_FB_EXTERN`,
  `JW_BACKEND_EXTERN`, `AMIGA_BENCH` = bare-metal raw-CPUSHA).
- `tb_corpus.v` is a lean derivative of AP68040's
  `tb_ap040_program.v`: flat 4 MB RAM (16-bit, zero wait states),
  reset vectors at 0, no fault injection, MMU walker tied off. A word
  write of `$600D` to `$F00000` ends the run; the results window is
  dumped to a host file, NUL-stripped, and fed to
  `gen/score_vs_oracle.py` against the silicon capture.
- Cross-platform layout differences (this payload's symbols vs the
  Mac capture's) come out as the scorer's `layout` class; anything
  REAL is the core diverging from Quadra 800 silicon.

Simulation speed under iverilog is ~50k cycles/s: the 10-row smoke is
minutes, the full corpus a few hours. Verilator would cut that 20-100x
(the TB avoids hierarchical references for exactly that reason) — worth
doing before pointing the fpu/integration corpora at the core.

The suites beyond cpu need nothing new conceptually: fpu/integration/
saverestore payloads are the same Makefile pattern (link the other
bench mains), and mmu additionally needs the walker port wired to the
TB RAM. Wire them up when the cpu corpus is clean.
