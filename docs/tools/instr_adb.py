#!/usr/bin/env python3
"""Add a plusarg-gated ADB event trace to a copy of rtl/iosb.sv + rtl/adb.sv.

Sim-only: every insertion sits inside `synthesis translate_off`. Run against a
scratch build tree (not the repo) and enable with +adbtrace.

  python3 instr_adb.py /home/dani/wombat33/rtl
"""
import sys

D = sys.argv[1].rstrip('/') + '/'


def sub(s, old, new, what):
    assert old in s, "anchor not found: " + what
    return s.replace(old, new, 1)


# ---------------------------------------------------------------- iosb.sv
p = D + "iosb.sv"
s = open(p).read()
assert "adbtrace_en" not in s, "already instrumented"

anchor = "// VIA1 SR shim (lbmactwo): the qualified 6522 access edge is A_VIA at"
anchor2 = anchor
obs = """// synthesis translate_off
reg adbtrace_en; initial adbtrace_en = $test$plusargs("adbtrace");
reg [1:0] dbg_st_p; reg dbg_int_p;
always @(posedge clk) begin
  dbg_st_p <= {ADBST1, ADBST0}; dbg_int_p <= adb_int_n;
  if (adbtrace_en) begin
    if ({ADBST1,ADBST0} != dbg_st_p)
      $display("[%0t] ST   %b->%b int=%b", $time, dbg_st_p, {ADBST1,ADBST0}, adb_int_n);
    if (adb_int_n != dbg_int_p)
      $display("[%0t] INT  %b st=%b", $time, adb_int_n, {ADBST1,ADBST0});
  end
end
// synthesis translate_on

"""
s = sub(s, anchor, obs + anchor, "shim header")

a2 = "wire via1_sr_rd  = via1_access && via1_ren && (via1_addr == 4'hA);"
obs2 = a2 + """
// synthesis translate_off
always @(posedge clk) if (adbtrace_en) begin
  if (via1_sr_wr)  $display("[%0t] SRW  %02x acr=%b act=%b st=%b", $time, via1_din, via1_acr_shift_mode, via1_sr_active, {ADBST1,ADBST0});
  if (via1_sr_rd)  $display("[%0t] SRR  %02x acr=%b act=%b st=%b pend=%b", $time, via1_dout, via1_acr_shift_mode, via1_sr_active, {ADBST1,ADBST0}, adb_resp_pending);
  if (via1_acr_wr) $display("[%0t] ACRW mode=%b", $time, via1_din[4:2]);
  if (via1_access && via1_wen && via1_addr == 4'h0) $display("[%0t] ORB  %02x", $time, via1_din);
  if (via1_access && via1_wen && via1_addr == 4'h2) $display("[%0t] DDRB %02x", $time, via1_din);
end
// synthesis translate_on"""
s = sub(s, a2, obs2, "SR access")

c1 = """			if (via1_kbd_to_mac_fresh) begin
				via1_shift_timer <= 22'd0;"""
c1n = """			if (via1_kbd_to_mac_fresh) begin
				// synthesis translate_off
				if (adbtrace_en) $display("[%0t] DLV  FRESH %02x st=%b act=%b int=%b pend=%b", $time, kbd_to_mac, {ADBST1,ADBST0}, via1_sr_active, adb_int_n, adb_resp_pending);
				// synthesis translate_on
				via1_shift_timer <= 22'd0;"""
s = sub(s, c1, c1n, "fresh completion")

c2 = """				if (!adb_resp_pending || adb_bus_idle) begin
					via1_shift_timer <= 22'd0;"""
c2n = """				if (!adb_resp_pending || adb_bus_idle) begin
					// synthesis translate_off
					if (adbtrace_en) $display("[%0t] DLV  STALE %02x st=%b act=%b int=%b pend=%b", $time, kbd_to_mac, {ADBST1,ADBST0}, via1_sr_active, adb_int_n, adb_resp_pending);
					// synthesis translate_on
					via1_shift_timer <= 22'd0;"""
s = sub(s, c2, c2n, "stale completion")

c3 = """			if (via1_shift_timer == 22'd1) begin
				via1_shift_timer <= 22'd0;
				via1_sr_ext_complete <= 1'b1;
				via1_sr_out_pending <= 1'b1;"""
c3n = """			if (via1_shift_timer == 22'd1) begin
				// synthesis translate_off
				if (adbtrace_en) $display("[%0t] DLV  OUT   %02x st=%b act=%b", $time, via1_sr_shadow, {ADBST1,ADBST0}, via1_sr_active);
				// synthesis translate_on
				via1_shift_timer <= 22'd0;
				via1_sr_ext_complete <= 1'b1;
				via1_sr_out_pending <= 1'b1;"""
s = sub(s, c3, c3n, "shift-out completion")

c4 = """			if (adb_dout_strobe) begin
				kbd_to_mac            <= adb_dout;"""
c4n = """			if (adb_dout_strobe) begin
				// synthesis translate_off
				if (adbtrace_en) $display("[%0t] CAP  %02x st=%b", $time, adb_dout, {ADBST1,ADBST0});
				// synthesis translate_on
				kbd_to_mac            <= adb_dout;"""
