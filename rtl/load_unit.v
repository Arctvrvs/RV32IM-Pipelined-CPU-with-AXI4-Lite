// -----------------------------------------------------------------------------
// RV32I load extraction/sign-extension unit
// Assumption: dmem_rdata is the 32-bit little-endian word containing addr[31:2].
// Unaligned halfword/word loads are not trapped in this simple core.
// -----------------------------------------------------------------------------
module load_unit (
    input  wire [31:0] dmem_rdata,
    input  wire [1:0]  addr_lsb,
    input  wire [2:0]  funct3,
    output reg  [31:0] load_data
);

    reg [7:0]  selected_byte;
    reg [15:0] selected_half;

    always @(*) begin
        case (addr_lsb)
            2'b00: selected_byte = dmem_rdata[7:0];
            2'b01: selected_byte = dmem_rdata[15:8];
            2'b10: selected_byte = dmem_rdata[23:16];
            2'b11: selected_byte = dmem_rdata[31:24];
            default: selected_byte = 8'h00;
        endcase

        case (addr_lsb[1])
            1'b0: selected_half = dmem_rdata[15:0];
            1'b1: selected_half = dmem_rdata[31:16];
            default: selected_half = 16'h0000;
        endcase

        case (funct3)
            3'b000: load_data = {{24{selected_byte[7]}}, selected_byte}; // LB
            3'b001: load_data = {{16{selected_half[15]}}, selected_half}; // LH
            3'b010: load_data = dmem_rdata;                              // LW
            3'b100: load_data = {24'h000000, selected_byte};             // LBU
            3'b101: load_data = {16'h0000, selected_half};               // LHU
            default: load_data = 32'h0000_0000;
        endcase
    end

endmodule
