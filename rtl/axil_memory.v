// -----------------------------------------------------------------------------
// Simple AXI4-Lite word-addressable memory model
// -----------------------------------------------------------------------------
// This module is intended for simulation/regression of the cached CPU.  It
// accepts one read or one write transaction at a time and returns the response
// after LATENCY cycles.  Addresses are byte addresses; storage is 32-bit words.
// -----------------------------------------------------------------------------
module axil_memory #(
    parameter integer MEM_WORDS = 65536,
    parameter integer LATENCY   = 3
) (
    input  wire        clk,
    input  wire        rst,

    // AXI-Lite read address channel
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,

    // AXI-Lite read data channel
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    // AXI-Lite write address channel
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,

    // AXI-Lite write data channel
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,

    // AXI-Lite write response channel
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready
);

    localparam [1:0] S_IDLE  = 2'd0;
    localparam [1:0] S_READ  = 2'd1;
    localparam [1:0] S_WRITE = 2'd2;

    reg [31:0] mem [0:MEM_WORDS-1];
    reg [1:0]  state;
    reg [31:0] lat_count;
    reg [31:0] rd_addr_q;
    reg [31:0] wr_addr_q;
    reg [31:0] wr_data_q;
    reg [3:0]  wr_strb_q;

    integer i;
    reg [1023:0] hexfile;

    assign s_axi_arready = (state == S_IDLE) && !s_axi_rvalid && !s_axi_bvalid;
    assign s_axi_awready = (state == S_IDLE) && !s_axi_rvalid && !s_axi_bvalid;
    assign s_axi_wready  = (state == S_IDLE) && !s_axi_rvalid && !s_axi_bvalid;

    function [31:0] apply_wstrb;
        input [31:0] old_word;
        input [31:0] new_word;
        input [3:0]  wstrb;
        begin
            apply_wstrb = old_word;
            if (wstrb[0]) apply_wstrb[7:0]   = new_word[7:0];
            if (wstrb[1]) apply_wstrb[15:8]  = new_word[15:8];
            if (wstrb[2]) apply_wstrb[23:16] = new_word[23:16];
            if (wstrb[3]) apply_wstrb[31:24] = new_word[31:24];
        end
    endfunction

    function [31:0] debug_word;
        input [31:0] word_addr;
        begin
            debug_word = mem[word_addr];
        end
    endfunction

    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            mem[i] = 32'h0000_0000;
        end
        if ($value$plusargs("DMEM_HEX=%s", hexfile)) begin
            $display("Loading AXI-Lite memory from %0s", hexfile);
            $readmemh(hexfile, mem);
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            lat_count <= 32'd0;
            rd_addr_q <= 32'd0;
            wr_addr_q <= 32'd0;
            wr_data_q <= 32'd0;
            wr_strb_q <= 4'd0;
            s_axi_rdata <= 32'd0;
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
        end else begin
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            case (state)
                S_IDLE: begin
                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_addr_q <= s_axi_araddr;
                        lat_count <= LATENCY;
                        state <= S_READ;
                    end else if (s_axi_awvalid && s_axi_wvalid && s_axi_awready && s_axi_wready) begin
                        wr_addr_q <= s_axi_awaddr;
                        wr_data_q <= s_axi_wdata;
                        wr_strb_q <= s_axi_wstrb;
                        lat_count <= LATENCY;
                        state <= S_WRITE;
                    end
                end

                S_READ: begin
                    if (lat_count != 32'd0) begin
                        lat_count <= lat_count - 32'd1;
                    end else if (!s_axi_rvalid) begin
                        s_axi_rdata <= mem[rd_addr_q[31:2]];
                        s_axi_rresp <= 2'b00;
                        s_axi_rvalid <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                S_WRITE: begin
                    if (lat_count != 32'd0) begin
                        lat_count <= lat_count - 32'd1;
                    end else if (!s_axi_bvalid) begin
                        mem[wr_addr_q[31:2]] <= apply_wstrb(mem[wr_addr_q[31:2]], wr_data_q, wr_strb_q);
                        s_axi_bresp <= 2'b00;
                        s_axi_bvalid <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
