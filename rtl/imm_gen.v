// -----------------------------------------------------------------------------
// RV32 immediate generator
// -----------------------------------------------------------------------------
module imm_gen (
    input  wire [31:0] insn,
    input  wire [2:0]  imm_sel,
    output reg  [31:0] imm
);

    localparam [2:0] IMM_I = 3'b000;
    localparam [2:0] IMM_S = 3'b001;
    localparam [2:0] IMM_B = 3'b010;
    localparam [2:0] IMM_U = 3'b011;
    localparam [2:0] IMM_J = 3'b100;

    always @(*) begin
        case (imm_sel)
            IMM_I: imm = {{20{insn[31]}}, insn[31:20]};
            IMM_S: imm = {{20{insn[31]}}, insn[31:25], insn[11:7]};
            IMM_B: imm = {{19{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
            IMM_U: imm = {insn[31:12], 12'b0};
            IMM_J: imm = {{11{insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};
            default: imm = 32'h0000_0000;
        endcase
    end

endmodule
