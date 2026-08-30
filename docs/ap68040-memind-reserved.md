# AP68040: reserved full-extension encodings trap where 68040 silicon executes

**Component:** `ap040_core.v` (AP68040), effective-address decode
**Severity:** wrong exception — instructions that run on real hardware take vector 4
**Found:** wombat33_MiSTer CPU acceptance gate, scored against a **real Quadra 800**
capture (`SingleStepTests/results/allinone/cpu_hardware_quadra800_2026-08-28.jsonl`)
**Patch:** `docs/ap68040-memind-reserved.patch` (one term removed from one line)

## Summary

For a 68020-style **full** extension word, `ap040_core.v` raises an illegal
instruction (vector 4) when the index is suppressed (`IS = 1`) and `I/IS[2] = 1`.
The M68000 PRM does mark that combination *reserved* — but **real 68040 silicon
executes it** and returns a value, so the guard is stricter than the part it
models.

This is the entire remaining CPU delta in the wombat33 gate: **2 REAL diffs out
of 717 rows / 13,585 field-groups**, both from this one term.

## The offending line

`ap040_core.v`, state `S_EA_EXTW2`:

```systemverilog
else if (extw[5:4] == 2'b00 || extw[3] ||
         extw[2:0] == 3'b100 || (extw[6] && extw[2])) begin
    go_illegal;
end
```

`extw[6]` is **IS** (index suppress); `extw[2]` is the top bit of **I/IS**. The
final term is the PRM's "if IS=1 then I/IS must be 0xx" rule. The other three
terms are correct and should stay.

## Evidence

Every memory-indirect row in the corpus, with its extension word decoded. The
guard fires on exactly the two rows that fail — a 4/4 correlation:

| test | extw | BS | IS | BD size | I/IS | guard fires | gate result |
|---|---|---|---|---|---|---|---|
| `MOVE.L ([bd.W,A6]),D1` | `0x0165` | 0 | **1** | word | **101** | **yes** | **FAIL** vec 4 |
| `MOVE.L ([bd.W,A6],D0.L*2,od.W),D1` | `0x0B26` | 0 | 0 | word | 110 | no | pass |
| `MOVE.L ([bd.W,A6,D0.L*2],od.W),D1` | `0x0B22` | 0 | 0 | word | 010 | no | pass |
| `MOVE.L ([bd.W=0,A6],od.W=4),D1` | `0x0166` | 0 | **1** | word | **110** | **yes** | **FAIL** vec 4 |

Silicon, from the hardware capture — all four report `"vec": 0`, i.e. **no
exception taken**. For row 1 the machine returned `D1 = 0x40809AE6` (a ROM
pointer that lives at `$1820` on a real Quadra; the value differs from the
synthetic `0xDEADCAFE` only because the bench read live low memory). The point
is the vector, not the datum: hardware executed, AP68040 trapped.

## Why removing the term is sufficient

The datapath already handles these encodings; only the guard rejects them. With
`IS = 1` the very next lines force the index to zero:

```systemverilog
ea_idx_v <= extw[6] ? 32'd0 : idx;   // IS = 1 -> index is 0
ea_post  <= extw[2];
```

and every later use of `ea_post` adds `ea_idx_v`, which is zero:

```systemverilog
// S_EA_BD
mrd(ea_base_v + bd + (ea_post ? 32'd0 : ea_idx_v), `AP040_SZ_L, S_EA_MIND);
// S_EA_MIND / S_EA_OD
ea_addr <= ea_mind + (ea_post ? ea_idx_v : 32'd0) + od;
```

So with the index suppressed, "pre-indexed" and "post-indexed" are
arithmetically **identical** — adding 0 either side of the indirection. That is
almost certainly why the real part does not bother to trap: the encoding is
harmless, and `I/IS[1:0]` still selects the outer-displacement size, which
`S_EA_MIND` already decodes (`01` null, `10` word, `11` long).

Dropping the term therefore makes the two rows execute and compute the correct
address, with no other change.

## Patch

`docs/ap68040-memind-reserved.patch`, generated against AP68040 `0e76761`. It
deletes `|| (extw[6] && extw[2])` and adds a comment recording why. The other
three illegality checks are untouched — `BD SIZE = 00`, `extw[3] != 0` and
`I/IS = 100` remain rejected.

## Caveats, stated plainly

- **Not verified on silicon as a fix.** The analysis is from the decode plus the
  hardware capture; the patched core has not yet been re-scored against the
  oracle. The wombat33 gate (`cpu` suite, no `--flat-env`) is the check, and
  should go from 2 REAL diffs to 0.
- **No evidence this causes the disk corruption** being chased separately in
  wombat33. An illegal-instruction trap is loud — a bomb or Sad Mac — not silent
  data damage. It is a real defect worth fixing on its own merits; it should not
  be assumed to be the corruption's cause without evidence.
- The reserved encodings are not something a compiler emits; this matters for
  hand-written or generated code that uses them, and for any test suite scored
  against silicon.
