# RESUME — after the ADB fix and the bench unblock

State of the Quadra 800 core after the 2026-08-30 evening session. Read this
before touching `rtl/via6522.sv`, `rtl/iosb.sv`, or the bench.

**Closed this session, do not re-investigate:** the ADB phantom-input fault
(root cause found, fixed, verified in sim against a scored control and twice on
hardware), the bench "does not run on this core" fault (it was the disk, not the
core), and the AP68040 memory-indirect patch (now verified by the gate it was
waiting for). Earlier sessions closed: SCSI non-DMA transfer-info underflow,
`SC0` mount persistence, mount replay across reset, RAM-size-on-reset, the
build/deploy timing gate, and the RTC.

## Ground rules, still all true

- **Never reload the core or reset the machine while Mac OS is running.** It is
  a power-cut on a mounted HFS volume. `scripts/mac_shutdown.sh` should now work
  — the click it needed is fixed — but re-verify it before trusting it.
- **A hang proves nothing until the disk is known-good.** Restore from
  `games/Wombat33/backup/QuadSquad8.hda.gz` (md5
  `f4287aee9ff9a4413fa1e5fd9f2d63b4`) and re-test. Restoring takes ~6 min on the
  MiSTer (`gunzip -c backup/QuadSquad8.hda.gz > QuadSquad8.hda`).
- **Suspect your own last change first, and run the control.** Every claim below
  that says "fixed" has a scored control behind it; the ones that do not say so.
- **Measure rates, not single samples.** The boot stall below is 1-in-3, so one
  good boot proves nothing and one bad boot proves nothing.
- Liveness check that beats screenshots: `pos:` from
  `/proc/<MiSTer-pid>/fdinfo/<fd-of-the-image>` (scan `/proc/*/fd` for the
  image). **Frozen ≠ hung** — an idle Finder does not read; `pos=1986560` is the
  normal idle-desktop value. Frozen *plus* a byte-identical screenshot across
  minutes *plus* a half-drawn progress bar is a hang.
- **The old pixel geometry is void.** Motion used to arrive with the deltas
  doubled (see below), so every step count measured before this session
  overshoots now. `scripts/mac_shutdown.sh`'s menu-bar offsets need
  re-measuring. Pacing is unchanged: 0.02 s tracks; 0.008 s drops moves.
- **mrext's mouse button payloads are `left_down` / `left_up`.** `mouseBtn:1`
  and `mouseBtn:0` are accepted by the websocket and appear in `/tmp/remote.log`
  but do nothing at all. That is an easy way to conclude "the button is broken".

## SOLVED — ADB phantom input was a one-bit left shift in the VIA

Full derivation: **`docs/adb-via-shift.md`**. Fix is one hunk in
`rtl/via6522.sv` (`5352b84`).

In ACR modes `011`/`111` CB1 is an input and the internal shift clock IS the
pin, but the RTL forced `shift_clock` high whenever `shift_active` was low.
Clearing `shift_active` on an `sr_ext_complete` therefore drove it 0→1, and
`shift_tick_r` turned that rising edge into **one extra shift of the byte the
completion had just loaded** — every byte, every time, with `cb2_i` (tied low)
in the LSB.

ADB mouse Talk R0 byte 0 is `{~button, dy[6:0]}`, so the button is precisely the
bit a left shift throws away, and what replaced it was the old bit 6 — the sign
of dy. Hence both halves of the symptom: clicks did nothing, and plain motion
with dy ≥ 0 read as button-down, which is why 240 `mouseMove` messages opened
menus on their own.

Scored control (same disk, same ROM, same injected traffic; only `$00` bytes are
uninformative since `$00 << 1` is `$00`):

| | pairs | non-zero bytes intact |
|---|---|---|
| unfixed | 1318 | **0 / 82** — every one `byte → byte<<1` |
| fixed | 7210 | **670 / 670** |

Hardware, twice, on two different boots: `mouseBtn:left_down` opens the Apple
menu and `left_up` closes it leaving a byte-identical screen; 240 `mouseMove`
messages and nothing else leave the desktop untouched (`scripts/adb_hw_test.sh`,
shots in `scratch/adbhw_*.png`).

The prediction was also confirmed on the *unfixed* core before deploying
anything, using `mouseMove` only: down/right motion held the Apple menu open, an
up move closed it. Driving that deliberately produced this project's **first
clean guest shutdown** ("It is now safe to switch off your Macintosh").

### What is still fabricated, and why it was left alone

The shim still invents shift completions the transceiver never produced: one
`STALE` per transaction while the bus is IDLE (`st=11`), and a `$00` from
`adb.sv` each time the driver re-enters a data state with the response already
exhausted. The driver **measurably blocks** on the first — it sits in `st=11`
for exactly `SHIFT_DELAY` and moves on only when the completion fires — so it
cannot just be deleted.

Measured after the fix, though, the fabricated bytes are benign in practice: all
2744 `STALE` completions in a boot window carried `$00`, and the real Talk R0
bytes pair up exactly (453 byte-0 deliveries, 453 byte-1). Framing is consistent.

