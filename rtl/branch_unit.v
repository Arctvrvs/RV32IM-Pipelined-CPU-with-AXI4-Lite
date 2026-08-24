// -----------------------------------------------------------------------------
// RV32I branch comparator
// -----------------------------------------------------------------------------
module branch_unit (
    input  wire [2:0]  funct3,
    input  wire [31:0] rs1_value,
    input  wire [31:0] rs2_value,
    output reg         branch_taken
);

    always @(*) begin
        case (funct3)
            3'b000: branch_taken = (rs1_value == rs2_value);                         // BEQ
            3'b001: branch_taken = (rs1_value != rs2_value);                         // BNE
            3'b100: branch_taken = ($signed(rs1_value) < $signed(rs2_value));         // BLT
            3'b101: branch_taken = ($signed(rs1_value) >= $signed(rs2_value));        // BGE
            3'b110: branch_taken = (rs1_value < rs2_value);                          // BLTU
            3'b111: branch_taken = (rs1_value >= rs2_value);                         // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

endmodule
