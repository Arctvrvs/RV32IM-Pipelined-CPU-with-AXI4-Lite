# Program and benchmark fixtures

This directory contains prebuilt memory images used by the simulation
testbenches. They are checked in so the RTL regressions can run without a
RISC-V compiler toolchain.

## Repository-specific fixtures

- `example.hex` is the basic smoke-test program.
- `directed.hex` and `directed.lst` drive the directed RV32I checks.
- `rv32im_extended.hex` and `rv32im_extended.lst` cover broader RV32IM behavior.
- `pipeline_hazard.hex` and `pipeline_hazard.lst` stress pipeline hazards.
- `cache_test.hex` and `cache_test.lst` force cache conflicts and writebacks.

## RISC-V ISA fixtures

The files below `riscv_isa/` use the `rv32ui-p-*` and `rv32um-p-*` names from
the upstream [riscv-tests](https://github.com/riscv-software-src/riscv-tests)
project. Each enabled test has separate instruction/data HEX images plus a
disassembly dump and section map. The three test-list files select all 46
enabled programs or the RV32I and RV32M subsets.

The original source revision, compiler version, and conversion command were not
recorded with these generated files. Treat them as fixed regression fixtures;
a reproducible regeneration flow should pin those details before replacing
them. The upstream source and its license are available in the
[riscv-tests repository](https://github.com/riscv-software-src/riscv-tests/blob/master/LICENSE).

`rv32ui-p-fence_i` is excluded because the core has no instruction-cache
invalidate or self-modifying-code synchronization path. `rv32ui-p-ma_data` is
excluded because misaligned accesses are neither supported nor trapped.

## Dhrystone fixture

`dhrystone_imem.hex`, `dhrystone_dmem.hex`, and `dhrystone.riscv.dump` are
preconverted benchmark artifacts. `dhrystone_sections.txt` records that the ELF
came from `riscv-tests/benchmarks/dhrystone.riscv` and that simulation
remaps the ELF base address from `0x80000000` to `0x00000000`.

The exact upstream revision and compiler configuration are not present in this
repository, so the recorded cycle count is a functional testbench result, not a
portable Dhrystone/DMIPS performance claim.

## Redistribution

Before a public release, confirm the exact origin of the converted fixtures and
include every license and notice required by that source revision. This file
documents the evidence currently present in the repository; it does not grant a
license for the processor RTL.
