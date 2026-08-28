#!/usr/bin/env python3
"""score_vs_oracle.py -- score a bench run against the Quadra 800 hardware
oracle captures. THE golden-baseline contract for wombat33 RTL bring-up.

Usage:
  score_vs_oracle.py <suite> <oracle.jsonl> <candidate.jsonl> [options]

  suite: cpu | fpu | integration | saverestore | mmu
  oracle:    a hardware capture (results/allinone/ or the singles)
  candidate: a device/RTL/emulator run of the SAME bench

Every mismatch is classified; only REAL diffs fail (exit 1):
  layout    a payload address shifted by the build's constant delta
            (finding 13/27) -- the delta is derived from the runs and
            applied only to values inside the payload window
  label     the retired "[040-unimpl->vec11]" FSGL name suffix (f22)
  golden    expected/pass differ but actual+vec agree: the host-side
            golden model changed between builds, machine behavior equal
            (e.g. the FDBcc fix, finding 26)
  fp-policy vec 11 vs execution on an 040-unimplemented FP op (FINT/
            FINTRZ trap on silicon, finding 22) -- a full-FPU core
            legitimately differs; decide per core, not a bench fail
  fpiar     FPIAR width: silicon keeps low 16 bits of an FMOVE.L
            data-register write (finding 26)
  ccr       undefined CCR bits (ABCD/SBCD/NBCD: N,V; CHK: Z,V,C;
            DIVx overflow: N,Z) under --ccr-policy arch (default);
            --ccr-policy silicon compares them exactly
  aexc      FPSR accrued-exception byte, only under --mask-aexc (use
            when the candidate did not run the full corpus in order --
            AEXC is sticky across rows, finding 27 close-out)
  env       mmu: a non-targeted MMU register differs (platform
            handoff state, finding 22)
  frame     mmu: fault-frame window bytes (contain payload PCs)
"""
import argparse
import json
import re
import sys

PAYLOAD_LO, PAYLOAD_HI = 0x40000, 0x80000
FSGL_SUFFIX = " [040-unimpl->vec11]"
FPSR_AEXC = 0xF8

# vec-4/vec-8-style CCR undefined classes: (name regex, undefined mask,
# condition on the oracle ccr for the mask to apply, or None)
CCR_UNDEF = [
    (re.compile(r"\b(ABCD|SBCD|NBCD)\b"), 0x0A, None),          # N,V
    (re.compile(r"\b(CHK2|CMP2)\b"),      0x0A, None),          # N,V
    (re.compile(r"\bCHK\b"),              0x07, None),          # Z,V,C
    (re.compile(r"\bDIV[SU]\b"),          0x0C, lambda c: c & 2),  # N,Z on ovf
]


def load(path):
    raw = open(path, "rb").read().decode("latin1").replace("\0", "")
    rows = []
    for line in raw.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return rows


class Tally:
    def __init__(self, verbose):
        self.verbose = verbose
        self.match = 0
        self.classes = {}
        self.real = []

    def ok(self):
        self.match += 1

    def cls(self, kind, msg):
        self.classes[kind] = self.classes.get(kind, 0) + 1
        if self.verbose:
            print(f"{kind:10s} {msg}")

    def fail(self, msg):
        self.real.append(msg)
        print(f"REAL      {msg}")

    def report(self, n_rows):
        cl = ", ".join(f"{k} {v}" for k, v in sorted(self.classes.items()))
        print(f"\n{n_rows} rows: {self.match} field-groups match"
              + (f"; classified: {cl}" if cl else "")
              + f"; REAL diffs: {len(self.real)}")
        return 1 if self.real else 0


def base_name(n):
    return n[:-len(FSGL_SUFFIX)] if n.endswith(FSGL_SUFFIX) else n


def pair_rows(oracle, cand, t):
    if len(oracle) != len(cand):
        print(f"row count differs: oracle {len(oracle)}, candidate {len(cand)}")
    pairs = []
    for o, c in zip(oracle, cand):
        if base_name(o.get("name", "")) != base_name(c.get("name", "")):
            t.fail(f"row order diverges at oracle '{o.get('name')}' vs "
                   f"candidate '{c.get('name')}'")
            break
        if o.get("name") != c.get("name"):
            t.cls("label", o["name"])
        pairs.append((o, c))
    return pairs


def in_payload(v):
    return isinstance(v, int) and PAYLOAD_LO <= v < PAYLOAD_HI


def derive_delta(pairs, fields):
    """The single constant payload shift between the two builds."""
    deltas = set()
    for o, c in pairs:
        so = o.get("final") or o.get("trap_state") or {}
        sc = c.get("final") or c.get("trap_state") or {}
        for f in fields:
            vo, vc = so.get(f), sc.get(f)
            if isinstance(vo, list):
                for x, y in zip(vo, vc or []):
                    if x != y and in_payload(x):
                        deltas.add(y - x)
            elif vo is not None and vo != vc and in_payload(vo):
                deltas.add(vc - vo)
    if len(deltas) > 1:
        sys.exit(f"cannot normalize: multiple payload deltas {sorted(deltas)}")
    return deltas.pop() if deltas else 0


