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
//   - VRAM is on-chip BRAM, 320 KB physical, advertised as 512 KB: the
//     driver's 1024-byte row pitch is compacted to the 640 bytes each
//     row can actually show, so every row of every depth is backed
//     exactly once — see the VRAM section.  The DAFB scanout expects
//     registered 1-cycle reads.  Still the main BRAM consumer.
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
	// SC0, not S0: the letter after S is a flag, and 'C' is what sets
	// store_name in the Main's option parser -- i.e. what makes MiSTer write
	// config/Wombat33.s0 and re-mount the image on the next core start. With a
	// plain S0 the mount works but is forgotten every boot, so the disk had to
	// be picked from the OSD by hand each time and the deploy's slot-0 seed was
	// inert. Every sibling Mac core (MacLC, MacLCII, MacIIvi, MacPlus,
	// LBMacTwo) uses SC0 for this reason.
	"SC0,HDAVHD,Mount SCSI disk;",
	"-;",
	"O[4:3],RAM,32MB,64MB,128MB;",
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
wire clk_ram;                              // 99 MHz = 3x clk_sys, SDRAM domain
wire pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_1(clk_ram),
	.outclk_0(clk_sys),                    // 33.000000 MHz machine clock — the
	                                       // real Quadra 800 rate, and the exact
	                                       // base every time-anchored divider
	                                       // assumes (RTC SEC_DIV, the 60.15 Hz
	                                       // tick, VIA E_HALF, ASC SAMPLE_DIV)
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
             ~rom_loaded | ~pll_locked | ram_cfg_change;

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
wire [13:0] vid_stride;

wire [255:0] m_debug_status;
wire [127:0] m_debug_status2;

localparam RAM_ADDR_BITS = 27;             // address ceiling: 128 MB

