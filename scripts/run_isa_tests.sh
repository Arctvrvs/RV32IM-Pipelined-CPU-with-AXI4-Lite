#!/usr/bin/env bash
set -u

LIST=${1:-programs/riscv_isa/testlist.txt}
SIM=${SIM:-build/simv_riscv_isa}
LOGDIR=${LOGDIR:-build/riscv_isa_logs}
TIMEOUT=${TIMEOUT:-50000}

mkdir -p "$LOGDIR"
pass=0
fail=0

while read -r test; do
    [[ -z "$test" || "$test" =~ ^# ]] && continue
    imem="programs/riscv_isa/${test}_imem.hex"
    dmem="programs/riscv_isa/${test}_dmem.hex"
    log="$LOGDIR/${test}.log"
    echo "===== RUN $test ====="
    if "$SIM" +TESTNAME="$test" +HEX="$imem" +DMEM_HEX="$dmem" +TIMEOUT="$TIMEOUT" -l "$log" -no_save; then
        echo "===== PASS $test ====="
        pass=$((pass+1))
    else
        echo "===== FAIL $test ====="
        fail=$((fail+1))
    fi
done < "$LIST"

echo "============================================"
echo "RISC-V ISA test summary: PASS=$pass FAIL=$fail"
echo "Logs: $LOGDIR"
echo "============================================"

if [[ $fail -ne 0 ]]; then
    exit 1
fi
