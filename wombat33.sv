//============================================================================
//  wombat33 — MiSTer top for the Quadra 800 machine.
//
//  Platform memory contract (see rtl/quadra800.sv and verilator/sim.v):
//  one ack-based beat port with mem_memsel (0 RAM, 1 ROM, 2 VRAM) plus a
//  registered 1-cycle video scanout port.  Here:
//   - RAM (32 MB) and ROM (1 MB) live in DDR3 behind a simple bridge —
//     the machine's bus FSM already tolerates wait states and the 68040
//     caches absorb the latency.  ROM writes are acked and discarded
//     (djMEMC behavior), which also write-protects the ROM region.
//   - VRAM is on-chip BRAM, 308 KB physical (640x480@8bpp + headroom
//     for the driver's framebuffer base offset — MacIIvi precedent)
//     advertised as 512 KB via window aliasing + a fold — see the VRAM
//     section — because the DAFB scanout expects registered 1-cycle
//     reads.  Still the main BRAM consumer (~2.5 Mbit).
//   - The ROM uploads as boot.rom (ioctl index 0) into the DDR3 ROM
//     region; the machine is held in reset until it lands.
//   - The SCSI disk is hps_io block device 0 (mount a .hda in the OSD);
//     the 53C96 speaks the 16-bit sd_buff interface natively.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1;                        // ASC samples are signed
assign AUDIO_MIX = 0;

assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"Wombat33;;",
	"S0,HDAVHD,Mount SCSI disk;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire  [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;

wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;
reg         ioctl_wait;

wire [31:0] sd_lba[1];
wire  [0:0] sd_rd, sd_wr;
wire  [0:0] sd_ack;
wire [12:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din[1];
wire        sd_buff_wr;
wire  [0:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;

hps_io #(.CONF_STR(CONF_STR), .WIDE(1), .VDNUM(1), .BLKSZ(2)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.buttons(buttons),
	.status(status),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	.sd_lba(sd_lba),
	.sd_blk_cnt('{6'd0}),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
wire pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),                    // 33.33 MHz machine clock
	.locked(pll_locked)
);

// hold the machine until the PLL locks and boot.rom has landed in DDR3
wire rom_index = (ioctl_index[5:0] == 0);
reg  rom_loaded = 0;
reg  dl_d = 0;
always @(posedge clk_sys) begin
	dl_d <= ioctl_download;
	if (dl_d && !ioctl_download && rom_index) rom_loaded <= 1;
end

wire reset = RESET | status[0] | buttons[1] | ioctl_download |
             ~rom_loaded | ~pll_locked;

///////////////////////   MACHINE   //////////////////////////////

wire        mem_req, mem_write;
wire [31:2] mem_addr;
wire  [3:0] mem_be;
wire [31:0] mem_wdata;
wire  [1:0] mem_memsel;
reg  [31:0] mem_rdata;
reg         mem_ack;

wire [21:2] vid_addr;
reg  [31:0] vid_rdata;

wire [255:0] m_debug_status;
wire [127:0] m_debug_status2;

localparam RAM_ADDR_BITS = 25;             // 32 MB

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

	.vid_addr(vid_addr),
	.vid_rdata(vid_rdata),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_HB(m_hblank),
	.VGA_VB(m_vblank),
	.CE_PIXEL(CE_PIXEL),

	.AUDIO_L(AUDIO_L),
	.AUDIO_R(AUDIO_R),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),

	.img_mounted(img_mounted[0]),
	.img_size(img_size),
	.io_lba(sd_lba[0]),
	.io_rd(sd_rd[0]),
	.io_wr(sd_wr[0]),
	.io_ack(sd_ack[0]),
	.sd_buff_addr(sd_buff_addr[7:0]),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din[0]),
	.sd_buff_wr(sd_buff_wr),

	.dbg_berr(),
	.dbg_berr_addr(),
	.dbg_overlay(),
	.debug_status(m_debug_status),
	.debug_status2(m_debug_status2),
	.debug_fault(),
	.debug_halted()
);

