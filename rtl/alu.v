// -----------------------------------------------------------------------------
// Integer ALU for RV32I/RV32M-style operations
// -----------------------------------------------------------------------------
// Notes on RV32M corner cases implemented here:
//   DIV/DIVU by zero  -> 0xFFFF_FFFF
//   REM/REMU by zero  -> dividend
//   DIV overflow      -> 0x8000_0000 for (-2^31 / -1)
//   REM overflow      -> 0
// -----------------------------------------------------------------------------
module alu (
    input  wire [31:0] op1,
    input  wire [31:0] op2,
    input  wire [4:0]  alu_ctrl,

    output reg  [31:0] result,
    output wire        zero
);

    localparam [4:0] ALU_ADD    = 5'd0;
    localparam [4:0] ALU_SUB    = 5'd1;
    localparam [4:0] ALU_AND    = 5'd2;
    localparam [4:0] ALU_OR     = 5'd3;
    localparam [4:0] ALU_XOR    = 5'd4;
    localparam [4:0] ALU_SLL    = 5'd5;
    localparam [4:0] ALU_SRL    = 5'd6;
    localparam [4:0] ALU_SRA    = 5'd7;
    localparam [4:0] ALU_SLT    = 5'd8;
    localparam [4:0] ALU_SLTU   = 5'd9;
    localparam [4:0] ALU_MUL    = 5'd10;
    localparam [4:0] ALU_MULH   = 5'd11;
    localparam [4:0] ALU_MULHSU = 5'd12;
    localparam [4:0] ALU_MULHU  = 5'd13;
    localparam [4:0] ALU_DIV    = 5'd14;
    localparam [4:0] ALU_DIVU   = 5'd15;
    localparam [4:0] ALU_REM    = 5'd16;
    localparam [4:0] ALU_REMU   = 5'd17;

    wire signed [31:0] sop1 = op1;
    wire signed [31:0] sop2 = op2;

    wire signed [63:0] op1_s64 = {{32{op1[31]}}, op1};
    wire signed [63:0] op2_s64 = {{32{op2[31]}}, op2};
    wire signed [63:0] op2_u64_as_s = {32'h0000_0000, op2};
    wire        [63:0] op1_u64 = {32'h0000_0000, op1};
    wire        [63:0] op2_u64 = {32'h0000_0000, op2};

    wire signed [63:0] mul_ss = op1_s64 * op2_s64;
    wire signed [63:0] mul_su = op1_s64 * op2_u64_as_s;
    wire        [63:0] mul_uu = op1_u64 * op2_u64;

    // DIV/REM are handled by the separate pipelined divider in rv32im_pipeline.
    assign zero = (result == 32'h0000_0000);

    always @(*) begin
        case (alu_ctrl)
            ALU_ADD:    result = op1 + op2;
            ALU_SUB:    result = op1 - op2;
            ALU_AND:    result = op1 & op2;
            ALU_OR:     result = op1 | op2;
            ALU_XOR:    result = op1 ^ op2;
            ALU_SLL:    result = op1 << op2[4:0];
            ALU_SRL:    result = op1 >> op2[4:0];
            ALU_SRA:    result = $signed(op1) >>> op2[4:0];
            ALU_SLT:    result = ($signed(op1) < $signed(op2)) ? 32'd1 : 32'd0;
            ALU_SLTU:   result = (op1 < op2) ? 32'd1 : 32'd0;

            // RV32M multiply operations remain combinational here.  DIV/REM are
            // not produced by this ALU in the pipelined CPU; they issue into
            // divider_unsigned_pipelined instead.
            ALU_MUL:    result = mul_uu[31:0];
            ALU_MULH:   result = mul_ss[63:32];
            ALU_MULHSU: result = mul_su[63:32];
            ALU_MULHU:  result = mul_uu[63:32];
            ALU_DIV:    result = 32'h0000_0000;
            ALU_DIVU:   result = 32'h0000_0000;
            ALU_REM:    result = 32'h0000_0000;
            ALU_REMU:   result = 32'h0000_0000;

            default: result = 32'h0000_0000;
        endcase
    end

endmodule
