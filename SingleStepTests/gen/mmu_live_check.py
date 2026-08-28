#!/usr/bin/env python3
"""Compare a device MMU-full /Results.jsonl against the MAME baseline.

The device runner relocates the corpus world (finding 24), so descriptor
ADDRESS bytes differ by construction; this checks what is comparable:
descriptor FLAG bytes (U/M/W/resident writebacks), stored data, vec, and
MMUSR presence. Known oracle-artifact classes are labeled, not failed:
  - atc: MAME models no ATC (its "stale" rows re-walk; silicon/QEMU hold
    the old translation) — silicon adjudicates.
  - vecbase: the capture ran vectors at VA 0, so its fault rows set U on
    page[0]; the bench's VBR lives in the payload.

Usage: mmu_live_check.py <mame_baseline.json> <device_results.jsonl>
"""
import json, sys

def load_device(path):
    out = {}
    raw = open(path, 'rb').read().decode('latin1').replace('\0', '')
    for line in raw.splitlines():
        if not line.strip():
            continue
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            continue
        if 'name' in r:
            out[r['name']] = r
    return out

def winbyte(row, addr):
    for w in row.get('windows', []):
        b = w['base']
        if b <= addr < b + len(w['bytes']):
            return w['bytes'][addr - b]
    return None

def classify(name, addr):
    if 'ATC stale' in name:
        return 'atc'
    if addr == 0x3403:
        return 'vecbase'
    return None

def main():
    base_path, dev_path = sys.argv[1], sys.argv[2]
    base = {r['name']: r for r in
            (json.loads(l) for l in open(base_path) if l.strip())}
    dev = load_device(dev_path)

    ran = sum(1 for r in dev.values() if not r.get('skipped'))
    print(f"device rows: {len(dev)} ({ran} ran)")

    ok = diff = labeled = 0
    for name, b in base.items():
        m = dev.get(name)
        if not m or not b['flags'].get('mmu_live') or m.get('skipped'):
            continue
        exp_vec = 2 if b['flags'].get('raises_exception') else 0
        if m.get('vec') != exp_vec:
            print(f"VEC {name[:52]}: device {m.get('vec')} vs baseline-model {exp_vec}"
                  f"  (hardware adjudication if PTEST/supervisor row)")
        for addr, val in b['final']['ram']:
            if 0x3FF00 <= addr < 0x40000:
                continue                     # fault frames differ by design
            if 0x3000 <= addr < 0x3500 and (addr & 3) != 3:
                continue                     # descriptor address bytes relocated
            mv = winbyte(m, addr)
            if mv is None:
                continue
            tag = classify(name, addr)
            if mv == val:
                ok += 1
            elif tag:
                labeled += 1
                print(f"{tag:8s} {name[:44]} @{addr:#x}: base {val:#04x} dev {mv:#04x}")
            else:
                diff += 1
                print(f"DIFF     {name[:44]} @{addr:#x}: base {val:#04x} dev {mv:#04x}")
        mm = m.get('final', {}).get('mmu', {})
        if 'PTEST' in name:
            print(f"MMUSR    {name[:44]}: {mm.get('mmusr', 0):#010x} (hw-adjudicated)")
    print(f"\nflag/data bytes: {ok} match, {labeled} known-artifact, {diff} REAL diffs")

if __name__ == '__main__':
    main()
