# First hardware run — 2026-08-29, MiSTer at 192.168.99.143

The core was compiled and run on real hardware for the first time, off the
2 GB *Quad Squad* disk.

**It boots Mac OS all the way to the Finder desktop.** The first run wedged at
the "Starting Up…" splash; the cause was found in sim, fixed, and confirmed on
hardware the same session — see *Root cause* below.

| | |
|---|---|
| first run | freeze at the splash, disk read offset frozen for minutes |
| after the fix (`c30adff`) | full boot to the desktop: menu bar, clock, mounted *Quad Squad* volume, control strip, apps |
| fixed build | `wombat33.rbf` md5 `41b0c93a38fad4ad3bfec1995a7cee43`, 82 % ALMs, timing met (+0.186 ns worst) |
| current build | `4c46a65c3a48b44ddb6f4fd6808d0422` (+0.245 ns) — **zero-touch**: core load → `SC0` auto-mount → desktop, no OSD interaction |

## Open: occasional phantom keystrokes

Reported 2026-08-30 after the ADB fix landed — much better, but keys still
appear now and then while using the mouse.

**mrext is ruled out.** Its log for the day shows 2,349 `mouseMove` and 13
`mouseBtn` messages and **zero `kbd` messages of any kind**
(`grep "received message" /tmp/remote.log`), so nothing is injecting keystrokes
from the host side. The events originate in the core's ADB path.

The likely residue, and where to look first: the A/B that validated the clock
gating left the fixed build at **96,321 VIA deliveries for 73,078 transceiver
bytes**. The duplicate-per-byte defect is gone (unfixed was 168,474), but ~23 k
deliveries still have no fresh byte behind them. Those come from the
idle-autopoll heartbeat, which re-delivers `kbd_to_mac` — the *last* byte —
when nothing fresh exists:

```
end else if (via1_shift_timer == 22'd1) begin
    if (!adb_resp_pending || adb_bus_idle) begin
        ... via1_sr_ext_data <= kbd_to_mac;     // stale byte, re-presented
```

That is by design and matches lbmactwo, so it is not obviously wrong — but a
stale byte re-presented at the wrong moment is exactly the shape of an
intermittent phantom key, and "sometimes, not always" fits. Next step is to
instrument which deliveries are fresh vs. stale (extend the ADBTAP counters to
split the two) before changing any RTL; do not guess at this one.

## Deploying the ADB/SC0 build broke it three ways (all fixed, `f72f849`)

Recorded because each one looked like something it was not:

1. **Spurious bus error → Sad Mac `$0000000F / $00000001`.** The A_SDMA escape
   aged its 7.9 ms counter while the SCSI target was legitimately waiting for
   the HPS to hand over a sector; SD latency on a busy card is tens of ms, so it
   fired on healthy transfers. Decoded via `docs/quadra800-rom-notes.md:153`:
   D7 `$0F` = "no DSAlertTab yet", D6 = `DSErrCode` = 1 = vector 2 = bus error.
   The tell that it was latency and not logic: the failure point *moved* between
   boots (extension load, then LBA 489 MB), and it appeared right after
   restoring a 2 GB image left the card churning. The counter now freezes while
   a block transfer is outstanding. Do **not** "fix" a future spurious timeout
   by enlarging the budget — past 2^21 the core watchdog wins and the deadlock
   the escape exists to break returns.
2. **`SC0` auto-mount invisible to the machine.** The Main mounts the instant
   the core loads, inside the reset window that spans the `boot.rom` upload;
   `ncr53c96` latches `mounted` only on the pulse, from a reset-gated block, so
   it was dropped. Symptom: fd open on the Main side with `pos` stuck at 0 while
   the machine showed the flashing-?. A latch outside the machine reset replays
   the mount once the machine runs.
3. **The build/deploy scripts would have flashed a timing-violated core.**
   `build_only.sh` printed `VIOLATED` then `RESULT: OK` (the check ran in a
   `{ ... } | tee` subshell, so its result was discarded), and
   `deploy_screenshot.sh` gated only on the Fitter — which reports success for
   a design that *placed*, not one that will *work*. Both refuse now.
   `ALLOW_TIMING_VIOLATION=1` overrides for a deliberate throwaway probe.

