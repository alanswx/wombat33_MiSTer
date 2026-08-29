//============================================================================
//  asc_wavetable — classic-ASC wavetable voice of the Quadra's EASC,
//  enough for the boot chime (MAME asc.cpp wavetable semantics).
//
//  Byte map (4 KB window at $50014000):
//    $000-$7FF  sample RAM, 4 banks x 512 bytes (unsigned 8-bit)
//    $800 version (0: the ROM then drives the classic wavetable path)
//    $801 mode (2 = wavetable)   $802 control   $806 volume (bits 7:5)
//    $810+ch*8  phase (24-bit in bytes 1..3 of the 4-byte slot)
//    $814+ch*8  increment (same layout)
//
//  Beat slave: one aligned longword per sel pulse, big-endian byte lanes
//  (be[3] = byte at a+0).  Each 22257 Hz tick advances the four phases
//  and sums the four bank samples — the ROM's chime writes the same
//  evolving byte to all banks and plays notes by loading increments.
//
//  Storage: the sample RAM is four asc_bank block RAMs (128 x 32), one
//  per voice.  Voice i only ever reads its own 512-byte bank, and an
//  aligned CPU longword lands entirely inside one bank, so each bank
//  needs just two ports: A = CPU read/write with byte enables at the
//  held bus address, B = the voice's own registered read.  A flat
//  wave[0:2047] with eight asynchronous read points cannot map to M10K
//  and cost 7,781 ALUTs / 16,621 registers in LABs.
//
//  Read latency: both RAM ports read free-running and registered.  The
//  voice pipe is settled ~1481 cycles before each tick consumes it, and
//  the CPU readback is settled by the time iosb's A_ASC wait state (one
//  ce, added for exactly this) samples rdata.  A CPU write landing
//  within two clocks of a tick can feed that one tick a stale or (on
//  hardware, mixed-port DONT_CARE) undefined sample byte — one sample
//  of a boot chime, accepted.
//============================================================================

module asc_wavetable
#(
	parameter SAMPLE_DIV = 1483            // 33 MHz / 22257 Hz
)
(
	input         clk,
	input         nreset,
	input         ce,

	input         sel,
	input         write,
	input  [11:2] a,
	input   [3:0] be,
	input  [31:0] wdata,
	output [31:0] rdata,

	output signed [15:0] sample_l,
	output signed [15:0] sample_r
);

reg  [7:0] mode, control, volume;
reg [23:0] phase [0:3];
reg [23:0] incr  [0:3];

// sample RAM: bank = byte address [10:9], word = [8:2], lane = [1:0]
// (lane n of a word is q[31-8n -: 8], matching the bus byte order)
wire [31:0] bank_qa [0:3];
wire [31:0] bank_qb [0:3];
wire        cpu_wr = ce && sel && write && !a[11];

generate
	genvar gi;
	for (gi = 0; gi < 4; gi = gi + 1) begin : banks
		asc_bank bank
		(
			.clk     (clk),
			.addr_a  (a[8:2]),
			.wdata_a (wdata),
			.be_a    (be),
			.we_a    (cpu_wr && (a[10:9] == gi[1:0])),
			.q_a     (bank_qa[gi]),
			.addr_b  (phase[gi][23:17]),
			.q_b     (bank_qb[gi])
		);
	end
endgenerate

// one register byte, by full byte address within the window ($800+ only;
// the sample RAM below $800 reads through the banks' port A instead)
function automatic [7:0] rd_byte(input [11:0] ba);
	case (ba[10:0])
		11'h001: rd_byte = mode;
		11'h002: rd_byte = control;
		11'h006: rd_byte = volume;
		default:
			if (ba[10:0] >= 11'h010 && ba[10:0] < 11'h030) begin
				case (ba[1:0])
				2'd1: rd_byte = ba[2] ? incr[ba[4:3]][23:16] : phase[ba[4:3]][23:16];
				2'd2: rd_byte = ba[2] ? incr[ba[4:3]][15:8]  : phase[ba[4:3]][15:8];
				2'd3: rd_byte = ba[2] ? incr[ba[4:3]][7:0]   : phase[ba[4:3]][7:0];
				default: rd_byte = 8'h00;
				endcase
			end
			else rd_byte = 8'h00;          // version, status, everything else
	endcase
endfunction

assign rdata = a[11] ? {rd_byte({a, 2'd0}), rd_byte({a, 2'd1}),
                        rd_byte({a, 2'd2}), rd_byte({a, 2'd3})}
                     : bank_qa[a[10:9]];

reg [$clog2(SAMPLE_DIV)-1:0] sdiv;
wire tick = (sdiv == SAMPLE_DIV-1);

// voice byte lane, delayed one clock to line up with the registered q_b
reg [1:0] lane_r [0:3];
always @(posedge clk) begin
	lane_r[0] <= phase[0][16:15];
	lane_r[1] <= phase[1][16:15];
	lane_r[2] <= phase[2][16:15];
	lane_r[3] <= phase[3][16:15];
end

function automatic [7:0] lane_byte(input [31:0] q, input [1:0] lane);
	case (lane)
		2'd0: lane_byte = q[31:24];
		2'd1: lane_byte = q[23:16];
		2'd2: lane_byte = q[15:8];
		default: lane_byte = q[7:0];
	endcase
endfunction

wire [7:0] s0 = lane_byte(bank_qb[0], lane_r[0]);
wire [7:0] s1 = lane_byte(bank_qb[1], lane_r[1]);
wire [7:0] s2 = lane_byte(bank_qb[2], lane_r[2]);
wire [7:0] s3 = lane_byte(bank_qb[3], lane_r[3]);
wire signed [10:0] acc = {3'd0, s0} + {3'd0, s1} + {3'd0, s2} + {3'd0, s3}
                       - 11'd512;

