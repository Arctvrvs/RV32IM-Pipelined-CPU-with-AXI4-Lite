# RV32IM five-stage pipelined CPU simulation targets
#
# Quick start with Synopsys VCS:
#   make run-vcs-basic
#   make run-vcs-directed
#   make run-vcs-extended
#   make run-vcs-dhrystone
#   make run-vcs-riscv-isa
#   make run-vcs-cache
#   make run-vcs-cache-dhrystone
#   make run-vcs-axil-cache
#   make run-vcs-axil-cache-dhrystone
#   make run-vcs-axil-icache
#   make run-vcs-axil-icache-dhrystone
#
# Run all major tests:
#   make run-vcs-all

IVERILOG ?= iverilog
VVP      ?= vvp
VCS      ?= vcs
BUILD    ?= build
HEX      ?= programs/example.hex
ISA_TIMEOUT ?= 200000
TEST ?= rv32ui-p-simple

RTL = rtl/regfile.v \
      rtl/alu.v \
      rtl/alu_control.v \
      rtl/imm_gen.v \
      rtl/branch_unit.v \
      rtl/load_unit.v \
      rtl/store_unit.v \
      rtl/divider_unsigned_pipelined.v \
      rtl/rv32im_pipeline.v

RTL_CACHE = $(RTL) rtl/direct_mapped_dcache.v
RTL_AXIL_CACHE = $(RTL) rtl/axil_direct_mapped_dcache.v rtl/axil_memory.v
RTL_AXIL_ICACHE = $(RTL_AXIL_CACHE) rtl/axil_direct_mapped_icache.v rtl/axil_imemory.v

TB_COMMON = tb/simple_imem.v tb/simple_dmem.v

.PHONY: \
    sim-ci sim-basic sim-directed sim-extended sim-dhrystone sim-hazard sim-cache sim-cache-dhrystone sim-axil-cache sim-axil-cache-dhrystone sim-axil-icache sim-axil-icache-dhrystone \
    vcs-basic run-vcs-basic \
    vcs-directed run-vcs-directed \
    vcs-extended run-vcs-extended \
    vcs-dhrystone run-vcs-dhrystone \
    vcs-hazard run-vcs-hazard \
    vcs-cache run-vcs-cache vcs-cache-dhrystone run-vcs-cache-dhrystone \
    vcs-axil-cache run-vcs-axil-cache vcs-axil-cache-dhrystone run-vcs-axil-cache-dhrystone vcs-axil-icache run-vcs-axil-icache vcs-axil-icache-dhrystone run-vcs-axil-icache-dhrystone \
    vcs-riscv-isa run-vcs-riscv-isa run-vcs-riscv-ui run-vcs-riscv-um run-vcs-riscv-isa-one \
    run-vcs-all clean

sim-ci: sim-basic sim-directed sim-extended sim-hazard sim-cache sim-axil-cache sim-axil-icache

sim-basic:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/pipeline_basic_tb $(RTL) $(TB_COMMON) tb/tb_pipeline_basic.v
	$(VVP) $(BUILD)/pipeline_basic_tb +HEX=$(HEX)

sim-directed:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/pipeline_directed_tb $(RTL) $(TB_COMMON) tb/tb_pipeline_directed.v
	$(VVP) $(BUILD)/pipeline_directed_tb +HEX=programs/directed.hex

sim-extended:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/pipeline_extended_tb $(RTL) $(TB_COMMON) tb/tb_pipeline_extended.v
	$(VVP) $(BUILD)/pipeline_extended_tb +HEX=programs/rv32im_extended.hex

sim-dhrystone:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/pipeline_dhrystone_tb $(RTL) $(TB_COMMON) tb/tb_pipeline_dhrystone.v
	$(VVP) $(BUILD)/pipeline_dhrystone_tb +HEX=programs/dhrystone_imem.hex +DMEM_HEX=programs/dhrystone_dmem.hex

sim-hazard:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/pipeline_hazard_tb $(RTL) $(TB_COMMON) tb/tb_pipeline_hazard.v
	$(VVP) $(BUILD)/pipeline_hazard_tb +HEX=programs/pipeline_hazard.hex

