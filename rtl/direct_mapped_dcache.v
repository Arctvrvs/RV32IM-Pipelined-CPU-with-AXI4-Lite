// -----------------------------------------------------------------------------
// Blocking direct-mapped write-back data cache for the RV32IM pipelined CPU.
// -----------------------------------------------------------------------------
// CPU-side protocol:
//   - cpu_valid marks a load/store request in the MEM stage.
//   - cpu_we == 0 means load; nonzero byte enables mean store.
//   - cpu_ready is high for a hit, or for one response cycle after a miss fill.
//   - The CPU holds request signals stable while cpu_ready is low.
//
// Cache organization:
//   - direct mapped
//   - one 32-bit word per line
//   - byte write enables
//   - write-back, write-allocate
//   - internal backing memory with optional +DMEM_HEX=<file> initialization
//
// This is a teaching cache, not an AXI cache. It gives the pipeline the key
// architectural behavior needed for a cache version: memory hit/miss latency,
// dirty victim writeback, write allocate, and pipeline stalls on misses.
// -----------------------------------------------------------------------------
module direct_mapped_dcache #(
    parameter integer MEM_WORDS    = 65536,
    parameter integer LINES        = 16,
    parameter integer INDEX_BITS   = 4,
    parameter integer MISS_PENALTY = 3
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        cpu_valid,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire [3:0]  cpu_we,
    output reg  [31:0] cpu_rdata,
    output wire        cpu_ready,

    output reg  [31:0] access_count,
    output reg  [31:0] hit_count,
    output reg  [31:0] miss_count
);

    localparam integer TAG_BITS = 32 - 2 - INDEX_BITS;
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_MISS = 2'd1;
    localparam [1:0] S_RESP = 2'd2;

    reg [31:0] backing_mem [0:MEM_WORDS-1];

    reg                  valid [0:LINES-1];
    reg                  dirty [0:LINES-1];
    reg [TAG_BITS-1:0]   tag   [0:LINES-1];
    reg [31:0]           data  [0:LINES-1];

    reg [1:0]  state;
    reg [31:0] req_addr;
    reg [31:0] req_wdata;
    reg [3:0]  req_we;
    reg [31:0] resp_data;
    reg [31:0] wait_count;

    wire [INDEX_BITS-1:0] cur_index = cpu_addr[INDEX_BITS+1:2];
    wire [TAG_BITS-1:0]   cur_tag   = cpu_addr[31:INDEX_BITS+2];
    wire [31:0]           cur_word  = cpu_addr[31:2];
    wire                  cur_hit   = valid[cur_index] && (tag[cur_index] == cur_tag);

    wire [INDEX_BITS-1:0] req_index = req_addr[INDEX_BITS+1:2];
    wire [TAG_BITS-1:0]   req_tag   = req_addr[31:INDEX_BITS+2];
    wire [31:0]           req_word  = req_addr[31:2];

    assign cpu_ready = (state == S_IDLE) ? (!cpu_valid || cur_hit) :
                       (state == S_RESP);

    integer i;
    reg [1023:0] hexfile;

    function [31:0] apply_store;
        input [31:0] old_word;
        input [31:0] store_word;
        input [3:0]  be;
        begin
            apply_store = old_word;
            if (be[0]) apply_store[7:0]   = store_word[7:0];
            if (be[1]) apply_store[15:8]  = store_word[15:8];
            if (be[2]) apply_store[23:16] = store_word[23:16];
            if (be[3]) apply_store[31:24] = store_word[31:24];
        end
    endfunction

    function [31:0] debug_word;
        input [31:0] word_addr;
        reg [INDEX_BITS-1:0] dbg_index;
        reg [TAG_BITS-1:0]   dbg_tag;
        begin
            dbg_index = word_addr[INDEX_BITS-1:0];
            dbg_tag   = word_addr[TAG_BITS+INDEX_BITS-1:INDEX_BITS];
            if (valid[dbg_index] && dirty[dbg_index] && (tag[dbg_index] == dbg_tag)) begin
                debug_word = data[dbg_index];
            end else begin
                debug_word = backing_mem[word_addr];
            end
        end
    endfunction

    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            backing_mem[i] = 32'h0000_0000;
        end

        if ($value$plusargs("DMEM_HEX=%s", hexfile)) begin
            $display("Loading data memory into D-cache backing store from %0s", hexfile);
            $readmemh(hexfile, backing_mem);
        end
    end

    always @(*) begin
        if (state == S_IDLE) begin
            cpu_rdata = cur_hit ? data[cur_index] : 32'h0000_0000;
        end else if (state == S_RESP) begin
            cpu_rdata = resp_data;
        end else begin
            cpu_rdata = 32'h0000_0000;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            req_addr <= 32'h0;
            req_wdata <= 32'h0;
            req_we <= 4'h0;
            resp_data <= 32'h0;
            wait_count <= 32'h0;
            access_count <= 32'h0;
            hit_count <= 32'h0;
            miss_count <= 32'h0;

            for (i = 0; i < LINES; i = i + 1) begin
                valid[i] <= 1'b0;
                dirty[i] <= 1'b0;
                tag[i]   <= {TAG_BITS{1'b0}};
                data[i]  <= 32'h0000_0000;
            end
        end else begin
            case (state)
                S_IDLE: begin
                    if (cpu_valid) begin
                        access_count <= access_count + 32'd1;
                        if (cur_hit) begin
                            hit_count <= hit_count + 32'd1;
                            if (cpu_we != 4'b0000) begin
                                data[cur_index] <= apply_store(data[cur_index], cpu_wdata, cpu_we);
                                dirty[cur_index] <= 1'b1;
                            end
                        end else begin
                            miss_count <= miss_count + 32'd1;
                            req_addr <= cpu_addr;
                            req_wdata <= cpu_wdata;
                            req_we <= cpu_we;

                            // Write back dirty victim before refill.  Because each line
                            // holds one word, the victim word address is {tag,index}.
                            if (valid[cur_index] && dirty[cur_index]) begin
                                backing_mem[{tag[cur_index], cur_index}] <= data[cur_index];
                            end

                            wait_count <= MISS_PENALTY;
                            state <= S_MISS;
                        end
                    end
                end

                S_MISS: begin
                    if (wait_count != 32'd0) begin
                        wait_count <= wait_count - 32'd1;
                    end else begin
                        tag[req_index] <= req_tag;
                        valid[req_index] <= 1'b1;
                        if (req_we != 4'b0000) begin
                            data[req_index] <= apply_store(backing_mem[req_word], req_wdata, req_we);
                            dirty[req_index] <= 1'b1;
                            resp_data <= apply_store(backing_mem[req_word], req_wdata, req_we);
                        end else begin
                            data[req_index] <= backing_mem[req_word];
                            dirty[req_index] <= 1'b0;
                            resp_data <= backing_mem[req_word];
                        end
                        state <= S_RESP;
                    end
                end

                S_RESP: begin
                    // The CPU observes cpu_ready=1 for this cycle and advances on
                    // this clock edge.  The next cycle accepts a new request.
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
