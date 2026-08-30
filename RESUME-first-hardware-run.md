# First hardware run — 2026-08-29, MiSTer at 192.168.99.143

The core was compiled and run on real hardware for the first time, off the
2 GB *Quad Squad* disk. **It boots Mac OS to the "Starting Up…" splash in
colour, then wedges.** Everything up to that point works.

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

### The hang is the known P1 gap

`RESUME-disk-gate.md`'s P1 backlog, first item:

> Hold-off bus error: a wedged PDMA beat should bus-error after a timeout (the
> blind driver path RELIES on it: ROM handler `$408D2606`, IOSB fault regs
> `$50F18300/$400` unimplemented). No timeout exists in `quadra800.sv` today — a
> wedge hangs forever.

That is exactly the signature: one SCSI beat stops, nothing bus-errors, the driver
waits forever. **This is the next thing to fix.**

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
