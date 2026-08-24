`timescale 1ns/1ps

module tb_pipeline_extended;

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

    integer errors;
    integer cycle;

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

    simple_imem imem (
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    assign imem_ready = 1'b1;

    simple_dmem dmem (
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

    task check_reg;
        input [4:0]  idx;
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

    initial begin
        $dumpfile("pipeline_extended.vcd");
        $dumpvars(0, tb_pipeline_extended);

        errors = 0;
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 500; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            if (illegal_insn) begin
                $display("FAIL: illegal instruction flag asserted at PC=0x%08h insn=0x%08h name=%0s", imem_addr, imem_rdata, dbg_insn_name);
                errors = errors + 1;
            end
            if (halt) begin
                $display("INFO: halt asserted at cycle %0d PC=0x%08h insn=0x%08h name=%0s", cycle, imem_addr, imem_rdata, dbg_insn_name);
                cycle = 500;
            end
        end

        if (!halt) begin
            $display("FAIL: halt was never asserted by ECALL");
            errors = errors + 1;
        end

        $display("\n--- RV32IM extended architectural checks ---");
        check_reg(5'd1,  32'h00000007);
        check_reg(5'd2,  32'h00000003);
        check_reg(5'd3,  32'h00000015); // MUL 7*3
        check_reg(5'd4,  32'h00000002); // DIV 7/3
        check_reg(5'd5,  32'h00000001); // REM 7%3
        check_reg(5'd6,  32'h00000002); // DIVU
        check_reg(5'd7,  32'h00000001); // REMU
        check_reg(5'd8,  32'hfffffff9); // -7
        check_reg(5'd9,  32'hffffffeb); // MUL -7*3 low
        check_reg(5'd10, 32'hfffffffe); // DIV -7/3 = -2
        check_reg(5'd11, 32'hffffffff); // REM -7%3 = -1
        check_reg(5'd12, 32'hffffffff); // -1
        check_reg(5'd13, 32'h00000002); // 2
        check_reg(5'd14, 32'hffffffff); // MULH signed high of -2
        check_reg(5'd15, 32'hffffffff); // MULHSU high of -2
        check_reg(5'd16, 32'h00000001); // MULHU high of 0xffffffff*2
        check_reg(5'd17, 32'hffffffff); // DIV by zero
        check_reg(5'd18, 32'hffffffff); // DIVU by zero
        check_reg(5'd19, 32'h00000007); // REM by zero -> dividend
        check_reg(5'd20, 32'h00000007); // REMU by zero -> dividend
        check_reg(5'd21, 32'h80000000); // LUI
        check_reg(5'd22, 32'h80000000); // signed DIV overflow
        check_reg(5'd23, 32'h00000000); // signed REM overflow
        check_reg(5'd24, 32'h0000007b); // FENCE did not stop execution

        if (errors == 0) begin
            $display("\nPASS: RV32IM pipelined extended CPU test passed all checks.");
        end else begin
            $display("\nFAIL: RV32IM pipelined extended CPU test had %0d error(s).", errors);
        end

        if (errors != 0)
            $fatal(1);
        $finish;
    end

endmodule
