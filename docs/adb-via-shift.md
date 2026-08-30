# The ADB phantom-input fault: every delivered byte was shifted left one bit

**Status:** root cause found and fixed in `rtl/via6522.sv`; proven in Verilator
against a scored control. Hardware validation pending.

## Symptom

Mouse motion reached the guest but **button presses never did** — an open menu
would not dismiss on a click — and pure motion *injected* input of its own:
240 `mouseMove` messages and nothing else made Photoshop's palettes vanish and
opened the File menu. `scripts/mac_shutdown.sh` could navigate to
Special → Shut Down but could not click it, which is why no core swap could be
done safely.

## What was actually happening

`rtl/adb.sv` and the VIA1 shift-register shim in `rtl/iosb.sv` were both
delivering the right bytes. The VIA then **shifted every one of them left by a
bit** before the driver could read it, with `cb2_i` (tied low) in the LSB.

Measured in sim, delivered byte → byte the driver read out of SR:

| delivered | driver read | note |
|---|---|---|
| `3c` | `78` | mouse Talk R0 command echoed back |
| `08` | `10` | Talk R0 byte 0, `{~button, dy}` — button **down** |
| `88` | `10` | Talk R0 byte 1, `{1, dx}` |
| `62` | `c4` | keyboard Talk R3 address/handler |

An ADB mouse Talk R0 response is `{~button, dy[6:0]}` / `{1, dx[6:0]}`, so
**bit 7 of byte 0 is the button** — exactly the bit a left shift throws away.
That is the whole button failure. What the guest saw in its place was the old
bit 6, the *sign of dy*: moving the mouse down (dy > 0, so `dy[6] = 0`, read as
`~button = 0`) pressed the button, and moving up released it. Hence "motion
opens menus".

The same shift mangles keyboard bytes — `{up_down, keycode[6:0]}` becomes
`{keycode[6], keycode[5:0], 0}` — so the up/down flag is replaced by a keycode
bit and the keycode is doubled. Any byte that reaches the keyboard path arrives
as a different key, pressed rather than released.

## Root cause

`via6522.sv` drove the *internal* shift clock from `shift_active`:

```verilog
if (shift_active == 1'b0) begin
    if (shift_mode_control == 3'b000) shift_clock <= cb1_i;
    else                              shift_clock <= 1'b1;   // idle high
end else if (shift_clk_sel == 2'b11) begin
    shift_clock <= cb1_i;                                    // external clock
end
```

In ACR modes `011` and `111` (`shift_clk_sel == 2'b11`) CB1 is an *input* and
the internal shift clock is simply the pin — which for VIA1 is `cb1_i = 1'b0`,
so there should be no shift edges at all. But the idle branch forced the clock
high, so arming and disarming a shift each produced an edge of their own:

- arm: `shift_clock` 1 → 0, a falling edge (`shift_tick_f`, the shift-*out* path)
- disarm: `shift_clock` 0 → 1, a rising edge (`shift_tick_r`, the shift-*in* path)

The shim's external completion clears `shift_active` and loads `sr_ext_data`
into `shift_reg` in the same cycle. One `rising` later the forced-high clock
produced the spurious `shift_tick_r`, and on the next `falling`:

```verilog
else if (shift_dir == 1'b0 && shift_tick_r == 1'b1)
    shift_reg <= {shift_reg[6:0], ser_cb2_c};
```

shifted the byte that had just been loaded. Exactly once, every time.

The fix is to let external-clock mode mean what it says — the internal clock
follows the pin whether or not a shift is armed:

```verilog
if (shift_mode_control == 3'b000 || shift_clk_sel == 2'b11) shift_clock <= cb1_i;
else if (shift_active == 1'b0)                              shift_clock <= 1'b1;
else if (shift_pulse == 1'b1)                               shift_clock <= ~shift_clock;
```

Non-external modes are untouched. VIA1 is the only `via6522` instance in the
core (VIA2 is the Quadra pseudo-VIA, ports and IFR/IER only).

## How it was measured

