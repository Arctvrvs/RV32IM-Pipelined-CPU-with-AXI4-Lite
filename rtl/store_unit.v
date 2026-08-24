// -----------------------------------------------------------------------------
// RV32I store byte-lane mask/data generation unit
// Assumption: data memory is little-endian and supports byte write enables.
// Unaligned halfword/word stores are not trapped in this simple core; invalid
// alignments produce no byte write enables.
// -----------------------------------------------------------------------------
module store_unit (
    input  wire [31:0] rs2_value,
    input  wire [1:0]  addr_lsb,
    input  wire [2:0]  funct3,
    input  wire        store_en,
    output reg  [31:0] store_data,
    output reg  [3:0]  store_we
);

    always @(*) begin
        store_data = 32'h0000_0000;
        store_we   = 4'b0000;

        if (store_en) begin
            case (funct3)
                3'b000: begin // SB
                    case (addr_lsb)
                        2'b00: begin store_we = 4'b0001; store_data = {24'h000000, rs2_value[7:0]}; end
                        2'b01: begin store_we = 4'b0010; store_data = {16'h0000, rs2_value[7:0], 8'h00}; end
                        2'b10: begin store_we = 4'b0100; store_data = {8'h00, rs2_value[7:0], 16'h0000}; end
                        2'b11: begin store_we = 4'b1000; store_data = {rs2_value[7:0], 24'h000000}; end
                        default: begin store_we = 4'b0000; store_data = 32'h0000_0000; end
                    endcase
                end

                3'b001: begin // SH
                    case (addr_lsb)
                        2'b00: begin store_we = 4'b0011; store_data = {16'h0000, rs2_value[15:0]}; end
                        2'b10: begin store_we = 4'b1100; store_data = {rs2_value[15:0], 16'h0000}; end
                        default: begin store_we = 4'b0000; store_data = 32'h0000_0000; end
                    endcase
                end

                3'b010: begin // SW
                    if (addr_lsb == 2'b00) begin
                        store_we   = 4'b1111;
                        store_data = rs2_value;
                    end else begin
                        store_we   = 4'b0000;
                        store_data = 32'h0000_0000;
                    end
                end

                default: begin
                    store_we   = 4'b0000;
                    store_data = 32'h0000_0000;
                end
            endcase
        end
    end

endmodule
