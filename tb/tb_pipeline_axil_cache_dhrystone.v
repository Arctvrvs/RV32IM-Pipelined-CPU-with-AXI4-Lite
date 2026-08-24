`timescale 1ns/1ps

module tb_pipeline_axil_cache_dhrystone;

    localparam integer MEM_WORDS = 65536;
    localparam integer TIMEOUT_CYCLES = 5000000;
    localparam [31:0] EXPECTED_X5 = 32'h003f_ffff;

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

    simple_imem #(.MEM_WORDS(MEM_WORDS)) imem (
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    assign imem_ready = 1'b1;

    axil_direct_mapped_dcache #(
        .LINES(64),
        .INDEX_BITS(6)
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
        .MEM_WORDS(MEM_WORDS),
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

    initial begin
        $dumpfile("pipeline_axil_cache_dhrystone.vcd");
        $dumpvars(0, tb_pipeline_axil_cache_dhrystone);

        errors = 0;
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        $display("Running Dhrystone benchmark with AXI-Lite D-cache...");
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
                $display("INFO: cache accesses=%0d hits=%0d misses=%0d writebacks=%0d",
                    dcache.access_count, dcache.hit_count, dcache.miss_count, dcache.writeback_count);
                if (dut.rf.regs[5] === EXPECTED_X5) begin
                    $display("PASS: Dhrystone passed after %0d cycles.", cycle);
                end else begin
                    $display("FAIL: Dhrystone expected x5=0x%08h, got 0x%08h", EXPECTED_X5, dut.rf.regs[5]);
                    errors = errors + 1;
                end
                cycle = TIMEOUT_CYCLES;
            end else if ((cycle > 0) && ((cycle % 100000) == 0)) begin
                $display("INFO: ran %0d cycles... PC=0x%08h insn=0x%08h name=%0s", cycle, imem_addr, imem_rdata, dbg_insn_name);
            end
        end

        if (!halt && errors == 0) begin
            $display("FAIL: Dhrystone timed out after %0d cycles.", TIMEOUT_CYCLES);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: RV32IM pipelined AXI-Lite D-cache Dhrystone test passed.");
        end else begin
            $display("FAIL: RV32IM pipelined AXI-Lite D-cache Dhrystone test had %0d error(s).", errors);
        end

        if (errors != 0)
            $fatal(1);
        $finish;
    end

endmodule
