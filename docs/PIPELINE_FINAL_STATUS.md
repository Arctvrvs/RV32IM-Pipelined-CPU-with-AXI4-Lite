# Final Status

This is the final RV32IM five-stage pipelined CPU checkpoint with a split AXI-Lite instruction/data cache hierarchy.

## Implemented CPU behavior

- RV32I base integer instructions
- RV32M multiply/divide/remainder instructions
- Five pipeline stages: IF, ID, EX, MEM, WB
- EX/MEM and MEM/WB forwarding into EX
- WB-to-ID bypass
- Load-use hazard detection and stalling
- Store-data forwarding for load-to-store and ALU-to-store cases
- Branch, JAL, and JALR flush handling
- ECALL/EBREAK halt at writeback so older instructions retire first
- 8-stage pipelined divider for DIV, DIVU, REM, and REMU
- Writeback trace/debug outputs for waveform inspection
- Instruction-side `imem_valid/imem_ready` stall interface
- Data-side `dmem_valid/dmem_ready` stall interface

## Implemented cache/memory behavior

- AXI-Lite direct-mapped read-only I-cache
- AXI-Lite direct-mapped write-back/write-allocate D-cache
- Dirty victim writeback for D-cache conflicts
- Blocking cache-miss handling
- Pipeline stalls during I-cache and D-cache misses
- AXI-Lite instruction backing-memory model
- AXI-Lite data backing-memory model
- Cache access/hit/miss/writeback counters

## Verification status

Validated on Synopsys VCS:

```text
Directed architectural test: PASS
Extended RV32IM test: PASS
Pipeline hazard/divider regression: PASS
RISC-V ISA regression: PASS=46 FAIL=0
Dhrystone benchmark without cache: PASS, x5 = 0x003fffff
AXI-Lite D-cache conflict/write-back test: PASS
AXI-Lite I-cache + D-cache conflict/write-back test: PASS
Dhrystone with AXI-Lite D-cache: PASS, x5 = 0x003fffff
Dhrystone with AXI-Lite I-cache + D-cache: PASS, x5 = 0x003fffff
```

Final cached Dhrystone result:

```text
AXI-Lite I-cache + D-cache Dhrystone: PASS after 1,365,924 cycles
I-cache accesses = 368,993, hits = 226,574, misses = 142,419
D-cache accesses = 79,394, hits = 68,740, misses = 10,654, writebacks = 6,056
```
