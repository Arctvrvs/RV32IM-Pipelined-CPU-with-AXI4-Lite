// -----------------------------------------------------------------------------
// RV32IM five-stage pipelined CPU core
// -----------------------------------------------------------------------------
// Educational in-order 5-stage pipeline:
//   IF  : instruction fetch
//   ID  : decode + register read
//   EX  : ALU / branch compare / jump target calculation
//   MEM : data memory access
//   WB  : register writeback
//
// Features:
//   - RV32I base integer instructions used by the riscv-tests rv32ui suite
//   - RV32M multiply plus 8-stage pipelined DIV/REM support
//   - forwarding from EX/MEM and MEM/WB plus MEM-stage store-data forwarding
//   - load-use interlock with optimized load-to-store-data bypass
//   - branch/JAL/JALR resolved in EX with IF/ID and ID/EX flush
//   - ECALL/EBREAK halt output
//   - FENCE/FENCE.I treated as NOPs
//
// Notes:
//   - DIV/REM issue into a separate 8-stage unsigned divider pipeline.
//     Independent DIV/REM operations may issue back-to-back; non-div followers
//     are interlocked while divider results drain.
//   - The data-memory interface includes dmem_valid/dmem_ready so the MEM stage
//     can stall cleanly for a blocking cache miss.
// -----------------------------------------------------------------------------
module rv32im_pipeline (
    input  wire        clk,
    input  wire        rst,

    output wire        imem_valid,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,
    input  wire        imem_ready,

    output wire        dmem_valid,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_we,
    input  wire [31:0] dmem_rdata,
    input  wire        dmem_ready,

    output wire        halt,
    output wire        illegal_insn,
    output wire [127:0] dbg_insn_name,

    // pipeline writeback trace/debug outputs. Existing testbenches may leave
    // these unconnected; they are useful for waveform/debug waveform and retirement-debug visibility.
    output wire        trace_writeback_valid,
    output wire [31:0] trace_writeback_pc,
    output wire [31:0] trace_writeback_insn,
    output wire [31:0] trace_writeback_cycle_status,
    output wire [4:0]  trace_writeback_rd,
    output wire [31:0] trace_writeback_wdata,
    output wire        trace_writeback_reg_write
);

    // -------------------------------------------------------------------------
    // Opcodes
    // -------------------------------------------------------------------------
    localparam [6:0] OPCODE_LOAD     = 7'b0000011;
    localparam [6:0] OPCODE_MISC_MEM = 7'b0001111;
    localparam [6:0] OPCODE_OP_IMM   = 7'b0010011;
    localparam [6:0] OPCODE_AUIPC    = 7'b0010111;
    localparam [6:0] OPCODE_STORE    = 7'b0100011;
    localparam [6:0] OPCODE_OP       = 7'b0110011;
    localparam [6:0] OPCODE_LUI      = 7'b0110111;
    localparam [6:0] OPCODE_BRANCH   = 7'b1100011;
    localparam [6:0] OPCODE_JALR     = 7'b1100111;
    localparam [6:0] OPCODE_JAL      = 7'b1101111;
    localparam [6:0] OPCODE_SYSTEM   = 7'b1110011;

    localparam [1:0] WB_ALU = 2'd0;
    localparam [1:0] WB_MEM = 2'd1;
    localparam [1:0] WB_PC4 = 2'd2;
    localparam [1:0] WB_IMM = 2'd3;

    // pipeline cycle-status values.  These are kept as plain localparams
    // instead of an enum so the core remains standalone Verilog/SystemVerilog.
    localparam [31:0] TRACE_INVALID = 32'd0;
    localparam [31:0] TRACE_RESET   = 32'd1;
    localparam [31:0] TRACE_OK      = 32'd2;
    localparam [31:0] TRACE_BRANCH  = 32'd4;
    localparam [31:0] TRACE_DIV     = 32'd8;
    localparam [31:0] TRACE_LOADUSE = 32'd16;
    localparam [31:0] TRACE_MEMSTALL = 32'd32;
    localparam [31:0] TRACE_HALT    = 32'd2;

    // -------------------------------------------------------------------------
    // IF stage
    // -------------------------------------------------------------------------
    reg [31:0] pc;
    wire [31:0] pc_plus4 = pc + 32'd4;

    assign imem_valid = 1'b1;
    assign imem_addr = pc;

    // -------------------------------------------------------------------------
    // IF/ID pipeline register
    // -------------------------------------------------------------------------
    reg        if_id_valid;
    reg [31:0] if_id_pc;
    reg [31:0] if_id_pc4;
    reg [31:0] if_id_insn;

    wire [6:0] id_opcode = if_id_insn[6:0];
    wire [4:0] id_rd     = if_id_insn[11:7];
    wire [2:0] id_funct3 = if_id_insn[14:12];
    wire [4:0] id_rs1    = if_id_insn[19:15];
    wire [4:0] id_rs2    = if_id_insn[24:20];
    wire [6:0] id_funct7 = if_id_insn[31:25];

    // -------------------------------------------------------------------------
    // Decode stage combinational control
    // -------------------------------------------------------------------------
    wire [31:0] id_imm;
    wire [4:0]  id_alu_ctrl;

    reg         id_reg_write;
    reg         id_mem_read;
    reg         id_mem_write;
    reg         id_branch;
    reg         id_jump;
    reg         id_jalr;
    reg         id_alu_src_imm;
    reg         id_alu_a_pc;
    reg [1:0]   id_wb_sel;
    reg         id_system;
    reg         id_illegal;
    reg [2:0]   id_imm_sel;
    reg [127:0] id_name;

    imm_gen u_imm_gen (
        .insn    (if_id_insn),
        .imm_sel (id_imm_sel),
        .imm     (id_imm)
    );

    alu_control u_alu_control (
        .opcode   (id_opcode),
        .funct3   (id_funct3),
        .funct7   (id_funct7),
        .alu_ctrl (id_alu_ctrl)
    );

    always @(*) begin
        id_reg_write   = 1'b0;
        id_mem_read    = 1'b0;
        id_mem_write   = 1'b0;
        id_branch      = 1'b0;
        id_jump        = 1'b0;
        id_jalr        = 1'b0;
        id_alu_src_imm = 1'b0;
        id_alu_a_pc    = 1'b0;
        id_wb_sel      = WB_ALU;
        id_system      = 1'b0;
        id_illegal     = 1'b0;
        id_imm_sel     = 3'b000;
        id_name        = "UNKNOWN";

        case (id_opcode)
            OPCODE_OP: begin
                id_reg_write = 1'b1;
                id_wb_sel    = WB_ALU;
                case ({id_funct7, id_funct3})
                    {7'b0000000,3'b000}: id_name = "ADD";
                    {7'b0100000,3'b000}: id_name = "SUB";
                    {7'b0000000,3'b001}: id_name = "SLL";
                    {7'b0000000,3'b010}: id_name = "SLT";
                    {7'b0000000,3'b011}: id_name = "SLTU";
                    {7'b0000000,3'b100}: id_name = "XOR";
                    {7'b0000000,3'b101}: id_name = "SRL";
                    {7'b0100000,3'b101}: id_name = "SRA";
                    {7'b0000000,3'b110}: id_name = "OR";
                    {7'b0000000,3'b111}: id_name = "AND";
                    {7'b0000001,3'b000}: id_name = "MUL";
                    {7'b0000001,3'b001}: id_name = "MULH";
                    {7'b0000001,3'b010}: id_name = "MULHSU";
                    {7'b0000001,3'b011}: id_name = "MULHU";
                    {7'b0000001,3'b100}: id_name = "DIV";
                    {7'b0000001,3'b101}: id_name = "DIVU";
                    {7'b0000001,3'b110}: id_name = "REM";
                    {7'b0000001,3'b111}: id_name = "REMU";
                    default: begin id_name = "ILLEGAL_OP"; id_illegal = 1'b1; id_reg_write = 1'b0; end
                endcase
            end

            OPCODE_OP_IMM: begin
                id_imm_sel     = 3'b000;
                id_reg_write   = 1'b1;
                id_alu_src_imm = 1'b1;
                id_wb_sel      = WB_ALU;
                case (id_funct3)
                    3'b000: id_name = "ADDI";
                    3'b001: begin id_name = "SLLI"; if (id_funct7 != 7'b0000000) id_illegal = 1'b1; end
                    3'b010: id_name = "SLTI";
                    3'b011: id_name = "SLTIU";
                    3'b100: id_name = "XORI";
                    3'b101: begin
                        if (id_funct7 == 7'b0000000) id_name = "SRLI";
                        else if (id_funct7 == 7'b0100000) id_name = "SRAI";
                        else begin id_name = "ILLEGAL_SHIFTI"; id_illegal = 1'b1; end
                    end
                    3'b110: id_name = "ORI";
                    3'b111: id_name = "ANDI";
                    default: begin id_name = "ILLEGAL_OPIMM"; id_illegal = 1'b1; end
                endcase
                if (id_illegal) id_reg_write = 1'b0;
            end

            OPCODE_LOAD: begin
                id_imm_sel     = 3'b000;
                id_reg_write   = 1'b1;
                id_mem_read    = 1'b1;
                id_alu_src_imm = 1'b1;
                id_wb_sel      = WB_MEM;
                case (id_funct3)
                    3'b000: id_name = "LB";
                    3'b001: id_name = "LH";
                    3'b010: id_name = "LW";
                    3'b100: id_name = "LBU";
                    3'b101: id_name = "LHU";
                    default: begin id_name = "ILLEGAL_LOAD"; id_illegal = 1'b1; id_reg_write = 1'b0; id_mem_read = 1'b0; end
                endcase
            end

            OPCODE_STORE: begin
                id_imm_sel     = 3'b001;
                id_mem_write   = 1'b1;
                id_alu_src_imm = 1'b1;
                case (id_funct3)
                    3'b000: id_name = "SB";
                    3'b001: id_name = "SH";
                    3'b010: id_name = "SW";
                    default: begin id_name = "ILLEGAL_STORE"; id_illegal = 1'b1; id_mem_write = 1'b0; end
                endcase
            end

            OPCODE_BRANCH: begin
                id_imm_sel     = 3'b010;
                id_branch = 1'b1;
                case (id_funct3)
                    3'b000: id_name = "BEQ";
                    3'b001: id_name = "BNE";
                    3'b100: id_name = "BLT";
                    3'b101: id_name = "BGE";
                    3'b110: id_name = "BLTU";
                    3'b111: id_name = "BGEU";
                    default: begin id_name = "ILLEGAL_BRANCH"; id_illegal = 1'b1; id_branch = 1'b0; end
                endcase
            end

            OPCODE_JAL: begin
                id_imm_sel     = 3'b100;
                id_reg_write = 1'b1;
                id_jump      = 1'b1;
                id_wb_sel    = WB_PC4;
                id_name      = "JAL";
            end

            OPCODE_JALR: begin
                id_imm_sel     = 3'b000;
                id_reg_write   = 1'b1;
                id_jump        = 1'b1;
                id_jalr        = 1'b1;
                id_alu_src_imm = 1'b1;
                id_wb_sel      = WB_PC4;
                id_name        = "JALR";
                if (id_funct3 != 3'b000) begin id_illegal = 1'b1; id_reg_write = 1'b0; id_jump = 1'b0; id_jalr = 1'b0; end
            end

            OPCODE_LUI: begin
                id_imm_sel     = 3'b011;
                id_reg_write = 1'b1;
                id_wb_sel    = WB_IMM;
                id_name      = "LUI";
            end

            OPCODE_AUIPC: begin
                id_imm_sel     = 3'b011;
                id_reg_write   = 1'b1;
                id_alu_src_imm = 1'b1;
                id_alu_a_pc    = 1'b1;
                id_wb_sel      = WB_ALU;
                id_name        = "AUIPC";
            end

            OPCODE_MISC_MEM: begin
                // FENCE/FENCE.I are treated as NOPs in this simple uncached core.
                id_name = "FENCE";
            end

            OPCODE_SYSTEM: begin
                id_system = 1'b1;
                if (if_id_insn == 32'h00000073) id_name = "ECALL";
                else if (if_id_insn == 32'h00100073) id_name = "EBREAK";
                else begin id_name = "SYSTEM"; id_illegal = 1'b1; id_system = 1'b0; end
            end

            default: begin
                // Treat all-zero/trailing X as NOP only if IF/ID is invalid. If valid,
                // an unknown opcode is an illegal instruction.
                id_name    = "ILLEGAL";
                id_illegal = 1'b1;
            end
        endcase
    end

    // Register file with WB-stage write and ID-stage reads.
    wire [31:0] rf_rs1_rdata;
    wire [31:0] rf_rs2_rdata;
    wire        wb_do_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_wdata;

    regfile rf (
        .clk       (clk),
        .rst       (rst),
        .we        (wb_do_write),
        .rs1       (id_rs1),
        .rs2       (id_rs2),
        .rd        (wb_rd),
        .rd_wdata  (wb_wdata),
        .rs1_rdata (rf_rs1_rdata),
        .rs2_rdata (rf_rs2_rdata)
    );

    // -------------------------------------------------------------------------
    // ID/EX pipeline register
    // -------------------------------------------------------------------------
    reg        id_ex_valid;
    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_pc4;
    reg [31:0] id_ex_insn;
    reg [31:0] id_ex_imm;
    reg [31:0] id_ex_rs1_val;
    reg [31:0] id_ex_rs2_val;
    reg [4:0]  id_ex_rs1;
    reg [4:0]  id_ex_rs2;
    reg [4:0]  id_ex_rd;
    reg [2:0]  id_ex_funct3;
    reg [6:0]  id_ex_opcode;
    reg [4:0]  id_ex_alu_ctrl;
    reg        id_ex_reg_write;
    reg        id_ex_mem_read;
    reg        id_ex_mem_write;
    reg        id_ex_branch;
    reg        id_ex_jump;
    reg        id_ex_jalr;
    reg        id_ex_alu_src_imm;
    reg        id_ex_alu_a_pc;
    reg [1:0]  id_ex_wb_sel;
    reg        id_ex_system;
    reg        id_ex_illegal;
    reg [127:0] id_ex_name;

    // Current ID instruction source-use classification.  Stores use rs1 in EX
    // for the address, but rs2 is not needed until MEM.  This matches the pipeline
    // style load->store-data optimization: `lw x5,...; sw x5,...` does not need
    // a decode stall because the loaded value can be forwarded into the store
    // during the MEM stage.
    reg id_uses_rs1;
    reg id_uses_rs2;
    reg id_needs_rs1_ex;
    reg id_needs_rs2_ex;
    always @(*) begin
        id_uses_rs1     = 1'b0;
        id_uses_rs2     = 1'b0;
        id_needs_rs1_ex = 1'b0;
        id_needs_rs2_ex = 1'b0;
        case (id_opcode)
            OPCODE_OP: begin
                id_uses_rs1 = 1'b1; id_uses_rs2 = 1'b1;
                id_needs_rs1_ex = 1'b1; id_needs_rs2_ex = 1'b1;
            end
            OPCODE_OP_IMM, OPCODE_LOAD, OPCODE_JALR: begin
                id_uses_rs1 = 1'b1;
                id_needs_rs1_ex = 1'b1;
            end
            OPCODE_STORE: begin
                id_uses_rs1 = 1'b1; id_uses_rs2 = 1'b1;
                id_needs_rs1_ex = 1'b1;
                id_needs_rs2_ex = 1'b0; // store data can be fixed in MEM
            end
            OPCODE_BRANCH: begin
                id_uses_rs1 = 1'b1; id_uses_rs2 = 1'b1;
                id_needs_rs1_ex = 1'b1; id_needs_rs2_ex = 1'b1;
            end
            default: begin
                id_uses_rs1 = 1'b0; id_uses_rs2 = 1'b0;
                id_needs_rs1_ex = 1'b0; id_needs_rs2_ex = 1'b0;
            end
        endcase
    end

    wire load_use_hazard =
        if_id_valid && id_ex_valid && id_ex_mem_read && (id_ex_rd != 5'd0) &&
        ((id_needs_rs1_ex && (id_ex_rd == id_rs1)) ||
         (id_needs_rs2_ex && (id_ex_rd == id_rs2)));

    // WB-to-ID bypass for values written in the same cycle that ID samples.
    wire [31:0] id_rs1_value = (wb_do_write && (wb_rd != 5'd0) && (wb_rd == id_rs1)) ? wb_wdata : rf_rs1_rdata;
    wire [31:0] id_rs2_value = (wb_do_write && (wb_rd != 5'd0) && (wb_rd == id_rs2)) ? wb_wdata : rf_rs2_rdata;

    // -------------------------------------------------------------------------
    // EX stage forwarding and execution
    // -------------------------------------------------------------------------
    reg [31:0] ex_mem_forward_value;
    reg [31:0] mem_wb_forward_value;

    // EX/MEM and MEM/WB declarations appear below; forward wires are assigned
    // after those regs are declared.

    // -------------------------------------------------------------------------
    // EX/MEM pipeline register declarations
    // -------------------------------------------------------------------------
    reg        ex_mem_valid;
    reg [31:0] ex_mem_pc;
    reg [31:0] ex_mem_pc4;
    reg [31:0] ex_mem_insn;
    reg [31:0] ex_mem_alu_result;
    reg [31:0] ex_mem_store_data;
    reg [31:0] ex_mem_imm;
    reg [4:0]  ex_mem_rs1;
    reg [4:0]  ex_mem_rs2;
    reg [4:0]  ex_mem_rd;
    reg [2:0]  ex_mem_funct3;
    reg        ex_mem_reg_write;
    reg        ex_mem_mem_read;
    reg        ex_mem_mem_write;
    reg [1:0]  ex_mem_wb_sel;
    reg        ex_mem_system;
    reg        ex_mem_illegal;
    reg [127:0] ex_mem_name;

    // -------------------------------------------------------------------------
    // MEM/WB pipeline register declarations
    // -------------------------------------------------------------------------
    reg        mem_wb_valid;
    reg [31:0] mem_wb_pc;
    reg [31:0] mem_wb_pc4;
    reg [31:0] mem_wb_insn;
    reg [31:0] mem_wb_alu_result;
    reg [31:0] mem_wb_load_data;
    reg [31:0] mem_wb_imm;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_write;
    reg [1:0]  mem_wb_wb_sel;
    reg [31:0] mem_wb_trace_status;
    reg        mem_wb_system;
    reg        mem_wb_illegal;
    reg [127:0] mem_wb_name;

    wire stop_for_system;
    wire mem_access;
    wire mem_stall;
    wire if_stall;
    wire pipe_stall;

    always @(*) begin
        case (ex_mem_wb_sel)
            WB_ALU: ex_mem_forward_value = ex_mem_alu_result;
            WB_PC4: ex_mem_forward_value = ex_mem_pc4;
            WB_IMM: ex_mem_forward_value = ex_mem_imm;
            default: ex_mem_forward_value = ex_mem_alu_result;
        endcase
    end

    always @(*) begin
        case (mem_wb_wb_sel)
            WB_ALU: mem_wb_forward_value = mem_wb_alu_result;
            WB_MEM: mem_wb_forward_value = mem_wb_load_data;
            WB_PC4: mem_wb_forward_value = mem_wb_pc4;
            WB_IMM: mem_wb_forward_value = mem_wb_imm;
            default: mem_wb_forward_value = mem_wb_alu_result;
        endcase
    end

    assign wb_wdata = mem_wb_forward_value;
    assign wb_rd = mem_wb_rd;
    assign wb_do_write = mem_wb_valid && mem_wb_reg_write && (mem_wb_rd != 5'd0);

    reg [31:0] ex_rs1_fwd;
    reg [31:0] ex_rs2_fwd;

    always @(*) begin
        ex_rs1_fwd = id_ex_rs1_val;
        ex_rs2_fwd = id_ex_rs2_val;

        if (ex_mem_valid && ex_mem_reg_write && !ex_mem_mem_read && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1)) begin
            ex_rs1_fwd = ex_mem_forward_value;
        end else if (mem_wb_valid && mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1)) begin
            ex_rs1_fwd = mem_wb_forward_value;
        end

        if (ex_mem_valid && ex_mem_reg_write && !ex_mem_mem_read && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2)) begin
            ex_rs2_fwd = ex_mem_forward_value;
        end else if (mem_wb_valid && mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2)) begin
            ex_rs2_fwd = mem_wb_forward_value;
        end
    end

    wire [31:0] ex_alu_op1 = id_ex_alu_a_pc ? id_ex_pc : ex_rs1_fwd;
    wire [31:0] ex_alu_op2 = id_ex_alu_src_imm ? id_ex_imm : ex_rs2_fwd;
    wire [31:0] ex_alu_result;
    wire        ex_alu_zero;

    alu u_alu (
        .op1      (ex_alu_op1),
        .op2      (ex_alu_op2),
        .alu_ctrl (id_ex_alu_ctrl),
        .result   (ex_alu_result),
        .zero     (ex_alu_zero)
    );

    wire ex_branch_taken_raw;
    branch_unit u_branch_unit (
        .funct3       (id_ex_funct3),
        .rs1_value    (ex_rs1_fwd),
        .rs2_value    (ex_rs2_fwd),
        .branch_taken (ex_branch_taken_raw)
    );

    wire ex_branch_taken = id_ex_valid && id_ex_branch && ex_branch_taken_raw;
    wire ex_jump_taken   = id_ex_valid && id_ex_jump;
    wire ex_redirect     = ex_branch_taken || ex_jump_taken;
    wire [31:0] ex_branch_target = id_ex_pc + id_ex_imm;
    wire [31:0] ex_jalr_target   = (ex_rs1_fwd + id_ex_imm) & 32'hFFFF_FFFE;
    wire [31:0] ex_redirect_pc   = id_ex_jalr ? ex_jalr_target : ex_branch_target;

    // -------------------------------------------------------------------------
    // Early declarations used by forwarding/divider logic
    // -------------------------------------------------------------------------
    wire [31:0] mem_load_data;

    reg halt_r;
    reg illegal_r;
    reg [127:0] dbg_name_r;

    // Memory-system interlock.  The simple-memory tests tie dmem_ready high;
    // cache tests drive it low on a miss.  While a MEM-stage load/store is
    // waiting, the pipeline holds IF/ID, ID/EX, and EX/MEM.  MEM/WB is turned
    // into a bubble after the previous WB instruction has had one cycle to
    // commit, avoiding repeated trace/writeback events during a long miss.
    assign mem_access = ex_mem_valid && (ex_mem_mem_read || ex_mem_mem_write);
    assign mem_stall  = mem_access && !dmem_ready;
    assign if_stall   = !imem_ready;
    assign pipe_stall = mem_stall || if_stall;

    // -------------------------------------------------------------------------
    // 8-stage pipelined DIV/REM issue and hazard control
    // -------------------------------------------------------------------------
    // DIV/REM issue from Decode into a separate divider pipeline.  They do not
    // occupy the normal EX stage.  Independent DIV/REM instructions can launch
    // on consecutive cycles.  Non-DIV instructions are held while divider
    // results drain so architectural commit order stays simple/in-order.

    wire id_is_divrem =
        if_id_valid && (id_opcode == OPCODE_OP) && (id_funct7 == 7'b0000001) &&
        ((id_funct3 == 3'b100) || (id_funct3 == 3'b101) ||
         (id_funct3 == 3'b110) || (id_funct3 == 3'b111));

    wire id_ex_is_divrem =
        id_ex_valid && (id_ex_opcode == OPCODE_OP) && (id_ex_insn[31:25] == 7'b0000001) &&
        ((id_ex_funct3 == 3'b100) || (id_ex_funct3 == 3'b101) ||
         (id_ex_funct3 == 3'b110) || (id_ex_funct3 == 3'b111));

    reg [31:0] id_ex_forward_value;
    always @(*) begin
        case (id_ex_wb_sel)
            WB_ALU: id_ex_forward_value = ex_alu_result;
            WB_PC4: id_ex_forward_value = id_ex_pc4;
            WB_IMM: id_ex_forward_value = id_ex_imm;
            default: id_ex_forward_value = ex_alu_result;
        endcase
    end

    // Decode-stage bypass used for divider launch operands.  Normal ALU/branch
    // instructions still get their newest operands through EX-stage forwarding.
    reg [31:0] id_rs1_launch;
    reg [31:0] id_rs2_launch;
    always @(*) begin
        id_rs1_launch = id_rs1_value;
        id_rs2_launch = id_rs2_value;

        if (id_ex_valid && id_ex_reg_write && !id_ex_mem_read && !id_ex_is_divrem &&
            (id_ex_rd != 5'd0) && (id_ex_rd == id_rs1)) begin
            id_rs1_launch = id_ex_forward_value;
        end else if (ex_mem_valid && ex_mem_reg_write && (ex_mem_rd != 5'd0) &&
                     (ex_mem_rd == id_rs1)) begin
            id_rs1_launch = ex_mem_mem_read ? mem_load_data : ex_mem_forward_value;
        end else if (mem_wb_valid && mem_wb_reg_write && (mem_wb_rd != 5'd0) &&
                     (mem_wb_rd == id_rs1)) begin
            id_rs1_launch = mem_wb_forward_value;
        end

        if (id_ex_valid && id_ex_reg_write && !id_ex_mem_read && !id_ex_is_divrem &&
            (id_ex_rd != 5'd0) && (id_ex_rd == id_rs2)) begin
            id_rs2_launch = id_ex_forward_value;
        end else if (ex_mem_valid && ex_mem_reg_write && (ex_mem_rd != 5'd0) &&
                     (ex_mem_rd == id_rs2)) begin
            id_rs2_launch = ex_mem_mem_read ? mem_load_data : ex_mem_forward_value;
        end else if (mem_wb_valid && mem_wb_reg_write && (mem_wb_rd != 5'd0) &&
                     (mem_wb_rd == id_rs2)) begin
            id_rs2_launch = mem_wb_forward_value;
        end
    end

    wire [31:0] div_abs_rs1 = id_rs1_launch[31] ? (~id_rs1_launch + 32'd1) : id_rs1_launch;
    wire [31:0] div_abs_rs2 = id_rs2_launch[31] ? (~id_rs2_launch + 32'd1) : id_rs2_launch;
    wire        id_div_signed = (id_funct3 == 3'b100) || (id_funct3 == 3'b110);
    wire        id_div_want_rem = (id_funct3 == 3'b110) || (id_funct3 == 3'b111);
    wire        id_div_by_zero = (id_rs2_launch == 32'd0);
    wire        id_div_overflow = id_div_signed && (id_rs1_launch == 32'h8000_0000) &&
                                  (id_rs2_launch == 32'hFFFF_FFFF);

    wire [31:0] div_dividend_u = id_div_signed ? div_abs_rs1 : id_rs1_launch;
    wire [31:0] div_divisor_u  = id_div_signed ? div_abs_rs2 : id_rs2_launch;

    reg        div_valid_q [0:7];
    reg [31:0] div_pc_q [0:7];
    reg [31:0] div_insn_q [0:7];
    reg [4:0]  div_rd_q [0:7];
    reg [2:0]  div_funct3_q [0:7];
    reg        div_sign_quot_q [0:7];
    reg        div_sign_rem_q [0:7];
    reg        div_want_rem_q [0:7];
    reg        div_special_q [0:7];
    reg [31:0] div_special_result_q [0:7];
    reg [127:0] div_name_q [0:7];

    integer div_h;
    reg div_dep_hazard;
    reg div_any_active;
    reg div_busy_prelast;
    always @(*) begin
        div_dep_hazard  = 1'b0;
        div_any_active  = 1'b0;
        div_busy_prelast = 1'b0;

        // Track all active divider metadata entries for debug/status.  For normal
        // non-DIV followers, only stages 0..6 force a stall.  When an older DIV/REM
        // is in the last stage, its result will be injected into EX/MEM on this
        // clock edge, so a younger non-DIV instruction may advance into ID/EX and
        // use the normal EX/MEM forwarding path on the following cycle.  A younger
        // DIV/REM that depends on an older DIV/REM still waits through stage 7,
        // because divider launch operands are captured from Decode before the
        // older result is available in EX/MEM.
        for (div_h = 0; div_h < 8; div_h = div_h + 1) begin
            if (div_valid_q[div_h]) begin
                div_any_active = 1'b1;
                if (div_h < 7) begin
                    div_busy_prelast = 1'b1;
                end

                if ((div_rd_q[div_h] != 5'd0) &&
                    ((id_uses_rs1 && (id_rs1 == div_rd_q[div_h])) ||
                     (id_uses_rs2 && (id_rs2 == div_rd_q[div_h])))) begin
                    if (id_is_divrem || (div_h < 7)) begin
                        div_dep_hazard = 1'b1;
                    end
                end
            end
        end
    end

    wire div_nondiv_hazard = if_id_valid && !id_is_divrem && div_busy_prelast;
    wire div_stall_hazard  = if_id_valid && ((id_is_divrem && div_dep_hazard) || div_nondiv_hazard);

    wire div_issue_now = id_is_divrem && !load_use_hazard && !div_stall_hazard &&
                         !pipe_stall && !ex_redirect && !stop_for_system;

    wire [31:0] div_launch_dividend = div_dividend_u;
    wire [31:0] div_launch_divisor  = (div_divisor_u == 32'd0) ? 32'd1 : div_divisor_u;
    wire [31:0] div_pipe_quot;
    wire [31:0] div_pipe_rem;
    divider_unsigned_pipelined u_divider (
        .clk         (clk),
        .rst         (rst),
        .stall       (pipe_stall),
        .i_dividend  (div_launch_dividend),
        .i_divisor   (div_launch_divisor),
        .o_remainder (div_pipe_rem),
        .o_quotient  (div_pipe_quot)
    );

    wire div_result_valid = div_valid_q[7];
    wire [31:0] div_raw_result = div_want_rem_q[7] ?
                                 (div_sign_rem_q[7]  ? (~div_pipe_rem  + 32'd1) : div_pipe_rem) :
                                 (div_sign_quot_q[7] ? (~div_pipe_quot + 32'd1) : div_pipe_quot);
    wire [31:0] div_result_value = div_special_q[7] ? div_special_result_q[7] : div_raw_result;
    wire [127:0] div_result_name = div_name_q[7];

    wire [31:0] ex_result_for_mem = ex_alu_result;

    integer div_i;
    always @(posedge clk) begin
        if (rst) begin
            for (div_i = 0; div_i < 8; div_i = div_i + 1) begin
                div_valid_q[div_i] <= 1'b0;
                div_pc_q[div_i] <= 32'd0;
                div_insn_q[div_i] <= 32'h00000013;
                div_rd_q[div_i] <= 5'd0;
                div_funct3_q[div_i] <= 3'd0;
                div_sign_quot_q[div_i] <= 1'b0;
                div_sign_rem_q[div_i] <= 1'b0;
                div_want_rem_q[div_i] <= 1'b0;
                div_special_q[div_i] <= 1'b0;
                div_special_result_q[div_i] <= 32'd0;
                div_name_q[div_i] <= "RESET";
            end
        end else if (!halt_r && !pipe_stall) begin
            div_valid_q[0] <= div_issue_now;
            div_pc_q[0] <= if_id_pc;
            div_insn_q[0] <= if_id_insn;
            div_rd_q[0] <= id_rd;
            div_funct3_q[0] <= id_funct3;
            div_sign_quot_q[0] <= id_div_signed && (id_rs1_launch[31] ^ id_rs2_launch[31]);
            div_sign_rem_q[0] <= id_div_signed && id_rs1_launch[31];
            div_want_rem_q[0] <= id_div_want_rem;
            div_special_q[0] <= id_div_by_zero || id_div_overflow;
            div_special_result_q[0] <= id_div_by_zero ?
                ((id_funct3 == 3'b100 || id_funct3 == 3'b101) ? 32'hFFFF_FFFF : id_rs1_launch) :
                ((id_funct3 == 3'b100) ? 32'h8000_0000 : 32'd0);
            div_name_q[0] <= id_name;
            for (div_i = 1; div_i < 8; div_i = div_i + 1) begin
                div_valid_q[div_i] <= div_valid_q[div_i-1];
                div_pc_q[div_i] <= div_pc_q[div_i-1];
                div_insn_q[div_i] <= div_insn_q[div_i-1];
                div_rd_q[div_i] <= div_rd_q[div_i-1];
                div_funct3_q[div_i] <= div_funct3_q[div_i-1];
                div_sign_quot_q[div_i] <= div_sign_quot_q[div_i-1];
                div_sign_rem_q[div_i] <= div_sign_rem_q[div_i-1];
                div_want_rem_q[div_i] <= div_want_rem_q[div_i-1];
                div_special_q[div_i] <= div_special_q[div_i-1];
                div_special_result_q[div_i] <= div_special_result_q[div_i-1];
                div_name_q[div_i] <= div_name_q[div_i-1];
            end
        end
    end

    // -------------------------------------------------------------------------
    // MEM stage: data memory, load/store formatting
    // -------------------------------------------------------------------------
    wire [31:0] mem_store_wdata;
    wire [3:0]  mem_store_we_raw;

    load_unit u_load_unit (
        .dmem_rdata (dmem_rdata),
        .addr_lsb   (ex_mem_alu_result[1:0]),
        .funct3     (ex_mem_funct3),
        .load_data  (mem_load_data)
    );

    wire [31:0] mem_store_data_fwd =
        (ex_mem_valid && ex_mem_mem_write && mem_wb_valid && mem_wb_reg_write &&
         (mem_wb_rd != 5'd0) && (mem_wb_rd == ex_mem_rs2)) ? mem_wb_forward_value : ex_mem_store_data;

    store_unit u_store_unit (
        .rs2_value  (mem_store_data_fwd),
        .addr_lsb   (ex_mem_alu_result[1:0]),
        .funct3     (ex_mem_funct3),
        .store_en   (ex_mem_valid && ex_mem_mem_write),
        .store_data (mem_store_wdata),
        .store_we   (mem_store_we_raw)
    );

    assign dmem_valid = mem_access && !if_stall;
    assign dmem_addr  = ex_mem_alu_result;
    assign dmem_wdata = mem_store_wdata;
    assign dmem_we    = mem_store_we_raw;

    // -------------------------------------------------------------------------
    // Halt/illegal handling and debug
    // -------------------------------------------------------------------------
    assign halt = halt_r;
    assign illegal_insn = illegal_r;
    assign dbg_insn_name = dbg_name_r;

    assign trace_writeback_valid        = mem_wb_valid;
    assign trace_writeback_pc           = mem_wb_valid ? mem_wb_pc : 32'h0000_0000;
    assign trace_writeback_insn         = mem_wb_valid ? mem_wb_insn : 32'h0000_0000;
    assign trace_writeback_cycle_status = mem_wb_trace_status;
    assign trace_writeback_rd           = mem_wb_rd;
    assign trace_writeback_wdata        = wb_wdata;
    assign trace_writeback_reg_write    = wb_do_write;

    // ECALL/EBREAK/illegal instructions are committed when they reach WB, so
    // all older instructions have completed.  Once a system/illegal instruction
    // reaches EX, stop fetching and flush younger IF/ID and ID/EX work while the
    // system instruction drains through EX/MEM into MEM/WB.  This prevents the
    // instruction immediately before ECALL from being lost, and also prevents
    // younger instructions after ECALL from committing side effects.
    assign stop_for_system =
        (id_ex_valid  && (id_ex_system  || id_ex_illegal))  ||
        (ex_mem_valid && (ex_mem_system || ex_mem_illegal)) ||
        (mem_wb_valid && (mem_wb_system || mem_wb_illegal));

    // -------------------------------------------------------------------------
    // Sequential pipeline updates
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'h0000_0000;

            if_id_valid <= 1'b0;
            if_id_pc    <= 32'h0;
            if_id_pc4   <= 32'h0;
            if_id_insn  <= 32'h00000013;

            id_ex_valid <= 1'b0;
            id_ex_pc    <= 32'h0;
            id_ex_pc4   <= 32'h0;
            id_ex_insn  <= 32'h00000013;
            id_ex_imm   <= 32'h0;
            id_ex_rs1_val <= 32'h0;
            id_ex_rs2_val <= 32'h0;
            id_ex_rs1 <= 5'd0;
            id_ex_rs2 <= 5'd0;
            id_ex_rd  <= 5'd0;
            id_ex_funct3 <= 3'd0;
            id_ex_opcode <= 7'd0;
            id_ex_alu_ctrl <= 5'd0;
            id_ex_reg_write <= 1'b0;
            id_ex_mem_read <= 1'b0;
            id_ex_mem_write <= 1'b0;
            id_ex_branch <= 1'b0;
            id_ex_jump <= 1'b0;
            id_ex_jalr <= 1'b0;
            id_ex_alu_src_imm <= 1'b0;
            id_ex_alu_a_pc <= 1'b0;
            id_ex_wb_sel <= WB_ALU;
            id_ex_system <= 1'b0;
            id_ex_illegal <= 1'b0;
            id_ex_name <= "RESET";

            ex_mem_valid <= 1'b0;
            ex_mem_pc <= 32'h0;
            ex_mem_pc4 <= 32'h0;
            ex_mem_insn <= 32'h00000013;
            ex_mem_alu_result <= 32'h0;
            ex_mem_store_data <= 32'h0;
            ex_mem_imm <= 32'h0;
            ex_mem_rs1 <= 5'd0;
            ex_mem_rs2 <= 5'd0;
            ex_mem_rd <= 5'd0;
            ex_mem_funct3 <= 3'd0;
            ex_mem_reg_write <= 1'b0;
            ex_mem_mem_read <= 1'b0;
            ex_mem_mem_write <= 1'b0;
            ex_mem_wb_sel <= WB_ALU;
            ex_mem_system <= 1'b0;
            ex_mem_illegal <= 1'b0;
            ex_mem_name <= "RESET";

            mem_wb_valid <= 1'b0;
            mem_wb_pc <= 32'h0;
            mem_wb_pc4 <= 32'h0;
            mem_wb_insn <= 32'h00000013;
            mem_wb_alu_result <= 32'h0;
            mem_wb_load_data <= 32'h0;
            mem_wb_imm <= 32'h0;
            mem_wb_rd <= 5'd0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_wb_sel <= WB_ALU;
            mem_wb_trace_status <= TRACE_INVALID;
            mem_wb_system <= 1'b0;
            mem_wb_illegal <= 1'b0;
            mem_wb_name <= "RESET";

            halt_r <= 1'b0;
            illegal_r <= 1'b0;
            dbg_name_r <= "RESET";

        end else if (!halt_r) begin
            // Commit halt/illegal only at WB.  At this point all older
            // instructions have already reached WB/MEM and younger instructions
            // have been flushed by stop_for_system.
            if (mem_wb_valid && mem_wb_system) begin
                halt_r <= 1'b1;
                dbg_name_r <= mem_wb_name;
            end
            if (mem_wb_valid && mem_wb_illegal) begin
                illegal_r <= 1'b1;
                halt_r <= 1'b1;
                dbg_name_r <= mem_wb_name;
            end

            // PC update. Redirects win over normal fetch; load-use/divider/cache stalls hold PC.
            if (ex_redirect) begin
                pc <= ex_redirect_pc;
            end else if (!load_use_hazard && !div_stall_hazard && !pipe_stall && !stop_for_system) begin
                pc <= pc_plus4;
            end

            // IF/ID update.
            if (pipe_stall) begin
                // Hold IF/ID during an I-cache or D-cache miss.
            end else if (ex_redirect || stop_for_system) begin
                if_id_valid <= 1'b0;
                if_id_insn  <= 32'h00000013;
                if_id_pc    <= 32'h0;
                if_id_pc4   <= 32'h0;
            end else if (!load_use_hazard && !div_stall_hazard) begin
                if_id_valid <= 1'b1;
                if_id_pc    <= pc;
                if_id_pc4   <= pc_plus4;
                if_id_insn  <= imem_rdata;
            end
            // else hold IF/ID during load-use/divider stall.

            // ID/EX update. Redirect/load-use/system inserts a bubble. A cache
            // miss holds ID/EX and EX/MEM until the MEM-stage request completes.
            if (pipe_stall) begin
                // Hold ID/EX during an I-cache or D-cache miss.
            end else if (ex_redirect || load_use_hazard || div_stall_hazard || stop_for_system || div_issue_now) begin
                id_ex_valid <= 1'b0;
                id_ex_insn  <= 32'h00000013;
                id_ex_reg_write <= 1'b0;
                id_ex_mem_read <= 1'b0;
                id_ex_mem_write <= 1'b0;
                id_ex_branch <= 1'b0;
                id_ex_jump <= 1'b0;
                id_ex_jalr <= 1'b0;
                id_ex_system <= 1'b0;
                id_ex_illegal <= 1'b0;
                id_ex_name <= "BUBBLE";
            end else begin
                id_ex_valid <= if_id_valid;
                id_ex_pc    <= if_id_pc;
                id_ex_pc4   <= if_id_pc4;
                id_ex_insn  <= if_id_insn;
                id_ex_imm   <= id_imm;
                id_ex_rs1_val <= id_rs1_value;
                id_ex_rs2_val <= id_rs2_value;
                id_ex_rs1 <= id_rs1;
                id_ex_rs2 <= id_rs2;
                id_ex_rd  <= id_rd;
                id_ex_funct3 <= id_funct3;
                id_ex_opcode <= id_opcode;
                id_ex_alu_ctrl <= id_alu_ctrl;
                id_ex_reg_write <= id_reg_write && if_id_valid;
                id_ex_mem_read <= id_mem_read && if_id_valid;
                id_ex_mem_write <= id_mem_write && if_id_valid;
                id_ex_branch <= id_branch && if_id_valid;
                id_ex_jump <= id_jump && if_id_valid;
                id_ex_jalr <= id_jalr && if_id_valid;
                id_ex_alu_src_imm <= id_alu_src_imm;
                id_ex_alu_a_pc <= id_alu_a_pc;
                id_ex_wb_sel <= id_wb_sel;
                id_ex_system <= id_system && if_id_valid;
                id_ex_illegal <= id_illegal && if_id_valid;
                id_ex_name <= id_name;
            end

            // EX/MEM update. Divider results re-enter the normal in-order
            // commit path here.  Non-DIV instructions are interlocked while the
            // divider pipe drains, so div_result_valid should not conflict with
            // a real EX-stage instruction.
            if (pipe_stall) begin
                // Hold EX/MEM while an I-cache or D-cache miss is pending;
                // load/store requests remain stable until the D-cache responds.
            end else if (div_result_valid) begin
                ex_mem_valid <= 1'b1;
                ex_mem_pc <= div_pc_q[7];
                ex_mem_pc4 <= div_pc_q[7] + 32'd4;
                ex_mem_insn <= div_insn_q[7];
                ex_mem_alu_result <= div_result_value;
                ex_mem_store_data <= 32'd0;
                ex_mem_imm <= 32'd0;
                ex_mem_rs1 <= 5'd0;
                ex_mem_rs2 <= 5'd0;
                ex_mem_rd <= div_rd_q[7];
                ex_mem_funct3 <= div_funct3_q[7];
                ex_mem_reg_write <= (div_rd_q[7] != 5'd0);
                ex_mem_mem_read <= 1'b0;
                ex_mem_mem_write <= 1'b0;
                ex_mem_wb_sel <= WB_ALU;
                ex_mem_system <= 1'b0;
                ex_mem_illegal <= 1'b0;
                ex_mem_name <= div_result_name;
            end else begin
                ex_mem_valid <= id_ex_valid;
                ex_mem_pc <= id_ex_pc;
                ex_mem_pc4 <= id_ex_pc4;
                ex_mem_insn <= id_ex_insn;
                ex_mem_alu_result <= ex_result_for_mem;
                ex_mem_store_data <= ex_rs2_fwd;
                ex_mem_imm <= id_ex_imm;
                ex_mem_rs1 <= id_ex_rs1;
                ex_mem_rs2 <= id_ex_rs2;
                ex_mem_rd <= id_ex_rd;
                ex_mem_funct3 <= id_ex_funct3;
                ex_mem_reg_write <= id_ex_reg_write && id_ex_valid;
                ex_mem_mem_read <= id_ex_mem_read && id_ex_valid;
                ex_mem_mem_write <= id_ex_mem_write && id_ex_valid;
                ex_mem_wb_sel <= id_ex_wb_sel;
                ex_mem_system <= id_ex_system && id_ex_valid;
                ex_mem_illegal <= id_ex_illegal && id_ex_valid;
                ex_mem_name <= id_ex_name;
            end

            // MEM/WB update.
            if (pipe_stall) begin
                // Hold MEM/WB stable while either cache is stalling.
                //
                // This is important for correctness: a younger instruction may
                // already be sitting in ID/EX with operands captured before an
                // older load wrote back.  During a long cache miss, that older
                // load must remain visible on the MEM/WB forwarding path.
                // Rewriting the same architectural register is harmless, and
                // preserving MEM/WB prevents stale operand use after the stall
                // releases.
                mem_wb_valid <= mem_wb_valid;
                mem_wb_pc <= mem_wb_pc;
                mem_wb_pc4 <= mem_wb_pc4;
                mem_wb_insn <= mem_wb_insn;
                mem_wb_alu_result <= mem_wb_alu_result;
                mem_wb_load_data <= mem_wb_load_data;
                mem_wb_imm <= mem_wb_imm;
                mem_wb_rd <= mem_wb_rd;
                mem_wb_reg_write <= mem_wb_reg_write;
                mem_wb_wb_sel <= mem_wb_wb_sel;
                mem_wb_trace_status <= TRACE_MEMSTALL;
                mem_wb_system <= mem_wb_system;
                mem_wb_illegal <= mem_wb_illegal;
                mem_wb_name <= mem_wb_name;
            end else begin
                mem_wb_valid <= ex_mem_valid;
                mem_wb_pc <= ex_mem_pc;
                mem_wb_pc4 <= ex_mem_pc4;
                mem_wb_insn <= ex_mem_insn;
                mem_wb_alu_result <= ex_mem_alu_result;
                mem_wb_load_data <= mem_load_data;
                mem_wb_imm <= ex_mem_imm;
                mem_wb_rd <= ex_mem_rd;
                mem_wb_reg_write <= ex_mem_reg_write && ex_mem_valid;
                mem_wb_wb_sel <= ex_mem_wb_sel;
                mem_wb_trace_status <= ex_mem_valid ? (ex_mem_system || ex_mem_illegal ? TRACE_HALT : TRACE_OK) :
                                        (div_any_active ? TRACE_DIV :
                                         (load_use_hazard ? TRACE_LOADUSE : TRACE_INVALID));
                mem_wb_system <= ex_mem_system && ex_mem_valid;
                mem_wb_illegal <= ex_mem_illegal && ex_mem_valid;
                mem_wb_name <= ex_mem_name;
            end

            // Default debug name follows the EX-stage instruction.
            if (!id_ex_system && !id_ex_illegal) begin
                dbg_name_r <= id_ex_name;
            end
        end
    end

endmodule
