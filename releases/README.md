# releases/

Dated core builds, named `wombat33_YYYYMMDD.rbf` (the convention the sibling
Mac cores use). The date is the **work date** the build belongs to, not
necessarily the wall-clock minute Quartus finished — an overnight session that
starts on the 29th is stamped `20260829` even if the fitter returned after
midnight.

Each entry records the md5 so a core on a MiSTer can be identified without
guessing, and the timing margin, because a build that fits but violates timing
must never be flashed (`scripts/deploy_screenshot.sh` refuses one).

| build | md5 | timing | notes |
|---|---|---|---|
| `wombat33_20260830.rbf` | `64c79dfb93ceefb549200c78671cdc31` | met, +0.248 ns | **ADB actually works** — the mouse button reaches the guest and motion stops inventing input. |
| `wombat33_20260829.rbf` | `4c46a65c3a48b44ddb6f4fd6808d0422` | met, +0.245 ns | First build that boots Mac OS unattended. |

## `wombat33_20260830.rbf`

The build where ADB input is correct. Deployed to the MiSTer at
192.168.99.143 and verified against the pristine *Quad Squad* image (md5
`f4287aee9ff9a4413fa1e5fd9f2d63b4`) on two separate boots.

One RTL hunk, in **`rtl/via6522.sv`**: in ACR modes `011`/`111` CB1 is an input
and the internal shift clock IS the pin, but the RTL forced `shift_clock` high
whenever `shift_active` was low. Clearing `shift_active` on an `sr_ext_complete`
therefore drove it 0→1, and that rising edge shifted the byte the completion had
just loaded one place left, with `cb2_i` (tied low) in the LSB — **every byte the
ADB shim delivered, every time**.

An ADB mouse Talk R0 byte 0 is `{~button, dy[6:0]}`, so the button is exactly the
bit a left shift throws away, and what took its place was the old bit 6, the sign
of dy. That is both halves of the fault the previous entry lists as a known
issue: clicks did nothing, and plain motion with dy ≥ 0 read as button-down,
which is why mouse movement alone opened menus and appeared to type.

Scored against a control build differing only in that hunk — same disk, same ROM,
same injected mouse traffic — non-`$00` bytes surviving from the transceiver to
the driver went from **0 / 82** to **670 / 670**. Full derivation and the
measurement method: `docs/adb-via-shift.md`.

Also here: fitter `SEED` 2 → 3. Seed 2 gave −0.283 ns hold on the 99 MHz
`clk_ram` domain, which a `clk_sys`-domain change cannot reach — the placement
swing the qsf comment warns about, not the RTL.

What this build makes possible: `scripts/mac_shutdown.sh` now drives Special →
Shut Down unattended, so a core can be swapped without power-cutting a mounted
HFS volume.

**Known issues.**

- **Boot stalls roughly 1 in 3.** Frozen at "Starting Up…", disk `pos` frozen,
  screen byte-identical for minutes. Present before this build and not caused by
  it; reproduced here on a freshly restored pristine image. See
  `RESUME-adb-and-corruption.md` for the ADB-deadlock hypothesis and the
  detector committed to test it.
- **Host keystrokes never reach the guest.** Host-side, not the core —
  `kbd:osd` does not open the MiSTer OSD either, so nothing is arriving at the
  Main. The core's ADB keyboard path is therefore untested end to end.
- The Mac reads exactly one hour behind the host (minutes dead-on), which looks
  like standard vs daylight time in what the Main sends.

## `wombat33_20260829.rbf`

First core that reaches the Mac OS desktop with no operator intervention:
core load → `SC0` auto-mount of `games/Wombat33/QuadSquad8.hda` → Finder.
Verified on the MiSTer at 192.168.99.143 against the pristine *Quad Squad*
image (md5 `f4287aee9ff9a4413fa1e5fd9f2d63b4`).

Fixes in this build, over the first hardware run:

- **`ncr53c96`** — a non-DMA transfer-info that underflows now ends the data
  phase (`PH_STAT` + `I_BUS`) instead of waiting forever for a byte the target
  will never produce. This was the freeze at "Starting Up…": an INQUIRY with a
  `$24` allocation length delivered all 36 bytes and the chip then sat in
  DATA-IN. Matches QEMU `esp.c:667-671`.
- **`iosb`** — the A_SDMA hold-off got an escape (a wedged pseudo-DMA beat
  releases into a bus error rather than deadlocking the machine), and that
  escape's watchdog is frozen while a platform block transfer is outstanding,
  so SD latency cannot trip it.
- **`iosb`** — the ADB transceiver handshake moved into the `adb_en` domain.
  Driving it at full `clk` dropped command bytes and delivered response bytes
  more than once.
- **`wombat33.sv`** — CONF_STR `S0` → `SC0` so the mount is remembered, plus a
  latch that replays a mount arriving while the machine is held in reset.
- **`wombat33.qsf`** — fitter `SEED` 1 → 2; seed 1 produced a −0.122 ns hold
  violation on the 99 MHz `clk_ram` domain.

**Known issue (RESOLVED in `wombat33_20260830.rbf`, and the guess below was
wrong — it was the VIA shift register, not the heartbeat):** occasional phantom
keystrokes remain. The ADB duplicate-byte
defect is fixed and measured (VIA deliveries per transceiver byte dropped from
~2.3× to ~1.3×), and mrext is ruled out — it sends only `mouseMove`/`mouseBtn`,
never `kbd`. The residue is most likely the idle-autopoll heartbeat
re-delivering a stale `kbd_to_mac`; see `RESUME-first-hardware-run.md`.

The Quadra 800 ROM (`quadra800.rom`) is **not** committed — Apple firmware, see
`.gitignore`. Put your own 1 MB image there; the deploy seeds it to the MiSTer
as `games/Wombat33/boot.rom`.
