`timescale 1ns/1ps

module tb_pipeline_dhrystone;

    localparam integer MEM_WORDS = 65536;      // 256 KiB per memory
    localparam integer TIMEOUT_CYCLES = 2000000; // pipelined CPU needs more cycles than single-cycle
    localparam [31:0] EXPECTED_X5 = 32'h003f_ffff; // (1 << 22) - 1

    reg clk;
    reg rst;

    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire        imem_valid;
    wire        imem_ready;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_we;
    wire [31:0] dmem_rdata;
    wire        dmem_ready;

    wire        halt;
    wire        illegal_insn;
    wire [127:0] dbg_insn_name;

    integer cycle;
    integer errors;

    wire        dmem_valid;
    wire        trace_writeback_valid;
    wire [31:0] trace_writeback_pc;
    wire [31:0] trace_writeback_insn;
    wire [31:0] trace_writeback_cycle_status;
    wire [4:0]  trace_writeback_rd;
    wire [31:0] trace_writeback_wdata;
    wire        trace_writeback_reg_write;

    rv32im_pipeline dut (
        .clk           (clk),
        .rst           (rst),
        .imem_valid    (imem_valid),
        .imem_addr     (imem_addr),
        .imem_rdata    (imem_rdata),
        .imem_ready    (imem_ready),
        .dmem_addr     (dmem_addr),
        .dmem_wdata    (dmem_wdata),
        .dmem_we       (dmem_we),
        .dmem_rdata    (dmem_rdata),
        .dmem_ready    (dmem_ready),
        .halt          (halt),
        .illegal_insn  (illegal_insn),
        .dbg_insn_name (dbg_insn_name),
        .dmem_valid                  (dmem_valid),
        .trace_writeback_valid       (trace_writeback_valid),
        .trace_writeback_pc          (trace_writeback_pc),
        .trace_writeback_insn        (trace_writeback_insn),
        .trace_writeback_cycle_status(trace_writeback_cycle_status),
        .trace_writeback_rd          (trace_writeback_rd),
        .trace_writeback_wdata       (trace_writeback_wdata),
        .trace_writeback_reg_write   (trace_writeback_reg_write)
    );

    simple_imem #(.MEM_WORDS(MEM_WORDS)) imem (
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    assign imem_ready = 1'b1;

    simple_dmem #(.MEM_WORDS(MEM_WORDS)) dmem (
        .clk   (clk),
        .addr  (dmem_addr),
        .wdata (dmem_wdata),
        .we    (dmem_we),
        .rdata (dmem_rdata)
    );

    assign dmem_ready = 1'b1;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("pipeline_dhrystone.vcd");
        $dumpvars(0, tb_pipeline_dhrystone);

        errors = 0;
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        $display("Running Dhrystone benchmark...");
        for (cycle = 0; cycle < TIMEOUT_CYCLES; cycle = cycle + 1) begin
            @(posedge clk);
            #1;

            if (illegal_insn) begin
                $display("FAIL: illegal instruction at cycle %0d PC=0x%08h insn=0x%08h name=%0s", cycle, imem_addr, imem_rdata, dbg_insn_name);
                errors = errors + 1;
                cycle = TIMEOUT_CYCLES;
            end else if (halt) begin
                $display("INFO: ECALL/halt at cycle %0d PC=0x%08h insn=0x%08h name=%0s", cycle, imem_addr, imem_rdata, dbg_insn_name);
                $display("INFO: Dhrystone success mask x5 = 0x%08h", dut.rf.regs[5]);
                if (dut.rf.regs[5] === EXPECTED_X5) begin
                    $display("PASS: Dhrystone passed after %0d cycles.", cycle);
                end else begin
                    $display("FAIL: Dhrystone expected x5=0x%08h, got 0x%08h", EXPECTED_X5, dut.rf.regs[5]);
                    errors = errors + 1;
                end
                cycle = TIMEOUT_CYCLES;
            end else if ((cycle > 0) && ((cycle % 10000) == 0)) begin
                $display("INFO: ran %0d cycles... PC=0x%08h insn=0x%08h name=%0s", cycle, imem_addr, imem_rdata, dbg_insn_name);
            end
        end

        if (!halt && errors == 0) begin
            $display("FAIL: Dhrystone timed out after %0d cycles.", TIMEOUT_CYCLES);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: RV32IM pipelined Dhrystone test passed.");
        end else begin
            $display("FAIL: RV32IM pipelined Dhrystone test had %0d error(s).", errors);
        end

        if (errors != 0)
            $fatal(1);
        $finish;
    end

endmodule