sim-cache:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/pipeline_cache_tb $(RTL_CACHE) tb/simple_imem.v tb/tb_pipeline_cache.v
	$(VVP) $(BUILD)/pipeline_cache_tb +HEX=programs/cache_test.hex

sim-cache-dhrystone:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/pipeline_cache_dhrystone_tb $(RTL_CACHE) tb/simple_imem.v tb/tb_pipeline_cache_dhrystone.v
	$(VVP) $(BUILD)/pipeline_cache_dhrystone_tb +HEX=programs/dhrystone_imem.hex +DMEM_HEX=programs/dhrystone_dmem.hex

sim-axil-cache:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/pipeline_axil_cache_tb $(RTL_AXIL_CACHE) tb/simple_imem.v tb/tb_pipeline_axil_cache.v
	$(VVP) $(BUILD)/pipeline_axil_cache_tb +HEX=programs/cache_test.hex

sim-axil-cache-dhrystone:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/pipeline_axil_cache_dhrystone_tb $(RTL_AXIL_CACHE) tb/simple_imem.v tb/tb_pipeline_axil_cache_dhrystone.v
	$(VVP) $(BUILD)/pipeline_axil_cache_dhrystone_tb +HEX=programs/dhrystone_imem.hex +DMEM_HEX=programs/dhrystone_dmem.hex

sim-axil-icache:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/pipeline_axil_icache_tb $(RTL_AXIL_ICACHE) tb/tb_pipeline_axil_icache.v
	$(VVP) $(BUILD)/pipeline_axil_icache_tb +IMEM_HEX=programs/cache_test.hex

sim-axil-icache-dhrystone:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/pipeline_axil_icache_dhrystone_tb $(RTL_AXIL_ICACHE) tb/tb_pipeline_axil_icache_dhrystone.v
	$(VVP) $(BUILD)/pipeline_axil_icache_dhrystone_tb +IMEM_HEX=programs/dhrystone_imem.hex +DMEM_HEX=programs/dhrystone_dmem.hex

vcs-basic:
	mkdir -p $(BUILD)
	$(VCS) -full64 -sverilog -kdb -timescale=1ns/1ps \
	    -debug_access+all \
	    -top tb_pipeline_basic \
	    -o $(BUILD)/simv_pipeline_basic \
	    -Mdir=$(BUILD)/csrc_pipeline_basic \
	    -l $(BUILD)/compile_pipeline_basic.log \
	    -f filelist_pipeline_basic.f

run-vcs-basic: vcs-basic
	./$(BUILD)/simv_pipeline_basic +HEX=$(HEX) -l $(BUILD)/run_pipeline_basic.log -no_save

vcs-directed:
	mkdir -p $(BUILD)
	$(VCS) -full64 -sverilog -kdb -timescale=1ns/1ps \
	    -debug_access+all \
	    -top tb_pipeline_directed \
	    -o $(BUILD)/simv_pipeline_directed \
	    -Mdir=$(BUILD)/csrc_pipeline_directed \
	    -l $(BUILD)/compile_pipeline_directed.log \
	    -f filelist_pipeline_directed.f

run-vcs-directed: vcs-directed
	./$(BUILD)/simv_pipeline_directed +HEX=programs/directed.hex -l $(BUILD)/run_pipeline_directed.log -no_save

vcs-extended:
	mkdir -p $(BUILD)
	$(VCS) -full64 -sverilog -kdb -timescale=1ns/1ps \
	    -debug_access+all \
	    -top tb_pipeline_extended \
	    -o $(BUILD)/simv_pipeline_extended \
	    -Mdir=$(BUILD)/csrc_pipeline_extended \
	    -l $(BUILD)/compile_pipeline_extended.log \
	    -f filelist_pipeline_extended.f

run-vcs-extended: vcs-extended
	./$(BUILD)/simv_pipeline_extended +HEX=programs/rv32im_extended.hex -l $(BUILD)/run_pipeline_extended.log -no_save

vcs-dhrystone:
	mkdir -p $(BUILD)
	$(VCS) -full64 -sverilog -kdb -timescale=1ns/1ps \
	    -debug_access+all \
	    -top tb_pipeline_dhrystone \
	    -o $(BUILD)/simv_pipeline_dhrystone \
	    -Mdir=$(BUILD)/csrc_pipeline_dhrystone \
	    -l $(BUILD)/compile_pipeline_dhrystone.log \
	    -f filelist_pipeline_dhrystone.f

