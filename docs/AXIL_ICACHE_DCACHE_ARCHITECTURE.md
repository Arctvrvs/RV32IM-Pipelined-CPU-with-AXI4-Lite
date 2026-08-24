# AXI-Lite I-cache + D-cache Architecture

This package implements the final split-cache memory system for the RV32IM five-stage pipelined CPU.

## Memory hierarchy

```text
CPU IF stage
  -> imem_valid/imem_ready fetch interface
  -> AXI-Lite direct-mapped read-only I-cache
  -> AXI-Lite instruction backing memory

CPU MEM stage
  -> dmem_valid/dmem_ready load/store interface
  -> AXI-Lite direct-mapped write-back D-cache
  -> AXI-Lite data backing memory
```

The I-cache and D-cache are separate. This keeps the core simple and models a
basic Harvard-style L1 cache structure.

## I-cache behavior

The new `axil_direct_mapped_icache.v` module is:

- direct mapped
- one 32-bit instruction word per line
- read-only
- blocking
- AXI4-Lite read-refill backed
- instrumented with access, hit, and miss counters

On an I-cache hit, the requested instruction is returned immediately. On a miss,
the cache sends an AXI-Lite read request, fills the line, returns the instruction,
and releases `imem_ready`.

## Pipeline stall behavior

The CPU now has an instruction fetch valid/ready interface:

```verilog
output wire        imem_valid;
output wire [31:0] imem_addr;
input  wire [31:0] imem_rdata;
input  wire        imem_ready;
```

If `imem_ready` is low, the pipeline is held until the I-cache miss completes.
The data memory request is gated while an I-cache miss is active so the D-cache
does not repeatedly accept the same held MEM-stage request.

The existing data-side cache stall behavior is preserved:

```verilog
output wire        dmem_valid;
input  wire        dmem_ready;
```

## New files

```text
rtl/axil_direct_mapped_icache.v
rtl/axil_imemory.v
tb/tb_pipeline_axil_icache.v
tb/tb_pipeline_axil_icache_dhrystone.v
filelist_pipeline_axil_icache.f
filelist_pipeline_axil_icache_dhrystone.f
```

## New Makefile targets

```bash
make run-vcs-axil-icache
make run-vcs-axil-icache-dhrystone
```

## Recommended regression order

```bash
make clean
make run-vcs-directed
make run-vcs-extended
make run-vcs-hazard
make run-vcs-riscv-isa
make run-vcs-dhrystone
make run-vcs-axil-cache
make run-vcs-axil-cache-dhrystone
make run-vcs-axil-icache
make run-vcs-axil-icache-dhrystone
```

The `axil-icache` tests should prove that both instruction fetch and data
load/store traffic can stall through cache misses and resume correctly.
