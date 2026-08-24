// -----------------------------------------------------------------------------
// Blocking direct-mapped read-only I-cache with AXI4-Lite backing-memory port
// -----------------------------------------------------------------------------
// CPU side: simple valid/ready instruction fetch interface used by the IF stage.
// AXI side: AXI4-Lite manager read interface used to refill a missing line from
// backing memory.  The cache has one 32-bit instruction word per line.
// -----------------------------------------------------------------------------
module axil_direct_mapped_icache #(
    parameter integer LINES      = 16,
    parameter integer INDEX_BITS = 4
) (
    input  wire        clk,
    input  wire        rst,

    // CPU fetch request/response
    input  wire        cpu_valid,
    input  wire [31:0] cpu_addr,
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

    output reg  [31:0] access_count,
    output reg  [31:0] hit_count,
    output reg  [31:0] miss_count
);

    localparam integer TAG_BITS = 32 - 2 - INDEX_BITS;

    localparam [1:0] S_IDLE      = 2'd0;
    localparam [1:0] S_REFILL_AR = 2'd1;
    localparam [1:0] S_REFILL_R  = 2'd2;
    localparam [1:0] S_RESP      = 2'd3;

    reg                  valid [0:LINES-1];
    reg [TAG_BITS-1:0]   tag   [0:LINES-1];
    reg [31:0]           data  [0:LINES-1];

    reg [1:0]  state;
    reg [31:0] req_addr;
    reg [31:0] resp_data;

    wire [INDEX_BITS-1:0] cur_index = cpu_addr[INDEX_BITS+1:2];
    wire [TAG_BITS-1:0]   cur_tag   = cpu_addr[31:INDEX_BITS+2];
    wire                  cur_hit   = valid[cur_index] && (tag[cur_index] == cur_tag);

    wire [INDEX_BITS-1:0] req_index = req_addr[INDEX_BITS+1:2];
    wire [TAG_BITS-1:0]   req_tag   = req_addr[31:INDEX_BITS+2];

    assign cpu_ready = (state == S_IDLE) ? (!cpu_valid || cur_hit) :
                       (state == S_RESP);

    integer i;

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
            cpu_rdata = cur_hit ? data[cur_index] : 32'h0000_0013; // NOP while missing
        end else if (state == S_RESP) begin
            cpu_rdata = resp_data;
        end else begin
            cpu_rdata = 32'h0000_0013;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            req_addr <= 32'd0;
            resp_data <= 32'h0000_0013;
            m_axi_araddr <= 32'd0;
            m_axi_arvalid <= 1'b0;
            m_axi_rready <= 1'b0;
            access_count <= 32'd0;
            hit_count <= 32'd0;
            miss_count <= 32'd0;
            for (i = 0; i < LINES; i = i + 1) begin
                valid[i] <= 1'b0;
                tag[i] <= {TAG_BITS{1'b0}};
                data[i] <= 32'h0000_0013;
            end
        end else begin
            m_axi_rready <= 1'b0;

            case (state)
                S_IDLE: begin
                    m_axi_arvalid <= 1'b0;
                    if (cpu_valid) begin
                        access_count <= access_count + 32'd1;
                        if (cur_hit) begin
                            hit_count <= hit_count + 32'd1;
                        end else begin
                            miss_count <= miss_count + 32'd1;
                            req_addr <= cpu_addr;
                            m_axi_araddr <= {cpu_addr[31:2], 2'b00};
                            m_axi_arvalid <= 1'b1;
                            state <= S_REFILL_AR;
                        end
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
                        data[req_index] <= m_axi_rdata;
                        resp_data <= m_axi_rdata;
                        state <= S_RESP;
                    end
                end

                S_RESP: begin
                    // One cycle of cpu_ready=1 lets IF capture the refilled word.
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
