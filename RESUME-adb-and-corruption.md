# RESUME — ADB phantom input, and disk corruption

Two open faults on the Quadra 800 core, plus one reverted CPU patch. Written
2026-08-30. Read this before touching `rtl/iosb.sv`, `rtl/adb.sv` or the SCSI
write path.

## Ground rules learned the hard way

- **Never reload the core, or reset the machine, while Mac OS is running.** It
  is a power-cut on a mounted HFS volume. Doing it repeatedly corrupted the
  Quad Squad image until it hung mid-boot at a repeatable offset, and that hang
  was then misdiagnosed as an RTL fault more than once. Shut down from inside
  (Special → Shut Down) first.
- **A hang is not evidence of an RTL bug until the disk is known-good.**
  Restore from `games/Wombat33/backup/QuadSquad8.hda.gz`
  (md5 `f4287aee9ff9a4413fa1e5fd9f2d63b4`) and re-test before believing one.
- **Suspect your own most recent change first.** See the CPU patch below.
- Liveness check that beats screenshots: read `pos:` from
  `/proc/<MiSTer-pid>/fdinfo/<fd-of-the-image>`. Moving = still doing SCSI.
  Frozen = wedged. Find the fd by scanning `/proc/*/fd` for the image name.
- Motion pacing over mrext: **0.02 s** between events tracks 1:1. 0.008 s
  outruns the ~90 Hz ADB poll and moves are silently dropped.

## Fault 1 — ADB phantom input (OPEN, reproducible on demand)

**Symptom.** Moving the mouse injects keystrokes. Reproduced deliberately: 240
`mouseMove` messages and nothing else made Photoshop's palettes vanish (its Tab
shortcut) and opened the File menu. Also, **mouse button presses do not reach
the guest at all** — an open menu will not dismiss on a click — while motion
works. Both are almost certainly the same defect.

**mrext is not the cause.** Its log for the day shows 2,349 `mouseMove`, 13
`mouseBtn`, and zero `kbd` messages (`grep "received message" /tmp/remote.log`).

**What is established.**

- `rtl/adb.sv` is byte-identical to lbmactwo's working copy. The fault is in
  wombat33's shim in `rtl/iosb.sv`, not the transceiver.
- `adb.sv` is *correct* when a device has nothing to report: it returns an empty
  response (`resp_len = 0`) and raises `_int`. Only the shim invents a byte.
- `via6522.sv:190` is `irq_events[2] = serial_event | sr_ext_complete`, so every
  `sr_ext_complete` raises the VIA1 shift-register interrupt. The shim's idle
  heartbeat fires that at the ADB driver roughly every 11 ms whether or not the
  ROM armed a shift, and the driver consumes each one as a real device response.
- Instrumented in sim: **all 338 fallback completions in a boot window fired
  with the ADB bus IDLE (`st=11`) and no interrupt asserted** — completions the
  real PIC would never have clocked, since it only clocks CB1 when it has data.

**Two fixes tried, neither sufficient.**

1. `$FF` instead of the stale `kbd_to_mac` in the fallback (`24eefbc`). Wrong,
   and it disproved itself: an ADB mouse Talk R0 is `{~button, dy}` / `{1, dx}`
   with **7-bit signed** deltas, so `$FF` reads as dx=-1, dy=-1 injected at
   ~90 Hz — a permanently drifting cursor, which is what the hardware then did.
   `$00` would be a phantom button-down. **There is no safe byte to invent**,
   which is the point: the completion itself is the defect.
2. Gating the fallback on `via1_sr_active` (`00a0721`). Did not stop the phantom
   keys. Note lbmactwo's own comment says the shim exists *because* "SR arming
   itself has verilator timing issues with wen/falling overlap", so `sr_active`
   may simply be high whenever the fallback runs — **measure it before trying
   this again**.

**Next steps.**

- Trace which of the ~23k surplus deliveries are fresh vs stale, with `st`,
  `sr_active` and `adb_int_n` captured at each. The tooling is in place:
  `verilator/sim_main.cpp` now takes `+mousebtn=N` (holds/releases the button
  across runs of wiggle reports) alongside `+mousewiggle=N`, so the button path
  can finally be exercised in sim. `~/adbC` in WSL has an instrumented tree.
- The button failure is the sharper lead: button and Y delta are in the **same
  byte** (`adb.sv:243`), so a byte that carries working motion must also carry
  the button. Find why `mouseButton` never reaches the guest as 1 and the
  keystroke question probably answers itself.
- Consider whether the fallback should complete the shift **without**
  `sr_ext_load` (interrupt but no new byte), which is closer to what real
  hardware does when the PIC does not clock.

## Fault 2 — disk corruption across boots (OPEN, cause unproven)

**Symptom.** A pristine image boots to the desktop; a later boot hangs with the
read offset frozen at **735,761,920** (LBA 1,437,035). Seen five times across
four builds, always the same offset.

**Do not conclude from this alone.** Much of this session's corruption was
self-inflicted by reloading the core mid-run (see ground rules). The open
question is whether *any* corruption remains once that is excluded.

**The one clean observation:** restore pristine → first boot reaches the desktop
→ reset → second boot hangs at that offset. If that reproduces with **no**
mid-run core reloads, the first boot's writes are damaging the volume, and the
prime suspect is the documented P1 in `docs/scsi/rtl-gap-analysis.md`:
*"Data-out only flushes at exactly `sbuf_pos == 512`; a transfer ending
mid-sector drops the tail"*. That would corrupt whatever HFS structure the
Finder writes on shutdown or first run.

**How to test it properly:** compare the image against pristine after exactly
one clean boot and dump the changed sectors — sane HFS updates versus garbage is
the whole question. exFAT cannot hold a read-only bit, so `chmod 444` does *not*
work for eliminating writes; find another way to get a read-only mount.

## Reverted — the AP68040 memory-indirect patch

`docs/ap68040-memind-reserved.md` + `.patch` identify a real decode difference
(AP68040 raises vector 4 for full-extension encodings with `IS=1` and
`I/IS[2]=1`; real silicon executes them, `vec=0` in the hardware capture; 4/4
correlation with the two failing corpus rows).

**But the patch regressed the bench on hardware** — it had run fine on this core
before, and with the patch it stalled after the happy Mac without completing the
payload read. The patch is reverted; the submodule is clean at `0e76761`. Do not
send the report upstream until the regression is understood — bisect it in the
Verilator gate, not on hardware.

## State of the machine

- Disk `games/Wombat33/QuadSquad8.hda`, pristine, md5 `f4287aee…`; slot 0
  points at it again. Backups: `backup/QuadSquad8.hda.gz` (pristine) and
  `backup/QuadSquad8_dirty_20260830.hda.gz` (this session's working state).
- `games/Wombat33/gate.hda` is the `2026-08-28b` bench image, left in place.
- **Beware:** `.143` is running a Main started by hand so its log lands in
  `/tmp/mister.log`. A reboot restores the inittab-started one; note inittab
  starts it once and does *not* respawn it.