Also: `qsf SEED 1 -> 2`. Seed 1 gave a −0.122 ns **hold** violation on the
99 MHz `clk_ram` domain after a change confined to `clk_sys`, where the two
prior builds held +0.449/+0.464 ns. That is placement variance at 82 %
utilisation, not an RTL regression — reseed rather than hunt the RTL.

The tell that it was really working, before anything appeared on screen: the
Main's read offset on the image started *moving* again (and seeking backwards),
where before it sat frozen. That is the cheapest liveness check on this machine
— see the operating notes at the end.

## What was run

| | |
|---|---|
| build | `wombat33.rbf`, md5 `d171c3a8dc35e35a9ac91fd2afdfec57` |
| commit | `defc72d` (SDRAM: machine RAM off DDR3 onto the SDRAM module) |
| board | DE10-Nano, `Found SDRAM config: 3` — the SDRAM module the new RAM path needs is present |
| Main | `Version 260828` |
| ROM | `games/Wombat33/boot.rom`, CRC32 `3318A935` (pristine 1 MB) |
| disk | `games/Wombat33/QuadSquad8.hda`, 2,146,461,696 B, md5 `f4287aee9ff9a4413fa1e5fd9f2d63b4` |

## Build

`scripts/build_only.sh` — A&S 3m55s, full compile 15m43s (A&S reused).

- Fitter **Successful**: 34,150 / 41,910 ALMs (81 %), 417/553 RAM blocks, 45 DSP, 3 PLLs.
- Timing **met, TNS 0.000 everywhere**:
  - `clk_sys` 33.000 MHz — setup **+1.334 ns**, hold +0.253 ns (was +1.138 pre-SDRAM,
    so the SDRAM move *gained* margin).
  - `clk_ram` 99 MHz — the new SDRAM domain — setup **+1.787 ns**, hold +0.449 ns.
    Closes on its first compile.
- A&S clean: 0 errors, 82 warnings, all pre-existing. The only one touching the new
  `rtl/sdram.sv` is `Pin "SDRAM_CKE" is stuck at VCC`, which is the controller
  holding clock-enable high — expected.
- All arrays still infer as `M10K block`/`AUTO`; `Total registers` 28,827 (the
  healthy band — a fallout to registers shows up as ~60 k).

## Boot sequence observed

1. Diskless: dithered 50 % grey desktop, mouse cursor, **flashing "?" floppy**.
   So ROM fetch, RAM (now SDRAM), DAFB video and the 60 Hz tick all work.
   The "?" blinks — a single screenshot catching the off-phase looks like a
   successful boot. Always take two.
2. Disk mounted: colour desktop pattern, **"Mac OS — Starting Up…"** splash with
   the progress bar. The System file is read and the extension chain starts.
3. Then it **hangs**. Confirmed hung, not slow: the Main's read offset on the image
   (`/proc/<pid>/fdinfo/<fd>`, `pos:`) froze at **732,289,536** = LBA **1,430,253**
   and did not move for >2 minutes, while consecutive screenshots stayed
   byte-identical.

### Root cause: non-DMA transfer-info underflow in `ncr53c96.sv`

**Reproduced in the Verilator sim** (WSL, headless, fast-boot ROM, the same
pristine image) and diagnosed there. The last SCSI activity before the freeze:

```
[NCR 1644582784] cdb 12 00 00 00 24 00 ...   INQUIRY, allocation length $24 = 36
[NCR 1644588258] cmd=90 ph=1 ... sp=0        transfer-info (DMA), data-in phase
[NCR 1644588983] cmd=90 ph=1 ... sp=16
[NCR 1644590160] cmd=10 ph=1 ... sp=32       non-DMA from here, one byte each
[NCR 1644591510] cmd=10 ph=1 ... sp=33   + INT+ ist=10
[NCR 1644592842] cmd=10 ph=1 ... sp=34   + INT+ ist=10
[NCR 1644594174] cmd=10 ph=1 ... sp=35   + INT+ ist=10
[NCR 1644597759] cmd=10 ph=1 ... sp=36   <- NO INTERRUPT.  Everything stops.
```

