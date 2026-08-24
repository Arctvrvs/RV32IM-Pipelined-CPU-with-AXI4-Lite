// -----------------------------------------------------------------------------
// RV32 register file
// - 32 architectural registers, x0 hardwired to zero
// - Asynchronous reads, synchronous write
// -----------------------------------------------------------------------------
module regfile (
    input  wire        clk,
    input  wire        rst,

    input  wire        we,
    input  wire [4:0]  rs1,
    input  wire [4:0]  rs2,
    input  wire [4:0]  rd,
    input  wire [31:0] rd_wdata,

    output reg  [31:0] rs1_rdata,
    output reg  [31:0] rs2_rdata
);

    reg [31:0] regs [31:0];
    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'h0000_0000;
            end
        end else if (we && (rd != 5'd0)) begin
            regs[rd] <= rd_wdata;
        end
    end

    always @(*) begin
        rs1_rdata = (rs1 == 5'd0) ? 32'h0000_0000 : regs[rs1];
        rs2_rdata = (rs2 == 5'd0) ? 32'h0000_0000 : regs[rs2];
    end

endmodule
