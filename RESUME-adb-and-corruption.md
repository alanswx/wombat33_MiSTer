# RESUME — ADB phantom input, the "corruption", and the bench stall

Open faults on the Quadra 800 core after the 2026-08-29/30 session. Read this
before touching `rtl/iosb.sv`, `rtl/adb.sv`, or believing any hang report.

Fixed and verified this session (do not re-investigate): SCSI non-DMA
transfer-info underflow, `SC0` mount persistence, mount replay across reset,
RAM-size-on-reset, build/deploy timing gate, and the RTC (both halves).

## Ground rules, learned expensively

- **Never reload the core or reset the machine while Mac OS is running.** It is
  a power-cut on a mounted HFS volume. Doing it repeatedly is what made the
  Quad Squad image unbootable, and those hangs were then misdiagnosed as RTL
  faults more than once.
- **A hang proves nothing until the disk is known-good.** Restore from
  `games/Wombat33/backup/QuadSquad8.hda.gz` (md5
  `f4287aee9ff9a4413fa1e5fd9f2d63b4`) and re-test before believing one.
- **Suspect your own last change first, and run the control.** The CPU patch
  below was blamed for a stall it did not cause, because the stock-CPU control
  was not run before the conclusion was written down.
- **Measure rates, not single samples.** The RTC looked "seeded but an hour off"
  from one screenshot; it was actually frozen, which is a different bug.
- Liveness check that beats screenshots: `pos:` from
  `/proc/<MiSTer-pid>/fdinfo/<fd-of-the-image>` (find the fd by scanning
  `/proc/*/fd`). Moving = doing SCSI. **Frozen ≠ hung**: `pos=1986560` is the
  normal idle-desktop value, because an idle Finder does not read.
- mrext motion pacing: **0.02 s** tracks 1:1. 0.008 s outruns the ~90 Hz ADB
  poll and moves are silently dropped.

## Fault 1 — ADB phantom input (OPEN, reproducible on demand)

**Symptom.** Mouse motion injects keystrokes. Reproduce: 240 `mouseMove`
messages and nothing else makes Photoshop's palettes vanish (its Tab shortcut)
and opens the File menu. Separately, **button presses never reach the guest** —
an open menu will not dismiss on a click — while motion works.

**mrext is not the cause**: its log for the day shows 2,349 `mouseMove`, 13
`mouseBtn`, zero `kbd` (`grep "received message" /tmp/remote.log`).

**Established.**

- `rtl/adb.sv` is byte-identical to lbmactwo's working copy, so the fault is in
  wombat33's shim in `rtl/iosb.sv`.
- `adb.sv` is *correct* with nothing to report: empty response (`resp_len = 0`)
  plus `_int`. Only the shim invents a byte.
- `via6522.sv:190` — `irq_events[2] = serial_event | sr_ext_complete` — so every
  `sr_ext_complete` raises the VIA1 shift-register interrupt. The shim's idle
  heartbeat fires it at the ADB driver every ~11 ms whether or not the ROM armed
  a shift, and the driver consumes each as a real device response.
- Instrumented in sim: **all 338 fallback completions in a boot window fired
  with the ADB bus IDLE (`st=11`) and no interrupt asserted** — completions the
  real PIC would never clock, since it only clocks CB1 when it has data.
- `ps2_mouse` decode is correct (`mouseBtn_s1 <= ps2_mouse[0]`, identical to
  lbmactwo), so the button failure is not a decode error.

**Two fixes tried, both insufficient — do not simply retry them.**

1. `$FF` instead of stale `kbd_to_mac` (`24eefbc`, reverted). Actively wrong: an
   ADB mouse Talk R0 is `{~button, dy}` / `{1, dx}` with **7-bit signed** deltas,
   so `$FF` = dx −1, dy −1 at ~90 Hz — a permanently drifting cursor, observed on
   hardware. `$00` would be a phantom button-down. **No invented byte is safe**,
   which is the point: the completion itself is the defect.
2. Gating the fallback on `via1_sr_active` (`00a0721`, still in tree). Did not
   stop the phantom keys. lbmactwo's own comment says the shim exists *because*
   "SR arming itself has verilator timing issues with wen/falling overlap", so
   `sr_active` may be high whenever the fallback runs — **measure it** rather
   than assuming the gate does anything.

**Next steps.**

- Split the ~23k surplus deliveries into fresh vs stale, logging `st`,
  `sr_active` and `adb_int_n` at each. Tooling is ready: `sim_main.cpp` now takes
  `+mousebtn=N` (holds/releases the button across runs of wiggle reports)
  alongside `+mousewiggle=N`; `~/adbC` in WSL is an instrumented tree.
- **The button failure is the sharper lead.** Button and Y delta are in the same
  byte (`adb.sv:243`), so working motion proves the byte arrives — find why
  `mouseButton` never gets there as 1 and the keystrokes likely follow.
- Consider completing the shift **without** `sr_ext_load` (interrupt, no new
  byte), which is closer to hardware when the PIC does not clock.

## Fault 2 — the "corruption" is NOT corruption (diagnosis corrected)

