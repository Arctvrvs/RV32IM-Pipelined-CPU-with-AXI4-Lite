# Pipeline Architecture

The core is a classic in-order five-stage RV32IM pipeline:

```text
IF -> ID -> EX -> MEM -> WB
```

## IF

The IF stage holds the PC and reads instruction memory. The PC normally increments by 4. If EX resolves a taken branch or jump, the PC redirects to the branch/JAL/JALR target.

## ID

The ID stage decodes the instruction, reads the register file, generates immediates, and creates control signals. The pipeline also detects load-use hazards here and stalls IF/ID while inserting a bubble into ID/EX.

## EX

The EX stage performs ALU work, branch comparisons, JAL/JALR target calculation, and store-data forwarding. Forwarding paths supply operands from EX/MEM and MEM/WB.

## MEM

The MEM stage drives the data-memory interface. Loads use `load_unit` for byte/halfword extraction and sign/zero extension. Stores use `store_unit` for byte-lane write enables and shifted write data. In the cache version, this interface includes `dmem_valid` and `dmem_ready`; a D-cache miss holds the MEM-stage instruction and stalls younger pipeline stages until the cache responds.

## WB

The WB stage writes the selected result to the register file. Sources include ALU result, load data, PC+4, and U-type immediate.

## Hazards

Implemented:

- EX/MEM -> EX forwarding for non-load results
- MEM/WB -> EX forwarding for ALU/load/PC+4/IMM results
- WB -> ID bypass for same-cycle register write/read
- load-use interlock
- control-hazard flush on taken branch/JAL/JALR

System-level features intentionally out of scope:

- branch prediction
- memory disambiguation
- nonblocking data cache
- out-of-order execution

The core itself uses instruction- and data-side `valid`/`ready` ports rather
than exposing AXI4-Lite directly. In the final repository checkpoint, those
ports connect to the blocking AXI4-Lite I-cache and D-cache described in
[`AXIL_ICACHE_DCACHE_ARCHITECTURE.md`](AXIL_ICACHE_DCACHE_ARCHITECTURE.md).
