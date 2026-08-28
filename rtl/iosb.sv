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
	output signed [15:0] audio_r
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

via6522 via1 (
	.clock     (clk),
	.rising    (e_rising),
	.falling   (e_falling),
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
	.port_b_i  ({4'b0000, 1'b1, 2'b00, rtc_line}),  // bit3: no ADB int

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

	.irq       (via1_irq),

	.sr_out_active (),
	.sr_out_dir    (),
	.sr_ext_clk    (),
	.sr_dbg_bit_cnt (),
	.sr_dbg_edge_pending (),
	.sr_dbg_fall_pending (),
	.sr_dbg_shift_reg ()
);

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
wire sel_id     = (addr[27:16] == 12'hFFF);
wire [3:0] rsel = addr[12:9];

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

localparam A_IDLE = 2'd0, A_VIA = 2'd1, A_CAPTURE = 2'd2;
reg [1:0] astate;

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
	end
	else if (ce) begin
		ack <= 0;

		// interrupt line edges latch into the pseudo-VIA IFR
		vbl_d <= vbl_irq; scsi_d <= scsi_irq; drq_d <= scsi_drq;
		asc_d <= asc_irq; slot_d <= slot_any;
		if (scsi_irq != scsi_d) via2_ifr[3] <= scsi_irq;
		if (scsi_drq != drq_d)  via2_ifr[0] <= scsi_drq;
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