run-vcs-dhrystone: vcs-dhrystone
	./$(BUILD)/simv_pipeline_dhrystone +HEX=programs/dhrystone_imem.hex +DMEM_HEX=programs/dhrystone_dmem.hex -l $(BUILD)/run_pipeline_dhrystone.log -no_save

vcs-hazard:
	mkdir -p $(BUILD)
	$(VCS) -full64 -sverilog -kdb -timescale=1ns/1ps \
	    -debug_access+all \
	    -top tb_pipeline_hazard \
	    -o $(BUILD)/simv_pipeline_hazard \
	    -Mdir=$(BUILD)/csrc_pipeline_hazard \
	    -l $(BUILD)/compile_pipeline_hazard.log \
	    -f filelist_pipeline_hazard.f

run-vcs-hazard: vcs-hazard
	./$(BUILD)/simv_pipeline_hazard +HEX=programs/pipeline_hazard.hex -l $(BUILD)/run_pipeline_hazard.log -no_save

vcs-cache:
	mkdir -p $(BUILD)
	$(VCS) -full64 -sverilog -kdb -timescale=1ns/1ps \
	    -debug_access+all \
	    -top tb_pipeline_cache \
	    -o $(BUILD)/simv_pipeline_cache \
	    -Mdir=$(BUILD)/csrc_pipeline_cache \
	    -l $(BUILD)/compile_pipeline_cache.log \
	    -f filelist_pipeline_cache.f

run-vcs-cache: vcs-cache
	./$(BUILD)/simv_pipeline_cache +HEX=programs/cache_test.hex -l $(BUILD)/run_pipeline_cache.log -no_save

vcs-cache-dhrystone:
	mkdir -p $(BUILD)
	$(VCS) -full64 -sverilog -kdb -timescale=1ns/1ps \
	    -debug_access+all \
	    -top tb_pipeline_cache_dhrystone \
	    -o $(BUILD)/simv_pipeline_cache_dhrystone \
	    -Mdir=$(BUILD)/csrc_pipeline_cache_dhrystone \
	    -l $(BUILD)/compile_pipeline_cache_dhrystone.log \
	    -f filelist_pipeline_cache_dhrystone.f

run-vcs-cache-dhrystone: vcs-cache-dhrystone
	./$(BUILD)/simv_pipeline_cache_dhrystone +HEX=programs/dhrystone_imem.hex +DMEM_HEX=programs/dhrystone_dmem.hex -l $(BUILD)/run_pipeline_cache_dhrystone.log -no_save

vcs-axil-cache:
	mkdir -p $(BUILD)
	$(VCS) -full64 -sverilog -kdb -timescale=1ns/1ps \
	    -debug_access+all \
	    -top tb_pipeline_axil_cache \
	    -o $(BUILD)/simv_pipeline_axil_cache \
	    -Mdir=$(BUILD)/csrc_pipeline_axil_cache \
	    -l $(BUILD)/compile_pipeline_axil_cache.log \
	    -f filelist_pipeline_axil_cache.f

run-vcs-axil-cache: vcs-axil-cache
	./$(BUILD)/simv_pipeline_axil_cache +HEX=programs/cache_test.hex -l $(BUILD)/run_pipeline_axil_cache.log -no_save

vcs-axil-cache-dhrystone:
	mkdir -p $(BUILD)
	$(VCS) -full64 -sverilog -kdb -timescale=1ns/1ps \
	    -debug_access+all \
	    -top tb_pipeline_axil_cache_dhrystone \
	    -o $(BUILD)/simv_pipeline_axil_cache_dhrystone \
	    -Mdir=$(BUILD)/csrc_pipeline_axil_cache_dhrystone \
	    -l $(BUILD)/compile_pipeline_axil_cache_dhrystone.log \
	    -f filelist_pipeline_axil_cache_dhrystone.f

run-vcs-axil-cache-dhrystone: vcs-axil-cache-dhrystone
	./$(BUILD)/simv_pipeline_axil_cache_dhrystone +HEX=programs/dhrystone_imem.hex +DMEM_HEX=programs/dhrystone_dmem.hex -l $(BUILD)/run_pipeline_axil_cache_dhrystone.log -no_save

