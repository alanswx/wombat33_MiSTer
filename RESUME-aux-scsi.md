# Resume prompt — A/UX 3.1 boot: SCSI protocol errors

Paste this file as the opening message of a new session. Repo on `main`
through `cfb37db` (never pushed). The goal: **get A/UX 3.1 to boot on
Wombat33.** It currently fails in its own SCSI driver before it reads a
single block.

**Binding rule, learned the hard way:** never load a core while the guest is
booting or running. Loading a core hard-resets the FPGA and yanks a mounted,
writable volume out from under the OS. Shut the guest down first
(`scripts/guest/shutdown.sh` for Mac OS; for A/UX see §6) and only flash once
the screen says it is safe. Doing this repeatedly corrupted the Quad Squad
image once already (`scripts/mac_shutdown.sh` header has that story).

## 1. Read first

The research corpus already contains the answer to this, written before A/UX
was ever attempted:

- **`docs/scsi/netbsd-ncr53c9x-expectations.md`** — the single most important
  file. NetBSD's `ncr53c9x` driver is the same driver *family* A/UX's is: a
  real Unix 53C9x driver rather than the Mac ROM. §2.1 "Which commands the
  driver issues" is the crux.
- **`docs/scsi/rtl-gap-analysis.md` item 16** — already names precisely what
  is missing for a non-ROM driver, and says "None of it is needed for the Mac
  ROM."
- **`rtl/ncr53c96.sv`, the header comment** — states plainly what the model
  is: shaped around *the Quadra 800 ROM's* access patterns, with "the bus
  itself is not modeled".
- `docs/scsi/README.md` for the rest of the corpus.

## 2. The symptom, observed 2026-09-01

A/UX Startup runs, then its log fills with this and never recovers:

```
Disk c0d0s0 Error: Protocol Error Processing SCSI request
Disk c0d0s0 Error: Protocol Error Processing SCSI request
Disk c0d0s0 Error: Protocol Error Processing SCSI request
generic disk c0d0s0 Retry limit: Logical block 0, physical block 0
autorecovery
  ... the same block repeats ...
fsck: Can't determine file system type of /dev/default
fsck: No file systems specified
Autorecovery failed.
chroot
startup#
```

Screenshot: `scratch/aux_now.png` (and `scratch/aux_bottom.png` for the
`startup#` prompt). Read them, they are the ground truth.

Four things in that log matter:

1. **"Protocol Error"**, not a media or timeout error. In a 53C9x driver that
   means the chip reported a bus phase or interrupt the driver did not expect
   for the state it thought it was in.
2. **Logical block 0, physical block 0** — every time. It never successfully
   reads *anything*. The failure is at or before the very first transfer, not
   part-way through the disk.
3. **`c0d0s0`** = controller 0, target 0, slice 0. `rtl/ncr53c96.sv` is
   instantiated with `DISK_ID(0)` (`rtl/iosb.sv:505`), so A/UX is talking to
   the right target. This is not an ID mismatch.
4. It ends at a **`startup#` shell**. That is a live single-user prompt and it
   is the best diagnostic surface available — see §5.

## 3. The leading hypothesis: the select form

**Mac OS boots from this same disk controller perfectly.** So the chip model
is not broken in general — it is broken *for a driver that is not the ROM*.

`rtl/ncr53c96.sv`'s header states its contract:

> selects are the DMA form (`$C1`/`$C2`) with TC preloaded and an **EMPTY
> FIFO**

And `docs/scsi/netbsd-ncr53c9x-expectations.md` §2.1 states what a Unix driver
does on mac68k — `NCR_F_DMASELECT` is never set, so:

> **all four select variants are FIFO-preloaded**, never the DMA form

| Case | Command | Preloaded into FIFO |
|---|---|---|
| REQUEST SENSE | `$41` SELNATN | CDB only |
| normal | `$42` SELATN | IDENTIFY + CDB |
| sync/wide negotiation pending | `$43` SELATNS | IDENTIFY + CDB |
| tagged, `NCR_F_SELATN3` | `$46` SELATN3 | IDENTIFY + 2 tag bytes + CDB |

The model implements **none** of these. If A/UX writes `$42` to the command
register with IDENTIFY+CDB sitting in the FIFO, our chip does not recognise
the select at all, so the command never runs, no phase advances, and the
driver reports a protocol error — **at logical block 0, having transferred
nothing**. That matches the symptom exactly.

`rtl-gap-analysis.md` item 16 predicted this in advance:

> NetBSD-only features if NetBSD boot ever becomes a goal: `$43`/`$46`
> selects, FIFO-preloaded `$41`/`$42`, seq-step 0..4 semantics + duplicate in
> FIFO-flags top bits, reselection two-byte FIFO contract.

**Confirm it before building anything.** The cheapest confirmation is to see
which byte A/UX writes to the command register (r3). If it is `$41`/`$42`/
`$43`/`$46` rather than `$C1`/`$C2`, the hypothesis is settled. Options:

- Add a debug tap in `rtl/ncr53c96.sv` that latches the last few command-
  register writes and surface it the way the existing `dbg_*` taps are
  surfaced (`rtl/iosb.sv:499` notes the convention), then read it out.
- Or reproduce in the Verilator sim if the A/UX disk can be attached there —
  far faster to iterate than flashing, and `verilator/sim_main.cpp` already
  has a block device.

