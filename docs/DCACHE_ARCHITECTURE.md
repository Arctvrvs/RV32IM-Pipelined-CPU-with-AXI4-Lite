# Blocking Direct-Mapped D-Cache

This package adds a blocking direct-mapped write-back data cache to the RV32IM pipelined CPU.

## CPU/cache interface

The CPU data-memory interface is now:

```verilog
output wire        dmem_valid;
output wire [31:0] dmem_addr;
output wire [31:0] dmem_wdata;
output wire [3:0]  dmem_we;
input  wire [31:0] dmem_rdata;
input  wire        dmem_ready;
```

`dmem_valid` is asserted when the MEM stage holds a load or store. `dmem_we == 0` means load; nonzero byte enables mean store. If `dmem_ready` is low, the pipeline holds PC, IF/ID, ID/EX, and EX/MEM until the memory request completes.

## Cache organization

`rtl/direct_mapped_dcache.v` implements:

```text
Direct-mapped placement
One 32-bit word per line
Write-back
Write-allocate
Byte write enables
Dirty-bit victim writeback
Blocking miss handling
```

A miss is handled by holding `cpu_ready=0`, optionally writing back a dirty victim, refilling the requested line from the internal backing memory, performing the load/store, and then asserting `cpu_ready=1` for one response cycle.

## Why blocking first?

A blocking cache is the right first cache for this CPU because it tests the important architectural behavior without adding out-of-order memory complexity:

```text
cache hit  -> MEM stage completes normally
cache miss -> whole in-order pipeline stalls until data is ready
```

That is the correct stepping stone before a more complex AXI-Lite cache, split I-cache/D-cache system, or nonblocking cache.

## Tests

`tb/tb_pipeline_cache.v` uses a four-line cache and intentionally accesses addresses 0 and 16, which map to the same cache index. This forces conflict misses and checks that a dirty line is written back correctly.

`tb/tb_pipeline_cache_dhrystone.v` runs the Dhrystone benchmark with a larger D-cache and verifies the same success signature as the non-cache benchmark:

```text
x5 = 0x003fffff
```
