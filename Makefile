# FPGA Specific Settings
FPGA_PKG = tq144:4k
FPGA_TYPE = hx8k
FPGA_PCF = rtl/top.pcf
TARGET_FREQ = 50
# -dsp infers SB_MAC16 cells, which the hx8k has none of - nextpnr then
# fails with "no BELs remaining to implement cell type ICESTORM_DSP".
YOSYS_FLAGS =

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

# ------------------------------------------------------------------------------
# Games
#
# GAME selects which program `asm`, `run`, `upload` and the FPGA build operate
# on. Everything downstream is derived from it, so there is exactly one place a
# new game has to be registered.
#
#   make run                 # the default game
#   make run GAME=nemo
#   make games               # list what is available
#
# Only one program can be resident at a time: rtl/ram.hex is baked into the
# RAM model by $readmemh, so every target that runs or synthesises stamps the
# hex from its own binary first. Without that, whichever game wrote ram.hex
# last would be the one that launched, because ram.hex would be newer than any
# .bin and make would consider it up to date.
# ------------------------------------------------------------------------------
GAMES = breakout nemo celeste
GAME ?= breakout

# Per-game definitions: entry point, sources to watch, extra include path.
#
# ASM selects the assembler: `customasm` (instruction set defined in
# src/isa/*.asm, one command straight to rtl/ram.hex) or `ca65` (the ld65
# linker chain, kept for games not yet migrated - see
# openspec/changes/add-custom-assembler). breakout is the migrated
# reference; nemo/celeste are still ca65's `.lbl` label files, which the
# Python test tooling (tools/test_nemo.py etc.) depends on.
breakout_SRC  = src/main.asm
breakout_DEPS = $(wildcard src/*.asm) $(wildcard src/isa/*.asm)
breakout_INC  =
breakout_ASM  = customasm
breakout_DESC = Breakout Hero - PICO-8 port (Krystman / Lazy Devs)

nemo_SRC  = src/nemo/main.asm
nemo_DEPS = $(wildcard src/nemo/*.asm)
nemo_INC  = -I src/nemo
nemo_ASM  = ca65
nemo_DESC = NEMO - Puzzle Pack II - PICO-8 port (mooon); ISA corpus

celeste_SRC  = src/celeste/main.asm
celeste_DEPS = $(wildcard src/celeste/*.asm)
celeste_INC  = -I src/celeste
celeste_ASM  = ca65
celeste_DESC = Celeste Classic - PICO-8 port (Thorson/Berry); ISA corpus

GAME_SRC  = $($(GAME)_SRC)
GAME_DEPS = $($(GAME)_DEPS)
GAME_INC  = $($(GAME)_INC)
GAME_ASM  = $($(GAME)_ASM)
GAME_OBJ  = build/$(GAME).o
GAME_BIN  = build/$(GAME).bin
GAME_LBL  = build/$(GAME).lbl
GAME_SYM  = build/$(GAME).sym

# Fail early and readably on a typo, rather than with an empty ca65 command line.
ifeq ($(GAME_SRC),)
$(error unknown GAME '$(GAME)'. Available: $(GAMES). Try `make games`)
endif

ASM_HEX = rtl/ram.hex
CA65 = ca65
LD65 = ld65
CA65FLAGS = -t none -v
LD65FLAGS = -C src/memory.cfg
HEXDUMP = hexdump

CUSTOMASM = customasm
CUSTOMASM_VERSION = 0.14.1

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

all: bin/toplevel.bin

# ------------------------------------------------------------------------------
# Building the selected game
# ------------------------------------------------------------------------------
# The ca65/ld65 chain. Used directly by nemo/celeste; kept for breakout as the
# `asm-ca65` bridge (openspec/changes/add-custom-assembler) until it is
# removed in the release after the ISA core slice lands.
$(GAME_OBJ): $(GAME_DEPS)
	mkdir -p build
	${CA65} -g ${CA65FLAGS} $(GAME_INC) -o $(GAME_OBJ) $(GAME_SRC)

$(GAME_BIN): $(GAME_OBJ)
	${LD65} ${LD65FLAGS} -Ln $(GAME_LBL) $(GAME_OBJ) -o $(GAME_BIN)

check-customasm-version:
	@actual="$$(${CUSTOMASM} --version 2>/dev/null)"; \
	case "$$actual" in \
	  "customasm v${CUSTOMASM_VERSION}"*) ;; \
	  *) echo "error: expected customasm v${CUSTOMASM_VERSION}, found: $${actual:-not installed}"; \
	     echo "  install/upgrade with: cargo install customasm --version ${CUSTOMASM_VERSION} --force"; \
	     exit 1;; \
	esac

# `hex`/`hex-ca65` are phony on purpose: they must re-stamp whenever GAME
# changes, and make cannot see that from timestamps alone.
ifeq ($(GAME_ASM),customasm)
hex: check-customasm-version $(GAME_SRC) $(GAME_DEPS)
	mkdir -p build rtl
	${CUSTOMASM} $(GAME_SRC) -t 10 --color=off --legacy=off \
	  -f binary -o $(GAME_BIN) -- \
	  -f symbols -o $(GAME_SYM) -- \
	  -f readmemh,width:8 -o ${ASM_HEX}
	@echo "rtl/ram.hex <- $(GAME_SRC) (customasm)"
else
hex: $(GAME_BIN)
	mkdir -p rtl
	${HEXDUMP} -v -e '16/1 "%02x " "\n"' $(GAME_BIN) > ${ASM_HEX}
	@echo "rtl/ram.hex <- $(GAME_BIN)"
endif

# Deprecated bridge: force the ca65/ld65 chain regardless of GAME_ASM. Only
# meaningful for games whose source ca65 can still parse - once a game
# migrates to customasm, its ca65-era source is gone and this target no
# longer applies to it.
hex-ca65: $(GAME_BIN)
	mkdir -p rtl
	${HEXDUMP} -v -e '16/1 "%02x " "\n"' $(GAME_BIN) > ${ASM_HEX}
	@echo "rtl/ram.hex <- $(GAME_BIN) (ca65, deprecated)"

asm: hex
asm-ca65: hex-ca65

games:
	@echo "Available games (select with GAME=<name>):"
	@$(foreach g,$(GAMES),printf '  %-10s %s%s\n' '$(g)' '$($(g)_DESC)' \
	   '$(if $(filter $(g),$(GAME)),  [default],)';)
	@echo
	@echo "  make run GAME=nemo        build and run in the simulator"
	@echo "  make asm GAME=nemo        just stamp rtl/ram.hex"
	@echo "  make asm-ca65             deprecated ca65/ld65 bridge (see docs/assembler.md)"

# ------------------------------------------------------------------------------
# FPGA bitstream
# ------------------------------------------------------------------------------
bin/toplevel.bin: bin/toplevel.asc
	icepack bin/toplevel.asc bin/toplevel.bin

bin/toplevel.asc: ${FPGA_PCF} bin/toplevel.json
	nextpnr-ice40 -q --freq ${TARGET_FREQ} --${FPGA_TYPE} --package ${FPGA_PKG} \
				  --json bin/toplevel.json --pcf ${FPGA_PCF} \
				  --asc bin/toplevel.asc --opt-timing

bin/toplevel.json: ${TOP_LEVEL} ${INCLUDE_FILES} ${PLL_FILE} ${FONT_HEX} hex
	mkdir -p bin
	yosys -p "read_verilog -Irtl -sv ${TOP_LEVEL}; synth_ice40 ${YOSYS_FLAGS} -top top -json bin/toplevel.json" > synthesis.log

# ------------------------------------------------------------------------------
# C++ / SDL2 simulator runner
# ------------------------------------------------------------------------------
SIM_BIN = build/obj_dir/console
$(SIM_BIN): sim/console.cpp rtl/*.sv rtl/*.bin rtl/*.hex
	verilator --cc rtl/top_simulator.sv --top-module top -Irtl -O3 \
		--x-assign fast --x-initial fast -Wno-DEFOVERRIDE \
		--exe $(abspath sim/console.cpp) -o console --build -j 8 \
		-Mdir build/obj_dir \
		-CFLAGS "-O2 $$(sdl2-config --cflags)" \
		-LDFLAGS "$$(sdl2-config --libs)"

# build/$(GAME).sym only exists for customasm games (see GAME_ASM above); pass
# it when present so --resolve and future symbolic traces have it to hand.
SIM_SYM_FLAGS = $(if $(wildcard $(GAME_SYM)),--sym $(GAME_SYM),)

run: hex ${FONT_HEX}
	$(MAKE) $(SIM_BIN)
	$(SIM_BIN) $(SIM_SYM_FLAGS) $(RUNFLAGS)

# Headless capture, for checking a change without a display:
#   make shot GAME=nemo FRAMES=60 SHOT=/tmp/menu.ppm KEYS=20:x,60:o
FRAMES ?= 60
SHOT   ?= build/shot.ppm
KEYS   ?=
shot: hex ${FONT_HEX}
	$(MAKE) $(SIM_BIN)
	$(SIM_BIN) $(SIM_SYM_FLAGS) --headless --frames $(FRAMES) --shot $(SHOT) \
		$(if $(KEYS),--keys $(KEYS),)

# PSG channel trace: per frame, the sfx and note row on each channel, in the
# same shape as PICO-8's stat(46..49)/stat(50..53) so the two can be diffed.
#   make psg-trace GAME=nemo FRAMES=240 > mine.txt
psg-trace: hex ${FONT_HEX}
	@$(MAKE) -s $(SIM_BIN)
	@$(SIM_BIN) --headless --frames $(FRAMES) --psg-trace $(if $(KEYS),--keys $(KEYS),) 2>/dev/null | grep '^@@'

# ------------------------------------------------------------------------------
# Simulation / testbenches
# ------------------------------------------------------------------------------
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

test_ram: rtl/ram_test_tb.v rtl/ram_async.sv rtl/ram.hex
	@echo "Running RAM testbench..."
	iverilog -g2012 -o ram_test.vvp rtl/ram_test_tb.v rtl/ram_async.sv
	vvp ram_test.vvp

test:
	iverilog -DSIMULATION -g2012 -y ./rtl -s cpu6502_tb rtl/cpu6502_defs.sv rtl/cpu6502_alu.sv rtl/cpu6502_wrapper.sv rtl/cpu6502_arlet.sv rtl/cpu6502_tb.sv && ./a.out

# NEMO's own suites: routine-level checks and a full main-loop drive, both
# against the assembled binary under tools/sim6502.py.
test-nemo:
	$(MAKE) GAME=nemo build/nemo.bin
	python3 tools/isa_metrics.py
	@echo
	python3 tools/test_nemo.py build/nemo.bin build/nemo.lbl
	@echo
	python3 tools/test_nemo_loop.py build/nemo.bin build/nemo.lbl

# Celeste's suite: the whole program driven from the reset vector with the PPU
# faked, checking the things a screenshot cannot - sub-pixel accumulation,
# collision against the room data, spikes, room transitions.
test-celeste:
	$(MAKE) GAME=celeste build/celeste.bin
	python3 tools/test_celeste.py build/celeste.bin build/celeste.lbl

metrics:
	python3 tools/isa_metrics.py

# ------------------------------------------------------------------------------
tools: ${FONT_CONVERT}

font: ${FONT_HEX}

timing: bin/toplevel.bin
	icetime -tmd ${FPGA_TYPE} -c ${TARGET_FREQ} -p ${FPGA_PCF} -P ${FPGA_PKG} bin/toplevel.asc

stat: bin/toplevel.asc
	icebox_stat -v bin/toplevel.asc

upload: bin/toplevel.bin
	stty -f /dev/cu.usbmodem00000000001A1 raw
	cat bin/toplevel.bin >/dev/cu.usbmodem00000000001A1

clean:
	rm -rf bin build *.log
	cd tools && cargo clean
	rm -f ${PLL_FILE} ${ASM_HEX} ${FONT_HEX}

.PHONY: all games hex hex-ca65 asm asm-ca65 check-customasm-version run shot \
        timing stat upload clean font tools test \
        sim debug debug_custom test_ram test-nemo test-celeste metrics