s = sub(s, c4, c4n, "dout capture")

# Deadlock detector, always on (not gated on +adbtrace): the ROM's ADB interrupt
# handler runs at IPL 7 (ori.w #$700,sr) and contains a spin on PB3,
#     bclr #5,(a1) ; btst #3,(a1) ; beq -2
# i.e. "wait until ADB INT deasserts", entered with the bus in Data1. adb.sv
# asserts INT in ST_DATA1 whenever there is no command and no response, so if
# the driver ever reaches that spin with the transceiver empty the machine
# deadlocks with the screen frozen, no disk I/O, and the SCSI engine idle --
# exactly the signature of the boot stall being chased. This prints if the
# condition holds for longer than any real transaction could take.
det = """// synthesis translate_off
// see docs/tools/instr_adb.py: the ROM spins at IPL 7 waiting for ADB INT to
// deassert while the bus is in Data1; adb.sv asserts it there whenever it has
// nothing to deliver, so a long hold is a hang, not a wait.
reg [25:0] dbg_intstuck;
always @(posedge clk) begin
  if (!nreset) dbg_intstuck <= 0;
  else if ({ADBST1, ADBST0} == 2'b01 && !adb_int_n) begin
    dbg_intstuck <= dbg_intstuck + 1'b1;
    if (dbg_intstuck == 26'd33000)   $display("[%0t] ADBSTUCK INT asserted in DATA1 for 1ms", $time);
    if (dbg_intstuck == 26'd330000)  $display("[%0t] ADBSTUCK INT asserted in DATA1 for 10ms", $time);
    if (dbg_intstuck == 26'd3300000) $display("[%0t] ADBSTUCK INT asserted in DATA1 for 100ms -- DEADLOCK", $time);
  end
  else dbg_intstuck <= 0;
end
// synthesis translate_on

"""
s = sub(s, anchor2, det + anchor2, "deadlock detector")
open(p, "w").write(s)
print("iosb.sv patched")

# ----------------------------------------------------------------- adb.sv
p = D + "adb.sv"
s = open(p).read()
assert "AST " not in s, "already instrumented"

a = """		if (st != st_prev) begin
			st_prev <= st;
"""
an = """		if (st != st_prev) begin
			// synthesis translate_off
			if ($test$plusargs("adbtrace")) $display("[%0t] AST  %b->%b ri=%0d rl=%0d cv=%b srq=%b", $time, st_prev, st, resp_idx, resp_len, cmd_valid, any_srq);
			// synthesis translate_on
			st_prev <= st;
"""
s = sub(s, a, an, "adb st transition")

b = """		if (st == ST_COMMAND && adb_din_strobe) begin
			if (!cmd_valid) begin"""
bn = """		if (st == ST_COMMAND && adb_din_strobe) begin
			// synthesis translate_off
			if ($test$plusargs("adbtrace")) $display("[%0t] CMDB %02x cv=%b", $time, adb_din, cmd_valid);
			// synthesis translate_on
			if (!cmd_valid) begin"""
s = sub(s, b, bn, "command byte in")

c = """					if (!resp_empty) begin
						adb_dout <= response[resp_idx];
						adb_dout_strobe <= 1;"""
cn = """					if (!resp_empty) begin
						// synthesis translate_off
						if ($test$plusargs("adbtrace")) $display("[%0t] OUT  %02x idx=%0d len=%0d st=%b", $time, response[resp_idx], resp_idx, resp_len, st);
						// synthesis translate_on
						adb_dout <= response[resp_idx];
						adb_dout_strobe <= 1;"""
s = sub(s, c, cn, "response out")

d = """						// No data - return 0
						adb_dout <= 8'h00;"""
dn = """						// synthesis translate_off
						if ($test$plusargs("adbtrace")) $display("[%0t] OUT0 -- st=%b (resp empty)", $time, st);
						// synthesis translate_on
						// No data - return 0
						adb_dout <= 8'h00;"""
s = sub(s, d, dn, "empty response out")

e = """		if (mouseStrobe && (mouseXraw != 9'd0 || mouseYraw != 9'd0 || mouseBtn != mouseButton)) begin"""
en = e + """
			// synthesis translate_off
			if ($test$plusargs("adbtrace")) $display("[%0t] PS2M dx=%0d dy=%0d btn=%b", $time, $signed(mouseXraw), $signed(mouseYraw), mouseBtn);
			// synthesis translate_on"""
s = sub(s, e, en, "ps2 mouse event")

f = """		if (cmd_valid && !cmd_processed && st == ST_COMMAND && cmd_type != 2'b10) begin
			process_command(1'b0);"""
fn = """		if (cmd_valid && !cmd_processed && st == ST_COMMAND && cmd_type != 2'b10) begin
			// synthesis translate_off
			if ($test$plusargs("adbtrace")) $display("[%0t] CMD  %02x a=%0d t=%0d r=%0d", $time, cmd_byte, cmd_addr, cmd_type, cmd_reg);
			// synthesis translate_on
			process_command(1'b0);"""
s = sub(s, f, fn, "command decode")
open(p, "w").write(s)
print("adb.sv patched")
