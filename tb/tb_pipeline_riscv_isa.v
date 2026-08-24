`timescale 1ns/1ps

module tb_pipeline_riscv_isa;

    localparam integer MEM_WORDS = 65536; // 256 KiB per memory
    localparam [31:0] EXPECTED_A0_PASS = 32'h0000_0000;

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
    integer timeout_cycles;
    reg [1023:0] testname;

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
        if (!$value$plusargs("TESTNAME=%s", testname)) begin
            testname = "unknown";
        end
        if (!$value$plusargs("TIMEOUT=%d", timeout_cycles)) begin
            timeout_cycles = 50000;
        end

        $dumpfile("pipeline_riscv_isa.vcd");
        $dumpvars(0, tb_pipeline_riscv_isa);

        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        $display("Running RISC-V ISA test: %0s", testname);
        for (cycle = 0; cycle < timeout_cycles; cycle = cycle + 1) begin
            @(posedge clk);
            #1;

            if (illegal_insn) begin
                $display("FAIL: %0s illegal instruction at cycle %0d PC=0x%08h insn=0x%08h name=%0s", testname, cycle, imem_addr, imem_rdata, dbg_insn_name);
                $display("REGS: x3/gp=0x%08h x10/a0=0x%08h x17/a7=0x%08h", dut.rf.regs[3], dut.rf.regs[10], dut.rf.regs[17]);
                $fatal(1);
            end

            if (halt) begin
                $display("INFO: %0s ECALL/halt at cycle %0d PC=0x%08h insn=0x%08h name=%0s", testname, cycle, imem_addr, imem_rdata, dbg_insn_name);
                $display("INFO: x3/gp=0x%08h x10/a0=0x%08h x17/a7=0x%08h", dut.rf.regs[3], dut.rf.regs[10], dut.rf.regs[17]);
                if (dut.rf.regs[10] === EXPECTED_A0_PASS) begin
                    $display("PASS: %0s passed.", testname);
                    $finish;
                end else begin
                    $display("FAIL: %0s failed with a0=0x%08h", testname, dut.rf.regs[10]);
                    $fatal(1);
                end
            end
        end

        $display("FAIL: %0s timed out after %0d cycles. PC=0x%08h insn=0x%08h name=%0s", testname, timeout_cycles, imem_addr, imem_rdata, dbg_insn_name);
        $display("REGS: x3/gp=0x%08h x10/a0=0x%08h x17/a7=0x%08h", dut.rf.regs[3], dut.rf.regs[10], dut.rf.regs[17]);
        $fatal(1);
    end

endmodule