`docs/tools/instr_adb.py` patches a *scratch copy* of `rtl/iosb.sv` and
`rtl/adb.sv` with a `+adbtrace` event log (all inside `synthesis translate_off`)
covering ST transitions, ADB INT, VIA SR/ACR/ORB accesses, transceiver response
bytes and shim completions. `docs/tools/adb_check.py` pairs every byte the shim
**delivered** with the next byte the driver **read** out of SR and scores the
match rate.

```bash
python3 docs/tools/instr_adb.py <scratch-tree>/rtl
# build, then:
./obj_dir/Vemu --headless --no-cpu-trace --max-cycles 3000000000 --disk run.hda \
    +rom=quadra800-fastboot.rom.hex +adbtrace +mousewiggle=3 +mousebtn=5 > trace.log
python3 docs/tools/adb_check.py trace.log
```

`+mousewiggle=N` moves the pointer every N frames and `+mousebtn=N` holds and
releases the button across runs of those reports, so real Talk R0 bytes with
both button states appear in the trace.

The checker must not pair across a shift-*out* completion or a CPU write to SR:
both replace the shift register's contents, so the read that follows is the
driver's own byte echoed back, not a delivered one.

## Result

Same disk, same ROM, same injected mouse traffic, scored against a control
build that differs only in the `via6522.sv` hunk above. Only non-`$00` bytes are
informative, since `$00 << 1` is still `$00`:

| | pairs | non-zero bytes intact |
|---|---|---|
| unfixed (control) | 1318 | **0 / 82 (0%)** — every one `byte → byte<<1` |
| fixed | 7210 | **670 / 670 (100%)** |

and the button now arrives: `08 → 08` (button down) and `88 → 88` (up), where
the control read `10` for both.

### Confirmed on hardware before the fix was even deployed

The prediction "the guest's button follows bit 6 of dy, not the button" was
tested against the *running, unfixed* core over the mrext websocket, sending
`mouseMove` only and **no `mouseBtn` at all**:

- pin to the top-left with `mouse:-12,-12` (dy < 0 → `dy[6] = 1` → reads as
  released), then move down and right onto the Apple menu (dy ≥ 0 → `dy[6] = 0`
  → reads as **pressed**): the menu opened and stayed open. `scratch/hw_motionclick.png`
- one `mouse:0,-1` (up): the menu closed. `scratch/hw_motionrelease.png`

Driving that deliberately is also what finally allowed a **clean guest shutdown**
— pin, drag right to Special, drag down to Shut Down, release with a 1-pixel up
move — reaching "It is now safe to switch off your Macintosh"
(`scratch/hw_shutdown_done2.png`) instead of another power-cut on a mounted HFS
volume. Once the fix is deployed the ordinary `mouseBtn` path should work and
`scripts/mac_shutdown.sh` needs no such trick.

## What this does *not* fix

The shim still fabricates shift completions the transceiver never produced:

- one `STALE` completion per transaction while the bus is IDLE (`st=11`),
  carrying whatever `kbd_to_mac` last held, and
- a `$00` from `adb.sv` each time the driver re-enters a data state with the
  response already exhausted.

In the fixed run all 2744 `STALE` completions carried `$00`, because the last
thing captured before each is that trailing resp-empty `$00` — so in practice
the fabricated byte is always the "no data" value, not a stale mouse report. The
real Talk R0 bytes also pair up exactly (453 byte-0 deliveries, 453 byte-1), so
the framing itself is consistent.

The driver measurably blocks waiting for the first of these — it sits in `st=11`
for exactly `SHIFT_DELAY` and moves on only once the completion fires — so it
cannot simply be deleted. Whether it still causes misframing now that the bytes
themselves are intact is the next thing to measure, not to assume.

Note also that the earlier experiments that rejected `$FF` and `$00` as the
invented byte (`24eefbc`) were run **with this shift bug present**: `$FF` was
delivered to the guest as `$FE` and `$00` as `$00`. Their conclusions are about
a corrupted channel and are worth re-deriving before being reused.