reg signed [15:0] out;
assign sample_l = out;
assign sample_r = out;

task automatic wr_byte(input [11:0] ba, input [7:0] d);
	case (ba[10:0])
		11'h001: mode    <= d;
		11'h002: control <= d;
		11'h006: volume  <= d;
		default:
			if (ba[10:0] >= 11'h010 && ba[10:0] < 11'h030) begin
				case (ba[1:0])
				2'd1: if (ba[2]) incr[ba[4:3]][23:16] <= d;
				      else       phase[ba[4:3]][23:16] <= d;
				2'd2: if (ba[2]) incr[ba[4:3]][15:8] <= d;
				      else       phase[ba[4:3]][15:8] <= d;
				2'd3: if (ba[2]) incr[ba[4:3]][7:0] <= d;
				      else       phase[ba[4:3]][7:0] <= d;
				default: ;
				endcase
			end
	endcase
endtask

always @(posedge clk) begin
	if (!nreset) begin
		mode <= 0; control <= 0; volume <= 0;
		phase[0] <= 0; phase[1] <= 0; phase[2] <= 0; phase[3] <= 0;
		incr[0] <= 0; incr[1] <= 0; incr[2] <= 0; incr[3] <= 0;
		sdiv <= 0; out <= 0;
	end
	else begin
		sdiv <= tick ? '0 : sdiv + 1'b1;
		if (tick && mode == 8'd2) begin
			phase[0] <= phase[0] + incr[0];
			phase[1] <= phase[1] + incr[1];
			phase[2] <= phase[2] + incr[2];
			phase[3] <= phase[3] + incr[3];
			out <= acc <<< 5;
		end
		else if (mode != 8'd2) out <= 0;

		if (ce && sel && write && a[11]) begin
			if (be[3]) wr_byte({a, 2'd0}, wdata[31:24]);
			if (be[2]) wr_byte({a, 2'd1}, wdata[23:16]);
			if (be[1]) wr_byte({a, 2'd2}, wdata[15:8]);
			if (be[0]) wr_byte({a, 2'd3}, wdata[7:0]);
		end
	end
end

endmodule

//============================================================================
//  asc_bank — one voice's 512-byte sample bank as 128 x 32 block RAM.
//  Port A: CPU read/write with byte enables.  Port B: voice read.
//  Both reads are registered (M10K semantics).  Mixed-port
//  read-during-write is DONT_CARE on hardware and old-data in the
//  sim branch — only reachable by a CPU write racing a voice
//  read of the same longword, per the note in asc_wavetable.
//============================================================================
module asc_bank
(
	input         clk,
	input   [6:0] addr_a,
	input  [31:0] wdata_a,
	input   [3:0] be_a,
	input         we_a,
	output [31:0] q_a,
	input   [6:0] addr_b,
	output [31:0] q_b
);

`ifdef VERILATOR

	reg [31:0] mem [0:127];
	reg [31:0] q_a_r, q_b_r;
	always @(posedge clk) begin
		if (we_a) begin
			if (be_a[3]) mem[addr_a][31:24] <= wdata_a[31:24];
			if (be_a[2]) mem[addr_a][23:16] <= wdata_a[23:16];
			if (be_a[1]) mem[addr_a][15:8]  <= wdata_a[15:8];
			if (be_a[0]) mem[addr_a][7:0]   <= wdata_a[7:0];
		end
		q_a_r <= mem[addr_a];
		q_b_r <= mem[addr_b];
	end
	assign q_a = q_a_r;
	assign q_b = q_b_r;

`else

	altsyncram ram
	(
		.clock0    (clk),
		.address_a (addr_a),
		.data_a    (wdata_a),
		.wren_a    (we_a),
		.byteena_a (be_a),
		.q_a       (q_a),

		.address_b (addr_b),
		.data_b    (32'd0),
		.wren_b    (1'b0),
		.q_b       (q_b),

		.aclr0(1'b0),
		.aclr1(1'b0),
		.addressstall_a(1'b0),
		.addressstall_b(1'b0),
		.byteena_b(1'b1),
		.clock1(1'b1),
		.clocken0(1'b1),
		.clocken1(1'b1),
		.clocken2(1'b1),
		.clocken3(1'b1),
		.eccstatus(),
		.rden_a(1'b1),
		.rden_b(1'b1)
	);
	defparam
		ram.numwords_a = 128,
		ram.widthad_a  = 7,
		ram.width_a    = 32,
		ram.width_byteena_a = 4,
		ram.numwords_b = 128,
		ram.widthad_b  = 7,
		ram.width_b    = 32,
		ram.width_byteena_b = 1,
		ram.address_reg_b = "CLOCK0",
		ram.clock_enable_input_a = "BYPASS",
		ram.clock_enable_input_b = "BYPASS",
		ram.clock_enable_output_a = "BYPASS",
		ram.clock_enable_output_b = "BYPASS",
		ram.indata_reg_b = "CLOCK0",
		ram.intended_device_family = "Cyclone V",
		ram.lpm_type = "altsyncram",
		ram.operation_mode = "BIDIR_DUAL_PORT",
		ram.outdata_aclr_a = "NONE",
		ram.outdata_aclr_b = "NONE",
		ram.outdata_reg_a = "UNREGISTERED",
		ram.outdata_reg_b = "UNREGISTERED",
		ram.power_up_uninitialized = "FALSE",
		ram.ram_block_type = "M10K",
		ram.read_during_write_mode_mixed_ports = "DONT_CARE",
		ram.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
		ram.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
		ram.wrcontrol_wraddress_reg_b = "CLOCK0";

`endif

endmodule
