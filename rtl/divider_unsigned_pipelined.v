// -----------------------------------------------------------------------------
// 8-stage unsigned pipelined divider
// -----------------------------------------------------------------------------
// Accepts a new unsigned divide operation every cycle.  Each stage performs four
// restoring-division iterations, so a result emerges after the 8-stage pipe is
// full.  This module intentionally avoids Verilog '/' and '%' so it is suitable
// for synthesis-oriented RTL exercises.
// -----------------------------------------------------------------------------
module divider_unsigned_pipelined (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire [31:0] i_dividend,
    input  wire [31:0] i_divisor,
    output reg  [31:0] o_remainder,
    output reg  [31:0] o_quotient
);
    localparam integer STAGES = 8;
    localparam integer ITERS_PER_STAGE = 4;

    // State vector layout:
    //   [127:96] dividend shift register
    //   [95:64]  divisor
    //   [63:32]  partial remainder
    //   [31:0]   quotient bits accumulated so far
    reg [127:0] st_q [0:STAGES-1];
    reg [127:0] st_d [0:STAGES-1];

    function [127:0] divu_1iter;
        input [127:0] s;
        reg [127:0] t;
        reg [32:0] trial;
        reg [32:0] sub;
        reg        take;
        begin
            trial = {s[63:32], s[127]};
            take  = (trial >= {1'b0, s[95:64]});
            sub   = trial - {1'b0, s[95:64]};

            t[127:96] = {s[126:96], 1'b0};
            t[95:64]  = s[95:64];
            t[63:32]  = take ? sub[31:0] : trial[31:0];
            t[31:0]   = {s[30:0], take};
            divu_1iter = t;
        end
    endfunction

    function [127:0] divu_4iters;
        input [127:0] s;
        reg [127:0] t;
        integer j;
        begin
            t = s;
            for (j = 0; j < ITERS_PER_STAGE; j = j + 1) begin
                t = divu_1iter(t);
            end
            divu_4iters = t;
        end
    endfunction

    integer k_comb;
    integer k_seq;
    always @(*) begin
        st_d[0] = divu_4iters({i_dividend, i_divisor, 32'd0, 32'd0});
        for (k_comb = 1; k_comb < STAGES; k_comb = k_comb + 1) begin
            st_d[k_comb] = divu_4iters(st_q[k_comb-1]);
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            for (k_seq = 0; k_seq < STAGES; k_seq = k_seq + 1) begin
                st_q[k_seq] <= 128'd0;
            end
        end else if (!stall) begin
            for (k_seq = 0; k_seq < STAGES; k_seq = k_seq + 1) begin
                st_q[k_seq] <= st_d[k_seq];
            end
        end
    end

    // Output the registered last stage. This gives an 8-cycle latency that
    // aligns with a matching valid/metadata shift register in the CPU.
    always @(*) begin
        o_quotient  = st_q[STAGES-1][31:0];
        o_remainder = st_q[STAGES-1][63:32];
    end
endmodule
