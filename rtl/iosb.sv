//============================================================================
//  iosb — the Quadra 800's I/O ASIC on the machine beat port.
//
//  Stage 2 scope (MAME iosb.cpp / pseudovia.cpp as reference): VIA1 (real
//  6522 at $50000000, 512-byte register stride, byte replicated across the
//  lanes), the quadra pseudo-VIA at $50002000 (ports + IFR/IER only, no
//  timers), the IOSB config registers at $50018000, the $A55A2BAD ID at
//  $5FFF0000, and the 3-level interrupt scheme (SCC=4, VIA2=2, VIA1=1).
//  SWIM2/ASC/SCC/SCSI/SONIC decode as present-but-inert: reads 0, writes
//  discarded, always acked — the real chips arrive in later stages.
//
//  Beat slave: sel is held until the single-cycle ack; rdata valid at ack.
//============================================================================

module iosb
#(
	parameter E_HALF    = 21,       // clk per E phase: 33 MHz/21 ~ 783.4 kHz VIA timers
	parameter TICK_HALF = 274314    // clk per CA1 half-period: 60.15 Hz tick
)
(
	input         clk,
	input         nreset,
	input         ce,

	// beat slave (offset within $50000000-$5FFFFFFF)
	input         sel,
	input         write,
	input  [27:2] addr,
	input   [3:0] be,
	input  [31:0] wdata,
	output reg [31:0] rdata,
	output reg    ack,

	// device interrupt lines (stage 3+ sources; quiet today)
	input         vbl_irq,
	input         scsi_irq,
	input         scsi_drq,
	input         asc_irq,
	input         scc_irq,

	output  [2:0] ipl_n,           // active-low to the CPU

	output signed [15:0] audio_l,
	output signed [15:0] audio_r,

	// SCSI disk on the MiSTer block-device interface
	input         img_mounted,
	input  [63:0] img_size,
	output [31:0] io_lba,
	output        io_rd,
	output        io_wr,
	input         io_ack,
	input   [7:0] sd_buff_addr,
	input  [15:0] sd_buff_dout,
	output [15:0] sd_buff_din,
	input         sd_buff_wr,

	// ADB input devices
	input  [10:0] ps2_key,
	input  [24:0] ps2_mouse
);

//----------------------------------------------------------------------------
// E-clock enables and the 60.15 Hz tick
//----------------------------------------------------------------------------
reg [$clog2(E_HALF)-1:0] ediv;
reg        ephase;
wire       e_pulse   = (ediv == E_HALF-1);
wire       e_rising  = e_pulse && !ephase;
wire       e_falling = e_pulse &&  ephase;

reg [$clog2(TICK_HALF)-1:0] tickdiv;
reg        tick_60hz;

always @(posedge clk) begin
	if (!nreset) begin
		ediv <= 0; ephase <= 0;
		tickdiv <= 0; tick_60hz <= 0;
	end
	else begin
		ediv <= e_pulse ? '0 : ediv + 1'b1;
		if (e_pulse) ephase <= ~ephase;
		if (tickdiv == TICK_HALF-1) begin
			tickdiv <= 0;
			tick_60hz <= ~tick_60hz;
		end
		else tickdiv <= tickdiv + 1'b1;
	end
end

//----------------------------------------------------------------------------
// VIA1 — machine ID $12 on port A (PA1|PA4); port B: PB0/1/2 bit-bang the
// RTC (data/clock/enable), PB3 reads the ADB interrupt (high = none)
//----------------------------------------------------------------------------
reg        via1_ren, via1_wen;
reg  [3:0] via1_addr;
reg  [7:0] via1_din;
wire [7:0] via1_dout;
wire       via1_irq;
wire [7:0] via1_pbo, via1_pbt;

// undriven VIA pins float high through the pull-ups
wire rtc_ce_n  = via1_pbt[2] ? via1_pbo[2] : 1'b1;
wire rtc_clk   = via1_pbt[1] ? via1_pbo[1] : 1'b1;
wire rtc_din   = via1_pbt[0] ? via1_pbo[0] : 1'b1;
wire rtc_dout, rtc_doe;
wire rtc_line  = rtc_doe ? rtc_dout : 1'b1;

