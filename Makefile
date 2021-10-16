# FPGA Specific Settings
FPGA_PKG = tq144:4k
FPGA_TYPE = hx8k
FPGA_PCF = rtl/top.pcf
TARGET_FREQ = 50

# Project Specific Settings
INCLUDE_FILES = rtl/**/*.v rtl/**/*.sv rtl/**/*.hex rtl/**/*.bin
TOP_LEVEL = rtl/top.sv
PLL_FILE = rtl/pll.v

# Simulator Specific Settings

# Dependencies
${PLL_FILE}:
	icepll -q -i 25 -o ${TARGET_FREQ} -m -f ${PLL_FILE}
	sed -i '' -e 's/PLLOUTCORE/PLLOUTGLOBAL/g' ${PLL_FILE}

bin/toplevel.bin: bin/toplevel.asc
	icepack bin/toplevel.asc bin/toplevel.bin

bin/toplevel.asc: ${FPGA_PCF} bin/toplevel.json
	nextpnr-ice40 -q --freq ${TARGET_FREQ} --${FPGA_TYPE} --package ${FPGA_PKG} \
				  --json bin/toplevel.json --pcf ${FPGA_PCF} \
				  --asc bin/toplevel.asc --opt-timing

bin/toplevel.json: ${TOP_LEVEL} ${INCLUDE_FILES} ${PLL_FILE}
	mkdir -p bin
	yosys -q -p "read_verilog -Irtl -sv ${TOP_LEVEL}; synth_ice40 -abc9 -dsp -top top -json bin/toplevel.json" 

rust/rtl:
	cd rust && ln -s ../rtl rtl 

# Commands
.PHONY: timing stat upload run clean

timing: bin/toplevel.bin
	icetime -tmd ${FPGA_TYPE} -c ${TARGET_FREQ} -p ${FPGA_PCF} -P ${FPGA_PKG} bin/toplevel.asc

stat: bin/toplevel.asc
	icebox_stat -v bin/toplevel.asc

upload: bin/toplevel.bin
	stty -f /dev/cu.usbmodem00000000001A1 raw 
	cat bin/toplevel.bin >/dev/cu.usbmodem00000000001A1

run: rust/rtl
	cp rtl/*.hex rust/
	cp rtl/*.bin rust/
	cd rust && cargo run --release

clean:
	rm -rf ${PLL_FILE} bin rust/rtl rust/*.hex rust/*.bin
	cd rust && cargo clean