Do not skip this step. "Protocol error" has other possible causes (§4) and
guessing wrong costs a full RTL cycle each time.

## 4. Other candidates, if the select form is not it

Ranked by how likely they are to bite this early:

1. **Seq-step (`r6`) semantics 0..4.** The driver reads it after every select
   interrupt to decide how far the select got; the model would need to report
   it correctly, plus the duplicate in the FIFO-flags top bits. §2.3 of the
   NetBSD doc has the verbatim semantics.
2. **Interrupt/status read order and clear-on-read side effects.** §2.2 and
   §3.4 of that doc call the read order "a hard chip expectation". Gap
   analysis items 12 and 13 are in this area.
3. **Non-DMA transfer info** — gap item 8 says it is "wrong in both
   directions". A Unix driver on mac68k uses PDMA with bus-error flow control
   (§1.5), which is a different mechanism from the ROM's DREQ polling.
4. **Synchronous negotiation.** If A/UX sends an SDTR message out, the model
   must at minimum reject it cleanly (asynchronous) rather than wedge.
   `$43` SELATNS exists precisely to stop after IDENTIFY for this.
5. **Disconnect/reselect.** A/UX may allow disconnection; the model has no bus
   and cannot reselect. §2.5 and gap item 16's "reselection two-byte FIFO
   contract".
6. **Command set.** The model answers TEST UNIT READY, REQUEST SENSE,
   INQUIRY, MODE SENSE(6), READ CAPACITY(10), READ(6/10), WRITE(6/10) and
   returns CHECK CONDITION / ILLEGAL REQUEST for anything else. A/UX may issue
   MODE SENSE(10), READ DEFECT DATA, START STOP UNIT, or a 12-byte CDB during
   probing. Worth logging rejected opcodes once you can see them.

## 5. The `startup#` shell is a gift

A/UX drops to a single-user shell after autorecovery fails. That is an
interactive prompt on the failing machine. Before changing any RTL, consider
what it can tell you — `dmesg`-style buffers, `/etc/` contents if any slice
mounts, whether a different device node behaves differently. It costs nothing
and it is running right now.

Note the window is the "A/UX Startup" Mac application with File/Edit/Execute/
Preferences menus, so it is a Mac-side shell over the A/UX kernel; what is
available there is worth establishing early.

## 6. The setup, exactly as it stands

| | |
|---|---|
| Core running | `releases/wombat33_20260901.rbf`, md5 `abb5ede4f776d20ccd74367813aa1d28` (seed 13, timing met +0.132 ns) |
| A/UX disk | `/media/fat/games/Wombat33/HD60_512-AUX3.1-Installed.hda`, 2.1 GB |
| Mounted as | slot 0, per `/media/fat/config/Wombat33.s0` |
| **Pristine backup** | `/media/fat/games/Wombat33/backup/HD60_512-AUX3.1-Installed.zip`, 61 MB |
| Mac OS disk (known good) | `/media/fat/games/Wombat33/QuadSquad8.hda` + `backup/QuadSquad8.hda.gz` |

**Restore a pristine A/UX image between attempts** — A/UX may have written to
the disk during its failed autorecovery, and a half-fscked filesystem will
send you chasing ghosts:

```
ssh root@$MISTER_HOST 'cd /media/fat/games/Wombat33 && unzip -o backup/HD60_512-AUX3.1-Installed.zip'
```

To go back to Mac OS, point `Wombat33.s0` at `games/Wombat33/QuadSquad8.hda`.
Keeping a known-good Mac OS boot on hand is worth it: it is the control that
proves the core and the SCSI model still work after every change.

Deploy is `bash scripts/deploy_screenshot.sh` — seed 13 passes the timing gate
with no override. Screenshots: `bash scripts/grab_fresh.sh <out.png>`.

**Shutting A/UX down safely is an open question.** `scripts/guest/shutdown.sh`
drives the *Mac OS Finder's* Special menu and will not work here. From
`startup#` there may be a `halt`/`shutdown`; if A/UX is wedged at the log
screen with nothing mounted read-write, a reflash is *probably* harmless — but
confirm before assuming, and restore from the zip afterwards if unsure.

## 7. Tooling you have

- `scripts/guest/click.sh <x> <y> [click|dclick|move]` — absolute pointer
  positioning. Necessary because mrext motion is relative and Mac OS
  accelerates it; the event-to-pixel scale is not stable (1.3 to 8+ px per
  event). It pins to the top-left corner and walks with screenshot feedback.
- `scripts/guest/menu.sh`, `scripts/guest/shutdown.sh`,
  `scripts/guest/probe_cursor.py` — menus, Mac OS shutdown, pointer finding.
- `scripts/mister_ws.py` — keys and mouse. **Guest Command key is PS/2 Left
  Alt** (`rtl/adb.sv:530` → ADB `$37`), Linux keycode 56.
- Do not screenshot during anything you are timing; the capture is an HTTP
  POST the core services.

## 8. What "done" looks like

A/UX 3.1 boots to its desktop (or at least mounts root and reaches multi-user)
from `HD60_512-AUX3.1-Installed.hda`, and **Mac OS still boots from
`QuadSquad8.hda`** afterwards. The second half matters: the model is currently
shaped tightly around the ROM's contract, and the risk in widening it is
breaking the path that already works. Whatever lands should keep the existing
`verilator/` SCSI regressions green and re-verify a Mac OS boot on hardware
before it is called finished.
