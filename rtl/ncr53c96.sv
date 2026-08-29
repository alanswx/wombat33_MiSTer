//============================================================================
//  ncr53c96 — the Quadra 800's SCSI controller with an integrated
//  single-disk target (SCSI ID DISK_ID, LUN 0) on the MiSTer block-device
//  interface.  Register-visible behavior follows the Quadra 800 ROM's
//  access patterns (docs/scsi/rom-driver-scsi-access-patterns.md) with
//  QEMU esp.c / MAME ncr53c90.cpp as semantic references
//  (docs/scsi/rtl-gap-analysis.md).  The bus itself is not modeled.
//
//  The ROM's contract, which this implements:
//   - selects are the DMA form ($C1/$C2) with TC preloaded and an EMPTY
//     FIFO; the select completes silently (the ROM's poll exits on DREQ)
//     and the CDB then arrives as FIFO writes plus PDMA bytes, mixed
//     (the last CDB byte always comes through the PDMA port).  The CDB
//     length is inferred from the opcode group; when complete the command
//     executes and I_BUS|I_FC is raised with the new phase visible.
//   - data moves THROUGH the 16-byte FIFO: $90 (DMA transfer info) loads
//     TC and streams sector data into/out of the FIFO; the ROM gates its
//     16-byte bursts on STATUS.TC0 + DREQ + FIFO-flags bit 4, drains via
//     the PDMA window, then waits for INT (raised when TC==0 and the
//     FIFO has drained below 2 — QEMU esp_dma_ti_check).
//   - $11 ICCS pushes status + message(0) and raises I_FC; $12 message
//     accept raises I_DISC and clears the FIFO.
//   - TC regs write a latch (write also clears STATUS.TC0); any command
//     with the DMA bit loads the live counter (0 means 65536).
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
//  /DTACK holdoff and is a continuous function of FIFO occupancy.
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
reg        dma_active;             // current command carried the DMA bit

//----------------------------------------------------------------------------
// transfer engine state
//----------------------------------------------------------------------------
reg        cdb_active;             // select done, collecting CDB bytes
reg  [3:0] cdb_pos;
reg  [3:0] cdb_need;               // 0 until the opcode byte arrives
reg        skip_msg;               // ATN select: discard the identify byte
reg        exec_pending;           // CDB complete, execute next cycle
reg        xfer_in;                // DMA transfer-info, target -> initiator
reg        xfer_out;               // DMA transfer-info, initiator -> target
reg        xfer_pio_in;            // non-DMA TI: hand over one byte
reg        xfer_pio_out;           // non-DMA TI: drain FIFO to buffer
reg        chunk_irq_armed;        // raise I_BUS once per TI command

//----------------------------------------------------------------------------
// target state
//----------------------------------------------------------------------------
reg        mounted;
reg [31:0] disk_blocks;
reg  [7:0] cdb [0:9];
reg [31:0] lba;
reg [31:0] blocks_left;            // read: blocks not yet fetched; write: not yet flushed
reg [15:0] sbuf [0:255];           // one sector / synthesized data
reg  [9:0] sbuf_len;               // valid bytes in sbuf
reg  [9:0] sbuf_pos;               // next byte index
reg        data_dir_in;            // 1 = target->initiator
reg  [7:0] scsi_status;            // 0 good, 2 check condition
reg  [7:0] sense_key;
reg        buf_valid;              // sbuf holds data ready to stream
reg        flush_pending;          // io_wr outstanding, sbuf owned by platform

assign sd_buff_din = sbuf[sd_buff_addr];

`ifdef VERILATOR
// bring-up taps: command writes, CDB executions, interrupt edges — with
// the transfer-engine state that decides completion.  Sim-only.
reg [63:0] dbg_cyc;
reg        dbg_irq_d, dbg_iow_d, dbg_ior_d, dbg_ack_d;
initial dbg_cyc = 0;
`endif

wire byte_avail = buf_valid && (sbuf_pos < sbuf_len);
wire [7:0] sbuf_byte = sbuf_pos[0] ? sbuf[sbuf_pos[9:1]][7:0]
                                   : sbuf[sbuf_pos[9:1]][15:8];
reg [7:0] dma_rlatch;
assign dma_rdata = dma_rlatch;

