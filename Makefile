# FPGA Specific Settings
FPGA_PKG = tq144:4k
FPGA_TYPE = hx8k
FPGA_PCF = rtl/top.pcf
TARGET_FREQ = 50
# YOSYS_FLAGS = -noflatten -abc9 -dsp
YOSYS_FLAGS = -dsp 

# Project Specific Settings
INCLUDE_FILES = rtl/**/*.v rtl/**/*.sv rtl/**/*.bin
TOP_LEVEL = rtl/top.sv
PLL_FILE = rtl/pll.v

# Simulation Settings
SIM_TOP = cpu6502_tb
SIM_FILES = rtl/cpu6502_tb.sv
DEBUG_TEST = debug_test
DEBUG_FILES = rtl/debug_test.sv
IVERILOG = iverilog
VVP = vvp
IVERILOG_FLAGS = -g2012 -I. -y rtl

# Assembly Settings
ASM_SRC = src/main.asm
ASM_OBJ = build/main.o
ASM_BIN = build/main.bin
ASM_HEX = rtl/ram.hex
CA65 = ca65
LD65 = ld65
CA65FLAGS = -t none -v
LD65FLAGS = -C src/memory.cfg
OBJCOPY = /opt/homebrew/opt/binutils/bin/objcopy
HEXDUMP = hexdump

# Font Settings
FONT_SRC = src/font_cp437_8x8.txt
FONT_HEX = rtl/font_cp437_8x8.hex
FONT_CONVERT = tools/target/release/convert-font

# Dependencies
${PLL_FILE}:
	icepll -q -i 25 -o ${TARGET_FREQ} -m -f ${PLL_FILE}
	sed -i '' -e 's/PLLOUTCORE/PLLOUTGLOBAL/g' ${PLL_FILE}

# Font conversion
${FONT_CONVERT}:
	cd tools && cargo build --release

${FONT_HEX}: ${FONT_SRC} ${FONT_CONVERT}
	mkdir -p rtl
	${FONT_CONVERT} text2hex ${FONT_SRC} ${FONT_HEX}

# Assembly to Hex conversion
all: bin/toplevel.bin

${ASM_HEX}: ${ASM_BIN}
	mkdir -p rtl
	${HEXDUMP} -v -e '16/1 "%02x " "\n"' ${ASM_BIN} > ${ASM_HEX}

${ASM_BIN}: ${ASM_OBJ}
	${LD65} ${LD65FLAGS} ${ASM_OBJ} -o ${ASM_BIN}

${ASM_OBJ}: ${ASM_SRC}
	mkdir -p build
	${CA65} ${CA65FLAGS} -o ${ASM_OBJ} ${ASM_SRC}

bin/toplevel.bin: bin/toplevel.asc
	icepack bin/toplevel.asc bin/toplevel.bin

bin/toplevel.asc: ${FPGA_PCF} bin/toplevel.json
	nextpnr-ice40 -q --freq ${TARGET_FREQ} --${FPGA_TYPE} --package ${FPGA_PKG} \
				  --json bin/toplevel.json --pcf ${FPGA_PCF} \
				  --asc bin/toplevel.asc --opt-timing

bin/toplevel.json: ${TOP_LEVEL} ${INCLUDE_FILES} ${PLL_FILE} ${ASM_HEX} ${FONT_HEX}
	mkdir -p bin
	yosys -p "read_verilog -Irtl -sv ${TOP_LEVEL}; synth_ice40 ${YOSYS_FLAGS} -top top -json bin/toplevel.json" > synthesis.log

rust/rtl:
	cd rust && ln -s ../rtl rtl 

# Simulation targets
bin/sim_${SIM_TOP}: ${SIM_FILES}
	mkdir -p bin
	${IVERILOG} ${IVERILOG_FLAGS} -o $@ ${SIM_FILES}

bin/sim_debug_${SIM_TOP}: ${SIM_FILES}
	mkdir -p bin
	${IVERILOG} ${IVERILOG_FLAGS} -DSIMULATION -DDEBUG -o $@ ${SIM_FILES}

bin/sim_${DEBUG_TEST}: ${DEBUG_FILES}
	mkdir -p bin
	${IVERILOG} ${IVERILOG_FLAGS} -DSIMULATION -DDEBUG -o $@ ${DEBUG_FILES}

sim: bin/sim_${SIM_TOP}
	${VVP} bin/sim_${SIM_TOP}

debug: bin/sim_debug_${SIM_TOP}
	${VVP} bin/sim_debug_${SIM_TOP}

debug_custom: bin/sim_${DEBUG_TEST}
	${VVP} bin/sim_${DEBUG_TEST}

# Testbench targets
test_ram: rtl/ram_test_tb.v rtl/ram_async.sv rtl/ram.hex
	@echo "Running RAM testbench..."
	iverilog -g2012 -o ram_test.vvp rtl/ram_test_tb.v rtl/ram_async.sv
	vvp ram_test.vvp

# Commands
.PHONY: timing stat upload run clean all asm font tools test sim debug debug_custom

test:
	iverilog -DSIMULATION -g2012 -y ./rtl -s cpu6502_tb rtl/cpu6502_defs.sv rtl/cpu6502_alu.sv rtl/cpu6502_wrapper.sv rtl/cpu6502_arlet.sv rtl/cpu6502_tb.sv && ./a.out

tools: ${FONT_CONVERT}

font: ${FONT_HEX}

asm: ${ASM_HEX}

timing: bin/toplevel.bin
	icetime -tmd ${FPGA_TYPE} -c ${TARGET_FREQ} -p ${FPGA_PCF} -P ${FPGA_PKG} bin/toplevel.asc

stat: bin/toplevel.asc
	icebox_stat -v bin/toplevel.asc

upload: bin/toplevel.bin
	stty -f /dev/cu.usbmodem00000000001A1 raw 
	cat bin/toplevel.bin >/dev/cu.usbmodem00000000001A1

run: rust/rtl ${ASM_HEX} ${FONT_HEX}
	cd rust && cd .. && cd rust && cargo run --release

clean:
	rm -rf bin build rust/rtl rust/*.hex rust/*.bin *.log
	cd rust && cargo clean
	cd tools && cargo clean
	rm -f ${PLL_FILE} ${ASM_HEX} ${FONT_HEX}