All 36 requested bytes are delivered. Every `cmd=10` raises `I_BUS` except the
last, and the chip never leaves data-in phase, so the driver polls forever (PC
cycling in `$00131E06`-`$00131F08`).

Why: `arm_pio_in` (`ncr53c96.sv:270`) gates on `byte_avail`. Once the source is
exhausted, `arm_pio_in` can never assert, so `xfer_pio_in` stays armed with no
byte to hand over — no `I_BUS`, no phase change, forever. The DMA side has an
explicit "data-in underflow -> PH_STAT + I_BUS" escape at `ncr53c96.sv:553`;
the PIO side simply never had one.

The fix adds the symmetric escape. It matches QEMU, whose equivalent
(`esp.c:667-671` -> `esp_command_complete()`, phase STATUS, `INTR_BS`) carries
the commit note that it is what makes EMILE boot on m68k — the same stall in
another Mac bootloader. See `docs/scsi/qemu-esp-behavior.md:357-369`.

**Verified in sim.** The fixed run is cycle-for-cycle identical to the broken one
up to the failure, then diverges exactly where it should:

```
[NCR 1644597759] cmd=10 ph=1 ... sp=36
[NCR 1644597761] INT+ ist=10 ph=3     <- the missing interrupt; phase -> STATUS
[NCR 1644600802] cmd=11 ph=3          -> INT+ ist=08 ph=7   command complete
[NCR 1644601819] cmd=12 ph=7          -> INT+ ist=20 ph=0   message accepted
[NCR 1644741010] cdb 28 00 00 15 bb 25 ...   READ(10), LBA 1,424,165
[NCR 1644741012] io_rd+ lba=1424165          reading the disk again
```

That LBA lands right where the hardware froze (1,424,088 on the extensions-off
boot), which ties the sim reproduction to the real failure: the driver was
issuing an INQUIRY between reads of that region and never came back from it.

### What it was NOT

Worth recording, because two plausible theories were wrong:

- **Not the missing hold-off bus error.** No bus error occurs anywhere near the
  wedge — the last one in the whole run is at cycle 651M, the ROM's NuBus card
  probe, roughly a billion cycles earlier. Nothing was stalled on the bus.
- **Not a deadlocked bus adapter.** That deadlock is real and reachable (see
  below) but is not this bug.

The A_SDMA hold-off deadlock *was* found while chasing this, and is fixed in the
same batch: `iosb.sv` waited for `sdma_valid` forever, and because
`quadra800.sv` only reaches `S_IDLE` on the matching ack, a wedged beat took the
whole machine down permanently — the CPU's own `ap040_bus_timeout`
(`wombat_cpu.sv:85`, 2^21 ≈ 63 ms) faults the CPU out but leaves both state
machines stuck. `iosb.sv` now times the beat out and releases it with
`sdma_fault`, which `quadra800.sv` turns into a bus error. That path did not
fire in this workload; it is a latent-deadlock fix, not the boot fix.

### The earlier P1 attribution (superseded)

`RESUME-disk-gate.md`'s P1 backlog, first item:

> Hold-off bus error: a wedged PDMA beat should bus-error after a timeout (the
> blind driver path RELIES on it: ROM handler `$408D2606`, IOSB fault regs
> `$50F18300/$400` unimplemented). No timeout exists in `quadra800.sv` today — a
> wedge hangs forever.

It looked like a match — one SCSI beat stops and the driver waits forever — and
it is what this doc originally blamed. It was wrong on both halves: a CPU-level
watchdog *does* exist (`wombat_cpu.sv:85`; the P1 note only inspected
`quadra800.sv`), and no bus error occurs at the wedge at all. The real cause is
the PIO underflow above. The hold-off gap was nonetheless real, and is fixed
alongside it.

### It is not an extension — ruled out by a clean boot

Suspicion was that something in the image (an ethernet/AppleTalk extension) was
poking hardware the core does not implement and wedging it. Tested by holding
**left shift** through the whole startup, which makes Mac OS skip every extension.

Confirmed the shift really registered: the startup screen showed the "Extensions
Off" badge (hand + document + red X) at the bottom left, and the boot reached
"Welcome to Mac OS" — a phase the loaded-extensions boot skipped past.