// DRQ: continuous function of FIFO occupancy and command state.
// CDB / data-out want bytes while TC remains and there is room (16-bit PDMA
// wants room for 2); data-in offers bytes while >= 2 are present (CONFIG3
// LBTM: the last odd byte is left for the processor).
assign drq = cdb_active ? (dma_active && !tc_zero && (fifo_cnt < 5'd15)) :
             xfer_out   ? (dma_active && !tc_zero && (fifo_cnt < 5'd15)) :
             xfer_in    ? (fifo_cnt >= 5'd2) :
             1'b0;

// register reads (side-effect-free except FIFO/istatus handled in the block)
assign rdata = (rs == 4'h0) ? tcounter[7:0]  :
               (rs == 4'h1) ? tcounter[15:8] :
               (rs == 4'h2) ? ((fifo_cnt != 0) ? fifo[0] : 8'h00) :
               (rs == 4'h3) ? cmd_r :
               (rs == 4'h4) ? {irq, 1'b0, 1'b0, tc_zero, 1'b0, phase} :   // bit7 = INT mirrors irq (QEMU esp STAT_INT)
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

// interrupt accumulator: raises collect here (blocking) and merge with the
// same-cycle interrupt-register read at the bottom of the main block, so a
// raise colliding with the ISR read-clear is never lost
/* verilator lint_off BLKSEQ */
reg [7:0] i_new;

task raise(input [7:0] bits);
	i_new = i_new | bits;
endtask
/* verilator lint_on BLKSEQ */

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

task dec_tc;
	tcounter <= tcounter - 1'b1;
	if (tcounter == 17'd1) tc_zero <= 1;
endtask

// one CDB byte arrived (from the FIFO drain or straight off the PDMA port)
task cdb_byte(input [7:0] b);
	if (skip_msg) skip_msg <= 0;             // ATN select: identify message
	else begin
		cdb[cdb_pos] <= b;
		if (cdb_pos == 0) cdb_need <= group_len(b);
		cdb_pos <= cdb_pos + 1'b1;
	end
endtask

// prepare synthesized data in sbuf (big-endian byte pairs)
task set_byte(input [9:0] idx, input [7:0] b);
	if (idx[0]) sbuf[idx[9:1]][7:0]  <= b;
	else        sbuf[idx[9:1]][15:8] <= b;
endtask

//----------------------------------------------------------------------------
// main
//----------------------------------------------------------------------------
wire reg_wr_cyc = ce && sel && write;
wire reg_rd_cyc = ce && sel && !write;
// cycles where the register interface itself touches the FIFO (push, pop,
// or a command that may flush/load it) — the engine chain stands down
wire fifo_ext   = (reg_wr_cyc && (rs == 4'h2 || rs == 4'h3)) ||
                  (reg_rd_cyc && rs == 4'h2);
wire isr_read   = reg_rd_cyc && (rs == 4'h5);

always @(posedge clk) begin
	if (!nreset) begin
		i_new = 8'h00;
		tc_latch <= 0; tcounter <= 0; tc_zero <= 0;
		fifo_cnt <= 0; cmd_r <= 0; phase <= PH_DOUT;
		istatus <= 0; seq_step <= 0; dest_id <= 0;
		conf1 <= 0; conf2 <= 0; conf3 <= 0; clkconv <= 0;
		timeout_r <= 0; syncp <= 0; synco <= 0; testr <= 0;
		irq <= 0; dma_valid <= 0; dma_rlatch <= 0;
		mounted <= 0; disk_blocks <= 0;
		io_lba <= 0; io_rd <= 0; io_wr <= 0;
		dma_active <= 0;
		cdb_active <= 0; cdb_pos <= 0; cdb_need <= 0; skip_msg <= 0;
		exec_pending <= 0;
		xfer_in <= 0; xfer_out <= 0; xfer_pio_in <= 0; xfer_pio_out <= 0;
		chunk_irq_armed <= 0;
		lba <= 0; blocks_left <= 0;
		sbuf_len <= 0; sbuf_pos <= 0; buf_valid <= 0; flush_pending <= 0;
		data_dir_in <= 0; scsi_status <= 0; sense_key <= 0;
	end
	else begin
		i_new = 8'h00;
		dma_valid <= 0;

`ifdef VERILATOR
		dbg_cyc <= dbg_cyc + 64'd1;
		if (ce && sel && write && rs == 4'h3)
			$display("[NCR %0d] cmd=%02X ph=%0d tc=%0d tz=%b ff=%0d bl=%0d sp=%0d xi=%b xo=%b fp=%b ca=%b",
			         dbg_cyc, wdata, phase, tcounter, tc_zero, fifo_cnt,
			         blocks_left, sbuf_pos, xfer_in, xfer_out, flush_pending,
			         cdb_active);
		if (exec_pending)
			$display("[NCR %0d] cdb %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X",
			         dbg_cyc, cdb[0], cdb[1], cdb[2], cdb[3], cdb[4],
			         cdb[5], cdb[6], cdb[7], cdb[8], cdb[9]);
		dbg_irq_d <= irq;
		if (irq && !dbg_irq_d)
			$display("[NCR %0d] INT+ ist=%02X ph=%0d", dbg_cyc, istatus, phase);
		if (io_wr && !dbg_iow_d)
			$display("[NCR %0d] io_wr+ lba=%0d fp=%b", dbg_cyc, io_lba, flush_pending);
		if (io_rd && !dbg_ior_d)
			$display("[NCR %0d] io_rd+ lba=%0d", dbg_cyc, io_lba);
		if (io_ack && !dbg_ack_d)
			$display("[NCR %0d] io_ack+ rd=%b wr=%b ff=%0d sp=%0d po=%b",
			         dbg_cyc, io_rd, io_wr, fifo_cnt, sbuf_pos, xfer_pio_out);
		if (!io_ack && dbg_ack_d)
			$display("[NCR %0d] io_ack- fp=%b ff=%0d sp=%0d po=%b",
			         dbg_cyc, flush_pending, fifo_cnt, sbuf_pos, xfer_pio_out);
		dbg_iow_d <= io_wr;
		dbg_ior_d <= io_rd;
		dbg_ack_d <= io_ack;
`endif

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
			flush_pending <= 0;
		end

		//---------------------------------------------------- block prefetch
		// data-in: fetch the next sector whenever the current one is spent
		if (phase == PH_DIN && data_dir_in && blocks_left != 0 &&
		    !io_rd && !io_wr && (!buf_valid || sbuf_pos >= sbuf_len)) begin
			buf_valid <= 0;
			io_lba <= lba;
			lba <= lba + 1'b1;
			blocks_left <= blocks_left - 1'b1;
			io_rd <= 1;
		end

		//---------------------------------------------------- FIFO engine
		// exactly one FIFO action per cycle; the register interface (push,
		// pop, flush) preempts the chain on its own cycles
		if (!fifo_ext) begin
			if (dma_rd && !dma_valid && fifo_cnt != 0) begin
				// PDMA read: pop the head
				dma_rlatch <= fifo[0];
				fifo_shift;
				dma_valid <= 1;
			end
			else if (dma_rd && !dma_valid && !xfer_in && !cdb_active) begin
				// PDMA read with nothing pending: don't wedge the bus
				dma_rlatch <= 8'hFF;
				dma_valid <= 1;
			end
			else if (dma_wr && !dma_valid && cdb_active && dma_active && !tc_zero) begin
				// PDMA write during CDB collection (the ROM's last CDB byte)
				cdb_byte(dma_wdata);
				dec_tc;
				dma_valid <= 1;
			end
			else if (dma_wr && !dma_valid && xfer_out && dma_active && !tc_zero &&
			         fifo_cnt < 5'd16) begin
				// PDMA write, data-out: into the FIFO; TC counts the DACK
				fifo_push(dma_wdata);
				dec_tc;
				dma_valid <= 1;
			end
			else if (dma_wr && !dma_valid && !cdb_active && !xfer_out) begin
				// stray PDMA write: swallow it rather than wedging the bus
				dma_valid <= 1;
			end
			else if (cdb_active && fifo_cnt != 0) begin
				// CDB bytes preloaded/pushed into the FIFO drain into cdb[]
				cdb_byte(fifo[0]);
				fifo_shift;
			end
			else if ((xfer_out || xfer_pio_out) && fifo_cnt != 0 &&
			         !flush_pending && sbuf_pos < 10'd512) begin
				// data-out: FIFO drains into the sector buffer
				set_byte(sbuf_pos, fifo[0]);
				sbuf_pos <= sbuf_pos + 1'b1;
				fifo_shift;
			end
			else if (xfer_in && dma_active && !tc_zero && fifo_cnt < 5'd16 &&
			         byte_avail) begin
				// data-in: sector buffer fills the FIFO; TC counts here
				fifo_push(sbuf_byte);
				sbuf_pos <= sbuf_pos + 1'b1;
				dec_tc;
			end
			else if (xfer_pio_in && byte_avail && fifo_cnt == 0) begin
				// non-DMA TI data-in: exactly one byte, then bus service
				fifo_push(sbuf_byte);
				sbuf_pos <= sbuf_pos + 1'b1;
				xfer_pio_in <= 0;
				raise(I_BUS);
			end
		end

		//---------------------------------------------------- CDB completion
		if (cdb_active && cdb_need != 0 && cdb_pos == cdb_need) begin
			cdb_active <= 0;
			exec_pending <= 1;
		end
		if (exec_pending) begin
			exec_pending <= 0;
			exec_cdb;
		end

		//---------------------------------------------------- transfer ends
		// data-in chunk complete: TC expired and the host drained the FIFO
		if (xfer_in && chunk_irq_armed && tc_zero && fifo_cnt < 5'd2) begin
			chunk_irq_armed <= 0;
			xfer_in <= 0;
			if (!byte_avail && blocks_left == 0 && !io_rd) phase <= PH_STAT;
			raise(I_BUS);
		end
		// data-in underflow: source exhausted before TC — go to status
		if (xfer_in && chunk_irq_armed && !tc_zero && !byte_avail &&
		    blocks_left == 0 && !io_rd) begin
			chunk_irq_armed <= 0;
			xfer_in <= 0;
			phase <= PH_STAT;
			raise(I_BUS);
		end
		// data-out: full sector in the buffer -> flush it
		if ((xfer_out || xfer_pio_out) && sbuf_pos == 10'd512 &&
		    !flush_pending && !io_rd && !io_wr) begin
			io_lba <= lba;
			lba <= lba + 1'b1;
			if (blocks_left != 0) blocks_left <= blocks_left - 1'b1;
			io_wr <= 1;
			flush_pending <= 1;
			sbuf_pos <= 0;
		end
		// data-out complete: TC expired, FIFO drained, buffer flushed
		if (xfer_out && chunk_irq_armed && tc_zero && fifo_cnt == 0 &&
		    !flush_pending && !io_wr) begin
			if (sbuf_pos != 0 && sbuf_pos < 10'd512) begin
				// trailing partial sector: flush what we have
				io_lba <= lba;
				lba <= lba + 1'b1;
				if (blocks_left != 0) blocks_left <= blocks_left - 1'b1;
				io_wr <= 1;
				flush_pending <= 1;
				sbuf_pos <= 0;
			end
			else begin
				chunk_irq_armed <= 0;
				xfer_out <= 0;
				if (blocks_left == 0) phase <= PH_STAT;
				raise(I_BUS);
			end
		end
		// non-DMA data-out: FIFO drained -> bus service
		if (xfer_pio_out && fifo_cnt == 0) begin
			xfer_pio_out <= 0;
			raise(I_BUS);
		end

		//---------------------------------------------------- registers
		if (ce && sel) begin
			if (write) begin
				case (rs)
				4'h0: begin tc_latch[7:0]  <= wdata; tc_zero <= 0; end
				4'h1: begin tc_latch[15:8] <= wdata; tc_zero <= 0; end
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
				default: ;                      // reg 5 handled below
				endcase
			end
		end

		//---------------------------------------------------- interrupt merge
		// reading the interrupt register clears it (and seq-step); a raise
		// arriving on the very same cycle survives instead of being lost
		if (isr_read) begin
			istatus  <= i_new;
			irq      <= (i_new != 8'h00);
			seq_step <= 0;
		end
		else if (i_new != 8'h00) begin
			istatus <= istatus | i_new;
			irq <= 1;
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
		dma_active <= dma;
		if (dma) begin
			// any DMA-bit command loads the live counter from the latch
			tcounter <= (tc_latch == 16'd0) ? 17'h10000 : {1'b0, tc_latch};
			tc_zero  <= 0;
		end
		case (op)
		7'h00: ;                                       // NOP
		7'h01: fifo_cnt <= 0;                          // flush FIFO
		7'h02: begin                                   // reset chip
			fifo_cnt <= 0; istatus <= 0; irq <= 0;
			phase <= PH_DOUT; seq_step <= 0;
			cdb_active <= 0; exec_pending <= 0;
			xfer_in <= 0; xfer_out <= 0;
			xfer_pio_in <= 0; xfer_pio_out <= 0;
			chunk_irq_armed <= 0;
			dma_active <= 0; tc_zero <= 0;
		end
		7'h03: begin                                   // reset SCSI bus
			if (!conf1[6]) raise(I_RST);               // CONFIG1 DISR gates INT
		end
		7'h41, 7'h42: begin                            // select (with ATN)
			if (dest_id == DISK_ID[3:0] && mounted) begin
				// the ROM's DMA select: complete silently; its poll exits
				// on DREQ and the CDB follows via FIFO/PDMA (QEMU defers
				// the select interrupt until the command has run)
				phase <= PH_CMD;
				cdb_active <= 1;
				cdb_pos <= 0;
				cdb_need <= 0;
				skip_msg <= (op == 7'h42);
				seq_step <= 3'd4;
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
			if (phase == PH_DIN) begin
				if (dma) begin
					xfer_in <= 1;
					chunk_irq_armed <= 1;
				end
				else if (fifo_cnt != 0) raise(I_BUS);  // byte already waiting
				else xfer_pio_in <= 1;
			end
			else if (phase == PH_DOUT) begin
				if (dma) begin
					xfer_out <= 1;
					chunk_irq_armed <= 1;
				end
				else xfer_pio_out <= 1;
			end
			else if (phase == PH_CMD) begin
				// TI while the CDB is still being collected: the ROM's
				// SCSICmd issues $90 here before pushing the bytes —
				// the DMA/TC latch above re-arms it; nothing else to do
			end
			else if (phase == PH_STAT) begin
				// treated like ICCS by some drivers
				fifo[0] <= scsi_status;
				fifo[1] <= 8'h00;
				fifo_cnt <= 5'd2;
				phase <= PH_MIN;
				raise(I_FC);
			end
			else if (phase == PH_MIN) begin
				fifo[0] <= 8'h00;
				fifo_cnt <= 5'd1;
				raise(I_FC);
			end
			else raise(I_ILL);
		end
		7'h11: begin                                   // initiator cmd complete
			fifo[0] <= scsi_status;
			fifo[1] <= 8'h00;                          // command complete msg
			fifo_cnt <= 5'd2;
			phase <= PH_MIN;
			raise(I_FC);
		end
		7'h12: begin                                   // message accept
			phase <= PH_DOUT;
			seq_step <= 3'd0;
			fifo_cnt <= 0;
			raise(I_DISC);
		end
		7'h18: begin                                   // transfer pad
			xfer_in <= 0; xfer_out <= 0;
			tc_zero <= 1;
			raise(I_BUS);
		end
		7'h1A, 7'h1B: ;                                // set/reset ATN
		default: raise(I_ILL);
		endcase
	end
endtask

//----------------------------------------------------------------------------
// CDB execution against the target — runs one cycle after the last CDB
// byte landed, so cdb[] is settled
//----------------------------------------------------------------------------
task exec_cdb;
	reg [31:0] cap;
	begin
		scsi_status <= 8'h00;
		buf_valid <= 0;
		sbuf_pos <= 0;
		blocks_left <= 0;
		data_dir_in <= 1;
		cap = disk_blocks - 1;
		// deferred select interrupt: BS|FC with the command's phase visible
		raise(I_BUS | I_FC);

		case (cdb[0])
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
			lba <= {11'd0, cdb[1][4:0], cdb[2], cdb[3]};
			blocks_left <= (cdb[4] == 0) ? 32'd256 : {24'd0, cdb[4]};
			phase <= PH_DIN;
		end
		8'h28: begin                                   // READ(10)
			lba <= {cdb[2], cdb[3], cdb[4], cdb[5]};
			blocks_left <= {16'd0, cdb[7], cdb[8]};
			phase <= PH_DIN;
		end
		8'h0A: begin                                   // WRITE(6)
			lba <= {11'd0, cdb[1][4:0], cdb[2], cdb[3]};
			blocks_left <= (cdb[4] == 0) ? 32'd256 : {24'd0, cdb[4]};
			data_dir_in <= 0;
			phase <= PH_DOUT;
		end
		8'h2A: begin                                   // WRITE(10)
			lba <= {cdb[2], cdb[3], cdb[4], cdb[5]};
			blocks_left <= {16'd0, cdb[7], cdb[8]};
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
