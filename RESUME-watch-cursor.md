# SOLVED — watch cursor, frozen clock, dead input (2026-08-31)

Fixed in `rtl/easc.sv`, shipped as `releases/wombat33_20260831.rbf`
(md5 `3901ef5705f58dba3279c0417412f5f8`, timing met +0.243 ns).

**Do not re-investigate the ASC interrupt or the pixel clock.** Both were the
named prime suspects in the original version of this document and both are
innocent — see the scored table below.

## What it was

`$804` FIFOSTAT bits 1/3 read `(cap == 0) || (cap >= 1023)`, so an **empty
FIFO reported itself FULL**. A guest that fills until the full flag sets wrote
nothing at all; with no bytes queued nothing ever popped, so the half-empty
edge never fired and no refill interrupt was ever raised. The wait never ended.

That is why every symptom looked the way it did:

- The desktop was **fully drawn** — the wedge happens after startup, in the
  foreground, once something asks the Sound Manager for audio.
- The **cursor still tracked the mouse**, because ADB is VIA1 at IPL 1 and was
  being serviced normally the whole time. Interrupts were never the problem.
- The **menu-bar clock stopped** because the Finder was blocked, not because
  the timebase stopped. The 60.15 Hz tick and the RTC one-second line are
  divided from `clk` in `rtl/iosb.sv` (`TICK_HALF`) and were always correct.

The original document's reading — a VIA2 interrupt pinning the CPU at IPL 2 and
starving VIA1 through the priority mux at `rtl/iosb.sv:745` — is wrong, and the
moving cursor is what disproves it. ADB is a VIA1 source; a genuine IPL 2 storm
would have frozen the cursor too.

The fault only appeared with `e0990f0` because the old `asc_wavetable` returned
`0x00` for `$804` ("version, status, everything else"), so the full flag was
never set and the fill loop always completed.

## Evidence

Every run on a freshly restored disk, scored against `wombat33_20260830.rbf`:

| build | scanout | ASC IRQ | menu-bar clock |
|---|---|---|---|
| `20260830` (known good) | 33 MHz | n/a | ticks |
| pre-fix | 25.175 MHz | off | FROZEN |
| pre-fix | 33 MHz | off | FROZEN |
| pre-fix | 25.175 MHz | off | FROZEN (2nd sample) |
| **fixed** | 25.175 MHz | **on** | **ticks** |

Rows 2–4 are what exonerate the two suspects: the wedge reproduced with the ASC
interrupt **disconnected** (so `6599b0b`/`e0990f0`'s interrupt is not it) and
with the DAFB scanout forced back off the pixel clock (so `1198644` is not it).

"Clock ticks" is measured, not eyeballed: consecutive screenshots differ **only**
in the 6x11 px patch at (588,4)–(594,15), which is the clock digits. A frozen
machine shows no diff there across minutes. Guest time tracked the host exactly
across 41 minutes at the documented −1:00 offset.

## Also fixed

`$806` volume is now applied (bits 7–5, eight steps, `x*256/7` so step 7 is
exactly unity). Reset value is `0xE0` (max), not 0 — the boot chime is
ROM-generated before Mac OS loads any sound preference.

## Corrections to the old ground rules

These cost real time. They are wrong as previously written.

- **`dd if=/dev/input/mouse5` is NOT a valid injection-liveness check.** MiSTer's
  main process holds `/dev/input/event16..18` open and grabs them exclusively,
  so `dd` reads zero bytes whether injection works or not. It read zero on a
  perfectly healthy machine and nearly sent this session chasing a phantom, and
  a MiSTer reboot "fixing" it in the past was probably coincidence. Test
  injection end to end instead: move the mouse and screenshot the cursor.
- **The 1-in-3-4 boot stall (Fault 2) looks deterministic, not random.** Both
  boots on a power-cut volume hung at the *byte-identical* frame with identical
  diff bboxes; all three boots on a freshly restored volume reached the desktop.
  `scripts/mac_shutdown.sh`'s own header already says a power-cut image "hung
  mid-boot at a repeatable offset — which then got misdiagnosed as an RTL fault
  more than once." Restore the disk before believing any mid-boot hang.
- **The old step 3 broke the video.** It said to point `.clk_vid(clk_sys)` at the
  `quadra800` instantiation "leaving `CLK_VIDEO` alone". Do not: the framework
  samples the core's video on `CLK_VIDEO`, so a 33.33 MHz scanout clocked out at
  25.175 MHz keeps 3 pixels in 4 and the picture comes out squeezed to 484 px of
  640 and blurred. Both clocks must move together.
- The OSD **cannot be driven from a script here.** Neither mrext's named keys
  (`kbd:osd`) nor raw keycodes (`raw:88` = F12) reach it, MiSTer writes no
  `.cfg` to confirm a change, and screenshots capture the core's native 640x480
  *before* the OSD and before aspect scaling. Runtime OSD toggles are therefore
  useless for A/B testing — make the arm you want to test the `status=0`
  default and rebuild.

## Still open

- **`scripts/mac_shutdown.sh` is unreliable.** It failed twice in a row against a
  plainly visible Finder menu bar with `Special` right there, reporting
  `no menu open (probe: NONE)` through every step and releasing with nothing
  selected. A plain desktop click worked immediately before, so mouse-down does
  register — something in its press-and-drag path does not. This matters: the
  script is the stated reason you never have to power-cut the volume.
- **clk_sys has ~0 ns timing margin.** The critical path is
  `ap040_core|ir[7] -> exc_fmt[0]`, inside the CPU core. Any netlist
  perturbation flips it, and it cost four wasted 20-minute builds in one
  session. Quartus is deterministic here (a clean fit reproduced −0.165 ns
  exactly, and wiping `db/` changed nothing), so reseeding is a real search, not
  a re-roll. See the seed history in `wombat33.qsf`.
- `make tb_easc` passes 18/18. Run it after any `rtl/easc.sv` change — it is
  seconds, and it now pins the FIFOSTAT semantics that caused this bug.
