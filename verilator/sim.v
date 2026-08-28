`timescale 1ns / 1ps
//============================================================================
//  wombat33 — Verilator simulation wrapper
//
//  Same shape as the other cores' verilator setups (MacLC_MiSTer et al):
//  `emu` here is the SIMULATION top — the sim-friendly port surface the
//  framework's sim_main.cpp drives — wrapping the core guts that the real
//  wombat33.sv `emu` wires to the MiSTer framework. Today the guts are the
//  MiSTer template's pattern generator (rtl/mycore.v); the AP68040 machine
//  replaces it as bring-up proceeds, and the debug taps below are the
//  landing pads for the core's debug_status wiring.
//============================================================================

module emu
(
	input         clk_sys,
	input         reset,

	// Template option bits (stand-ins for the MiSTer status word):
	//   sim_status[2]   TV mode (0 NTSC, 1 PAL)
	//   sim_status[4:3] Noise colour (0 white, 1 red, 2 green, 3 blue)
	input  [31:0] sim_status,

	// PS2 keyboard/mouse (unused by the template; wired for the machine)
	input  [10:0] ps2_key,
	input  [24:0] ps2_mouse,

	// VGA output
	output [7:0]  VGA_R,
	output [7:0]  VGA_G,
	output [7:0]  VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_HB,
	output        VGA_VB,
	output        CE_PIXEL,

	// Audio output
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,

	// ROM/disk loading interface (ioctl) — the future quadra800.rom path
	input         ioctl_download,
	input         ioctl_wr,
	input  [24:0] ioctl_addr,
	input  [15:0] ioctl_dout,
	input  [7:0]  ioctl_index,
	output reg    ioctl_wait = 1'b0,

	// CPU debug taps (tied off until the AP68040 machine lands)
	output [31:0] debug_pc,
	output [15:0] debug_opcode,
	output        debug_fetch_valid,
	output [31:0] debug_data_addr
);

wire HBlank, HSync, VBlank, VSync;
wire ce_pix;
wire hvcnt_atzero;
wire [7:0] video;

// Same reset release rule as wombat33.sv: hold the pattern core in reset
// until the H/V counters pass zero so the first frame is stable.
reg reset_core = 1;
always @(posedge clk_sys) begin
	if (reset) reset_core <= 1;
	else if (hvcnt_atzero) reset_core <= 0;
end

mycore mycore
(
	.clk(clk_sys),
	.reset(reset_core),

	.pal(sim_status[2]),
	.scandouble(1'b0),

	.ce_pix(ce_pix),
	.hvcnt_atzero(hvcnt_atzero),

	.HBlank(HBlank),
	.HSync(HSync),
	.VBlank(VBlank),
	.VSync(VSync),

	.video(video)
);

wire [1:0] col = sim_status[4:3];

assign CE_PIXEL = ce_pix;
assign VGA_HS = HSync;
assign VGA_VS = VSync;
assign VGA_HB = HBlank;
assign VGA_VB = VBlank;
assign VGA_G  = (!col || col == 2) ? video : 8'd0;
assign VGA_R  = (!col || col == 1) ? video : 8'd0;
assign VGA_B  = (!col || col == 3) ? video : 8'd0;

assign AUDIO_L = 16'd0;
assign AUDIO_R = 16'd0;

assign debug_pc = 32'd0;
assign debug_opcode = 16'd0;
assign debug_fetch_valid = 1'b0;
assign debug_data_addr = 32'd0;

endmodule
