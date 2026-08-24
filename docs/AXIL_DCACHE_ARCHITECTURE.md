# AXI-Lite D-Cache Architecture

> **Checkpoint note:** This document describes the D-cache-only integration
> stage retained for regression and teaching purposes. The final system adds a
> separate AXI4-Lite I-cache as described in
> [`AXIL_ICACHE_DCACHE_ARCHITECTURE.md`](AXIL_ICACHE_DCACHE_ARCHITECTURE.md).

This version upgrades the previous internal-memory teaching cache into an AXI4-Lite-backed data cache.

## Memory hierarchy

```text
RV32IM pipeline MEM stage
    |
    | simple valid/ready CPU-side request
    v
axil_direct_mapped_dcache
    |
    | AXI4-Lite manager port
    v
axil_memory backing memory model
```

## Cache organization

```text
mapping:        direct mapped
line size:      1 word / 4 bytes
write policy:   write-back
write miss:     write-allocate
replacement:    direct-map victim
miss behavior:  blocking
```

Each line stores:

```text
valid bit
dirty bit
tag
data word
```

## CPU-side protocol

The CPU uses the same memory-stage interface as the simple D-cache:

```verilog
cpu_valid
cpu_addr
cpu_wdata
cpu_we
cpu_rdata
cpu_ready
```

When `cpu_ready` is low, the MEM stage holds the memory instruction and the rest of the pipeline stalls behind it.

## AXI-Lite side

The cache drives a standard AXI-Lite manager interface:

```text
ARADDR / ARVALID / ARREADY
RDATA  / RVALID  / RREADY
AWADDR / AWVALID / AWREADY
WDATA  / WSTRB   / WVALID / WREADY
BVALID / BREADY
```

On a clean miss, the cache issues an AXI-Lite read to refill the line.

On a dirty victim miss, the cache first writes the victim word back through AXI-Lite AW/W/B, then issues an AXI-Lite read to refill the requested line.

## Testbenches

```text
tb/tb_pipeline_axil_cache.v
    Runs a small conflict test that forces a dirty eviction and verifies that
    the dirty victim reaches AXI memory.

tb/tb_pipeline_axil_cache_dhrystone.v
    Runs Dhrystone using the AXI-Lite D-cache and checks x5=0x003fffff.
```

## Difference from the simple D-cache

The older `direct_mapped_dcache.v` contains its own backing memory internally.  The AXI-Lite cache separates cache behavior from memory behavior.  This is closer to a real SoC memory hierarchy because the cache must obey external bus handshakes instead of directly reading an internal array.

## Checkpoint limitation

At this checkpoint, the instruction side still uses the simple instruction
memory. The final integration in this repository adds an instruction-side cache
and uses `imem_valid`/`imem_ready` to stall fetch during I-cache misses.
