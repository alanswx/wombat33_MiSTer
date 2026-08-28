//============================================================================
//  rtc3430042 — Apple RTC/PRAM chip (343-0042-B flavor: 256-byte XPRAM),
//  bit-banged over VIA1 port B: PB0 data (bidir), PB1 clock, PB2 enable
//  (active low).  Protocol and command set per MAME macrtc.cpp: shift on
//  the clock's falling edge, MSB first; command byte selects clock
//  registers, classic 20-byte PRAM slots, the write-protect/test
//  registers, or the $38 extended-command path into full XPRAM.
//
//  PRAM powers up zeroed — the ROM sees an invalid checksum and writes
//  its defaults, exactly like a Mac with a dead battery.
//============================================================================

module rtc3430042
#(
	parameter SEC_DIV = 33000000        // clk per wall second
)
(
	input        clk,
	input        nreset,

	input        ce_n,                  // PB2, low = selected
	input        clk_in,                // PB1
	input        data_in,               // PB0 as driven by the host
	output       data_out,              // PB0 read-back
	output       data_oe                // chip is driving PB0 (send phase)
);

localparam ST_NORMAL = 2'd0, ST_WRITE = 2'd1, ST_XPCMD = 2'd2, ST_XPWRITE = 2'd3;

reg  [7:0] pram [0:255];
reg  [7:0] seconds [0:3];
reg  [1:0] state;
reg  [7:0] cmd;
reg  [7:0] data_byte;
reg  [3:0] bit_count;
reg        dir_out;                    // 1 = sending to host
reg        out_bit;
reg        wprot;
reg  [7:0] xpaddr;
reg        ce_d, clk_d;

assign data_out = out_bit;
assign data_oe  = dir_out && !ce_n;

// wall-clock seconds
reg [$clog2(SEC_DIV)-1:0] secdiv;
wire sec_tick = (secdiv == SEC_DIV-1);
wire [31:0] sec_q = {seconds[3], seconds[2], seconds[1], seconds[0]};
wire [31:0] sec_n = sec_q + 32'd1;

integer i;
initial for (i = 0; i < 256; i = i + 1) pram[i] = 8'h00;

// register index of a classic command
wire [4:0] regsel = cmd[6:2];

always @(posedge clk) begin
	if (!nreset) begin
		state <= ST_NORMAL; cmd <= 0; data_byte <= 0; bit_count <= 0;
		dir_out <= 0; out_bit <= 0; wprot <= 0; xpaddr <= 0;
		ce_d <= 1; clk_d <= 0;
		secdiv <= 0;
		seconds[0] <= 0; seconds[1] <= 0; seconds[2] <= 0; seconds[3] <= 0;
	end
	else begin
		secdiv <= sec_tick ? '0 : secdiv + 1'b1;
		if (sec_tick) begin
			seconds[0] <= sec_n[7:0];   seconds[1] <= sec_n[15:8];
			seconds[2] <= sec_n[23:16]; seconds[3] <= sec_n[31:24];
		end

		ce_d  <= ce_n;
		clk_d <= clk_in;

		if (ce_n != ce_d) begin
			// select/deselect aborts any transfer in flight
			data_byte <= 0; bit_count <= 0; dir_out <= 0; out_bit <= 0;
			state <= ST_NORMAL;
		end
		else if (!ce_n && clk_d && !clk_in) begin
			// falling clock edge with the chip selected
			if (dir_out) begin
				out_bit   <= data_byte[bit_count - 1'b1];
				bit_count <= bit_count - 1'b1;
			end
			else begin
				if (bit_count == 4'd7)
					exec_cmd({data_byte[6:0], data_in});
				else begin
					data_byte <= {data_byte[6:0], data_in};
					bit_count <= bit_count + 1'b1;
				end
			end
		end
	end
end

// One received byte: dispatch per state (MAME rtc_execute_cmd)
task exec_cmd;
	input [7:0] b;
	reg   [4:0] r;
	begin
		data_byte <= 0;
		bit_count <= 0;
		case (state)
		ST_XPCMD: begin
			xpaddr <= {cmd[2:0], b[6:2]};
			if (cmd[7]) begin
				dir_out   <= 1;
				data_byte <= pram[{cmd[2:0], b[6:2]}];
				bit_count <= 4'd8;
				state     <= ST_NORMAL;
			end
			else state <= ST_XPWRITE;
		end
		ST_XPWRITE: begin
			if (!wprot) pram[xpaddr] <= b;
			state <= ST_NORMAL;
		end
		ST_WRITE: begin
			state <= ST_NORMAL;
			r = cmd[6:2];
			if (!wprot || r == 5'd13) begin
				casez (r)
				5'b00???: seconds[r[1:0]] <= b;            // 0-7 clock bytes
				5'b010??: pram[{3'b000, r}] <= b;          // classic PRAM, raw
				5'd13:    wprot <= b[7];
				5'b1????: pram[{3'b000, r}] <= b;          // slots as MAME stores
				default: ;                                 // test register etc
				endcase
			end
		end
		default: begin
			cmd <= b;
			if (b[6:3] == 4'b0111) begin                   // $38: extended
				state <= ST_XPCMD;
			end
			else if (b[7]) begin                           // register read
				dir_out   <= 1;
				bit_count <= 4'd8;
				casez (b[6:2])
				5'b00???: data_byte <= seconds[b[3:2]];    // (cmd>>2)&3
				5'b010??: data_byte <= pram[{3'b000, b[6:2]}];
				5'b1????: data_byte <= pram[{3'b000, b[6:2]}];
				default:  data_byte <= 8'h00;
				endcase
			end
			else state <= ST_WRITE;                        // wait for data
		end
		endcase
	end
endtask

endmodule