def scalar(t, row, field, vo, vc, delta):
    if vo == vc:
        t.ok()
    elif in_payload(vo) and vc == vo + delta:
        t.cls("layout", f"{row} {field}: {vo:#x} -> {vc:#x}")
    else:
        t.fail(f"{row} {field}: oracle {vo} candidate {vc}")


def ram_bytes(t, row, bo, bc, delta):
    if bo == bc:
        t.ok()
        return
    bad = []
    for off in range(0, min(len(bo), len(bc)) & ~3, 4):
        wo = bo[off:off + 4]
        wc = bc[off:off + 4]
        if wo == wc:
            continue
        io = int.from_bytes(bytes(wo), "big")
        ic = int.from_bytes(bytes(wc), "big")
        if in_payload(io) and ic == io + delta:
            t.cls("layout", f"{row} ram+{off:#x}: {io:#x} -> {ic:#x}")
        else:
            bad.append(off)
    if len(bo) != len(bc):
        bad.append("length")
    if bad:
        t.fail(f"{row} ram: unexplained diffs at {bad[:8]}")
    else:
        t.ok()


def ccr_check(t, name, vo, vc, policy):
    if vo == vc:
        t.ok()
        return
    if policy == "arch":
        for rx, mask, cond in CCR_UNDEF:
            if rx.search(name) and (cond is None or cond(vo)):
                if (vo & ~mask) == (vc & ~mask):
                    t.cls("ccr", f"{name} ccr: {vo:#x} vs {vc:#x} "
                                 f"(undefined bits {mask:#x})")
                    return
                break
    t.fail(f"{name} ccr: oracle {vo:#x} candidate {vc:#x}")


def score_cpu(oracle, cand, args, t):
    pairs = pair_rows(oracle, cand, t)
    delta = derive_delta(pairs, ("pc", "a"))
    if delta:
        print(f"payload layout delta: {delta:+#x}")
    for o, c in pairs:
        n = o["name"]
        if o.get("vec", 0) != c.get("vec", 0):
            t.fail(f"{n} vec: oracle {o.get('vec')} candidate {c.get('vec')}")
            continue
        ko = "final" if "final" in o else "trap_state"
        kc = "final" if "final" in c else "trap_state"
        if ko != kc:
            t.fail(f"{n}: state kind {ko} vs {kc}")
            continue
        so, sc = o[ko], c[kc]
        if "ccr" in so:
            ccr_check(t, n, so["ccr"], sc.get("ccr"), args.ccr_policy)
        for f in ("pc",):
            if f in so:
                scalar(t, n, f, so[f], sc.get(f), delta)
        for f in ("d", "a"):
            for i, (vo, vc) in enumerate(zip(so.get(f, []), sc.get(f, []))):
                scalar(t, n, f"{f}{i}", vo, vc, delta)
        if "ram" in so:
            ram_bytes(t, n, so["ram"], sc.get("ram", []), delta)
    return t.report(len(pairs))


def score_fpu(oracle, cand, args, t):
    pairs = pair_rows(oracle, cand, t)
    delta = derive_delta(pairs, ("a", "fpiar"))
    if delta:
        print(f"payload layout delta: {delta:+#x}")
    for o, c in pairs:
        n = base_name(o["name"])
        if o.get("vec", 0) != c.get("vec", 0):
            vo, vc = o.get("vec", 0), c.get("vec", 0)
            if 11 in (vo, vc) and 0 in (vo, vc):
                t.cls("fp-policy", f"{n}: vec {vo} vs {vc}")
            else:
                t.fail(f"{n} vec: oracle {vo} candidate {vc}")
            continue
        ko = "final" if "final" in o else "trap_state"
        so, sc = o.get(ko, {}), c.get(ko, {})
        for f in ("d", "a"):
            for i, (vo, vc) in enumerate(zip(so.get(f, []), sc.get(f, []))):
                scalar(t, n, f"{f}{i}", vo, vc, delta)
        if so.get("fp") != sc.get("fp"):
            t.fail(f"{n} fp registers differ")
        else:
            t.ok()
        scalar(t, n, "fpcr", so.get("fpcr"), sc.get("fpcr"), 0)
        scalar(t, n, "fpiar", so.get("fpiar"), sc.get("fpiar"), delta)
        vo, vc = so.get("fpsr"), sc.get("fpsr")
        if vo == vc:
            t.ok()
        elif args.mask_aexc and (vo & ~FPSR_AEXC) == (vc & ~FPSR_AEXC):
            t.cls("aexc", f"{n} fpsr: {vo:#x} vs {vc:#x}")
        else:
            t.fail(f"{n} fpsr: oracle {vo:#x} candidate {vc:#x}")
    return t.report(len(pairs))


