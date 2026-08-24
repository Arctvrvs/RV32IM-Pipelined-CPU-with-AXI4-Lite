`timescale 1ns/1ps

module tb_pipeline_axil_icache;

    reg clk;
    reg rst;

    wire        imem_valid;
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire        imem_ready;

    wire        dmem_valid;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_we;
    wire [31:0] dmem_rdata;
    wire        dmem_ready;

    // I-cache AXI read interface
    wire [31:0] i_araddr;
    wire        i_arvalid;
    wire        i_arready;
    wire [31:0] i_rdata;
    wire [1:0]  i_rresp;
    wire        i_rvalid;
    wire        i_rready;
    wire [31:0] i_awaddr;
    wire        i_awvalid;
    wire        i_awready;
    wire [31:0] i_wdata;
    wire [3:0]  i_wstrb;
    wire        i_wvalid;
    wire        i_wready;
    wire [1:0]  i_bresp;
    wire        i_bvalid;
    wire        i_bready;

    // D-cache AXI interface
    wire [31:0] d_araddr;
    wire        d_arvalid;
    wire        d_arready;
    wire [31:0] d_rdata;
    wire [1:0]  d_rresp;
    wire        d_rvalid;
    wire        d_rready;
    wire [31:0] d_awaddr;
    wire        d_awvalid;
    wire        d_awready;
    wire [31:0] d_wdata;
    wire [3:0]  d_wstrb;
    wire        d_wvalid;
    wire        d_wready;
    wire [1:0]  d_bresp;
    wire        d_bvalid;
    wire        d_bready;

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

    axil_direct_mapped_icache #(
        .LINES(4),
        .INDEX_BITS(2)
    ) icache (
        .clk          (clk),
        .rst          (rst),
        .cpu_valid    (imem_valid),
        .cpu_addr     (imem_addr),
        .cpu_rdata    (imem_rdata),
        .cpu_ready    (imem_ready),
        .m_axi_araddr (i_araddr),
        .m_axi_arvalid(i_arvalid),
        .m_axi_arready(i_arready),
        .m_axi_rdata  (i_rdata),
        .m_axi_rresp  (i_rresp),
        .m_axi_rvalid (i_rvalid),
        .m_axi_rready (i_rready),
        .access_count (),
        .hit_count    (),
        .miss_count   ()
    );

    axil_imemory #(
        .MEM_WORDS(256),
        .LATENCY(3)
    ) imemory (
        .clk          (clk),
        .rst          (rst),
        .s_axi_araddr (i_araddr),
        .s_axi_arvalid(i_arvalid),
        .s_axi_arready(i_arready),
        .s_axi_rdata  (i_rdata),
        .s_axi_rresp  (i_rresp),
        .s_axi_rvalid (i_rvalid),
        .s_axi_rready (i_rready),
        .s_axi_awaddr (i_awaddr),
        .s_axi_awvalid(i_awvalid),
        .s_axi_awready(i_awready),
        .s_axi_wdata  (i_wdata),
        .s_axi_wstrb  (i_wstrb),
        .s_axi_wvalid (i_wvalid),
        .s_axi_wready (i_wready),
        .s_axi_bresp  (i_bresp),
        .s_axi_bvalid (i_bvalid),
        .s_axi_bready (i_bready)
    );

    assign i_awaddr  = 32'd0;
    assign i_awvalid = 1'b0;
    assign i_wdata   = 32'd0;
    assign i_wstrb   = 4'd0;
    assign i_wvalid  = 1'b0;
    assign i_bready  = 1'b1;

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
        .m_axi_araddr (d_araddr),
        .m_axi_arvalid(d_arvalid),
        .m_axi_arready(d_arready),
        .m_axi_rdata  (d_rdata),
        .m_axi_rresp  (d_rresp),
        .m_axi_rvalid (d_rvalid),
        .m_axi_rready (d_rready),
        .m_axi_awaddr (d_awaddr),
        .m_axi_awvalid(d_awvalid),
        .m_axi_awready(d_awready),
        .m_axi_wdata  (d_wdata),
        .m_axi_wstrb  (d_wstrb),
        .m_axi_wvalid (d_wvalid),
        .m_axi_wready (d_wready),
        .m_axi_bresp  (d_bresp),
        .m_axi_bvalid (d_bvalid),
        .m_axi_bready (d_bready),
        .access_count (),
        .hit_count    (),
        .miss_count   (),
        .writeback_count ()
    );

    axil_memory #(
        .MEM_WORDS(256),
        .LATENCY(3)
    ) dmemory (
        .clk          (clk),
        .rst          (rst),
        .s_axi_araddr (d_araddr),
        .s_axi_arvalid(d_arvalid),
        .s_axi_arready(d_arready),
        .s_axi_rdata  (d_rdata),
        .s_axi_rresp  (d_rresp),
        .s_axi_rvalid (d_rvalid),
        .s_axi_rready (d_rready),
        .s_axi_awaddr (d_awaddr),
        .s_axi_awvalid(d_awvalid),
        .s_axi_awready(d_awready),
        .s_axi_wdata  (d_wdata),
        .s_axi_wstrb  (d_wstrb),
        .s_axi_wvalid (d_wvalid),
        .s_axi_wready (d_wready),
        .s_axi_bresp  (d_bresp),
        .s_axi_bvalid (d_bvalid),
        .s_axi_bready (d_bready)
    );

    initial begin clk = 1'b0; forever #5 clk = ~clk; end

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
        $dumpfile("pipeline_axil_icache.vcd");
        $dumpvars(0, tb_pipeline_axil_icache);

        errors = 0;
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 5000; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            if (illegal_insn) begin
                $display("FAIL: illegal instruction at cycle %0d PC=0x%08h insn=0x%08h name=%0s", cycle, imem_addr, imem_rdata, dbg_insn_name);
                errors = errors + 1;
                cycle = 5000;
            end else if (halt) begin
                cycle = 5000;
            end
        end

        if (!halt && errors == 0) begin
            $display("FAIL: AXI-Lite I/D-cache test timed out.");
            errors = errors + 1;
        end

        $display("\n--- RV32IM pipelined AXI-Lite I-cache + D-cache checks ---");
        check_reg(5'd2, 32'd42);
        check_reg(5'd3, 32'd42);
        check_reg(5'd4, 32'd16);
        check_reg(5'd5, 32'd99);
        check_reg(5'd6, 32'd99);
        check_reg(5'd7, 32'd42);
        check_reg(5'd8, 32'd141);
        check_reg(5'd9, 32'd42);

        if (dmemory.debug_word(32'd0) !== 32'd42) begin
            $display("FAIL: D-side AXI memory word[0] expected 42 after dirty writeback, got 0x%08h", dmemory.debug_word(32'd0));
            errors = errors + 1;
        end else begin
            $display("PASS: D-side AXI memory word[0] = 42 after dirty writeback");
        end

        check_stat_min("I-cache accesses", icache.access_count, 32'd1);
        check_stat_min("I-cache misses",   icache.miss_count,   32'd1);
        check_stat_min("D-cache accesses", dcache.access_count, 32'd5);
        check_stat_min("D-cache misses",   dcache.miss_count,   32'd1);
        check_stat_min("D-cache dirty writebacks", dcache.writeback_count, 32'd1);

        if (errors == 0) begin
            $display("\nPASS: RV32IM pipelined AXI-Lite I-cache + D-cache test passed.");
        end else begin
            $display("\nFAIL: RV32IM pipelined AXI-Lite I-cache + D-cache test had %0d error(s).", errors);
        end
        if (errors != 0)
            $fatal(1);
        $finish;
    end
endmodule