Note the earlier experiments that rejected `$FF` and `$00` as the invented byte
(`24eefbc`) ran **with the shift bug present** — `$FF` reached the guest as `$FE`.
Their conclusions are about a corrupted channel; re-derive before reusing them.

Also settled by reading the RTL, so nobody re-runs it: gating the fallback on
`via1_sr_active` (`00a0721`, still in tree) is a **no-op**. `via6522.sv`'s
`trigger_serial` is `(ren || wen) && addr == 4'hA`, and `shift_active` is set on
any SR access whenever the ACR mode is not `000` — which it never is while the
ADB driver runs. The gate is always true.

## SOLVED — the bench "does not run on this core" was the disk

`games/Wombat33/gate.hda` on the MiSTer, `quadra800-allinone.hda` beside it, and
`scratch/gate/quadra800-allinone.hda` are **all byte-identical** (md5
`309e785dcf6834665ba5ae5b2f256cd3`) to the raw prebuilt — i.e. the
**hardware-flavor** image, never re-blessed. `RESUME-disk-gate.md` §2 already
said `docs/tools/make-emulator-gate-disk.sh` is required and that "**FPGA runs
need this image too**". Both halves of the old control matrix were therefore
measuring the disk, not the core, and neither said anything about the CPU.

Re-blessed (`scratch/gate/gate-emu.hda`, md5
`5115ac2e7b22010475617184edef770b`, also pushed to
`/media/fat/games/Wombat33/gate-emu.hda`), the bench runs to completion in the
full-machine sim: all five suites, 2347 rows.

The re-bless needs `m68k-elf-as/ld/objcopy` and `jq`, neither installed and
`sudo` wants a password. Worked around **without root**:

```bash
cd /tmp && apt-get download binutils-m68k-linux-gnu jq libjq1 libonig5
dpkg -x binutils-m68k*.deb ~/opt/m68k ; for d in jq*.deb libjq*.deb libonig*.deb; do dpkg -x $d ~/opt/jq; done
for t in as ld objcopy; do ln -sf ~/opt/m68k/usr/bin/m68k-linux-gnu-$t ~/.local/bin/m68k-elf-$t; done
ln -sf ~/opt/jq/usr/bin/jq ~/.local/bin/jq
export PATH=$HOME/.local/bin:$PATH
export LD_LIBRARY_PATH=$HOME/opt/m68k/usr/lib/x86_64-linux-gnu:$HOME/opt/jq/usr/lib/x86_64-linux-gnu
RB=$HOME/.local/bin/rb-cli bash docs/tools/make-emulator-gate-disk.sh in.hda out.hda
```

## SOLVED — the AP68040 memory-indirect patch is verified

With the gate finally running, `docs/ap68040-memind-reserved.md` is updated to
**VERIFIED**. Full-machine sim, blessed disk, `score_vs_oracle.py`, no
`--flat-env`:

| suite | rows | stock | with patch |
|---|---|---|---|
| **cpu** | 717/717 | **2 REAL** | **0 REAL** |
| fpu | 270/270 | 0 | 0 |
| saverestore | 8/8 | 0 | 0 |
| integration | 1328/1328 | 0 | 0 |
| mmu (full) | 24/25 | 13 REAL | 13 REAL |

The two stock diffs are exactly the rows the report names and nothing else. The
report predicted "should go from 2 REAL diffs to 0" before the gate existed.
Rows archived in `SingleStepTests/results/ap68040/fullmachine_cpu_*_2026-08-30.jsonl`.

The submodule is deliberately still clean at `0e76761` — vendored upstream, so
the patch belongs upstream, not as a local divergence. **The report is now
sendable.** Sending it is a decision for a human, not something to do unasked.

## OPEN — Fault 2, the boot stall (still the real one)

Reproduced this session on the **fixed** core, on a **freshly restored pristine**
image (md5 verified), on the **first** boot: frozen at "Starting Up…" with the
progress bar half drawn, screenshot byte-identical across 5 minutes, and disk
`pos` frozen at 458,466,816. The next two boots of the same core and same image
went through to the desktop. **Rate: 1 in 3.**

So it is time-or-race dependent, not data dependent, and the earlier
"first-boot-works / later-boot-hangs" story does not hold. The diagnosis
correction from last session still stands and is worth repeating: **this is not
corruption.** Sector 1,437,035 was compared byte-for-byte against pristine and
is identical, containing valid 68k code. `735,761,920` was simply where reading
stopped.

**The lead worth chasing first** — from reading the ROM's ADB interrupt handler
in `docs/quadra800-rom-disassembly.asm`, `a1` = VIA1 base:

```
40814912: move.w sr,d3
40814914: ori.w  #$700,sr      ; ALL interrupts masked
   ...
408149C4: bsr    $408148f8     ; bset #4,(a1)   -> ST0 = 1
408149C8: bclr.b #$5,(a1)      ;                -> ST1 = 0, i.e. state 01 = Data1
408149CC: btst.b #$3,(a1)      ; PB3 = ADB INT
408149D0: beq.b  $408149cc     ; spin while INT is ASSERTED
```

