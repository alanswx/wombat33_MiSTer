# RESUME — watch cursor, frozen clock, dead input (regression, 2026-08-31)

A regression reported on the core currently on the MiSTer
(`/media/fat/_Unstable/wombat33.rbf`, md5 `2be4c8d06cb91c8238a91f500c3e973b`,
built from `6599b0b`). **Almost certainly introduced by the 2026-08-30 evening
work**, most likely the sound chip's interrupt. Start here, not with the RTC.

## Symptoms

1. **The menu-bar clock is frozen.** Two screenshots 80 s apart are
   byte-identical (`scratch/watch_cursor.png`, `scratch/watch_cursor2.png`),
   both reading `Sun 11:43` while the host clock said 07:19. This is a stopped
   clock, **not** the documented one-hour standard/daylight offset — do not go
   chase `rtl/rtc3430042.sv`.
2. **The cursor is a watch (busy) cursor and stays one** — zoomed in
   `scratch/z_watch.png`, unmistakably the Mac OS wristwatch.
3. **The mouse still moves the cursor**, but nothing else responds. The user
   also suspects this explains input "not taking correctly" earlier.
4. The desktop is fully drawn and the machine is not Sad-Mac'd; it is running.

## The reading that makes this testable

Moving cursor + frozen clock + watch cursor = **interrupts are still being
serviced while the foreground is starved.** Now look at how this core presents
interrupt levels (`rtl/iosb.sv:745`):

```verilog
assign ipl_n = scc_irq     ? 3'b011 :   // IPL 4
               via2_active ? 3'b101 :   // IPL 2
               via1_irq    ? 3'b110 :   // IPL 1
                             3'b111;
```

It is a **priority mux, not an OR**. While `via2_active` is true, VIA1's level
is never presented to the CPU at all. And of the two chips:

| | VIA1 (IPL 1) | VIA2 (IPL 2) |
|---|---|---|
| 60 Hz tick (CA1) | **yes** | |
| RTC one-second (CA2) | **yes** | |
| ADB shift register | **yes** | |
| VBL / slot | | yes (`nubus_irqs` bit 6 → `via2_ifr[1]`) |
| SCSI IRQ/DRQ | | yes |
| **ASC** | | **yes, `via2_ifr[4]`** |

So a VIA2 interrupt that never goes away pins the CPU at IPL 2 and starves
**every VIA1 source**: the 60 Hz tick (→ the clock stops), the RTC one-second
line, and ADB. Meanwhile the cursor keeps tracking because the VBL task that
moves it hangs off VIA2, which is still being serviced. **Every symptom above
falls out of that one fact**, including the input flakiness.

## Prime suspect

`6599b0b` / `e0990f0` connected the **ASC interrupt for the first time**. Before
those commits `quadra800.sv` tied `iosb`'s `asc_irq` port to `1'b0` and
`via2_ifr[4]` could never be set by anything. Now:

```verilog
// rtl/iosb.sv:428
wire asc_irq_i = asc_irq | easc_irq;
...
if (asc_irq_i && !asc_d) via2_ifr[4] <= 1'b1;
```

The first cut of that interrupt was a genuine level-storm (it asserted whenever
a FIFO was under half full, and an *empty* FIFO always is) and it froze the
machine at the desktop on hardware. `6599b0b` reworked it to MAME's edges — the
pop that crosses half-empty, the push that fills, cleared by a FIFOSTAT read —
and `make tb_easc` has a check that an idle FIFO does not interrupt. **That test
passes, so whatever is happening now is not the same bug**, but the ASC is still
the one genuinely new interrupt source in the machine and it is where to look
first.

Specific things to scrutinise in `rtl/easc.sv`:

- `stat_read` — does the guest's actual FIFOSTAT access match this decode? It
  requires `a[11]` and the longword at offset `$004`. If Mac OS reads the
  status some other way, `irq_r` never clears.
- Whether `half_cross_a/b` can fire at the pop rate (22 kHz) rather than once
  per FIFO drain — e.g. if the guest keeps the capacity hovering at 511.
- Whether `via2_ifr[4]` is actually clearable in practice. The path exists
  (`rtl/iosb.sv:600`, `via2_ifr[6:0] & ~(wbyte[6:0] & 7'h1b)`, and bit 4 is in
  that mask), but confirm the guest reaches it.

