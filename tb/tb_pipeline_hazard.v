`timescale 1ns/1ps

module tb_pipeline_hazard;
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

    wire        trace_writeback_valid;
    wire [31:0] trace_writeback_pc;
    wire [31:0] trace_writeback_insn;
    wire [31:0] trace_writeback_cycle_status;
    wire [4:0]  trace_writeback_rd;
    wire [31:0] trace_writeback_wdata;
    wire        trace_writeback_reg_write;

    wire        dmem_valid;

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
        .halt       (halt),
        .illegal_insn(illegal_insn),
        .dbg_insn_name(dbg_insn_name),
        .trace_writeback_valid(trace_writeback_valid),
        .trace_writeback_pc(trace_writeback_pc),
        .trace_writeback_insn(trace_writeback_insn),
        .trace_writeback_cycle_status(trace_writeback_cycle_status),
        .trace_writeback_rd(trace_writeback_rd),
        .trace_writeback_wdata(trace_writeback_wdata),
        .trace_writeback_reg_write(trace_writeback_reg_write),
        .dmem_valid                  (dmem_valid)
    );

    simple_imem imem (.addr(imem_addr), .rdata(imem_rdata));

    assign imem_ready = 1'b1;
    simple_dmem dmem (.clk(clk), .addr(dmem_addr), .wdata(dmem_wdata), .we(dmem_we), .rdata(dmem_rdata));

    assign dmem_ready = 1'b1;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer cycle;
    integer errors;

    task check_reg;
        input [4:0] idx;
        input [31:0] exp;
        begin
            if (dut.rf.regs[idx] !== exp) begin
                $display("FAIL: x%0d expected 0x%08h, got 0x%08h", idx, exp, dut.rf.regs[idx]);
                errors = errors + 1;
            end else begin
                $display("PASS: x%0d = 0x%08h", idx, exp);
            end
        end
    endtask

    task check_mem;
        input integer idx;
        input [31:0] exp;
        begin
            if (dmem.mem[idx] !== exp) begin
                $display("FAIL: mem[%0d] expected 0x%08h, got 0x%08h", idx, exp, dmem.mem[idx]);
                errors = errors + 1;
            end else begin
                $display("PASS: mem[%0d] = 0x%08h", idx, exp);
            end
        end
    endtask

    initial begin
        $dumpfile("pipeline_hazard.vcd");
        $dumpvars(0, tb_pipeline_hazard);

        errors = 0;
        cycle = 0;
        rst = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;

        while (!halt && cycle < 500) begin
            @(posedge clk);
            cycle = cycle + 1;
            if (illegal_insn) begin
                $display("FAIL: illegal instruction asserted at cycle %0d", cycle);
                errors = errors + 1;
                cycle = 500;
            end
        end

        if (!halt) begin
            $display("FAIL: timeout waiting for ECALL/halt");
            errors = errors + 1;
        end

        $display("\n--- pipeline hazard/divider checks ---");
        check_reg(3,  32'h00000055); // loaded original value
        check_reg(4,  32'h00000055); // load->store-data forwarding preserved it
        check_reg(7,  32'd14);       // div 100/7
        check_reg(8,  32'd2);        // rem 100%7
        check_reg(9,  32'd16);       // consumer after long-latency DIV/REM
        check_reg(10, 32'd123);      // instruction immediately before ECALL commits
        check_mem(64, 32'h00000055);
        check_mem(65, 32'h00000055);

        if (errors == 0) begin
            $display("\nPASS: RV32IM pipelined hazard/divider test passed in %0d cycles.", cycle);
        end else begin
            $display("\nFAIL: RV32IM pipelined hazard/divider test had %0d error(s).", errors);
        end
        if (errors != 0)
            $fatal(1);
        $finish;
    end
endmodule
