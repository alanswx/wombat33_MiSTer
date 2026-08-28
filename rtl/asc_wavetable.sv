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

reg  [7:0] wave [0:2047];
reg  [7:0] mode, control, volume;
reg [23:0] phase [0:3];
reg [23:0] incr  [0:3];

// one register byte, by full byte address within the window
function automatic [7:0] rd_byte(input [11:0] ba);
	if (!ba[11]) rd_byte = wave[ba[10:0]];
	else case (ba[10:0])
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

assign rdata = {rd_byte({a, 2'd0}), rd_byte({a, 2'd1}),
                rd_byte({a, 2'd2}), rd_byte({a, 2'd3})};

reg [$clog2(SAMPLE_DIV)-1:0] sdiv;
wire tick = (sdiv == SAMPLE_DIV-1);

wire [7:0] s0 = wave[{2'd0, phase[0][23:15]}];
wire [7:0] s1 = wave[{2'd1, phase[1][23:15]}];
wire [7:0] s2 = wave[{2'd2, phase[2][23:15]}];
wire [7:0] s3 = wave[{2'd3, phase[3][23:15]}];
wire signed [10:0] acc = {3'd0, s0} + {3'd0, s1} + {3'd0, s2} + {3'd0, s3}
                       - 11'd512;

reg signed [15:0] out;
assign sample_l = out;
assign sample_r = out;

task automatic wr_byte(input [11:0] ba, input [7:0] d);
	if (!ba[11]) wave[ba[10:0]] <= d;
	else case (ba[10:0])
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

		if (ce && sel && write) begin
			if (be[3]) wr_byte({a, 2'd0}, wdata[31:24]);
			if (be[2]) wr_byte({a, 2'd1}, wdata[23:16]);
			if (be[1]) wr_byte({a, 2'd2}, wdata[15:8]);
			if (be[0]) wr_byte({a, 2'd3}, wdata[7:0]);
		end
	end
end

endmodule
