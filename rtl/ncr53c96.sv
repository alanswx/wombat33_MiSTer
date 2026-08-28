//============================================================================
//  ncr53c96 — the Quadra 800's SCSI controller with an integrated
//  single-disk target (SCSI ID DISK_ID, LUN 0) on the MiSTer block-device
//  interface.  Register-visible behavior follows MAME ncr53c90.cpp; the
//  bus itself is not modeled — a select executes the CDB against the
//  target directly, and INFO TRANSFER streams the prepared data.
//
//  Boot-path command set: TEST UNIT READY, REQUEST SENSE, INQUIRY, MODE
//  SENSE(6), READ CAPACITY(10), READ(6/10), WRITE(6/10).  Anything else
//  returns CHECK CONDITION with ILLEGAL REQUEST sense.
//
//  Register file (16-byte strides upstream; rs = reg number):
//   r0 tcount lo   r1 tcount hi   r2 FIFO      r3 command
//   r4 status/dest-id             r5 istatus/timeout
//   r6 seq-step/sync-period      r7 fifo-flags/sync-offset
//   r8 conf1  r9 clkconv  rA test  rB conf2  rC conf3
//
//  DMA side (Turbo SCSI pseudo-DMA): dma_rd/dma_wr pull/push one byte per
//  handshake; dma_valid pulses when the byte moved.  drq gates the IOSB's
//  /DTACK holdoff.
//============================================================================

module ncr53c96
#(
	parameter DISK_ID = 0
)
(
	input         clk,
	input         nreset,
	input         ce,

	// register byte access, one per sel pulse
	input         sel,
	input         write,
	input   [3:0] rs,
	input   [7:0] wdata,
	output  [7:0] rdata,

	// pseudo-DMA byte stream
	input         dma_rd,          // level-held until dma_valid
	input         dma_wr,
	input   [7:0] dma_wdata,
	output  [7:0] dma_rdata,
	output reg    dma_valid,
	output        drq,
	output reg    irq,

	// MiSTer block device (512-byte blocks, 16-bit buffer bus)
	input         img_mounted,
	input  [63:0] img_size,
	output reg [31:0] io_lba,
	output reg    io_rd,
	output reg    io_wr,
	input         io_ack,
	input   [7:0] sd_buff_addr,
	input  [15:0] sd_buff_dout,
	output [15:0] sd_buff_din,
	input         sd_buff_wr
);

// SCSI phases
localparam [2:0] PH_DOUT = 3'd0, PH_DIN = 3'd1, PH_CMD = 3'd2, PH_STAT = 3'd3,
                 PH_MOUT = 3'd6, PH_MIN = 3'd7;
// interrupt status bits
localparam [7:0] I_SEL = 8'h01, I_SELATN = 8'h02, I_RESEL = 8'h04,
                 I_FC = 8'h08, I_BUS = 8'h10, I_DISC = 8'h20, I_ILL = 8'h40,
                 I_RST = 8'h80;

//----------------------------------------------------------------------------
// registers
//----------------------------------------------------------------------------
reg [15:0] tc_latch;
reg [16:0] tcounter;               // 0 in the latch means 65536
reg        tc_zero;
reg  [7:0] fifo [0:15];
reg  [4:0] fifo_cnt;               // count; head is fifo[0] (shift on read)
reg  [7:0] cmd_r;
reg  [2:0] phase;
reg  [7:0] istatus;
reg  [2:0] seq_step;
reg  [3:0] dest_id;
reg  [7:0] conf1, conf2, conf3, clkconv, timeout_r, syncp, synco, testr;

//----------------------------------------------------------------------------
// target state
//----------------------------------------------------------------------------
reg        mounted;
reg [31:0] disk_blocks;
reg  [7:0] cdb [0:9];
reg  [3:0] cdb_len;
reg [31:0] lba;
reg [31:0] blocks_left;            // blocks still to move for READ/WRITE
reg [15:0] sbuf [0:255];           // one sector / synthesized data
reg  [9:0] sbuf_len;               // valid bytes in sbuf
reg  [9:0] sbuf_pos;               // next byte index
reg        data_dir_in;            // 1 = target->initiator
reg  [7:0] scsi_status;            // 0 good, 2 check condition
reg  [7:0] sense_key;
reg        buf_valid;              // sbuf holds data ready to stream

