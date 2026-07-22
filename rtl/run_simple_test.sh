#!/bin/bash
# Compile and run simplified reset vector test

# Generate test RAM file
cat > test_ram.hex << EOL
@00000000
00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F
@00000010
10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F
@00000300
A9 48 8D 00 10 A9 45 8D 01 10 A9 4C 8D 02 10 A9
4C 8D 03 10 A9 4F 8D 04 10 20 50 03 A9 21 8D 05
10 4C 30 03
@00000ffc
00 03
EOL

# Compile SystemVerilog testbench
echo "Compiling testbench..."
iverilog -g2012 -Wall -o simple_reset_tb rtl/simple_reset_tb.sv rtl/ram_async.sv --timing

# Run simulation
echo "Running simulation..."
vvp simple_reset_tb

# Clean up
rm test_ram.hex
echo "Test complete."

# Generate waveform file for viewing (optional)
# gtkwave dump.vcd & 