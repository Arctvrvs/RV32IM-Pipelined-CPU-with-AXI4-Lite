// -----------------------------------------------------------------------------
// ALU operation decoder for RV32I + optional RV32M integer multiply/divide ops
// -----------------------------------------------------------------------------
module alu_control (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,

    output reg  [4:0] alu_ctrl
);

    localparam [6:0] OPCODE_OP       = 7'b0110011;
    localparam [6:0] OPCODE_OP_IMM   = 7'b0010011;
    localparam [6:0] OPCODE_LOAD     = 7'b0000011;
    localparam [6:0] OPCODE_STORE    = 7'b0100011;
    localparam [6:0] OPCODE_BRANCH   = 7'b1100011;
    localparam [6:0] OPCODE_JALR     = 7'b1100111;
    localparam [6:0] OPCODE_LUI      = 7'b0110111;
    localparam [6:0] OPCODE_AUIPC    = 7'b0010111;

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

    always @(*) begin
        alu_ctrl = ALU_ADD;

        case (opcode)
            OPCODE_OP: begin
                if (funct7 == 7'b0000001) begin
                    case (funct3)
                        3'b000: alu_ctrl = ALU_MUL;
                        3'b001: alu_ctrl = ALU_MULH;
                        3'b010: alu_ctrl = ALU_MULHSU;
                        3'b011: alu_ctrl = ALU_MULHU;
                        3'b100: alu_ctrl = ALU_DIV;
                        3'b101: alu_ctrl = ALU_DIVU;
                        3'b110: alu_ctrl = ALU_REM;
                        3'b111: alu_ctrl = ALU_REMU;
                        default: alu_ctrl = ALU_ADD;
                    endcase
                end else begin
                    case (funct3)
                        3'b000: alu_ctrl = (funct7 == 7'b0100000) ? ALU_SUB : ALU_ADD; // SUB/ADD
                        3'b001: alu_ctrl = ALU_SLL;
                        3'b010: alu_ctrl = ALU_SLT;
                        3'b011: alu_ctrl = ALU_SLTU;
                        3'b100: alu_ctrl = ALU_XOR;
                        3'b101: alu_ctrl = (funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL; // SRA/SRL
                        3'b110: alu_ctrl = ALU_OR;
                        3'b111: alu_ctrl = ALU_AND;
                        default: alu_ctrl = ALU_ADD;
                    endcase
                end
            end

            OPCODE_OP_IMM: begin
                case (funct3)
                    3'b000: alu_ctrl = ALU_ADD;  // ADDI
                    3'b001: alu_ctrl = ALU_SLL;  // SLLI
                    3'b010: alu_ctrl = ALU_SLT;  // SLTI
                    3'b011: alu_ctrl = ALU_SLTU; // SLTIU
                    3'b100: alu_ctrl = ALU_XOR;  // XORI
                    3'b101: alu_ctrl = (funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL; // SRAI/SRLI
                    3'b110: alu_ctrl = ALU_OR;   // ORI
                    3'b111: alu_ctrl = ALU_AND;  // ANDI
                    default: alu_ctrl = ALU_ADD;
                endcase
            end

            OPCODE_LOAD,
            OPCODE_STORE,
            OPCODE_JALR,
            OPCODE_LUI,
            OPCODE_AUIPC: begin
                alu_ctrl = ALU_ADD;
            end

            OPCODE_BRANCH: begin
                alu_ctrl = ALU_SUB;
            end

            default: begin
                alu_ctrl = ALU_ADD;
            end
        endcase
    end

endmodule