rtc3430042 rtc (
	.clk(clk),
	.nreset(nreset),
	.ce_n(rtc_ce_n),
	.clk_in(rtc_clk),
	.data_in(rtc_din),
	.data_out(rtc_dout),
	.data_oe(rtc_doe)
);

wire       via1_sr_active;
reg        via1_sr_ext_complete, via1_sr_ext_load;
reg  [7:0] via1_sr_ext_data;
wire       adb_int_n;

via6522 via1 (
	.clock     (clk),
	.rising    (e_rising),
	.falling   (e_falling),
	.timer_tick(e_falling),        // T1/T2 count at the 783 kHz E rate
	.reset     (!nreset),

	.addr      (via1_addr),
	.wen       (via1_wen),
	.ren       (via1_ren),
	.data_in   (via1_din),
	.data_out  (via1_dout),

	.phi2_ref  (),

	.port_a_o  (),
	.port_a_t  (),
	.port_a_i  (8'h12),
	.port_b_o  (via1_pbo),
	.port_b_t  (via1_pbt),
	.port_b_i  ({4'b0000, adb_int_n, 2'b00, rtc_line}),

	.ca1_i     (tick_60hz),
	.ca2_o     (),
	.ca2_i     (1'b0),
	.ca2_t     (),
	.cb1_o     (),
	.cb1_i     (1'b0),
	.cb1_t     (),
	.cb2_o     (),
	.cb2_i     (1'b0),
	.cb2_t     (),
	.ca2_lvl_i (1'b0),
	.cb2_lvl_i (1'b0),

	.irq       (via1_irq),
	.dbg_irq_state (),
	.sr_active (via1_sr_active),

	.sr_ext_complete (via1_sr_ext_complete),
	.sr_ext_load     (via1_sr_ext_load),
	.sr_ext_data     (via1_sr_ext_data)
);

//----------------------------------------------------------------------------
// ADB modem (Mac II style): the ROM talks to it through VIA1's shift
// register (CB1/CB2) with the state bits on PB4/PB5 and the interrupt on
// PB3.  adb.sv + the Snow-style timer shim come from lbmactwo_MiSTer,
// where this exact arrangement is hardware-proven.
//----------------------------------------------------------------------------
wire ADBST0 = ~via1_pbt[4] | via1_pbo[4];
wire ADBST1 = ~via1_pbt[5] | via1_pbo[5];
wire adb_bus_idle = ADBST0 & ADBST1;
wire adb_resp_pending;
wire [7:0] adb_dout;
wire       adb_dout_strobe;
reg  [7:0] adb_din;
reg        adb_din_strobe;

// ~8 MHz enable for the transceiver's bit timing
reg [1:0] adbdiv;
wire adb_en = (adbdiv == 2'd3);
always @(posedge clk) adbdiv <= !nreset ? 2'd0 : adbdiv + 1'b1;

adb adbx (
	.clk(clk),
	.clk_en(adb_en),
	.reset(~nreset),
	.st({ADBST1, ADBST0}),
	._int(adb_int_n),
	.viaBusy(1'b0),
	.listen(),
	.adb_din(adb_din),
	.adb_din_strobe(adb_din_strobe),
	.adb_dout(adb_dout),
	.adb_dout_strobe(adb_dout_strobe),

	.ps2_mouse(ps2_mouse),
	.ps2_key(ps2_key),
	.resp_pending(adb_resp_pending),
	.dbg_adb(),
	.mouse_has_event_o()
);

// VIA1 SR shim (lbmactwo): the qualified 6522 access edge is A_VIA at
// e_falling with via1_addr/din held; SR reg $A, ACR reg $B
wire via1_access = (astate == A_VIA) && e_falling;
wire via1_sr_wr  = via1_access && via1_wen && (via1_addr == 4'hA);
wire via1_acr_wr = via1_access && via1_wen && (via1_addr == 4'hB);
wire via1_sr_rd  = via1_access && via1_ren && (via1_addr == 4'hA);

reg [2:0] via1_acr_shift_mode;
reg [7:0] via1_sr_shadow;
reg [21:0] via1_shift_timer;
reg via1_shift_dir;                // 1 = shift-out, 0 = shift-in
reg via1_sr_out_pending;
reg via1_sr_out_ack;
reg via1_kbd_to_mac_fresh;
reg [7:0] kbd_to_mac;

localparam SHIFT_DELAY = 22'd100000;    // ~3 ms at 33 MHz
localparam IDLE_DELAY  = 22'd363000;    // ~11 ms autopoll heartbeat

always @(posedge clk) begin
	if (!nreset) begin
		via1_acr_shift_mode <= 3'b000;
		via1_sr_shadow <= 8'h00;
		via1_shift_timer <= 22'd0;
		via1_shift_dir <= 1'b0;
		via1_sr_ext_complete <= 1'b0;
		via1_sr_ext_load <= 1'b0;
		via1_sr_ext_data <= 8'h00;
		via1_sr_out_pending <= 1'b0;
		via1_sr_out_ack <= 1'b0;
		via1_kbd_to_mac_fresh <= 1'b0;
		kbd_to_mac <= 8'h00;
		adb_din <= 8'h00;
		adb_din_strobe <= 1'b0;
	end
	else begin
		via1_sr_ext_complete <= 1'b0;
		via1_sr_ext_load <= 1'b0;
		via1_sr_out_ack <= 1'b0;
		adb_din_strobe <= 1'b0;

		if (adb_dout_strobe) begin
			kbd_to_mac <= adb_dout;
			via1_kbd_to_mac_fresh <= 1'b1;
		end

		// shift-out completion delivers the command byte to the modem
		if (via1_sr_out_pending && !via1_sr_out_ack) begin
			adb_din <= via1_sr_shadow;
			adb_din_strobe <= 1'b1;
			via1_sr_out_ack <= 1'b1;
			via1_sr_out_pending <= 1'b0;
		end

		if (via1_acr_wr) begin
			via1_acr_shift_mode <= via1_din[4:2];
			if (via1_din[4:2] == 3'b111 && via1_acr_shift_mode != 3'b111) begin
				via1_shift_timer <= SHIFT_DELAY;
				via1_shift_dir <= 1'b1;
			end
			else if (via1_din[4:2] == 3'b011 && via1_acr_shift_mode != 3'b011) begin
				via1_shift_timer <= SHIFT_DELAY;
				via1_shift_dir <= 1'b0;
			end
			else if (via1_din[4:2] == 3'b000)
				via1_shift_timer <= 22'd0;
		end

		// an SR read in shift-in mode re-arms the next shift (autopoll
		// heartbeat); fast only while a real response byte is on the way
		if (via1_sr_rd && via1_acr_shift_mode == 3'b011) begin
			via1_shift_timer <= adb_resp_pending ? SHIFT_DELAY : IDLE_DELAY;
			via1_shift_dir <= 1'b0;
		end

		if (via1_sr_wr) begin
			via1_sr_shadow <= via1_din;
			if (via1_acr_shift_mode == 3'b111) begin
				via1_shift_timer <= SHIFT_DELAY;
				via1_shift_dir <= 1'b1;
			end
			if (via1_acr_shift_mode == 3'b011) begin
				via1_shift_timer <= SHIFT_DELAY;
				via1_shift_dir <= 1'b0;
			end
		end

		if (via1_shift_timer > 22'd1)
			via1_shift_timer <= via1_shift_timer - 22'd1;

		if (via1_shift_dir) begin
			if (via1_shift_timer == 22'd1) begin
				via1_shift_timer <= 22'd0;
				via1_sr_ext_complete <= 1'b1;
				via1_sr_out_pending <= 1'b1;
			end
		end
		else begin
			// shift-in completes the instant a fresh byte exists; the timer
			// path only fires when nothing is pending (or the bus idled)
			if (via1_kbd_to_mac_fresh) begin
				via1_shift_timer <= 22'd0;
				via1_sr_ext_complete <= 1'b1;
				via1_sr_ext_load <= 1'b1;
				via1_sr_ext_data <= kbd_to_mac;
				via1_kbd_to_mac_fresh <= 1'b0;
			end
			else if (via1_shift_timer == 22'd1) begin
				if (!adb_resp_pending || adb_bus_idle) begin
					via1_shift_timer <= 22'd0;
					via1_sr_ext_complete <= 1'b1;
					via1_sr_ext_load <= 1'b1;
					via1_sr_ext_data <= kbd_to_mac;
				end
			end
		end
	end
end

//----------------------------------------------------------------------------
// VIA2 — quadra pseudo-VIA (MAME quadra_pseudovia_device): ports and
// IFR/IER only.  IFR bits: 0 SCSI DRQ, 1 any-slot (VBL/NuBus/SONIC via
// nubus_irqs), 3 SCSI IRQ, 4 ASC (latched).  Port A reads the active-low
// per-source slot status.
//----------------------------------------------------------------------------
reg  [7:0] via2_ifr;      // bit 7 = summary, computed below
reg  [7:0] via2_ier;
wire [7:0] nubus_irqs = {1'b1, ~vbl_irq, 5'b11111};   // bit 6 = DAFB VBL
wire       slot_any   = (nubus_irqs & 8'h79) != 8'h79;

reg vbl_d, scsi_d, drq_d, asc_d, slot_d;
wire via2_active = |(via2_ifr[6:0] & via2_ier[6:0] & 7'h1b);
wire [7:0] via2_ifr_r = {via2_active, via2_ifr[6:0]};
wire scsi_irq_i = scsi_irq | ncr_irq;
wire scsi_drq_i = scsi_drq | ncr_drq;

//----------------------------------------------------------------------------
// IOSB config registers: 16-bit scratch at 256-byte strides, readback only
// (reg 2 also times Turbo SCSI pseudo-DMA — consumed in stage 3)
//----------------------------------------------------------------------------
reg [15:0] iosb_regs [0:31];

//----------------------------------------------------------------------------
// djMEMC memory controller registers at $5000E000 (QEMU hw/misc/djmemc.c:
// interleave, bank0-9 config, memtop, config, refresh).  Architecturally
// djMEMC's, but they live in the I/O block this module decodes.  The ROM's
// RAM sizing writes bank configurations and reads them back — scratch
// readback is what the known-good QEMU model provides.
//----------------------------------------------------------------------------
reg [31:0] djmemc_regs [0:15];

//----------------------------------------------------------------------------
// Decode (offset relative to $50000000; MAME iosb.cpp map with mirrors)
//----------------------------------------------------------------------------
wire in_low     = (addr[27:24] == 4'h0);
wire sel_via1   = in_low && (addr[17:13] == 5'b00000);
wire sel_via2   = in_low && (addr[19:13] == 7'b0000001);
wire sel_regs   = in_low && (addr[19:13] == 7'b0001100);
wire sel_djmemc = in_low && (addr[19:13] == 7'b0000111);   // $E000-$FFFF
wire sel_asc    = in_low && (addr[19:12] == 8'h14);
wire sel_scsi   = in_low && (addr[19:8] == 12'h100);   // 53C96 regs, 16-byte strides
wire sel_sdma   = in_low && (addr[19:8] == 12'h101);   // Turbo SCSI pseudo-DMA
wire sel_id     = (addr[27:16] == 12'hFFF);
wire [3:0] rsel = addr[12:9];

//----------------------------------------------------------------------------
// NCR 53C96 + Turbo SCSI pseudo-DMA
//----------------------------------------------------------------------------
wire       scsi_strobe = ce && (astate == A_IDLE) && sel && !ack && sel_scsi;
wire [7:0] ncr_rdata;
reg        sdma_rd, sdma_wr;
wire [7:0] sdma_rbyte;
reg  [7:0] sdma_wbyte;
wire       sdma_valid;
wire       ncr_irq, ncr_drq;
reg  [2:0] sdma_left;              // bytes still to move in this beat
reg [31:0] sdma_shift;

ncr53c96 #(.DISK_ID(0)) scsi (
	.clk(clk),
	.nreset(nreset),
	.ce(ce),

	.sel(scsi_strobe),
	.write(write),
	.rs(addr[7:4]),
	.wdata(wbyte),
	.rdata(ncr_rdata),

	.dma_rd(sdma_rd),
	.dma_wr(sdma_wr),
	.dma_wdata(sdma_wbyte),
	.dma_rdata(sdma_rbyte),
	.dma_valid(sdma_valid),
	.drq(ncr_drq),
	.irq(ncr_irq),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.io_lba(io_lba),
	.io_rd(io_rd),
	.io_wr(io_wr),
	.io_ack(io_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr)
);

//----------------------------------------------------------------------------
// EASC wavetable voice (the boot chime); FIFO mode is a later stage
//----------------------------------------------------------------------------
wire        asc_stb = ce && (astate == A_IDLE) && sel && !ack && sel_asc;
wire [31:0] asc_rdata;

asc_wavetable asc (
	.clk(clk),
	.nreset(nreset),
	.ce(ce),

	.sel(asc_stb),
	.write(write),
	.a(addr[11:2]),
	.be(be),
	.wdata(wdata),
	.rdata(asc_rdata),

	.sample_l(audio_l),
	.sample_r(audio_r)
);

// write byte: highest enabled lane (VIA registers never span lanes)
wire [7:0] wbyte = be[3] ? wdata[31:24] :
                   be[2] ? wdata[23:16] :
                   be[1] ? wdata[15:8]  : wdata[7:0];

localparam A_IDLE = 2'd0, A_VIA = 2'd1, A_CAPTURE = 2'd2, A_SDMA = 2'd3;
reg [1:0] astate;
reg       sdma_word2;              // 16-bit pseudo-DMA beat (else 32-bit)

always @(posedge clk) begin
	if (!nreset) begin
		astate    <= A_IDLE;
		ack       <= 0;
		rdata     <= 0;
		via1_ren  <= 0;
		via1_wen  <= 0;
		via1_addr <= 0;
		via1_din  <= 0;
		via2_ifr  <= 8'h00;
		via2_ier  <= 8'h00;
		vbl_d <= 0; scsi_d <= 0; drq_d <= 0; asc_d <= 0; slot_d <= 0;
		for (int j = 0; j < 16; j = j + 1) djmemc_regs[j] <= 32'd0;
		for (int j = 0; j < 32; j = j + 1) iosb_regs[j] <= 16'd0;
		iosb_regs[0] <= 16'd1;               // IOSB_CONFIG: BCLK 33 MHz (QEMU)
		sdma_rd <= 0; sdma_wr <= 0; sdma_left <= 0;
		sdma_shift <= 0; sdma_wbyte <= 0; sdma_word2 <= 0;
	end
	else if (ce) begin
		ack <= 0;

		// interrupt line edges latch into the pseudo-VIA IFR
		vbl_d <= vbl_irq; scsi_d <= scsi_irq_i; drq_d <= scsi_drq_i;
		asc_d <= asc_irq; slot_d <= slot_any;
		if (scsi_irq_i != scsi_d) via2_ifr[3] <= scsi_irq_i;
		if (scsi_drq_i != drq_d)  via2_ifr[0] <= scsi_drq_i;
		if (slot_any != slot_d) via2_ifr[1] <= slot_any;
		if (asc_irq && !asc_d)  via2_ifr[4] <= 1'b1;

		case (astate)
		A_IDLE: if (sel && !ack) begin
			if (sel_via1) begin
				via1_addr <= rsel;
				via1_din  <= wbyte;
				via1_wen  <= write;
				via1_ren  <= ~write;
				astate    <= A_VIA;
			end
			else begin
				ack <= 1;
				if (sel_via2) begin
					if (write) begin
						case (rsel)
						4'd13:   via2_ifr[6:0] <= via2_ifr[6:0] & ~(wbyte[6:0] & 7'h1b);
						4'd14:   via2_ier[6:0] <= wbyte[7]
						             ? (via2_ier[6:0] |  (wbyte[6:0] & 7'h1b))
						             : (via2_ier[6:0] & ~(wbyte[6:0] & 7'h1b));
						default: ;              // ports B/A out: DFAC etc, ignored
						endcase
					end
					else begin
						case (rsel)
						4'd1, 4'd15: rdata <= {4{nubus_irqs}};
						4'd13:       rdata <= {4{via2_ifr_r}};
						4'd14:       rdata <= {4{via2_ier}};
						default:     rdata <= 32'h0;
						endcase
					end
				end
				else if (sel_regs) begin
					// one u16 reg per 256-byte stride; every word slot in the
					// block aliases it (MAME offset>>7), low slot written last
					if (write) begin
						if (be[1] | be[0]) begin
							if (be[1]) iosb_regs[addr[12:8]][15:8] <= wdata[15:8];
							if (be[0]) iosb_regs[addr[12:8]][7:0]  <= wdata[7:0];
						end
						else begin
							if (be[3]) iosb_regs[addr[12:8]][15:8] <= wdata[31:24];
							if (be[2]) iosb_regs[addr[12:8]][7:0]  <= wdata[23:16];
						end
					end
					else rdata <= {2{iosb_regs[addr[12:8]]}};
				end
				else if (sel_djmemc) begin
					if (write) djmemc_regs[addr[5:2]] <= wdata;
					else       rdata <= djmemc_regs[addr[5:2]];
				end
				else if (sel_asc) rdata <= asc_rdata;   // writes strobe asc_stb
				else if (sel_scsi) rdata <= {4{ncr_rdata}};  // scsi_strobe fires
				else if (sel_sdma) begin
					// pseudo-DMA beat: hold off the ack until the chip has
					// moved every byte (the real IOSB holds /DTACK on !DRQ;
					// a wedged transfer ends in the CPU watchdog's berr)
					ack        <= 0;
					sdma_word2 <= !(be == 4'b1111);
					sdma_left  <= (be == 4'b1111) ? 3'd4 : 3'd2;
					sdma_shift <= wdata;
					sdma_wbyte <= wdata[31:24];
					sdma_rd    <= ~write;
					sdma_wr    <= write;
					astate     <= A_SDMA;
				end
				else if (sel_id) rdata <= 32'hA55A2BAD;
				else rdata <= 32'h0;             // inert device space
			end
		end
		A_VIA: if (e_falling) begin
			// the 6522 samples ren/wen on this qualified edge; exactly one
			via1_ren <= 0;
			via1_wen <= 0;
			astate   <= A_CAPTURE;
		end
		A_CAPTURE: begin
			rdata  <= {4{via1_dout}};
			ack    <= 1;
			astate <= A_IDLE;
		end
		A_SDMA: if (sdma_valid) begin
			if (sdma_left == 3'd1) begin
				sdma_rd <= 0;
				sdma_wr <= 0;
				ack     <= 1;
				rdata   <= sdma_word2 ? {sdma_shift[7:0], sdma_rbyte, 16'h0}
				                      : {sdma_shift[23:0], sdma_rbyte};
				astate  <= A_IDLE;
			end
			else begin
				sdma_shift <= {sdma_shift[23:0], sdma_rbyte};
				sdma_wbyte <= sdma_shift[23:16];
				sdma_left  <= sdma_left - 1'b1;
			end
		end
		endcase
	end
end

//----------------------------------------------------------------------------
// 3-level autovector scheme: SCC=4, VIA2=2, VIA1=1
//----------------------------------------------------------------------------
assign ipl_n = scc_irq     ? 3'b011 :
               via2_active ? 3'b101 :
               via1_irq    ? 3'b110 : 3'b111;

endmodule
