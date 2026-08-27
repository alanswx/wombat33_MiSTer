#!/usr/bin/env python3
"""Recursive-descent m68k disassembler.

A linear sweep of a ROM decodes data as garbage instructions and loses
sync for pages afterwards. This follows control flow from a set of entry
points instead, so what comes out is code that is actually reachable,
with everything else reported as data.

    m68k_rdisasm.py IMAGE --base 0x40800000 --entry 0x40800000 [...] \
        [--vectors] [--out listing.asm]

--vectors treats the image as starting with a 68k exception vector table
and seeds entry points from it.
"""
import argparse
import sys
from capstone import (Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_040,
                      CS_GRP_JUMP, CS_GRP_CALL, CS_GRP_RET, CS_GRP_IRET)

# instructions after which linear flow does not continue
STOP = {"rts", "rte", "rtr", "rtd", "jmp", "bra", "bras", "braw", "bral",
        "illegal", "stop", "reset", "halt"}
# instructions whose target should be queued but which also fall through
CALLISH = {"bsr", "bsrs", "bsrw", "bsrl", "jsr"}


def target_of(insn):
    """Resolve a branch/call target when it is a plain absolute address."""
    op = insn.op_str.strip()
    for tok in (op.split(",")[0].strip(), op):
        t = tok.strip()
        if t.startswith("$"):
            t = t[1:]
        elif t.startswith("0x"):
            t = t[2:]
        else:
            continue
        t = t.split("(")[0].strip()
        try:
            return int(t, 16)
        except ValueError:
            continue
    return None


def disassemble(data, base, entries, limit=4_000_000):
    md = Cs(CS_ARCH_M68K, CS_MODE_BIG_ENDIAN | CS_MODE_M68K_040)
    md.detail = True
    md.skipdata = False             # undecodable bytes must fail, not decode
    end = base + len(data)

    code = {}                       # addr -> (size, text)
    seen = set()
    work = list(entries)
    queued = set(entries)
    steps = 0

    while work:
        pc = work.pop()
        while base <= pc < end and steps < limit:
            if pc in code:
                break
            off = pc - base
            chunk = data[off:off + 16]
            insns = list(md.disasm(chunk, pc, count=1))
            if not insns:
                break                       # undecodable -> treat as data
            ins = insns[0]
            steps += 1
            code[pc] = (ins.size, f"{ins.mnemonic} {ins.op_str}".strip())
            for b in range(pc, pc + ins.size):
                seen.add(b)

            mnem = ins.mnemonic.lower()
            try:
                groups = set(ins.groups or ())
            except Exception:
                groups = set()          # capstone raises on non-code
                if mnem in ("data", ".data", "dc.w"):
                    del code[pc]
                    break
            is_call = mnem in CALLISH or CS_GRP_CALL in groups
            is_jump = mnem in STOP or CS_GRP_JUMP in groups
            is_ret = CS_GRP_RET in groups or CS_GRP_IRET in groups

            tgt = target_of(ins) if (is_call or is_jump) else None
            if tgt is not None and base <= tgt < end and tgt not in queued:
                queued.add(tgt)
                work.append(tgt)

            if is_ret or mnem in STOP:
                break                       # flow ends here
            pc += ins.size
    return code, seen, steps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--base", type=lambda x: int(x, 0), required=True)
    ap.add_argument("--entry", type=lambda x: int(x, 0), action="append",
                    default=[])
    ap.add_argument("--vectors", action="store_true",
                    help="seed entries from a 68k vector table at offset 0")
    ap.add_argument("--scan-pointers", action="store_true",
                    help="seed at every longword that holds an address "
                         "inside the image (jump/dispatch tables)")
    ap.add_argument("--scan-prologues", action="store_true",
                    help="also seed at every LINK A6 / MOVEM.L -(SP) / "
                         "JMP-table-looking word. Heuristic: a seed only "
                         "survives if it decodes, but false seeds are "
                         "possible, so treat prologue-seeded code as "
                         "lower confidence than vector-reached code.")
    ap.add_argument("--out", default="-")
    args = ap.parse_args()

    data = open(args.image, "rb").read()
    entries = list(args.entry)

    if args.vectors:
        for v in range(64):
            a = int.from_bytes(data[v * 4:v * 4 + 4], "big")
            if args.base <= a < args.base + len(data):
                entries.append(a)

    if args.scan_pointers:
        # Any longword holding an address inside this image is almost
        # always a jump-table / dispatch-table entry. Mac ROMs are full
        # of them and they are the only way to reach trap-dispatched code
        # statically.
        for off in range(0, len(data) - 3, 2):
            a = int.from_bytes(data[off:off + 4], "big")
            if args.base <= a < args.base + len(data) and (a & 1) == 0:
                entries.append(a)

    if args.scan_prologues:
        # 4E56 = LINK A6,#d16 ; 48E7 = MOVEM.L <regs>,-(SP) ; 4E75 = RTS,
        # so the word after an RTS is very often a function start.
        for off in range(0, len(data) - 1, 2):
            w = int.from_bytes(data[off:off + 2], "big")
            if w in (0x4E56, 0x48E7):
                entries.append(args.base + off)
            elif w == 0x4E75 and off + 2 < len(data):
                entries.append(args.base + off + 2)

    if not entries:
        entries = [args.base]

    code, seen, steps = disassemble(data, args.base, entries)

    out = sys.stdout if args.out == "-" else open(args.out, "w")
    cov = 100.0 * len(seen) / len(data) if data else 0
    print(f"; recursive-descent disassembly of {args.image}", file=out)
    print(f"; base=0x{args.base:08X} size={len(data)} "
          f"entries={len(set(entries))}", file=out)
    print(f"; decoded {len(code)} instructions, {len(seen)} bytes "
          f"({cov:.1f}% of image) in {steps} steps", file=out)
    print(";", file=out)

    addr = args.base
    end = args.base + len(data)
    while addr < end:
        if addr in code:
            size, text = code[addr]
            raw = data[addr - args.base: addr - args.base + size].hex()
            print(f"{addr:08X}:  {raw:<20s} {text}", file=out)
            addr += size
        else:
            run = addr
            while run < end and run not in code:
                run += 1
            n = run - addr
            print(f"{addr:08X}:  ; ==== {n} bytes not reached as code ====",
                  file=out)
            # emit every byte so the listing accounts for 100% of the image
            for line in range(addr, run, 16):
                blk = data[line - args.base:min(line + 16, run) - args.base]
                hx = " ".join(f"{b:02x}" for b in blk)
                asc = "".join(chr(b) if 32 <= b < 127 else "." for b in blk)
                print(f"{line:08X}:  {hx:<47s} |{asc}|", file=out)
            addr = run
    if out is not sys.stdout:
        out.close()
    print(f"decoded {len(code)} insns, {cov:.1f}% coverage", file=sys.stderr)


if __name__ == "__main__":
    main()
