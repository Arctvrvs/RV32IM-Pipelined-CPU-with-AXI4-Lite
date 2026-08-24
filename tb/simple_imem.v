// -----------------------------------------------------------------------------
// Simple combinational instruction memory for simulation.
// Optional +HEX=<file> plusarg loads initial instructions using $readmemh.
// Supports @<word_address> markers in the hex file.
// -----------------------------------------------------------------------------
module simple_imem #(
    parameter MEM_WORDS = 256
) (
    input  wire [31:0] addr,
    output wire [31:0] rdata
);

    reg [31:0] mem [0:MEM_WORDS-1];
    reg [1023:0] hexfile;
    integer i;

    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            mem[i] = 32'h00000013; // ADDI x0, x0, 0 = NOP
        end

        if (!$value$plusargs("HEX=%s", hexfile)) begin
            hexfile = "programs/example.hex";
        end

        $display("Loading instruction memory from %0s", hexfile);
        $readmemh(hexfile, mem);
    end

    assign rdata = mem[addr[31:2]];

endmodule
