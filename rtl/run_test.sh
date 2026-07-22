#!/bin/bash
# Compile and run CPU testbench

# Compile the testbench
verilator --cc --exe --timing -Wno-CMPCONST -Wno-CASEX -Wno-CASEOVERLAP -Wno-CASEINCOMPLETE \
    --build -j 4 \
    --top-module cpu6502_tb \
    -CFLAGS "-std=c++11 -Wall -O3" \
    -o test_cpu cpu6502_tb.sv cpu6502_arlet.sv ram_async.sv

# Run the testbench
./obj_dir/test_cpu 