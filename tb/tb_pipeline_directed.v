`timescale 1ns/1ps

module tb_pipeline_directed;

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

    integer errors;

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

    task check_mem;
        input [31:0] word_addr;
        input [31:0] expected;
        begin
            if (dmem.mem[word_addr] !== expected) begin
                $display("FAIL: mem[%0d] expected 0x%08h, got 0x%08h", word_addr, expected, dmem.mem[word_addr]);
                errors = errors + 1;
            end else begin
                $display("PASS: mem[%0d] = 0x%08h", word_addr, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("pipeline_directed.vcd");
        $dumpvars(0, tb_pipeline_directed);

        errors = 0;
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        // directed.hex is 81 words. Run extra cycles so the PC reaches trailing NOPs.
        repeat (700) @(posedge clk);

        $display("\n--- RV32I directed architectural checks ---");

        check_reg(5'd0,  32'h00000000); // x0 hardwired zero despite attempted write
        check_reg(5'd1,  32'h00000005); // ADDI
        check_reg(5'd2,  32'h00000007); // ADDI
        check_reg(5'd3,  32'h0000000c); // ADD
        check_reg(5'd4,  32'h00000002); // SUB
        check_reg(5'd5,  32'hfffffff8); // negative immediate
        check_reg(5'd6,  32'hfffffffe); // SRA
        check_reg(5'd7,  32'h3ffffffe); // SRL
        check_reg(5'd8,  32'h00000001); // SLT signed
        check_reg(5'd9,  32'h00000000); // SLTU unsigned
        check_reg(5'd10, 32'h00000001); // SLTI
        check_reg(5'd11, 32'h00000001); // SLTIU
        check_reg(5'd12, 32'h00000006); // XORI
        check_reg(5'd13, 32'h00000015); // ORI
        check_reg(5'd14, 32'h00000005); // ANDI
        check_reg(5'd15, 32'h00000028); // SLLI
        check_reg(5'd16, 32'h0000000a); // SRLI
        check_reg(5'd17, 32'hfffffffc); // SRAI
        check_reg(5'd18, 32'h12345000); // LUI
        check_reg(5'd19, 32'h00000054); // AUIPC with imm=0 at PC 0x54
        check_reg(5'd20, 32'h00000040); // data-memory base pointer
        check_reg(5'd21, 32'h00000456); // final store-half source value
        check_reg(5'd22, 32'hddccbbaa); // LW after four SB lanes
        check_reg(5'd23, 32'hffffffaa); // LB sign extend
        check_reg(5'd24, 32'h000000aa); // LBU zero extend
        check_reg(5'd25, 32'hffffbbaa); // LH sign extend
        check_reg(5'd26, 32'h0000ddcc); // LHU zero extend from upper half
        check_reg(5'd27, 32'hffffffff); // ADDI -1
        check_reg(5'd28, 32'hffffffff); // LW after SW
        check_reg(5'd29, 32'h00000120); // JALR target address loaded into x29
        check_reg(5'd30, 32'h0000011c); // JALR link = PC+4 of JALR instruction
        check_reg(5'd31, 32'h000001ff); // branch/JAL/JALR signature = 511

        check_mem(32'd16, 32'hddccbbaa); // SB lane assembly at byte address 64
        check_mem(32'd17, 32'hffffffff); // SW at byte address 68
        check_mem(32'd18, 32'h0456f823); // SH lower + SH upper at byte address 72

        if (errors == 0) begin
            $display("\nPASS: RV32IM pipelined directed CPU test passed all checks.");
        end else begin
            $display("\nFAIL: RV32IM pipelined directed CPU test had %0d error(s).", errors);
        end

        if (errors != 0)
            $fatal(1);
        $finish;
    end

endmodule
