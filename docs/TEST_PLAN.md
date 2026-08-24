# Test Plan

The package includes a layered set of regressions that bring up the CPU from basic pipeline behavior through the final AXI-Lite cached-memory system.

## Core pipeline tests

```bash
make run-vcs-directed
make run-vcs-extended
make run-vcs-hazard
make run-vcs-riscv-isa
make run-vcs-dhrystone
```

These tests cover:

- RV32I arithmetic, logic, load/store, branch, and jump behavior
- RV32M multiply/divide/remainder behavior
- EX/MEM and MEM/WB forwarding
- WB-to-ID bypass
- load-use stalls
- store-data forwarding
- branch/jump flushes
- divider dependency interlocks
- Dhrystone compiled-code execution
- 46 RV32I/RV32M ISA regression programs

## Cache tests

Simple internal-memory D-cache checkpoint:

```bash
make run-vcs-cache
make run-vcs-cache-dhrystone
```

AXI-Lite D-cache checkpoint:

```bash
make run-vcs-axil-cache
make run-vcs-axil-cache-dhrystone
```

Final AXI-Lite I-cache + D-cache checkpoint:

```bash
make run-vcs-axil-icache
make run-vcs-axil-icache-dhrystone
```

The cache tests check:

- cache hits and misses
- direct-map conflicts
- dirty victim writeback
- write-allocate behavior
- byte-enabled stores
- pipeline stalls during memory misses
- Dhrystone execution through cached instruction and data memory

## Full regression

```bash
make run-vcs-all
```