wire m_hblank, m_vblank;
assign CLK_VIDEO = clk_sys;
assign VGA_DE = ~(m_hblank | m_vblank);

assign LED_USER = ioctl_download | sd_rd[0] | sd_wr[0];
assign LED_DISK = {1'b1, sd_rd[0] | sd_wr[0]};

//////////////////////////////////////////////////////////////////
// VRAM — on-chip, true dual port: CPU beats on port A (2-cycle
// handshake: capture, then deliver), DAFB scanout on port B with the
// registered 1-cycle read the machine expects.
//
// Physical storage is 308 KB: 640x480 @ 8bpp needs 307,200 visible
// bytes, but drivers place the framebuffer at a BASE OFFSET — sizing
// to exactly 300 KB put the last scanlines past the array on real
// hardware in MacIIvi_MiSTer (base = 4 rows = 2,560 bytes; they
// scanned out white).  308 KB covers base + framebuffer with ~9 rows
// spare; the same repo found 320 KB broke HDMI-scaler timing closure,
// so don't grow this casually (MacIIvi.sv MDC_VRAM_WORDS, 2026-08-10).
//
// The machine's 2 MB window aliases mod 512 KB, so a ROM size probe
// sees the classic power-of-2 wrap and ADVERTISES 512 KB; the
// unbacked 308K..512K range folds down by 204 KB onto 104K..308K so
// probe readbacks anywhere in the window still succeed.  Only
// software genuinely storing data in the top 204 KB would see the
// aliasing — no supported mode does.
//////////////////////////////////////////////////////////////////
localparam VRAM_WORDS = 78848;             // 308 KB
localparam [16:0] VRAM_FOLD = 17'd52224;   // 204 KB, in words

function [16:0] vram_map(input [16:0] w);  // window word -> storage word
	vram_map = (w >= 17'd78848) ? (w - VRAM_FOLD) : w;
endfunction

reg [31:0] vram [0:VRAM_WORDS-1];
reg [31:0] vram_qa;
reg        vram_ph;                        // port-A phase: 0 capture, 1 deliver

wire         mem_is_ram  = (mem_memsel == 2'd0);
wire         mem_is_rom  = (mem_memsel == 2'd1);
wire         mem_is_vram = !mem_is_ram && !mem_is_rom;
wire [16:0]  va_addr     = vram_map(mem_addr[18:2]);
wire         va_we       = mem_req && mem_is_vram && mem_write && !vram_ph;

always @(posedge clk_sys) begin
	if (va_we) begin
		if (mem_be[3]) vram[va_addr][31:24] <= mem_wdata[31:24];
		if (mem_be[2]) vram[va_addr][23:16] <= mem_wdata[23:16];
		if (mem_be[1]) vram[va_addr][15:8]  <= mem_wdata[15:8];
		if (mem_be[0]) vram[va_addr][7:0]   <= mem_wdata[7:0];
	end
	vram_qa <= vram[va_addr];
end

always @(posedge clk_sys) vid_rdata <= vram[vram_map(vid_addr[18:2])];

//////////////////////////////////////////////////////////////////
// DDR3 bridge — RAM + ROM regions, plus the boot.rom upload path.
// 64-bit word convention: the machine's 32-bit word at byte address A
// sits in DDRAM_DOUT[31:0] when A[2]=0 and [63:32] when A[2]=1; the
// big-endian byte packing inside the 32-bit lane is preserved, so
// mem_be maps 1:1 onto DDRAM_BE (shifted by the half-select).
//////////////////////////////////////////////////////////////////
assign DDRAM_CLK = clk_sys;

localparam [28:0] DDR_RAM_BASE = 29'h0600_0000;   // byte 0x3000_0000 >> 3
localparam [28:0] DDR_ROM_BASE = 29'h0640_0000;   // byte 0x3200_0000 >> 3

reg  [7:0] ddram_burstcnt;
reg [28:0] ddram_addr;
reg [63:0] ddram_din;
reg  [7:0] ddram_be;
reg        ddram_we, ddram_rd;
assign DDRAM_BURSTCNT = ddram_burstcnt;
assign DDRAM_ADDR     = ddram_addr;
assign DDRAM_DIN      = ddram_din;
assign DDRAM_BE       = ddram_be;
assign DDRAM_WE       = ddram_we;
assign DDRAM_RD       = ddram_rd;

reg        ioctl_pend;
reg [26:0] ioctl_a;
reg [15:0] ioctl_d;
reg        ddr_wait_data;                  // read issued, awaiting DOUT_READY
reg        ddr_rd_hi;

always @(posedge clk_sys) begin
	mem_ack <= 0;

	// boot.rom halfwords: capture, then stall hps_io until written
	if (ioctl_download && rom_index && ioctl_wr) begin
		ioctl_pend <= 1;
		ioctl_wait <= 1;
		ioctl_a <= ioctl_addr;
		ioctl_d <= ioctl_dout;
	end

	if (!DDRAM_BUSY) begin
		ddram_we <= 0;
		ddram_rd <= 0;
	end

	// VRAM beats (BRAM port A): capture edge, then deliver vram_qa
	if (mem_req && !mem_ack && mem_is_vram) begin
		if (!vram_ph) vram_ph <= 1;
		else begin
			vram_ph <= 0;
			mem_rdata <= vram_qa;
			mem_ack <= 1;
		end
	end

	if (ddr_wait_data) begin
		if (DDRAM_DOUT_READY) begin
			mem_rdata <= ddr_rd_hi ? DDRAM_DOUT[63:32] : DDRAM_DOUT[31:0];
			mem_ack   <= 1;
			ddr_wait_data <= 0;
		end
	end
	else if (!DDRAM_BUSY && !ddram_we && !ddram_rd) begin
		if (ioctl_pend) begin
			// file bytes are big-endian in the 32-bit lane: swap the
			// little-endian ioctl halfword and replicate across lanes,
			// steering with BE
			ddram_addr     <= DDR_ROM_BASE | {10'd0, ioctl_a[19:3]};
			ddram_din      <= {4{{ioctl_d[7:0], ioctl_d[15:8]}}};
			ddram_be       <= ioctl_a[1] ? (ioctl_a[2] ? 8'h30 : 8'h03)
			                             : (ioctl_a[2] ? 8'hC0 : 8'h0C);
			ddram_burstcnt <= 8'd1;
			ddram_we       <= 1;
			ioctl_pend     <= 0;
			ioctl_wait     <= 0;
		end
		else if (mem_req && !mem_ack && (mem_is_ram || mem_is_rom)) begin
			if (mem_write && mem_is_rom) begin
				mem_ack <= 1;              // djMEMC discards ROM writes
			end
			else if (mem_write) begin
				ddram_addr     <= DDR_RAM_BASE | {7'd0, mem_addr[24:3]};
				ddram_din      <= {2{mem_wdata}};
				ddram_be       <= mem_addr[2] ? {mem_be, 4'b0000}
				                              : {4'b0000, mem_be};
				ddram_burstcnt <= 8'd1;
				ddram_we       <= 1;
				mem_ack        <= 1;       // posted; ordering held by !we gate
			end
			else begin
				ddram_addr     <= mem_is_rom
				                  ? (DDR_ROM_BASE | {12'd0, mem_addr[19:3]})
				                  : (DDR_RAM_BASE | {7'd0,  mem_addr[24:3]});
				ddram_burstcnt <= 8'd1;
				ddram_rd       <= 1;
				ddr_rd_hi      <= mem_addr[2];
				ddr_wait_data  <= 1;
			end
		end
	end

	if (reset && !ioctl_download) begin
		vram_ph <= 0;
		ddr_wait_data <= 0;
	end
	if (RESET) begin
		ioctl_pend <= 0;
		ioctl_wait <= 0;
	end
end

endmodule
