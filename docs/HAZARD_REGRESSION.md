# Pipeline Hazard/Divider Regression

The hazard regression keeps the focused pipeline tests that stress the cases most likely to break in a 5-stage CPU.

Target:

```bash
make run-vcs-hazard
```

Files:

```text
tb/tb_pipeline_hazard.v
programs/pipeline_hazard.hex
programs/pipeline_hazard.lst
filelist_pipeline_hazard.f
```

The regression checks:

- Load-to-store data forwarding
- Store-data forwarding into the MEM stage
- Long-latency DIV and REM behavior
- Consumer-after-DIV/REM dependency handling
- Instruction immediately before ECALL commits before halt

The test is intentionally small so it can be debugged easily in Verdi.
