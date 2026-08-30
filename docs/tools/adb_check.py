#!/usr/bin/env python3
"""Score an +adbtrace log: does the byte the driver READS match the byte the
shim DELIVERED?

Pairs every `DLV FRESH/STALE xx` with the next `SRR yy` and reports the
mismatch rate, plus a histogram of (delivered -> read).  A healthy core is 100%
match; with the VIA shift-clock bug every pair is (byte -> byte<<1).

  python3 adb_check.py <trace.log>
"""
import re
import sys
from collections import Counter

dlv = re.compile(r"^\[(\d+)\] DLV  (FRESH|STALE) ([0-9a-f]{2})")
srr = re.compile(r"^\[(\d+)\] SRR  ([0-9a-f]{2})")
out = re.compile(r"^\[(\d+)\] OUT  ([0-9a-f]{2}) idx=(\d+)")
# a shift-OUT completion, or the CPU writing SR, replaces the shift register's
# contents: anything the shim delivered before it is gone, so don't pair across
# one -- the SR read that follows is the driver's own byte echoed back.
drop = re.compile(r"^\[(\d+)\] (DLV  OUT|SRW )")

pending = None
pairs = Counter()
match = miss = 0
unread = 0
real_out = 0

for line in open(sys.argv[1], errors="replace"):
    m = dlv.match(line)
    if m:
        if pending is not None:
            unread += 1
        pending = (m.group(2), int(m.group(3), 16))
        continue
    m = srr.match(line)
    if m:
        if pending is None:
            continue
        kind, sent = pending
        got = int(m.group(2), 16)
        pending = None
        pairs[(sent, got)] += 1
        if sent == got:
            match += 1
        else:
            miss += 1
        continue
    if drop.match(line):
        pending = None
        continue
    if out.match(line):
        real_out += 1

tot = match + miss
# $00 pairs are uninformative: 0 << 1 is still 0, so they match either way.
info = sum(n for (s, g), n in pairs.items() if s)
info_ok = sum(n for (s, g), n in pairs.items() if s and s == g)

print(f"delivered->read pairs : {tot}")
print(f"  match               : {match}"
      + (f"  ({100.0*match/tot:.1f}%)" if tot else ""))
print(f"  mismatch            : {miss}"
      + (f"  ({100.0*miss/tot:.1f}%)" if tot else ""))
print(f"  non-zero bytes      : {info_ok}/{info} intact"
      + (f"  ({100.0*info_ok/info:.1f}%)" if info else ""))
print(f"  delivered, never read: {unread}")
print(f"real device bytes (adb.sv OUT, non-empty): {real_out}")
print("\ntop delivered->read pairs:")
for (s, g), n in pairs.most_common(12):
    tag = "ok" if s == g else ("<<1" if ((s << 1) & 0xFF) == g else "??")
    print(f"  {s:02x} -> {g:02x}  x{n:<6d} {tag}")
