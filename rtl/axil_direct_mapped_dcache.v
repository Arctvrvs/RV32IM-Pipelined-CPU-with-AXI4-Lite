// -----------------------------------------------------------------------------
// Blocking direct-mapped write-back D-cache with AXI4-Lite backing-memory port
// -----------------------------------------------------------------------------
// CPU side: simple valid/ready memory-stage interface used by rv32im_pipeline.
// AXI side: AXI4-Lite manager interface used to read/write the external backing
// memory on misses and dirty victim evictions.
//
// Organization:
//   - direct mapped
//   - one 32-bit word per line
//   - write-back, write-allocate
//   - byte write enables
//   - blocking: one outstanding CPU request and one outstanding AXI transaction
//
// This is a realistic next step beyond the internal-memory teaching cache: the
// cache is now separated from memory by AXI-Lite handshakes, so a miss stalls the
// CPU until AXI refill/writeback completes.
// -----------------------------------------------------------------------------
module axil_direct_mapped_dcache #(
    parameter integer LINES      = 16,
    parameter integer INDEX_BITS = 4
) (
    input  wire        clk,
    input  wire        rst,

    // CPU memory-stage request/response
    input  wire        cpu_valid,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire [3:0]  cpu_we,
    output reg  [31:0] cpu_rdata,
    output wire        cpu_ready,

    // AXI-Lite read address channel
    output reg  [31:0] m_axi_araddr,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,

    // AXI-Lite read data channel
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready,

    // AXI-Lite write address channel
    output reg  [31:0] m_axi_awaddr,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,

    // AXI-Lite write data channel
    output reg  [31:0] m_axi_wdata,
    output reg  [3:0]  m_axi_wstrb,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,

    // AXI-Lite write response channel
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,

    output reg  [31:0] access_count,
    output reg  [31:0] hit_count,
    output reg  [31:0] miss_count,
    output reg  [31:0] writeback_count
);

    localparam integer TAG_BITS = 32 - 2 - INDEX_BITS;

    localparam [2:0] S_IDLE      = 3'd0;
    localparam [2:0] S_WB_ADDR   = 3'd1;
    localparam [2:0] S_WB_RESP   = 3'd2;
    localparam [2:0] S_REFILL_AR = 3'd3;
    localparam [2:0] S_REFILL_R  = 3'd4;
    localparam [2:0] S_RESP      = 3'd5;

    reg                  valid [0:LINES-1];
    reg                  dirty [0:LINES-1];
    reg [TAG_BITS-1:0]   tag   [0:LINES-1];
    reg [31:0]           data  [0:LINES-1];

    reg [2:0]  state;
    reg [31:0] req_addr;
    reg [31:0] req_wdata;
    reg [3:0]  req_we;
    reg [31:0] resp_data;
    reg        aw_done;
    reg        w_done;

    wire [INDEX_BITS-1:0] cur_index = cpu_addr[INDEX_BITS+1:2];
    wire [TAG_BITS-1:0]   cur_tag   = cpu_addr[31:INDEX_BITS+2];
    wire                  cur_hit   = valid[cur_index] && (tag[cur_index] == cur_tag);

    wire [INDEX_BITS-1:0] req_index = req_addr[INDEX_BITS+1:2];
    wire [TAG_BITS-1:0]   req_tag   = req_addr[31:INDEX_BITS+2];
    wire [31:0]           victim_addr = {tag[req_index], req_index, 2'b00};

    assign cpu_ready = (state == S_IDLE) ? (!cpu_valid || cur_hit) :
                       (state == S_RESP);

    integer i;

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

    function [31:0] debug_cached_word;
        input [31:0] byte_addr;
        reg [INDEX_BITS-1:0] dbg_index;
        reg [TAG_BITS-1:0]   dbg_tag;
        begin
            dbg_index = byte_addr[INDEX_BITS+1:2];
            dbg_tag   = byte_addr[31:INDEX_BITS+2];
            if (valid[dbg_index] && (tag[dbg_index] == dbg_tag)) begin
                debug_cached_word = data[dbg_index];
            end else begin
                debug_cached_word = 32'hxxxx_xxxx;
            end
        end
    endfunction

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
            req_addr <= 32'd0;
            req_wdata <= 32'd0;
            req_we <= 4'd0;
            resp_data <= 32'd0;
            aw_done <= 1'b0;
            w_done <= 1'b0;

            m_axi_araddr <= 32'd0;
            m_axi_arvalid <= 1'b0;
            m_axi_rready <= 1'b0;
            m_axi_awaddr <= 32'd0;
            m_axi_awvalid <= 1'b0;
            m_axi_wdata <= 32'd0;
            m_axi_wstrb <= 4'd0;
            m_axi_wvalid <= 1'b0;
            m_axi_bready <= 1'b0;

            access_count <= 32'd0;
            hit_count <= 32'd0;
            miss_count <= 32'd0;
            writeback_count <= 32'd0;

            for (i = 0; i < LINES; i = i + 1) begin
                valid[i] <= 1'b0;
                dirty[i] <= 1'b0;
                tag[i] <= {TAG_BITS{1'b0}};
                data[i] <= 32'd0;
            end
        end else begin
            // Default ready strobes low; states raise them when needed.
            m_axi_rready <= 1'b0;
            m_axi_bready <= 1'b0;

            case (state)
                S_IDLE: begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid <= 1'b0;
                    aw_done <= 1'b0;
                    w_done <= 1'b0;

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
                            if (valid[cur_index] && dirty[cur_index]) begin
                                m_axi_awaddr <= {tag[cur_index], cur_index, 2'b00};
                                m_axi_wdata  <= data[cur_index];
                                m_axi_wstrb  <= 4'b1111;
                                m_axi_awvalid <= 1'b1;
                                m_axi_wvalid  <= 1'b1;
                                aw_done <= 1'b0;
                                w_done <= 1'b0;
                                writeback_count <= writeback_count + 32'd1;
                                state <= S_WB_ADDR;
                            end else begin
                                m_axi_araddr <= {cpu_addr[31:2], 2'b00};
                                m_axi_arvalid <= 1'b1;
                                state <= S_REFILL_AR;
                            end
                        end
                    end
                end

                S_WB_ADDR: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        aw_done <= 1'b1;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        w_done <= 1'b1;
                    end
                    if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
                        (w_done  || (m_axi_wvalid  && m_axi_wready))) begin
                        state <= S_WB_RESP;
                    end
                end

                S_WB_RESP: begin
                    m_axi_bready <= 1'b1;
                    if (m_axi_bvalid) begin
                        dirty[req_index] <= 1'b0;
                        m_axi_araddr <= {req_addr[31:2], 2'b00};
                        m_axi_arvalid <= 1'b1;
                        state <= S_REFILL_AR;
                    end
                end

                S_REFILL_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        state <= S_REFILL_R;
                    end
                end

                S_REFILL_R: begin
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid) begin
                        tag[req_index] <= req_tag;
                        valid[req_index] <= 1'b1;
                        if (req_we != 4'b0000) begin
                            data[req_index] <= apply_store(m_axi_rdata, req_wdata, req_we);
                            dirty[req_index] <= 1'b1;
                            resp_data <= apply_store(m_axi_rdata, req_wdata, req_we);
                        end else begin
                            data[req_index] <= m_axi_rdata;
                            dirty[req_index] <= 1'b0;
                            resp_data <= m_axi_rdata;
                        end
                        state <= S_RESP;
                    end
                end

                S_RESP: begin
                    // One cycle of cpu_ready=1 lets the MEM stage retire the
                    // request.  Next cycle the cache can accept a new access.
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