assign sd_buff_din = sbuf[sd_buff_addr];

localparam T_IDLE = 3'd0, T_FETCH = 3'd1, T_XFER = 3'd2, T_FLUSH = 3'd3,
           T_STATUS = 3'd4, T_MSGIN = 3'd5;
reg [2:0] tstate;

// DRQ: during a DMA transfer command with bytes ready to move
reg        xfer_dma;               // active transfer is DMA
wire byte_avail = buf_valid && (sbuf_pos < sbuf_len);
assign drq = xfer_dma && (tstate == T_XFER) &&
             (data_dir_in ? byte_avail : 1'b1) && !tc_zero;

wire [7:0] sbuf_byte = sbuf_pos[0] ? sbuf[sbuf_pos[9:1]][7:0]
                                   : sbuf[sbuf_pos[9:1]][15:8];
// the byte rides with dma_valid: sbuf_pos advances on the same edge
reg [7:0] dma_rlatch;
assign dma_rdata = dma_rlatch;

// register reads (side-effect-free except FIFO/istatus handled in the block)
assign rdata = (rs == 4'h0) ? tcounter[7:0]  :
               (rs == 4'h1) ? tcounter[15:8] :
               (rs == 4'h2) ? ((fifo_cnt != 0) ? fifo[0] : 8'h00) :
               (rs == 4'h3) ? cmd_r :
               (rs == 4'h4) ? {1'b0, 1'b0, 1'b0, tc_zero, 1'b1, phase} :
               (rs == 4'h5) ? istatus :
               (rs == 4'h6) ? {5'd0, seq_step} :
               (rs == 4'h7) ? {3'd0, fifo_cnt} :
               (rs == 4'h8) ? conf1 :
               (rs == 4'h9) ? clkconv :
               (rs == 4'hA) ? testr :
               (rs == 4'hB) ? conf2 :
               (rs == 4'hC) ? conf3 : 8'h00;

// CDB length by opcode group
function [3:0] group_len(input [7:0] op);
	group_len = (op[7:5] == 3'b001 || op[7:5] == 3'b010) ? 4'd10 : 4'd6;
endfunction

integer i;

task fifo_push(input [7:0] b);
	if (fifo_cnt < 16) begin
		fifo[fifo_cnt] <= b;
		fifo_cnt <= fifo_cnt + 1'b1;
	end
endtask

task fifo_shift;                    // drop head
	for (i = 0; i < 15; i = i + 1) fifo[i] <= fifo[i+1];
	fifo_cnt <= fifo_cnt - 1'b1;
endtask

task raise(input [7:0] bits);
	istatus <= istatus | bits;
	irq <= 1;
endtask

// prepare synthesized data in sbuf (big-endian byte pairs)
task set_byte(input [9:0] idx, input [7:0] b);
	if (idx[0]) sbuf[idx[9:1]][7:0]  <= b;
	else        sbuf[idx[9:1]][15:8] <= b;
endtask

//----------------------------------------------------------------------------
// main
//----------------------------------------------------------------------------
always @(posedge clk) begin
	if (!nreset) begin
		tc_latch <= 0; tcounter <= 0; tc_zero <= 0;
		fifo_cnt <= 0; cmd_r <= 0; phase <= PH_DOUT;
		istatus <= 0; seq_step <= 0; dest_id <= 0;
		conf1 <= 0; conf2 <= 0; conf3 <= 0; clkconv <= 0;
		timeout_r <= 0; syncp <= 0; synco <= 0; testr <= 0;
		irq <= 0; dma_valid <= 0; dma_rlatch <= 0;
		mounted <= 0; disk_blocks <= 0;
		io_lba <= 0; io_rd <= 0; io_wr <= 0;
		tstate <= T_IDLE; xfer_dma <= 0;
		lba <= 0; blocks_left <= 0;
		sbuf_len <= 0; sbuf_pos <= 0; buf_valid <= 0;
		data_dir_in <= 0; scsi_status <= 0; sense_key <= 0;
		cdb_len <= 0;
	end
	else begin
		dma_valid <= 0;

		if (img_mounted) begin
			mounted <= (img_size != 0);
			disk_blocks <= img_size[40:9];
		end

		// sector arrives from the platform during io_rd service
		if (sd_buff_wr) sbuf[sd_buff_addr] <= sd_buff_dout;

		if (io_ack) begin
			if (io_rd) begin
				buf_valid <= 1;
				sbuf_len <= 10'd512;
				sbuf_pos <= 0;
			end
			io_rd <= 0;
			io_wr <= 0;
		end

		//------------------------------------------------------------ DMA moves
		if (drq && dma_rd && data_dir_in && !dma_valid) begin
			dma_valid <= 1;
			dma_rlatch <= sbuf_byte;
			sbuf_pos <= sbuf_pos + 1'b1;
			tcounter <= tcounter - 1'b1;
			if (tcounter == 17'd1) tc_zero <= 1;
		end
		if (drq && dma_wr && !data_dir_in && !dma_valid) begin
			dma_valid <= 1;
			set_byte(sbuf_pos, dma_wdata);
			sbuf_pos <= sbuf_pos + 1'b1;
			tcounter <= tcounter - 1'b1;
			if (tcounter == 17'd1) tc_zero <= 1;
		end

		//------------------------------------------------------------ target FSM
		case (tstate)
		T_FETCH: if (!io_rd && !io_wr && buf_valid) tstate <= T_XFER;
		T_XFER: begin
			if (data_dir_in) begin
				if (tc_zero) begin
					// count exhausted: bus wants service (status next)
					phase  <= PH_STAT;
					tstate <= T_IDLE;
					xfer_dma <= 0;
					raise(I_BUS);
				end
				else if (!byte_avail) begin
					// sector drained mid-transfer: next block or done
					if (blocks_left != 0) begin
						buf_valid <= 0;
						io_lba <= lba;
						lba <= lba + 1'b1;
						blocks_left <= blocks_left - 1'b1;
						io_rd <= 1;
						tstate <= T_FETCH;
					end
					else begin
						phase  <= PH_STAT;
						tstate <= T_IDLE;
						xfer_dma <= 0;
						raise(I_BUS);
					end
				end
			end
			else begin
				// data out: flush each filled sector
				if (sbuf_pos == 10'd512) begin
					io_lba <= lba;
					lba <= lba + 1'b1;
					io_wr <= 1;
					sbuf_pos <= 0;
					tstate <= T_FLUSH;
				end
				else if (tc_zero) begin
					phase  <= PH_STAT;
					tstate <= T_IDLE;
					xfer_dma <= 0;
					raise(I_BUS);
				end
			end
		end
		T_FLUSH: if (io_ack) begin
			// io_rd/io_wr cleared above; continue or finish
			if (tc_zero) begin
				phase  <= PH_STAT;
				tstate <= T_IDLE;
				xfer_dma <= 0;
				raise(I_BUS);
			end
			else tstate <= T_XFER;
		end
		default: ;
		endcase

		//------------------------------------------------------------ registers
		if (ce && sel) begin
			if (write) begin
				case (rs)
				4'h0: tc_latch[7:0]  <= wdata;
				4'h1: tc_latch[15:8] <= wdata;
				4'h2: fifo_push(wdata);
				4'h3: begin
					cmd_r <= wdata;
					exec_command(wdata);
				end
				4'h4: dest_id  <= wdata[3:0];
				4'h5: timeout_r <= wdata;
				4'h6: syncp <= wdata;
				4'h7: synco <= wdata;
				4'h8: conf1 <= wdata;
				4'h9: clkconv <= wdata;
				4'hA: testr <= wdata;
				4'hB: conf2 <= wdata;
				4'hC: conf3 <= wdata;
				default: ;
				endcase
			end
			else begin
				case (rs)
				4'h2: if (fifo_cnt != 0) fifo_shift;
				4'h5: begin                     // reading ISR clears int
					istatus <= 0;
					irq <= 0;
				end
				default: ;
				endcase
			end
		end
	end
end

//----------------------------------------------------------------------------
// command execution (invoked on command-register writes)
//----------------------------------------------------------------------------
task exec_command(input [7:0] c);
	reg [6:0] op;
	reg       dma;
	begin
		op  = c[6:0];
		dma = c[7];
		case (op)
		7'h00: ;                                       // NOP
		7'h01: fifo_cnt <= 0;                          // flush FIFO
		7'h02: begin                                   // reset chip
			fifo_cnt <= 0; istatus <= 0; irq <= 0;
			tstate <= T_IDLE; phase <= PH_DOUT; xfer_dma <= 0;
		end
		7'h03: raise(I_RST);                           // reset SCSI bus
		7'h41, 7'h42: begin                            // select (with ATN)
			if (dest_id == DISK_ID[3:0] && mounted) begin
				// FIFO: [identify] cdb...; without ATN: cdb only
				run_cdb((op == 7'h42) ? 5'd1 : 5'd0);
				seq_step <= 3'd4;
				raise(I_FC | I_BUS);
			end
			else begin
				// selection timeout
				seq_step <= 3'd0;
				fifo_cnt <= 0;
				raise(I_DISC);
			end
		end
		7'h44, 7'h45: ;                                // en/dis selection
		7'h10: begin                                   // information transfer
			xfer_dma <= dma;
			if (dma) begin
				tcounter <= (tc_latch == 0) ? 17'h10000 : {1'b0, tc_latch};
				tc_zero  <= 0;
			end
			if (phase == PH_DIN || phase == PH_DOUT) begin
				if (data_dir_in && !buf_valid && blocks_left != 0) begin
					io_lba <= lba;
					lba <= lba + 1'b1;
					blocks_left <= blocks_left - 1'b1;
					io_rd <= 1;
					tstate <= T_FETCH;
				end
				else tstate <= T_XFER;
				// non-DMA data-in: hand over a FIFO's worth immediately
				if (!dma && data_dir_in) fill_fifo_from_buf;
			end
			else if (phase == PH_STAT) begin
				// treated like ICCS by some drivers
				fifo_push(scsi_status);
				fifo_push(8'h00);
				phase <= PH_MIN;
				raise(I_FC);
			end
			else if (phase == PH_MIN) begin
				fifo_push(8'h00);
				raise(I_FC);
			end
			else raise(I_ILL);
		end
		7'h11: begin                                   // initiator cmd complete
			fifo_push(scsi_status);
			fifo_push(8'h00);                          // command complete msg
			phase <= PH_MIN;
			raise(I_FC);
		end
		7'h12: begin                                   // message accept
			phase <= PH_DOUT;
			seq_step <= 3'd0;
			raise(I_DISC);
		end
		7'h18: begin                                   // transfer pad
			tstate <= T_IDLE;
			raise(I_BUS);
		end
		7'h1A, 7'h1B: ;                                // set/reset ATN
		default: raise(I_ILL);
		endcase
	end
endtask

// non-DMA data-in: move up to a FIFO's worth from the sector buffer;
// polled drivers re-issue XFER for more
task fill_fifo_from_buf;
	reg [9:0] p;
	reg [4:0] n;
	begin
		p = sbuf_pos;
		n = 0;
		for (i = 0; i < 16; i = i + 1) begin
			if (buf_valid && (p < sbuf_len)) begin
				fifo[n] <= p[0] ? sbuf[p[9:1]][7:0] : sbuf[p[9:1]][15:8];
				p = p + 1'b1;
				n = n + 1'b1;
			end
		end
		fifo_cnt <= n;
		sbuf_pos <= p;
	end
endtask

//----------------------------------------------------------------------------
// CDB execution against the target (bytes read straight from the FIFO —
// nonblocking cdb[] copies are not visible within this cycle)
//----------------------------------------------------------------------------
task run_cdb(input [4:0] skip);
	reg [7:0] opc, c1, c2, c3, c4, c7, c8;
	reg [31:0] cap;
	begin
		opc = (skip < fifo_cnt) ? fifo[skip] : 8'h00;
		c1 = fifo[skip+1]; c2 = fifo[skip+2]; c3 = fifo[skip+3];
		c4 = fifo[skip+4]; c7 = fifo[skip+7]; c8 = fifo[skip+8];
		for (i = 0; i < 10; i = i + 1)
			cdb[i] <= (skip + i < fifo_cnt) ? fifo[skip + i] : 8'h00;
		fifo_cnt <= 0;
		scsi_status <= 8'h00;
		buf_valid <= 0;
		sbuf_pos <= 0;
		blocks_left <= 0;
		data_dir_in <= 1;
		cap = disk_blocks - 1;

		case (opc)
		8'h00: begin                                   // TEST UNIT READY
			phase <= PH_STAT;
		end
		8'h03: begin                                   // REQUEST SENSE
			for (i = 0; i < 9; i = i + 1) sbuf[i] <= 16'h0000;
			set_byte(10'd0, 8'h70);
			set_byte(10'd2, sense_key);
			set_byte(10'd7, 8'h0A);
			sense_key <= 0;
			sbuf_len <= 10'd18; buf_valid <= 1;
			phase <= PH_DIN;
		end
		8'h12: begin                                   // INQUIRY
			for (i = 0; i < 18; i = i + 1) sbuf[i] <= 16'h2020;
			set_byte(10'd0, 8'h00);                    // direct-access
			set_byte(10'd1, 8'h00);
			set_byte(10'd2, 8'h02);                    // SCSI-2
			set_byte(10'd3, 8'h02);
			set_byte(10'd4, 8'd31);
			set_byte(10'd8,  "W"); set_byte(10'd9,  "O");
			set_byte(10'd10, "M"); set_byte(10'd11, "B");
			set_byte(10'd12, "A"); set_byte(10'd13, "T");
			set_byte(10'd14, "3"); set_byte(10'd15, "3");
			sbuf_len <= 10'd36; buf_valid <= 1;
			phase <= PH_DIN;
		end
		8'h1A: begin                                   // MODE SENSE(6)
			for (i = 0; i < 6; i = i + 1) sbuf[i] <= 16'h0000;
			set_byte(10'd0, 8'h03);
			sbuf_len <= 10'd4; buf_valid <= 1;
			phase <= PH_DIN;
		end
		8'h25: begin                                   // READ CAPACITY(10)
			set_byte(10'd0, cap[31:24]);
			set_byte(10'd1, cap[23:16]);
			set_byte(10'd2, cap[15:8]);
			set_byte(10'd3, cap[7:0]);
			set_byte(10'd4, 8'd0); set_byte(10'd5, 8'd0);
			set_byte(10'd6, 8'd2); set_byte(10'd7, 8'd0);   // 512-byte blocks
			sbuf_len <= 10'd8; buf_valid <= 1;
			phase <= PH_DIN;
		end
		8'h08: begin                                   // READ(6)
			lba <= {11'd0, c1[4:0], c2, c3};
			blocks_left <= (c4 == 0) ? 32'd256 : {24'd0, c4};
			phase <= PH_DIN;
		end
		8'h28: begin                                   // READ(10)
			lba <= {c2, c3, c4, fifo[skip+5]};
			blocks_left <= {16'd0, c7, c8};
			phase <= PH_DIN;
		end
		8'h0A: begin                                   // WRITE(6)
			lba <= {11'd0, c1[4:0], c2, c3};
			data_dir_in <= 0;
			phase <= PH_DOUT;
		end
		8'h2A: begin                                   // WRITE(10)
			lba <= {c2, c3, c4, fifo[skip+5]};
			data_dir_in <= 0;
			phase <= PH_DOUT;
		end
		default: begin
			scsi_status <= 8'h02;                      // CHECK CONDITION
			sense_key <= 8'h05;                        // ILLEGAL REQUEST
			phase <= PH_STAT;
		end
		endcase
	end
endtask

endmodule
