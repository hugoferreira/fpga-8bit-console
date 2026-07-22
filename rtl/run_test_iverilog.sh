#!/bin/bash
# Compile and run CPU testbench with Icarus Verilog

# Create test memory hex file if it doesn't exist
if [ ! -f test_ram.hex ]; then
  echo "Creating test memory file"
  # This creates a 16K file with zeros
  for i in {1..1024}; do
    echo "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" >> test_ram.hex
  done
  
  # Replace line at offset 48 (0x300) with the test program
  sed -i '' '49s/.*/A9 42 A2 69 EA EA 4C 06 03 00 00 00 00 00 00 00/' test_ram.hex
  
  # Replace the line containing the reset vector (near end of file)
  sed -i '' '1024s/.*/00 00 00 00 00 00 00 00 00 00 00 00 00 03 00 00/' test_ram.hex
fi

# Compile the testbench with iverilog
iverilog -g2012 -o cpu_test \
  -D SIM \
  -D IVERILOG \
  cpu6502_arlet.sv \
  ram_async.sv \
  cpu6502_tb.sv

# Run the simulation
vvp cpu_test

# Generate waveform file for viewing (optional)
# gtkwave dump.vcd & 