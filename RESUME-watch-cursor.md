# RESUME — watch cursor, frozen clock, dead input (regression, 2026-08-31)

A regression on the core currently on the MiSTer
(`/media/fat/_Unstable/wombat33.rbf`, md5 `2be4c8d06cb91c8238a91f500c3e973b`,
built from `6599b0b`).

**Bisected already — the user confirms `releases/wombat33_20260830.rbf` does NOT
show it.** That build is `5352b84`: the via6522 ADB fix and nothing else. So the
regression is in exactly three commits, all from the night of 2026-08-30:

| commit | what it did | hang risk |
|---|---|---|
| `e0990f0` | EASC FIFO mode; **connected the ASC interrupt for the first time** | **high** |
| `1198644` | DAFB scanout moved to a 25.175 MHz pixel clock | low, see below |
| `6599b0b` | made the EASC interrupt edge-triggered instead of level | **high** |

Start with the ASC interrupt. Do not go near the RTC.

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

## Why the pixel clock is the weaker suspect

Worth knowing before spending a build on it. The clk_sys → clk_vid crossings in
`1198644` are: a 2FF sync on quasi-static config, a toggle + edge detect for the
VBL, a dual-clock M10K for the VRAM read, and two combinational reads
(`vid_stride` into the address mapper, and the CLUT into the pixel path). The
combinational ones are declared false paths, so if they are too slow the result
is **wrong pixels, not a wedged CPU** — and the reported screen is drawn
correctly. Nothing in that commit can hold a VIA2 interrupt line up.

**But note the sim cannot test it.** `verilator/sim.v` ties `.clk_vid(clk_sys)`
deliberately (so existing frame counts do not move), so in simulation the two
domains are the same clock and the crossing barely exercises. A bug that needs a
genuinely different clock will not reproduce there. The ASC, by contrast,
reproduces in sim perfectly well.

## Do these in order

**1. Isolate the ASC interrupt with a one-line change.** In `rtl/iosb.sv:428`:

```verilog
wire asc_irq_i = asc_irq;   // was: asc_irq | easc_irq
```

Rebuild, deploy. If the clock ticks again, it is the ASC interrupt and the fix
belongs in `rtl/easc.sv` — do not ship the machine with the line cut, because
without it the Sound Manager fills the FIFO once and is never asked for more, so
sound plays for 46 ms and stops.

**2. Prove it in sim — the probe is already written.**
`scratch/instr_irq.py` patches a scratch copy of `rtl/iosb.sv` with a
`synthesis translate_off` block that logs:

- every change of VIA2 IFR/IER, with which source is up (asc / vbl / scsi / drq)
- how long `ipl_n` has been continuously presenting IPL 2 — it prints at 1 ms,
  10 ms, 100 ms (`STUCK`) and 1 s (`WEDGED`)
- once-a-second rates of ASC and VBL interrupt edges

A handful of ASC edges per second is the Sound Manager working; a `STUCK`/
`WEDGED` line, or IFR bit 4 set with IER bit 4 enabled and never clearing, is
the bug. Build and run it with:

```bash
rsync -a --exclude .git --exclude 'obj_dir*' rtl verilator ~/irqchk/
python3 scratch/instr_irq.py ~/irqchk/rtl/iosb.sv
cd ~/irqchk/verilator && ln -sf ~/adbC/verilator/quadra800-fastboot.rom.hex . && make -j10
./obj_dir/Vemu --headless --no-cpu-trace --max-cycles 9000000000     --disk ~/boots/irq.hda +rom=quadra800-fastboot.rom.hex +mousewiggle=3 > ~/logs/irq1.log
grep -E 'VIA2|IPL2|RATE' ~/logs/irq1.log
```

That tree is built and a 9G-cycle boot was left running when this was written;
`~/logs/irq1.log` may already have the answer in it. Mac OS is reached at around
5G cycles, so the interesting part is the tail, not the head.

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