// Installed RAM from the OSD (0=32MB, 1=48MB, 2=64MB).  The ROM probes for
// the top of memory once, early in startup, so a change only takes effect
// out of reset — fold it into the reset rather than letting it move under a
// running machine.
wire [1:0] ram_cfg = (status[4:3] == 2'd3) ? 2'd0 : status[4:3];
reg  [1:0] ram_cfg_d;
always @(posedge clk_sys) ram_cfg_d <= ram_cfg;
wire ram_cfg_change = (ram_cfg != ram_cfg_d);

quadra800 #(.RAM_ADDR_BITS(RAM_ADDR_BITS)) machine (
	.clk(clk_sys),
	.nreset(~reset),
	.ce(1'b1),
	.ram_cfg(ram_cfg),

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
	.vid_stride(vid_stride),
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
// SDRAM — the machine's RAM.  ROM stays in DDR3 (it is uploaded once
// through the ioctl path and read rarely enough that latency is free).
//
// The MiSTer module is a 16-bit part, so one 32-bit machine beat is two
// consecutive 16-bit accesses.  The controller (Sorgelig's, from
// NeoGeo_MiSTer) runs at 99 MHz — three times clk_sys, from the same PLL —
// and derives SDRAM_CLK itself with an altddio_out, so no phase-shifted
// clock is needed here.
//
// Byte lanes: the machine's convention is big-endian, mem_be[3] selecting
// mem_wdata[31:24] = the byte at offset 0 (see the VRAM lane comment).  So
// the first SDRAM word carries wdata[31:16] and the second wdata[15:0],
// with bs[1] driving the high half of each.  Nothing else reads this
// memory, so the in-chip order only has to agree with itself.
//////////////////////////////////////////////////////////////////

wire        sdr_ready;
wire [15:0] sdr_dout;
reg         sdr_refresh = 0;
reg  [9:0]  sdr_refcnt  = 0;

// 8192 refreshes / 64 ms = one every 7.8 us = 772 cycles at 99 MHz
always @(posedge clk_ram) begin
	sdr_refcnt <= sdr_refcnt + 1'b1;
	if (sdr_refcnt == 10'd771) begin
		sdr_refcnt  <= 0;
		sdr_refresh <= ~sdr_refresh;
	end
end

// ---- clk_sys side: hand one beat over, wait for the ack toggle ----------
reg         sdr_req_tgl = 0;
reg         sdr_ack_seen = 0;
reg  [1:0]  sdr_ack_sync = 0;
reg         sdr_busy_s  = 0;
reg  [26:2] sdr_addr;
reg  [31:0] sdr_wdata;
reg  [3:0]  sdr_be;
reg         sdr_we;
wire        sdr_ack_tgl;
wire [31:0] sdr_rdata;

// ---- clk_ram side: two 16-bit accesses per beat ------------------------
reg         sdr_req_seen = 0;
reg  [1:0]  sdr_req_sync = 0;
reg         sdr_busy_r = 0;
reg         sdr_acc = 0;             // 0 = high half, 1 = low half
reg         sdr_ready_d = 0;
reg  [31:0] sdr_hold;

assign sdr_rdata  = sdr_hold;
assign sdr_ack_tgl = sdr_ack_r;
reg         sdr_ack_r = 0;

// rd/wr are held for the whole access: the controller may still be walking
// back to its idle state when a request arrives, and it samples the request
// only there.  Completion is the RISING edge of ready — ready sits low
// before the very first access and through the ~122 us power-up sequence,
// so waiting on the edge cannot false-trigger or deadlock.
wire sdr_rd = sdr_busy_r && !sdr_we;
wire sdr_wr = sdr_busy_r &&  sdr_we;

always @(posedge clk_ram) begin
	sdr_req_sync <= {sdr_req_sync[0], sdr_req_tgl};
	sdr_ready_d  <= sdr_ready;

	if (!sdr_busy_r) begin
		if (sdr_req_sync[1] != sdr_req_seen) begin
			sdr_req_seen <= sdr_req_sync[1];
			sdr_acc      <= 0;
			sdr_busy_r   <= 1;
		end
	end
	else if (sdr_ready && !sdr_ready_d) begin
		if (!sdr_acc) begin
			sdr_hold[31:16] <= sdr_dout;
			sdr_acc         <= 1;          // address advances with it
		end
		else begin
			sdr_hold[15:0] <= sdr_dout;
			sdr_busy_r     <= 0;
			sdr_ack_r      <= ~sdr_ack_r;
		end
	end
end

sdram sdram
(
	.init      (~pll_locked),
	.clk       (clk_ram),
	.SDRAM_EN  (1'b1),

	.SDRAM_DQ  (SDRAM_DQ),
	.SDRAM_A   (SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA  (SDRAM_BA),
	.SDRAM_nCS (SDRAM_nCS),
	.SDRAM_nWE (SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CKE (SDRAM_CKE),
	.SDRAM_CLK (SDRAM_CLK),

	.sel       (1'b1),
	.addr      ({sdr_addr, sdr_acc}),      // word address; acc picks the half
	.dout      (sdr_dout),
	.din       (sdr_acc ? sdr_wdata[15:0] : sdr_wdata[31:16]),
	.wr        (sdr_wr),
	.bs        (sdr_acc ? sdr_be[1:0] : sdr_be[3:2]),
	.rd        (sdr_rd),
	.ready     (sdr_ready),
	.refresh   (sdr_refresh),

	.cpsel     (1'b0),
	.cpaddr    (26'd0),
	.cpdin     (16'd0),
	.cprd      (),
	.cpreq     (1'b0),
	.cpbusy    ()
);

//////////////////////////////////////////////////////////////////
// VRAM — on-chip, true dual port: CPU beats on port A (2-cycle
// handshake: capture, then deliver), DAFB scanout on port B with the
// registered 1-cycle read the machine expects.
//
// The machine's 2 MB window aliases mod 512 KB, so a ROM size probe sees
// the classic power-of-2 wrap and ADVERTISES 512 KB.  Backing all of it
// is impossible on this device — but it does not have to be backed
// densely; see the compaction note on VRAM_WORDS below.
//////////////////////////////////////////////////////////////////
// STRIDE COMPACTION.  The ROM programs a 1024-byte row pitch (confirmed on
// hardware and by the sim's [DAFB] tap), so a 480-row framebuffer spans
// 0x1000 + 480*1024 = 495,616 bytes — far past anything M10K can hold, and
// the old fold aliased screen rows 304..479 back onto rows 100..275 (the
// duplicated boot floppy seen on the DE10).
//
// But at 640 pixels wide only the FIRST 640 bytes of each 1024-byte row are
// ever visible: 80 bytes at 1bpp, 160 at 2bpp, 320 at 4bpp, 640 at 8bpp.
// The remaining 384 bytes are pitch padding no supported depth reaches.  So
// store 640 bytes of every row and drop the tail: the whole 512 KB window
// becomes 512*640 = 320 KB of BRAM, which fits with room to spare, and
// EVERY row of EVERY depth (8bpp included) is backed exactly once — no
// aliasing anywhere in the visible framebuffer.
//
// The 384-byte tails all share one scratch block, so a write and read-back
// at the same tail address still agree (VRAM size probes poke row-aligned
// offsets, which are all col 0).  Only software genuinely storing data in
// the pitch padding of two different rows at once would notice.
//
// Compaction assumes the 1024-byte pitch, so it engages only when the
// driver has actually programmed one; any pitch <= 640 already fits the
// array linearly and maps identically (with the old fold as a backstop for
// probe reads past the end).
localparam VRAM_WORDS = 82016;             // 320.4 KB: 512*160 + 96 tail
localparam [16:0] VRAM_FOLD = 17'd52224;   // 204 KB, in words
localparam [16:0] VRAM_TAIL = 17'd81920;   // 512 rows * 160 words

wire vram_compact = (vid_stride == 14'd1024);

function [16:0] vram_map(input [16:0] w);  // window word -> storage word
	reg [8:0] row;                         // 1024 B = 256 words per row
	reg [7:0] col;
	begin
		row = w[16:8];
		col = w[7:0];
		if (!vram_compact)
			vram_map = (w >= VRAM_WORDS) ? (w - VRAM_FOLD) : w;
		else if (col < 8'd160)             // visible 640 bytes: row*160 + col
			vram_map = {row, 7'd0} + {2'd0, row, 5'd0} + {9'd0, col};
		else                               // pitch padding: shared scratch
			vram_map = VRAM_TAIL + {9'd0, (col - 8'd160)};
	end
endfunction

reg [31:0] vram_qa;
reg        vram_ph;                        // port-A phase: 0 capture, 1 deliver

wire         mem_is_ram  = (mem_memsel == 2'd0);
wire         mem_is_rom  = (mem_memsel == 2'd1);
wire         mem_is_vram = !mem_is_ram && !mem_is_rom;
wire [16:0]  va_addr     = vram_map(mem_addr[18:2]);
wire [16:0]  vb_addr     = vram_map(vid_addr[18:2]);
wire         va_we       = mem_req && mem_is_vram && mem_write && !vram_ph;

// Storage is one byte-wide array per lane rather than one 32-bit array
// with byte enables: mem_be becomes each lane's write enable, so nothing
// rests on Quartus inferring byte enables on a true-dual-port M10K, and a
// x8 two-read-port array is the simplest shape a block can take.
// no_rw_check is accurate here — port A throws its read away on a write
// cycle (vram_ph delivers on the FOLLOWING cycle), so the
// read-during-write value is a genuine don't-care.  Without these
// attributes Quartus honors the implied "old data" same-port
// read-during-write in logic cells, and 2.5 Mbit of registers is what
// turns Analysis & Synthesis into an all-day run that never finishes.
(* ramstyle = "M10K, no_rw_check" *) reg [7:0] vram0 [0:VRAM_WORDS-1];
(* ramstyle = "M10K, no_rw_check" *) reg [7:0] vram1 [0:VRAM_WORDS-1];
(* ramstyle = "M10K, no_rw_check" *) reg [7:0] vram2 [0:VRAM_WORDS-1];
(* ramstyle = "M10K, no_rw_check" *) reg [7:0] vram3 [0:VRAM_WORDS-1];

always @(posedge clk_sys) begin            // port A: CPU beats
	if (va_we && mem_be[0]) vram0[va_addr] <= mem_wdata[7:0];
	if (va_we && mem_be[1]) vram1[va_addr] <= mem_wdata[15:8];
	if (va_we && mem_be[2]) vram2[va_addr] <= mem_wdata[23:16];
	if (va_we && mem_be[3]) vram3[va_addr] <= mem_wdata[31:24];
	vram_qa <= {vram3[va_addr], vram2[va_addr],
	            vram1[va_addr], vram0[va_addr]};
end

always @(posedge clk_sys)                  // port B: DAFB scanout
	vid_rdata <= {vram3[vb_addr], vram2[vb_addr],
	              vram1[vb_addr], vram0[vb_addr]};

//////////////////////////////////////////////////////////////////
// DDR3 bridge — RAM + ROM regions, plus the boot.rom upload path.
// 64-bit word convention: the machine's 32-bit word at byte address A
// sits in DDRAM_DOUT[31:0] when A[2]=0 and [63:32] when A[2]=1; the
// big-endian byte packing inside the 32-bit lane is preserved, so
// mem_be maps 1:1 onto DDRAM_BE (shifted by the half-select).
//////////////////////////////////////////////////////////////////
assign DDRAM_CLK = clk_sys;

localparam [28:0] DDR_RAM_BASE = 29'h0600_0000;   // byte 0x3000_0000 >> 3
localparam [28:0] DDR_ROM_BASE = 29'h0700_0000;   // byte 0x3800_0000 >> 3

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
		else if (mem_req && !mem_ack && mem_is_rom) begin
			if (mem_write) begin
				mem_ack <= 1;              // djMEMC discards ROM writes
			end
			else begin
				ddram_addr     <= DDR_ROM_BASE | {12'd0, mem_addr[19:3]};
				ddram_burstcnt <= 8'd1;
				ddram_rd       <= 1;
				ddr_rd_hi      <= mem_addr[2];
				ddr_wait_data  <= 1;
			end
		end
		// RAM beats go to SDRAM: hand the request across with a toggle and
		// wait for the matching ack toggle back.  Writes are NOT posted here
		// (unlike the old DDR3 path) — the controller has no write queue, so
		// the beat completes when the second half has actually been issued.
		else if (mem_req && !mem_ack && mem_is_ram && !sdr_busy_s) begin
			sdr_addr    <= mem_addr[26:2];
			sdr_wdata   <= mem_wdata;
			sdr_be      <= mem_be;
			sdr_we      <= mem_write;
			sdr_req_tgl <= ~sdr_req_tgl;
			sdr_busy_s  <= 1;
		end
	end

	// SDRAM beat completion
	sdr_ack_sync <= {sdr_ack_sync[0], sdr_ack_tgl};
	if (sdr_busy_s && (sdr_ack_sync[1] != sdr_ack_seen)) begin
		sdr_ack_seen <= sdr_ack_sync[1];
		sdr_busy_s   <= 0;
		mem_rdata    <= sdr_rdata;
		mem_ack      <= 1;
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
