// -----------------------------------------------------------------------------
// Simple little-endian data memory with byte write enables for simulation.
// Optional +DMEM_HEX=<file> plusarg loads initial data using $readmemh.
// Supports @<word_address> markers in the hex file.
// -----------------------------------------------------------------------------
module simple_dmem #(
    parameter MEM_WORDS = 256
) (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  we,
    output wire [31:0] rdata
);

    reg [31:0] mem [0:MEM_WORDS-1];
    reg [1023:0] hexfile;
    integer i;

    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            mem[i] = 32'h0000_0000;
        end

        if ($value$plusargs("DMEM_HEX=%s", hexfile)) begin
            $display("Loading data memory from %0s", hexfile);
            $readmemh(hexfile, mem);
        end
    end

    assign rdata = mem[addr[31:2]];

    always @(posedge clk) begin
        if (we[0]) mem[addr[31:2]][7:0]   <= wdata[7:0];
        if (we[1]) mem[addr[31:2]][15:8]  <= wdata[15:8];
        if (we[2]) mem[addr[31:2]][23:16] <= wdata[23:16];
        if (we[3]) mem[addr[31:2]][31:24] <= wdata[31:24];
    end

endmodule
