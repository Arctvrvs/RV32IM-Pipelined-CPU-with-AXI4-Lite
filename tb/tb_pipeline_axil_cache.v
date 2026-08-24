`timescale 1ns/1ps

module tb_pipeline_axil_cache;

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

    wire [31:0] axi_araddr;
    wire        axi_arvalid;
    wire        axi_arready;
    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid;
    wire        axi_rready;
    wire [31:0] axi_awaddr;
    wire        axi_awvalid;
    wire        axi_awready;
    wire [31:0] axi_wdata;
    wire [3:0]  axi_wstrb;
    wire        axi_wvalid;
    wire        axi_wready;
    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    wire        axi_bready;

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
    axil_direct_mapped_dcache #(
        .LINES(4),
        .INDEX_BITS(2)
    ) dcache (
        .clk          (clk),
        .rst          (rst),
        .cpu_valid    (dmem_valid),
        .cpu_addr     (dmem_addr),
        .cpu_wdata    (dmem_wdata),
        .cpu_we       (dmem_we),
        .cpu_rdata    (dmem_rdata),
        .cpu_ready    (dmem_ready),
        .m_axi_araddr (axi_araddr),
        .m_axi_arvalid(axi_arvalid),
        .m_axi_arready(axi_arready),
        .m_axi_rdata  (axi_rdata),
        .m_axi_rresp  (axi_rresp),
        .m_axi_rvalid (axi_rvalid),
        .m_axi_rready (axi_rready),
        .m_axi_awaddr (axi_awaddr),
        .m_axi_awvalid(axi_awvalid),
        .m_axi_awready(axi_awready),
        .m_axi_wdata  (axi_wdata),
        .m_axi_wstrb  (axi_wstrb),
        .m_axi_wvalid (axi_wvalid),
        .m_axi_wready (axi_wready),
        .m_axi_bresp  (axi_bresp),
        .m_axi_bvalid (axi_bvalid),
        .m_axi_bready (axi_bready),
        .access_count (),
        .hit_count    (),
        .miss_count   (),
        .writeback_count ()
    );

    axil_memory #(
        .MEM_WORDS(256),
        .LATENCY(3)
    ) memory (
        .clk          (clk),
        .rst          (rst),
        .s_axi_araddr (axi_araddr),
        .s_axi_arvalid(axi_arvalid),
        .s_axi_arready(axi_arready),
        .s_axi_rdata  (axi_rdata),
        .s_axi_rresp  (axi_rresp),
        .s_axi_rvalid (axi_rvalid),
        .s_axi_rready (axi_rready),
        .s_axi_awaddr (axi_awaddr),
        .s_axi_awvalid(axi_awvalid),
        .s_axi_awready(axi_awready),
        .s_axi_wdata  (axi_wdata),
        .s_axi_wstrb  (axi_wstrb),
        .s_axi_wvalid (axi_wvalid),
        .s_axi_wready (axi_wready),
        .s_axi_bresp  (axi_bresp),
        .s_axi_bvalid (axi_bvalid),
        .s_axi_bready (axi_bready)
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

    task check_stat_min;
        input [127:0] name;
        input [31:0] got;
        input [31:0] min_value;
        begin
            if (got < min_value) begin
                $display("FAIL: %0s expected >= %0d, got %0d", name, min_value, got);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %0d", name, got);
            end
        end
    endtask

    initial begin
        $dumpfile("pipeline_axil_cache.vcd");
        $dumpvars(0, tb_pipeline_axil_cache);

        errors = 0;
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 2000; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            if (illegal_insn) begin
                $display("FAIL: illegal instruction at cycle %0d PC=0x%08h insn=0x%08h name=%0s", cycle, imem_addr, imem_rdata, dbg_insn_name);
                errors = errors + 1;
                cycle = 2000;
            end else if (halt) begin
                cycle = 2000;
            end
        end

        if (!halt && errors == 0) begin
            $display("FAIL: AXI-Lite cache test timed out.");
            errors = errors + 1;
        end

        $display("\n--- RV32IM pipelined AXI-Lite D-cache checks ---");
        check_reg(5'd2, 32'd42);
        check_reg(5'd3, 32'd42);
        check_reg(5'd4, 32'd16);
        check_reg(5'd5, 32'd99);
        check_reg(5'd6, 32'd99);
        check_reg(5'd7, 32'd42);
        check_reg(5'd8, 32'd141);
        check_reg(5'd9, 32'd42);

        // The access pattern stores address 0, evicts it with address 16, then
        // reloads address 0.  That forces a dirty writeback to AXI memory.
        if (memory.debug_word(32'd0) !== 32'd42) begin
            $display("FAIL: AXI memory word[0] expected 42 after dirty writeback, got 0x%08h", memory.debug_word(32'd0));
            errors = errors + 1;
        end else begin
            $display("PASS: AXI memory word[0] = 42 after dirty writeback");
        end

        check_stat_min("cache accesses", dcache.access_count, 32'd5);
        check_stat_min("cache hits",     dcache.hit_count,    32'd1);
        check_stat_min("cache misses",   dcache.miss_count,   32'd1);
        check_stat_min("dirty writebacks", dcache.writeback_count, 32'd1);

        if (errors == 0) begin
            $display("\nPASS: RV32IM pipelined AXI-Lite D-cache test passed.");
        end else begin
            $display("\nFAIL: RV32IM pipelined AXI-Lite D-cache test had %0d error(s).", errors);
        end

        if (errors != 0)
            $fatal(1);
        $finish;
    end

endmodule