**The hang sector is byte-identical to pristine.** Sector 1,437,035 (offset
735,761,920) compared between a booted image and the pristine backup: identical,
and it contains valid 68k code (`a06e` traps, `4eb9` JSRs). Nothing wrote
garbage there. **735,761,920 is simply where reading stopped.**

**Why first-boot-works / later-boot-hangs:** after a hard reset HFS is flagged
not-cleanly-unmounted, so the next boot runs a volume check — far more I/O — and
that extra traffic trips the real fault. The pattern is about *how much gets
read*, not about damaged bytes.

So the open question is a **read-path stall under sustained I/O**, not data
corruption. The P1 write-path gap in `docs/scsi/rtl-gap-analysis.md`
("data-out only flushes at exactly `sbuf_pos == 512`") is *not* implicated by
this evidence and should not be assumed.

Note `chmod 444` cannot make the image read-only — exFAT carries no Unix
permission bits (mount uses `fmask=0022`). Find another route if you want a
write-free control.

## Fault 3 — the bench does not run on this core (OPEN, and NOT SCSI)

`SingleStepTests/prebuilt/quadra800-allinone-2026-08-28b.tgz` stalls early. The
control matrix is unambiguous:

| | hardware | Verilator |
|---|---|---|
| stock CPU | stalls, `pos=65536` | stalls, `ncr=2042`, last `lba=97` |
| patched CPU | stalls, `pos=65536` | stalls, `ncr=2042`, last `lba=97` |

**It is not a SCSI wedge.** The last transaction completes textbook clean: read
`lba=97`, 512 bytes, status phase, `cmd=11` command-complete, `cmd=12` message
accepted, `INT+ ist=20 ph=0`, bus idle. The engine is healthy and **idle** — the
driver simply stops issuing commands. This is a software/CPU-side stop.

Caveat on the sim half: those runs used the **hardware-flavor** image, which
`RESUME-disk-gate.md` says needs `make-emulator-gate-disk.sh` re-blessing to boot
under sim at all — so sim may be stalling for that reason instead. Re-blessing
needs `m68k-elf-as`, `jq` and `rb-cli`, none installed in WSL.

Results land at byte 715776 (LBA 1398), 1 MB, per the manifest; then
`gen/split_allinone_results.py` and `gen/score_vs_oracle.py {suite} <oracle>`
with **no** `--flat-env`.

## Reverted, unverified — the AP68040 memory-indirect patch

`docs/ap68040-memind-reserved.md` + `.patch`. `ap040_core.v` raises vector 4 for
full-extension encodings with `IS=1` and `I/IS[2]=1`; real silicon executes them
(`vec: 0` in the hardware capture), with a 4/4 correlation between the guard term
and the two failing corpus rows.

**It was wrongly recorded as regressing hardware.** The stock-CPU control shows
the bench stalls identically without it (table above). The patch is therefore
**unverified, not disproven** — reverted, submodule clean at `0e76761`, report
not to be sent as "verified" until a scored gate exists. That gate is blocked on
Fault 3.

## Fixed this session — RTC (both halves)

Recorded because the first fix hid the second:

1. The RTC was never seeded — `seconds` started at the 1904 epoch, hence
   "Fri 12:00". Now `hps_io TIMESTAMP` → `quadra800` → `iosb` → `rtc3430042`,
   seeded once from `timestamp + 2082844800`, MacLC's pattern.
2. `.ca2_i` was tied to `1'b0`. VIA1 CA2 is the one-second interrupt Mac OS uses
   to advance its clock; with it dead the OS read the RTC once and never ticked.
   Now derived from 60 CA1 periods (`dataController_top.sv:729`).

Verified on hardware: host 17:14 → Mac 4:14, host 17:20 → Mac 4:20, and the
screensaver fires on its idle timeout (impossible with a frozen time base).
Byte order was checked against MAME `macrtc.cpp:154` first — `m_seconds[0]` is
LSB, matching `sec_q` — because wombat33 uses the bit-banged 343-0042 while
MacLC uses Egret.

**Still open:** the Mac reads exactly **one hour behind** (minutes dead-on), i.e.
standard vs daylight time in what the Main sends. Probably host-side config
rather than a core bug — the core reflects `TIMESTAMP` faithfully. Check
MacLC's clock on the same machine: if MacLC is correct, the difference is ours.

## Machine state

- `games/Wombat33/QuadSquad8.hda`, pristine (`f4287aee…`); slot 0 points at it.
  Backups: `backup/QuadSquad8.hda.gz` (pristine) and
  `backup/QuadSquad8_dirty_20260830.hda.gz` (a volume that reproduces Fault 2).
- `games/Wombat33/gate.hda` is the `2026-08-28b` bench image.
- **`.143` runs a Main started by hand** so its log lands in `/tmp/mister.log`.
  A reboot restores the inittab-started one — note inittab starts it once and
  does *not* respawn it, so do not kill it without restarting it.
- `/tmp` on the MiSTer is a 247 MB tmpfs; do not decompress the 2 GB image there.
