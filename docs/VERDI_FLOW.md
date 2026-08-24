# Verdi Flow

Compile with VCS KDB support:

```bash
make vcs-riscv-isa
```

Open Verdi using the VCS database:

```bash
verdi -dbdir build/simv_pipeline_riscv_isa.daidir -top tb_pipeline_riscv_isa &
```

Useful debug steps:

1. Add pipeline registers to the waveform.
2. Follow one instruction through IF/ID, ID/EX, EX/MEM, and MEM/WB.
3. Trace `load_use_hazard` for load-dependent tests.
4. Trace `ex_redirect` and `ex_redirect_pc` for branch/JAL/JALR tests.
5. Trace `wb_do_write`, `wb_rd`, and `wb_wdata` for architectural register updates.
