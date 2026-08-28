`timescale 1ns / 1ps
//============================================================================
//  wombat33 — Verilator simulation wrapper
//
//  `emu` here is the SIMULATION top — the sim-friendly port surface the
//  framework's sim_main.cpp drives.  Stage 1 of the machine bring-up: the
//  quadra800 machine (AP68040 + overlay + decode) with RAM/ROM/VRAM as
//  plain arrays behind the platform beat port.  The ROM image loads from
//  +rom=<hexfile> (default quadra800.rom.hex, built by the Makefile from
//  releases/quadra800.rom).  The template pattern core still paints the
//  VGA window and paces frames until DAFB lands in stage 2.
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

	// ROM/disk loading interface (ioctl) — the MiSTer quadra800.rom path;
	// the sim loads the ROM by $readmemh instead
	input         ioctl_download,
	input         ioctl_wr,
	input  [24:0] ioctl_addr,
	input  [15:0] ioctl_dout,
	input  [7:0]  ioctl_index,
	output reg    ioctl_wait = 1'b0,

	// CPU debug taps
	output [31:0] debug_pc,        // fetch pointer (debug_status pc)
	output [15:0] debug_opcode,    // current IR
	output        debug_fetch_valid,
	output [31:0] debug_data_addr, // last bus-error address
	output        debug_berr,      // machine bus-error pulse
	output        debug_overlay,
	output        debug_cpu_fault,
	output        debug_cpu_halted
);

//----------------------------------------------------------------------------
// Template pattern core: VGA timing/frame pacing until DAFB exists
//----------------------------------------------------------------------------
wire HBlank, HSync, VBlank, VSync;
wire ce_pix;
wire hvcnt_atzero;
wire [7:0] video;

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

//----------------------------------------------------------------------------
// The machine
//----------------------------------------------------------------------------
localparam RAM_ADDR_BITS = 23;                 // 8 MB
localparam RAM_WORDS  = 1 << (RAM_ADDR_BITS-2);
localparam ROM_WORDS  = 262144;                // 1 MB
localparam VRAM_WORDS = 262144;                // 1 MB

wire        mem_req, mem_write;
wire [31:2] mem_addr;
wire  [3:0] mem_be;
wire [31:0] mem_wdata;
wire  [1:0] mem_memsel;
reg  [31:0] mem_rdata;
reg         mem_ack;

wire [255:0] m_debug_status;
wire [127:0] m_debug_status2;

quadra800 #(.RAM_ADDR_BITS(RAM_ADDR_BITS)) machine (
	.clk(clk_sys),
	.nreset(~reset),
	.ce(1'b1),

	.mem_req(mem_req),
	.mem_write(mem_write),
	.mem_addr(mem_addr),
	.mem_be(mem_be),
	.mem_wdata(mem_wdata),
	.mem_memsel(mem_memsel),
	.mem_rdata(mem_rdata),
	.mem_ack(mem_ack),

	.dbg_berr(debug_berr),
	.dbg_berr_addr(debug_data_addr),
	.dbg_overlay(debug_overlay),
	.debug_status(m_debug_status),
	.debug_status2(m_debug_status2),
	.debug_fault(debug_cpu_fault),
	.debug_halted(debug_cpu_halted)
);

assign debug_pc          = m_debug_status[31:0];
assign debug_opcode      = m_debug_status[63:48];
assign debug_fetch_valid = ~reset;

//----------------------------------------------------------------------------
// Platform memory: plain arrays behind the beat port (see quadra800.sv for
// the contract).  ROM writes are acked and discarded, as djMEMC does.
//----------------------------------------------------------------------------
reg [31:0] ram  [0:RAM_WORDS-1]  /*verilator public*/;
reg [31:0] rom  [0:ROM_WORDS-1]  /*verilator public*/;
reg [31:0] vram [0:VRAM_WORDS-1] /*verilator public*/;

reg [1023:0] rom_file;
initial begin
	if (!$value$plusargs("rom=%s", rom_file))
		rom_file = "quadra800.rom.hex";
	$readmemh(rom_file, rom);
end

wire [RAM_ADDR_BITS-3:0] ram_idx  = mem_addr[RAM_ADDR_BITS-1:2];
wire [17:0]              rom_idx  = mem_addr[19:2];
wire [17:0]              vram_idx = mem_addr[19:2];

always @(posedge clk_sys) begin
	mem_ack <= 0;
	if (mem_req && !mem_ack) begin
		mem_ack <= 1;
		case (mem_memsel)
		2'd0: begin
			mem_rdata <= ram[ram_idx];
			if (mem_write) begin
				if (mem_be[3]) ram[ram_idx][31:24] <= mem_wdata[31:24];
				if (mem_be[2]) ram[ram_idx][23:16] <= mem_wdata[23:16];
				if (mem_be[1]) ram[ram_idx][15:8]  <= mem_wdata[15:8];
				if (mem_be[0]) ram[ram_idx][7:0]   <= mem_wdata[7:0];
			end
		end
		2'd1: mem_rdata <= rom[rom_idx];
		default: begin
			mem_rdata <= vram[vram_idx];
			if (mem_write) begin
				if (mem_be[3]) vram[vram_idx][31:24] <= mem_wdata[31:24];
				if (mem_be[2]) vram[vram_idx][23:16] <= mem_wdata[23:16];
				if (mem_be[1]) vram[vram_idx][15:8]  <= mem_wdata[15:8];
				if (mem_be[0]) vram[vram_idx][7:0]   <= mem_wdata[7:0];
			end
		end
		endcase
	end
end

endmodule