vcs-axil-icache:
	mkdir -p $(BUILD)
	$(VCS) -full64 -sverilog -kdb -timescale=1ns/1ps \
	    -debug_access+all \
	    -top tb_pipeline_axil_icache \
	    -o $(BUILD)/simv_pipeline_axil_icache \
	    -Mdir=$(BUILD)/csrc_pipeline_axil_icache \
	    -l $(BUILD)/compile_pipeline_axil_icache.log \
	    -f filelist_pipeline_axil_icache.f

run-vcs-axil-icache: vcs-axil-icache
	./$(BUILD)/simv_pipeline_axil_icache +IMEM_HEX=programs/cache_test.hex -l $(BUILD)/run_pipeline_axil_icache.log -no_save

vcs-axil-icache-dhrystone:
	mkdir -p $(BUILD)
	$(VCS) -full64 -sverilog -kdb -timescale=1ns/1ps \
	    -debug_access+all \
	    -top tb_pipeline_axil_icache_dhrystone \
	    -o $(BUILD)/simv_pipeline_axil_icache_dhrystone \
	    -Mdir=$(BUILD)/csrc_pipeline_axil_icache_dhrystone \
	    -l $(BUILD)/compile_pipeline_axil_icache_dhrystone.log \
	    -f filelist_pipeline_axil_icache_dhrystone.f

run-vcs-axil-icache-dhrystone: vcs-axil-icache-dhrystone
	./$(BUILD)/simv_pipeline_axil_icache_dhrystone +IMEM_HEX=programs/dhrystone_imem.hex +DMEM_HEX=programs/dhrystone_dmem.hex -l $(BUILD)/run_pipeline_axil_icache_dhrystone.log -no_save

vcs-riscv-isa:
	mkdir -p $(BUILD)
	$(VCS) -full64 -sverilog -kdb -timescale=1ns/1ps \
	    -debug_access+all \
	    -top tb_pipeline_riscv_isa \
	    -o $(BUILD)/simv_pipeline_riscv_isa \
	    -Mdir=$(BUILD)/csrc_pipeline_riscv_isa \
	    -l $(BUILD)/compile_pipeline_riscv_isa.log \
	    -f filelist_pipeline_riscv_isa.f

run-vcs-riscv-isa-one: vcs-riscv-isa
	./$(BUILD)/simv_pipeline_riscv_isa \
	    +TESTNAME=$(TEST) \
	    +HEX=programs/riscv_isa/$(TEST)_imem.hex \
	    +DMEM_HEX=programs/riscv_isa/$(TEST)_dmem.hex \
	    +TIMEOUT=$(ISA_TIMEOUT) \
	    -l $(BUILD)/run_pipeline_$(TEST).log \
	    -no_save

run-vcs-riscv-isa: vcs-riscv-isa
	SIM=$(BUILD)/simv_pipeline_riscv_isa LOGDIR=$(BUILD)/pipeline_riscv_isa_logs TIMEOUT=$(ISA_TIMEOUT) bash scripts/run_isa_tests.sh programs/riscv_isa/testlist.txt

run-vcs-riscv-ui: vcs-riscv-isa
	SIM=$(BUILD)/simv_pipeline_riscv_isa LOGDIR=$(BUILD)/pipeline_riscv_isa_logs TIMEOUT=$(ISA_TIMEOUT) bash scripts/run_isa_tests.sh programs/riscv_isa/testlist_rv32ui.txt

run-vcs-riscv-um: vcs-riscv-isa
	SIM=$(BUILD)/simv_pipeline_riscv_isa LOGDIR=$(BUILD)/pipeline_riscv_isa_logs TIMEOUT=$(ISA_TIMEOUT) bash scripts/run_isa_tests.sh programs/riscv_isa/testlist_rv32um.txt

run-vcs-all: run-vcs-basic run-vcs-directed run-vcs-extended run-vcs-hazard run-vcs-dhrystone run-vcs-riscv-isa run-vcs-cache run-vcs-cache-dhrystone run-vcs-axil-cache run-vcs-axil-cache-dhrystone run-vcs-axil-icache run-vcs-axil-icache-dhrystone

clean:
	rm -rf $(BUILD) csrc simv simv.daidir ucli.key novas.* verdiLog *.vcd *.fsdb *.log