Second suspect, much weaker: `1198644` moved the DAFB scanout to a 25.175 MHz
pixel clock and the VBL crossing became a toggle + 2FF edge detect
(`rtl/dafb.sv`). If VBL were being *lost*, though, the cursor would stutter and
the symptom is the opposite — the cursor is the thing that still works.

## Do these in order

**0. Bisect with the released binaries. No build, ~5 minutes, and it decides
whether this is even last night's later work.** All three exist already:

| binary | contains |
|---|---|
| `releases/wombat33_20260829.rbf` | before the ADB fix |
| `releases/wombat33_20260830.rbf` | ADB fix only (`5352b84`) — **no sound, no pixel clock** |
| the deployed `_Unstable/wombat33.rbf` | + EASC + pixel clock (`6599b0b`) |

```bash
scp -i ~/.ssh/mister_only releases/wombat33_20260830.rbf root@192.168.99.143:/media/fat/_Unstable/bisect.rbf
ssh -i ~/.ssh/mister_only root@192.168.99.143 "echo 'load_core /media/fat/_Unstable/bisect.rbf' > /dev/MiSTer_cmd"
```

Boot it and watch the menu-bar clock for two minutes. If the clock ticks and the
cursor is an arrow, the fault is in the sound or video work and step 1 finds it.
If it is *also* frozen, this predates last night's later work and the ASC is
exonerated — go look at what else changed.

**1. Isolate the ASC interrupt with a one-line change.** In `rtl/iosb.sv:428`:

```verilog
wire asc_irq_i = asc_irq;   // was: asc_irq | easc_irq
```

Rebuild, deploy. If the clock ticks again, it is the ASC interrupt and the fix
belongs in `rtl/easc.sv` — do not ship the machine with the line cut, because
without it the Sound Manager fills the FIFO once and is never asked for more, so
sound plays for 46 ms and stops.

**2. Prove it in sim rather than guessing at the guest.** Add a counter to
`rtl/iosb.sv` under `synthesis translate_off` that reports how long
`via2_ifr[4] & via2_ier[4]` has been continuously set, and how many times it is
set per second. Boot the full sim (`~/vidchk/verilator`, the tree used last
night) and read it. A handful per second is the Sound Manager working; hundreds
or a permanently-set bit is the bug. `docs/tools/instr_adb.py` is the model for
this kind of probe.

**3. Only then** consider the video CDC: point `.clk_vid(clk_sys)` in
`wombat33.sv`'s `quadra800` instantiation (leaving `CLK_VIDEO` alone) and see
whether anything changes.

## Traps that will otherwise cost you an hour each

- **mrext's input injection dies, repeatedly** — four times in one session. The
  websocket keeps logging every message to `/tmp/remote.log` while
  `/dev/input/event16..18` and `/dev/input/mouse5` go completely silent. A
  `-service restart` does not fix it; a MiSTer reboot does. Check it with
  `dd if=/dev/input/mouse5 bs=3 count=60` (NOT `bs=1`, which evdev rejects, and
  NOT `timeout cat`, which buffers and loses everything on SIGTERM) **before**
  concluding the guest has hung. If the user says the mouse moves and your
  script sees nothing, this is why.
- **The boot stalls about 1 in 3-4** at "Starting Up…", with the disk file
  position frozen. That is Fault 2 in `RESUME-adb-and-corruption.md`, it long
  predates this regression, and it is a different signature (frozen *during*
  boot, no watch cursor). Do not conflate them.
- The volume is currently NOT cleanly unmounted, so a boot shows the "may not
  have been shut down properly" alert. `scripts/mac_shutdown.sh` shuts the guest
  down unattended and works — but it needs mrext alive.
- Restore the disk from `games/Wombat33/backup/QuadSquad8.hda.gz` (md5
  `f4287aee9ff9a4413fa1e5fd9f2d63b4`, ~6 min) before believing any hang.

## Context you will want

- `RESUME-adb-and-corruption.md` — everything else open on this core, and the
  ground rules.
- `docs/adb-via-shift.md` — the ADB fix in `5352b84`, for what the 0830 release
  behaves like.
- Last night's commits: `5352b84` via6522, `e0990f0` EASC FIFO, `1198644` pixel
  clock, `6599b0b` EASC interrupt edges.
- `make tb_easc` in `verilator/` — 18 directed checks on the sound chip, seconds,
  no ROM or disk needed. Run it after any change to `rtl/easc.sv`.
