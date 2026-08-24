`timescale 1ns/1ps

module tb_pipeline_basic;

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

    wire        dmem_valid;
    wire        halt;
    wire        illegal_insn;
    wire [127:0] dbg_insn_name;
    wire        trace_writeback_valid;
    wire [31:0] trace_writeback_pc;
    wire [31:0] trace_writeback_insn;
    wire [31:0] trace_writeback_cycle_status;
    wire [4:0]  trace_writeback_rd;
    wire [31:0] trace_writeback_wdata;
    wire        trace_writeback_reg_write;

    rv32im_pipeline dut (
        .clk        (clk),
        .rst        (rst),
        .imem_valid (imem_valid),
        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),
        .imem_ready (imem_ready),
        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_we    (dmem_we),
        .dmem_rdata (dmem_rdata),
        .dmem_ready (dmem_ready),
        .dmem_valid                  (dmem_valid),
        .halt                        (halt),
        .illegal_insn                (illegal_insn),
        .dbg_insn_name               (dbg_insn_name),
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

    initial begin
        $dumpfile("pipeline_basic.vcd");
        $dumpvars(0, tb_pipeline_basic);

        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        repeat (200) @(posedge clk);

        $display("x1  = %0d", dut.rf.regs[1]);
        $display("x2  = %0d", dut.rf.regs[2]);
        $display("x3  = %0d", dut.rf.regs[3]);
        $display("x4  = %0d", dut.rf.regs[4]);
        $display("x5  = %0d", dut.rf.regs[5]);
        $display("x6  = %0d", dut.rf.regs[6]);
        $display("x7  = 0x%08h", dut.rf.regs[7]);
        $display("x8  = %0d", dut.rf.regs[8]);
        $display("mem[0] = %0d", dmem.mem[0]);

        if (dut.rf.regs[1] !== 32'd5) begin
            $display("FAIL: x1 should be 5");
            $fatal(1);
        end
        if (dut.rf.regs[2] !== 32'd7) begin
            $display("FAIL: x2 should be 7");
            $fatal(1);
        end
        if (dut.rf.regs[3] !== 32'd12) begin
            $display("FAIL: x3 should be 12");
            $fatal(1);
        end
        if (dut.rf.regs[4] !== 32'd12) begin
            $display("FAIL: x4 should be loaded value 12");
            $fatal(1);
        end
        if (dut.rf.regs[5] !== 32'd1) begin
            $display("FAIL: x5 should be 1 from SLT");
            $fatal(1);
        end
        if (dut.rf.regs[6] !== 32'd222) begin
            $display("FAIL: branch should skip x6=111 and set x6=222");
            $fatal(1);
        end
        if (dut.rf.regs[7] !== 32'h00000028) begin
            $display("FAIL: JAL link x7 should be PC+4 = 0x28");
            $fatal(1);
        end
        if (dut.rf.regs[8] !== 32'd42) begin
            $display("FAIL: JAL should skip x8=123 and set x8=42");
            $fatal(1);
        end
        if (dmem.mem[0] !== 32'd12) begin
            $display("FAIL: data memory word 0 should be 12");
            $fatal(1);
        end

        $display("PASS: RV32IM pipelined CPU basic test passed.");
        $finish;
    end

endmodule