def score_selfscored(oracle, cand, args, t):
    pairs = pair_rows(oracle, cand, t)
    for o, c in pairs:
        n = o["name"]
        vo, vc = o.get("vec", 0), c.get("vec", 0)
        if vo != vc:
            if 11 in (vo, vc) and 0 in (vo, vc):
                t.cls("fp-policy", f"{n}: vec {vo} vs {vc}")
            else:
                t.fail(f"{n} vec: oracle {vo} candidate {vc}")
            continue
        if o.get("actual") != c.get("actual"):
            if "FPIAR" in n and (o.get("actual", 0) & 0xFFFF) == \
                               (c.get("actual", 0) & 0xFFFF):
                t.cls("fpiar", f"{n}: actual {o.get('actual')} vs "
                               f"{c.get('actual')} (low 16 agree)")
            else:
                t.fail(f"{n} actual: oracle {o.get('actual')} candidate "
                       f"{c.get('actual')}")
            continue
        if o.get("expected") != c.get("expected") or o.get("pass") != c.get("pass"):
            t.cls("golden", f"{n}: expected {o.get('expected')} vs "
                            f"{c.get('expected')} (actual agrees)")
        else:
            t.ok()
    return t.report(len(pairs))


MMU_TARGET = re.compile(r"MOVEC (TC|ITT0|ITT1|DTT0|DTT1|URP|SRP|MMUSR)\b")


def score_mmu(oracle, cand, args, t):
    def split(rows):
        reloc = {}
        out = []
        for r in rows:
            if "reloc" in r:
                reloc = r["reloc"]
            elif "name" in r:
                out.append(r)
        return reloc, out

    ro, oracle = split(oracle)
    rc, cand = split(cand)
    shifts = {k: rc.get(k, v) - v for k, v in ro.items()}
    if any(shifts.values()):
        print(f"reloc shifts: {shifts}")

    def translated(v):
        # a payload-space value moved by its region's reloc shift
        for k, base in ro.items():
            size = 0x1000 if k not in ("data",) else 0x40
            if base <= v < base + size:
                return v + shifts.get(k, 0)
        return v

    pairs = pair_rows(oracle, cand, t)
    for o, c in pairs:
        n = o["name"][:48]
        if bool(o.get("skipped")) != bool(c.get("skipped")):
            t.fail(f"{n}: skipped {o.get('skipped')} vs {c.get('skipped')}")
            continue
        if o.get("skipped"):
            t.ok()
            continue
        if o.get("vec", 0) != c.get("vec", 0):
            t.fail(f"{n} vec: oracle {o.get('vec')} candidate {c.get('vec')}")
            continue
        so, sc = o.get("final", {}), c.get("final", {})
        for f in ("d", "a"):
            for i, (vo, vc) in enumerate(zip(so.get(f, []), sc.get(f, []))):
                if vo == vc or translated(vo) == vc:
                    t.ok()
                else:
                    t.fail(f"{n} {f}{i}: oracle {vo:#x} candidate {vc:#x}")
        mo, mc = so.get("mmu", {}), sc.get("mmu", {})
        target = MMU_TARGET.search(o["name"])
        target = target.group(1).lower() if target else None
        for k in sorted(set(mo) | set(mc)):
            vo, vc = mo.get(k), mc.get(k)
            if vo == vc or (k in ("urp", "srp") and translated(vo) == vc):
                t.ok()
            elif target and k != target:
                t.cls("env", f"{n} mmu.{k}: {vo:#x} vs {vc:#x} (not the "
                             f"row's target register)")
            else:
                t.fail(f"{n} mmu.{k}: oracle {vo:#x} candidate {vc:#x}")
        wo = {w["base"]: w["bytes"] for w in o.get("windows", [])}
        wc = {w["base"]: w["bytes"] for w in c.get("windows", [])}
        for base in sorted(set(wo) | set(wc)):
            if 0x3FF00 <= base < 0x40000:
                if wo.get(base) != wc.get(base):
                    t.cls("frame", f"{n} window {base:#x} (fault frame)")
                else:
                    t.ok()
            elif wo.get(base) != wc.get(base):
                t.fail(f"{n} window {base:#x} differs")
            else:
                t.ok()
    return t.report(len(pairs))


SUITES = {"cpu": score_cpu, "fpu": score_fpu, "integration": score_selfscored,
          "saverestore": score_selfscored, "mmu": score_mmu}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("suite", choices=sorted(SUITES))
    ap.add_argument("oracle")
    ap.add_argument("candidate")
    ap.add_argument("--ccr-policy", choices=("arch", "silicon"), default="arch")
    ap.add_argument("--mask-aexc", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    t = Tally(args.verbose)
    return SUITES[args.suite](load(args.oracle), load(args.candidate), args, t)


if __name__ == "__main__":
    sys.exit(main())
