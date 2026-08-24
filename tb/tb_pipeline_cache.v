`timescale 1ns/1ps

module tb_pipeline_cache;

    reg clk;
    reg rst;

    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire        imem_valid;
    wire        imem_ready;

    wire        dmem_valid;
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
        .dmem_valid    (dmem_valid),
        .dmem_addr     (dmem_addr),
        .dmem_wdata    (dmem_wdata),
        .dmem_we       (dmem_we),
        .dmem_rdata    (dmem_rdata),
        .dmem_ready    (dmem_ready),
        .halt          (halt),
        .illegal_insn  (illegal_insn),
        .dbg_insn_name (dbg_insn_name),
        .trace_writeback_valid       (trace_writeback_valid),
        .trace_writeback_pc          (trace_writeback_pc),
        .trace_writeback_insn        (trace_writeback_insn),
        .trace_writeback_cycle_status(trace_writeback_cycle_status),
        .trace_writeback_rd          (trace_writeback_rd),
        .trace_writeback_wdata       (trace_writeback_wdata),
        .trace_writeback_reg_write   (trace_writeback_reg_write)
    );

    simple_imem #(.MEM_WORDS(256)) imem (
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    assign imem_ready = 1'b1;

    // Small four-line cache so addresses 0 and 16 conflict in this test.
    direct_mapped_dcache #(
        .MEM_WORDS(256),
        .LINES(4),
        .INDEX_BITS(2),
        .MISS_PENALTY(3)
    ) dcache (
        .clk          (clk),
        .rst          (rst),
        .cpu_valid    (dmem_valid),
        .cpu_addr     (dmem_addr),
        .cpu_wdata    (dmem_wdata),
        .cpu_we       (dmem_we),
        .cpu_rdata    (dmem_rdata),
        .cpu_ready    (dmem_ready),
        .access_count (),
        .hit_count    (),
        .miss_count   ()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task check_reg;
        input [4:0] idx;
        input [31:0] expected;
        begin
            if (dut.rf.regs[idx] !== expected) begin
                $display("FAIL: x%0d expected 0x%08h, got 0x%08h", idx, expected, dut.rf.regs[idx]);
                errors = errors + 1;
            end else begin
                $display("PASS: x%0d = 0x%08h", idx, expected);
            end
        end
    endtask

    task check_cache_stat;
        input [127:0] name;
        input [31:0] got;
        input [31:0] expected;
        begin
            if (got !== expected) begin
                $display("FAIL: %0s expected %0d, got %0d", name, expected, got);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %0d", name, got);
            end
        end
    endtask

    initial begin
        $dumpfile("pipeline_cache.vcd");
        $dumpvars(0, tb_pipeline_cache);

        errors = 0;
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 500; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            if (illegal_insn) begin
                $display("FAIL: illegal instruction at cycle %0d PC=0x%08h insn=0x%08h name=%0s", cycle, imem_addr, imem_rdata, dbg_insn_name);
                errors = errors + 1;
                cycle = 500;
            end else if (halt) begin
                cycle = 500;
            end
        end

        if (!halt && errors == 0) begin
            $display("FAIL: cache test timed out.");
            errors = errors + 1;
        end

        $display("\n--- RV32IM pipelined D-cache checks ---");
        check_reg(5'd2, 32'd42);
        check_reg(5'd3, 32'd42);
        check_reg(5'd4, 32'd16);
        check_reg(5'd5, 32'd99);
        check_reg(5'd6, 32'd99);
        check_reg(5'd7, 32'd42);
        check_reg(5'd8, 32'd141);
        check_reg(5'd9, 32'd42);

        if (dcache.debug_word(32'd0) !== 32'd42) begin
            $display("FAIL: debug_word[0] expected 42, got 0x%08h", dcache.debug_word(32'd0));
            errors = errors + 1;
        end else begin
            $display("PASS: debug_word[0] = 42");
        end

        if (dcache.debug_word(32'd4) !== 32'd99) begin
            $display("FAIL: debug_word[4] expected 99, got 0x%08h", dcache.debug_word(32'd4));
            errors = errors + 1;
        end else begin
            $display("PASS: debug_word[4] = 99");
        end

        check_cache_stat("cache accesses", dcache.access_count, 32'd5);
        check_cache_stat("cache hits",     dcache.hit_count,    32'd2);
        check_cache_stat("cache misses",   dcache.miss_count,   32'd3);

        if (errors == 0) begin
            $display("\nPASS: RV32IM pipelined D-cache test passed.");
        end else begin
            $display("\nFAIL: RV32IM pipelined D-cache test had %0d error(s).", errors);
        end

        if (errors != 0)
            $fatal(1);
        $finish;
    end

endmodule
