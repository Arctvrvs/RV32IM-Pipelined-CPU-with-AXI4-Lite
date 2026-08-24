# Cache Stall Forwarding Fix

The AXI-Lite cache version can stall the pipeline for multiple cycles on an
I-cache or D-cache miss.  During these stalls the pipeline holds IF/ID, ID/EX,
and EX/MEM stable.

The important subtlety is MEM/WB: it must also remain visible during the stall.
A younger instruction may already be in ID/EX with an operand value captured
before an older instruction wrote back.  If MEM/WB were replaced with a bubble
while the cache miss is pending, the younger instruction could resume after the
miss with a stale operand and no forwarding source.

The fix is to hold MEM/WB stable during `pipe_stall`, preserving the forwarding
source until the stalled instruction can execute.  Rewriting the same register
for a few stall cycles is architecturally harmless for this simple in-order core,
and it keeps cache-miss recovery correct.

This specifically fixes sequences like:

```asm
lw   x6, 0(x4)
lw   x7, 0(x0)      # cache miss stalls the pipe
add  x8, x3, x6     # must still see x6 after the stall
```

and similar I-cache-miss cases where a store address/data operand was captured
before an older producer became visible.