**It hung anyway**, in the same place:

| boot | hang offset | LBA | ≈ into image |
|---|---|---|---|
| extensions on | 732,289,536 | 1,430,253 | 698.4 MB |
| extensions off | 729,133,056 | 1,424,088 | 695.4 MB |

So the wedge is in the core's SCSI path, not in the disk's software payload. Note
the two offsets are close but **not identical**, so it is not one bad block or a
specific sector the core mis-decodes — it is a protocol/timing wedge that trips
after a similar amount of I/O. Sim reproduction should drive volume of transfers,
not one target LBA.

## Two MiSTer-integration bugs found

**1. `S0` should be `SC0`** — see BUILD.md. The disk mount is never remembered, so
`config/Wombat33.s0` seeding is inert and the disk has to be mounted from the OSD
on every boot. One-character CONF_STR fix, needs a rebuild.

**2. Blind OSD navigation is unreliable on this host.** `launch_unstable_core.py`
lost one keypress at the root menu on both attempts, opened `_Other` instead of
`_Unstable`, and launched an unrelated core. Fixed by adding `--launch cmd`, which
writes `load_core <path>` to `/dev/MiSTer_cmd` over ssh — deterministic, no reboot.
It is now the default whenever an ssh key is configured.

## Operating notes for the next session

- **Mount by hand from the OSD** until `SC0` lands. The key sequence that works,
  with the core running and the OSD closed:
  `osd`, `confirm` (opens the browser on "Mount SCSI disk"), **`down`**, `confirm`.
  The `down` matters — the browser's first row is the parent-directory entry.
  Send them with `python scripts/mister_ws.py --host <mister> --delay 1.5 osd sleep:2 confirm sleep:3 down sleep:1 confirm`.
  **That single `down` only lands on the image when the image is the only thing in
  the folder.** With `backup/` and `quadra800-allinone.hda` present the browser has
  four rows and one `down` selects the `backup` folder instead. Since the OSD is
  invisible to screenshots, either move the others aside for the duration or count
  the rows — and always confirm the mount by checking the Main has the file open.
- **Holding a modifier** (shift-boot, Command-Option-P-R, …) needs a key held DOWN,
  which `kbd:` taps cannot do. `scripts/mister_ws.py` takes `down:<linux-keycode>`
  and `up:<code>` for this (mrext's `kbdRawDown`/`kbdRawUp`). Left shift is 42:
  `python scripts/mister_ws.py down:42 sleep:200 up:42`. Always send the `up:` —
  a held key stays held until you release it or reload the core.
- **You cannot see the OSD.** The screenshot API captures the core's video only, so
  the OSD overlay never appears in a grab. Verify a mount by checking that the Main
  has the image open instead:
  `for p in /proc/[0-9]*; do for f in $p/fd/*; do readlink $f; done; done | grep <image>`
- **Watching for progress vs. a hang**: read `pos:` from
  `/proc/<pid>/fdinfo/<fd-of-the-image>`. A moving offset means the core is still
  doing SCSI; a frozen one is a wedge. Far faster than staring at screenshots.
- **The Main's own log** is worth having. It goes to `/dev/console` normally; to
  capture it, `kill` the Main and relaunch it as
  `setsid nohup /media/fat/MiSTer > /tmp/mister.log 2>&1 < /dev/null &`.
  It logs the parsed CONF_STR (`get cfgstring 2 = S0,HDAVHD,Mount SCSI disk`),
  ROM selection, MGL parsing and the SDRAM probe. **`.143` is running such a
  manually started Main right now** — a reboot restores the inittab-started one
  (`::sysinit:/media/fat/MiSTer &`; note inittab starts it once and does *not*
  respawn it, so don't kill it without restarting it).
- **The disk image is now dirty.** Booting wrote to it (mtime moved). The pristine
  copy is `games/Wombat33/backup/QuadSquad8.hda.gz` (342,339,235 B); it has been
  restore-tested and decompresses to md5 `f4287aee9ff9a4413fa1e5fd9f2d63b4`.
  Restore on the MiSTer with
  `gzip -dc backup/QuadSquad8.hda.gz > QuadSquad8.hda`.