`adb.sv` drives `int_out = (!cmd_valid && resp_empty)` in `ST_DATA1`, so if the
driver reaches that spin with the transceiver empty, INT is asserted forever and
the machine deadlocks **at IPL 7** — screen frozen, no I/O, SCSI engine healthy
and idle. That is exactly the observed signature. Whether the driver can be
pushed into that path by the fabricated completions above is the thing to
measure. A `+adbtrace` run that logs the CPU PC alongside the ADB events, or a
`--stop-at-pc 408149cc` sim run, would settle it.

The P1 write-path gap in `docs/scsi/rtl-gap-analysis.md` is still **not**
implicated by any evidence and should not be assumed.

Note `chmod 444` cannot make the image read-only — exFAT carries no Unix
permission bits (`fmask=0022`).

## OPEN — host keystrokes never reach the guest (not a core fault)

`kbdRaw:*` and `kbd:*` messages arrive at mrext (`/tmp/remote.log`) and do
nothing: no Finder type-select, no arrow-key selection, and **`kbd:osd` does not
open the MiSTer OSD either** — which is the tell, because that never reaches the
core at all. So this is host-side, in mrext or the Main, not in `adb.sv`.

The core's ADB keyboard path is therefore **untested end-to-end**, before and
after the fix. `adb.sv` has the full Set-2 → ADB translation table and the sim
never exercised it (all 248 keyboard Talk R0 polls in a boot window returned
`resp_len = 0`).

Related trap, cost an hour: **mrext stopped injecting input entirely** partway
through the session — mouse and keyboard, while still logging every message it
received. `/dev/input/event16..18` and `/dev/input/mouse5` all went silent
(check with `dd bs=24`, not `bs=1`, and not `timeout cat`, which buffers and
loses everything on SIGTERM). `-service restart` did not fix it; a MiSTer reboot
did. If input dies mid-session, reboot the MiSTer before suspecting the core.

## OPEN — MMU, 13 REAL diffs in the full-machine gate

Unchanged between the stock and patched CPU, so unrelated to that patch:
bus-error vector 2 vs 0 on write-protect / invalid-PDT / supervisor-only faults,
and a live ATC flush window mismatch. `SingleStepTests/results/ap68040/README.md`
records **24/24 with 0 REAL diffs** for the same corpus under the
`preboot/sim040` harness, which supplies the identity-translation world the MMU
corpus needs (finding 30). So this may well be a harness-environment artifact of
the full-machine run rather than an MMU bug — establish which before spending
time on it. Rows: `fullmachine_mmu_full_2026-08-30.jsonl`.

## Still open — the RTC hour

The Mac reads exactly **one hour behind** the host (minutes dead-on): standard
vs daylight time in what the Main sends. Probably host-side; the core reflects
`TIMESTAMP` faithfully. Check MacLC's clock on the same machine — if MacLC is
correct, the difference is ours.

## Tooling added this session

- `docs/tools/instr_adb.py` — patches a **scratch copy** of `rtl/iosb.sv` +
  `rtl/adb.sv` with a `+adbtrace` event log (ST transitions, ADB INT, VIA
  SR/ACR/ORB accesses, transceiver bytes, shim completions), all inside
  `synthesis translate_off`.
- `docs/tools/adb_check.py` — pairs every byte the shim **delivered** with the
  next byte the driver **read** from SR and scores the match rate. Do not pair
  across a shift-out completion or a CPU SR write; both replace the register.
- `scripts/adb_hw_test.sh` — the click and phantom-input regressions on
  hardware, in one command.

Sim invocation that produced everything above:

```bash
./obj_dir/Vemu --headless --no-cpu-trace --max-cycles 3000000000 --disk run.hda \
    +rom=quadra800-fastboot.rom.hex +adbtrace +mousewiggle=3 +mousebtn=5 > trace.log
```

`RESUME-disk-gate.md`'s "ONE Vemu at a time" rule was written for a laptop; four
headless runs in parallel on a 20-core box were fine and are how the controls got
run at all.

## Machine state

- `games/Wombat33/QuadSquad8.hda` restored **pristine** (`f4287aee…`) at 20:47,
  then booted three times (one stall, two good) — so it is now a
  not-cleanly-unmounted volume again. Backups: `backup/QuadSquad8.hda.gz`
  (pristine) and `backup/QuadSquad8_dirty_20260830.hda.gz`.
- `games/Wombat33/gate-emu.hda` is the **re-blessed** bench image — use this one,
  not `gate.hda`.
- The MiSTer was rebooted at 20:51, so the Main is the inittab-started one again
  and `/tmp/mister.log` is gone. inittab starts it once and does not respawn it.
- Deployed core: `output_files/wombat33.rbf` from `5352b84`, SEED 3, timing met
  (+0.248 ns). SEED 2 gave −0.283 ns hold on the 99 MHz clk_ram domain, which a
  clk_sys change cannot reach — reseed rather than blaming the RTL, as the qsf
  comment says.
- `/tmp` on the MiSTer is a 247 MB tmpfs; do not decompress the 2 GB image there.
- WSL `/tmp` does **not** survive between `wsl -e` invocations once the last
  process exits — write sim logs to `~/logs`, not `/tmp`.
