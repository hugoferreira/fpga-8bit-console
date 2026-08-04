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
#   make run game=celeste    # lowercase compatibility alias
#   make games               # list what is available
#
# Only one program can be resident at a time: rtl/ram.hex is baked into the
# RAM model by $readmemh, so every target that runs or synthesises stamps the
# hex from its own binary first. Without that, whichever game wrote ram.hex
# last would be the one that launched, because ram.hex would be newer than any
# .bin and make would consider it up to date.
# ------------------------------------------------------------------------------
GAMES = breakout nemo celeste

# Accept the lowercase spelling used by older commands and shell habits. An
# explicit uppercase GAME remains canonical and wins when both are supplied.
ifeq ($(origin GAME), undefined)
ifneq ($(origin game), undefined)
GAME := $(game)
endif
endif
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

celeste_SRC  = src/celeste/main.inlay.asm
celeste_DEPS = $(wildcard src/celeste/*.inlay.asm)
celeste_INC  = -I src/celeste
celeste_ASM  = customasm
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
	@python3 tools/sym_to_lbl.py $(GAME_SYM) build/$(GAME).lbl
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

# rtl/pll.v is generated, not checked in (.gitignore). top.sv instantiates it
# now, so a fresh clone needs this rule or synthesis fails on a missing module.
# 112.5 MHz: see the header comment the tool writes plus rtl/clocks.sv.
rtl/pll.v:
	icepll -i 25 -o 112.5 -m -f $@

bin/toplevel.json: ${TOP_LEVEL} ${INCLUDE_FILES} ${PLL_FILE} rtl/pll.v ${FONT_HEX} hex
	mkdir -p bin
	yosys -p "read_verilog -Irtl -sv ${TOP_LEVEL}; synth_ice40 ${YOSYS_FLAGS} -top top -json bin/toplevel.json" > synthesis.log

# ------------------------------------------------------------------------------
# C++ / SDL2 simulator runner
# ------------------------------------------------------------------------------
SIM_BIN = build/obj_dir/console
# rtl/*.svh as well as rtl/*.sv: psg_common.svh is `include'd, so without it a
# change to the PSG's shared parameters left the console binary stale.
# -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC: the same established width-warning pair
# the psg_wav and test-psg builds pass. Verilator 5 exits nonzero on the three
# known WIDTHTRUNC warnings otherwise, so a clean rebuild of the console (run/
# shot/psg-trace) fails; a stale prebuilt build/obj_dir masked that for months.
$(SIM_BIN): sim/console.cpp rtl/*.sv rtl/*.svh rtl/*.bin rtl/*.hex
	verilator --cc rtl/top_simulator.sv --top-module top -Irtl -O3 \
		--x-assign fast --x-initial fast -Wno-DEFOVERRIDE \
		-Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
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

# PSG audio, rendered with nothing else in the system: no CPU, no game, no
# video. Answers "does it SOUND right", which --psg-trace cannot.
#   make psg-wav CART=~/Stuff/carts/celeste-15133.p8.png MUSIC=0 MASK=7
#   make psg-wav CART=... SFX=3 SECONDS=2 WAV=build/dash.wav
CART    ?=
MUSIC   ?= 0
MASK    ?= 7
SFX     ?=
SECONDS ?= 12
WAV     ?= build/psg.wav
PSG_WAV  = build/obj_psg/psg_wav
PSG_RTL  = rtl/psg.sv rtl/psg_common.svh rtl/psg_timing.sv \
	rtl/psg_aram.sv rtl/psg_mulsvc.sv rtl/psg_mulmp.sv rtl/psg_divsvc.sv \
	rtl/psg_state_mem.sv rtl/psg_wave.sv rtl/psg_walk.sv rtl/psg_seq.sv

$(PSG_WAV): $(PSG_RTL) sim/psg_wav.cpp
	verilator --cc rtl/psg.sv --top-module psg -Irtl -O3 \
		--x-assign fast --x-initial fast \
		-Wno-DEFOVERRIDE -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
		--exe $(abspath sim/psg_wav.cpp) -o psg_wav --build -j 8 \
		-Mdir build/obj_psg -CFLAGS "-O2"

# The SAME model built with the simulator's REALTIME_PREVIEW schedule, which is
# the only schedule `make run` ever executes and the one nothing used to gate.
# The oracle cannot cover it: the oracle builds REALTIME_PREVIEW=0, so everything
# inside `if (REALTIME_PREVIEW)` is invisible to it BY CONSTRUCTION. That blind
# spot let the preview path go first out of tune (5bdead3 left its oscillator
# store map on the pre-crossfade layout) and then silent (4658091 stopped
# deferring an overrun sample boundary), across a whole campaign of green gates.
#
# CLK_HZ is a variable, not the console's 3,506,580: rendering preview at the
# hardware clock separates "is the preview schedule CORRECT" from "does it FIT
# the console's 159 clocks per sample". Those are different questions and
# conflating them wasted a bisect.
PSG_PV_CLK ?= 28125000
# Gate the combined tune and each real pattern channel. Register $21's MASK is
# reservation metadata and cannot isolate channels; the checker disables the
# other three pattern bytes in a private audio-image copy instead.
PSG_PV_ARGS ?= --all-channels
# Object dir carries the clock: a correctness run (28.125 MHz) and a fit run
# (3,506,580, what the console supplies) must coexist without rebuilding.
PSG_WAV_PV  = build/obj_psg_pv_$(PSG_PV_CLK)/psg_wav

$(PSG_WAV_PV): $(PSG_RTL) sim/psg_wav.cpp
	verilator --cc rtl/psg.sv --top-module psg -Irtl -O3 \
		--x-assign fast --x-initial fast \
		-Wno-DEFOVERRIDE -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
		-GREALTIME_PREVIEW=1 -GCLK_HZ=$(PSG_PV_CLK) \
		--exe $(abspath sim/psg_wav.cpp) -o psg_wav --build -j 8 \
		-Mdir build/obj_psg_pv_$(PSG_PV_CLK) -CFLAGS "-O2"

psg-wav-preview: $(PSG_WAV_PV)
	@test -n "$(CART)" || { echo "usage: make psg-wav-preview CART=<cart.p8.png> [MUSIC=n|SFX=n]"; exit 1; }
	@mkdir -p build
	@python3 -c "import sys; sys.path.insert(0,'tools'); \
	  from p8_audio import rom_from_png; \
	  open('build/psg_audio.bin','wb').write(rom_from_png('$(CART)')[0x3100:0x4300])"
	$(PSG_WAV_PV) --audio build/psg_audio.bin --mask $(MASK) --seconds $(SECONDS) \
	  --clk $(PSG_PV_CLK) \
	  $(if $(SFX),--sfx $(SFX),--music $(MUSIC)) --out $(WAV)

# The preview path's gate: does the simulator play the same TUNE as the hardware
# schedule? Pitch agreement, not byte equality - the preview is deliberately an
# approximation, so a byte gate would be false-red on every legitimate preview
# change, while "plays the same notes" is exactly the property that broke.
#   make test-psg-preview CART=~/Stuff/carts/celeste-15133.p8.png
# The hardware reference model is built by tools/psg_oracle_render.py at the
# matching -GCLK_HZ; $(PSG_WAV) cannot serve, it is compiled for the default clock.
# FIDELITY against real PICO-8, where bytes cannot be compared. psg-bytecheck is
# a regression gate - it diffs our RTL against frozen renders of our own RTL - so
# it cannot see a fault that was already present when the set was frozen. This
# can: it sweeps pitch through a noise SFX and compares the statistics AND their
# pitch dependence against a PICO-8 recording committed under tests/psg.
#   make test-psg-fidelity              # gate
#   make test-psg-fidelity RECORD=1     # re-capture the reference (needs PICO-8)
test-psg-fidelity:
	python3 tools/psg_fidelity_gate.py $(if $(RECORD),--record,)

# Full-track fidelity with candidate provenance. This target always renders the
# current hardware-schedule RTL; it never accepts a pre-existing candidate WAV.
#   make test-psg-track CART=... MUSIC=30 PSG_REFERENCE=build/p8ref/pico8-30.wav
#   make test-psg-track ... SPECDIFF=1     one difference chart, not two panels
PSG_REFERENCE ?=
SPECDIFF ?=
test-psg-track:
	@test -n "$(CART)" || { echo "usage: make test-psg-track CART=<cart.p8.png> MUSIC=n PSG_REFERENCE=<pico8.wav>"; exit 2; }
	@test -n "$(PSG_REFERENCE)" || { echo "usage: make test-psg-track CART=<cart.p8.png> MUSIC=n PSG_REFERENCE=<pico8.wav>"; exit 2; }
	python3 tools/psg_track_gate.py --cart "$(CART)" --music "$(MUSIC)" \
	  --reference "$(PSG_REFERENCE)" \
	  --candidate-out "build/psg_track_gate/music$(MUSIC)-current-rtl.wav" \
	  --spectrogram-file "build/psg_track_gate/music$(MUSIC)-comparison.png" \
	  $(if $(SPECDIFF),--spectrogram-difference,)

# Celeste's five entry points cover every chained music pattern used by the
# game. This is the final PSG integration gate.
CELESTE_MUSIC ?= 0 10 20 30 40
PSG_REFERENCE_DIR ?= build/p8ref
test-psg-celeste-tracks:
	@test -n "$(CART)" || { echo "usage: make test-psg-celeste-tracks CART=<celeste.p8.png> [PSG_REFERENCE_DIR=build/p8ref]"; exit 2; }
	@failed=0; for music in $(CELESTE_MUSIC); do \
	  ref="$(PSG_REFERENCE_DIR)/pico8-$$music.wav"; \
	  test -f "$$ref" || { echo "missing PICO-8 reference: $$ref"; exit 2; }; \
	  echo "=== Celeste music $$music ==="; \
	  python3 tools/psg_track_gate.py --cart "$(CART)" --music "$$music" \
	    --reference "$$ref" \
	    --candidate-out "build/psg_track_gate/music$$music-current-rtl.wav" \
	    --spectrogram-file "build/psg_track_gate/music$$music-comparison.png" \
	    || failed=1; \
	done; exit $$failed

test-psg-preview: $(PSG_WAV_PV)
	@test -n "$(CART)" || { echo "usage: make test-psg-preview CART=<cart.p8.png>"; exit 1; }
	python3 tools/psg_preview_check.py --cart $(CART) \
	  --preview $(PSG_WAV_PV) --preview-clk $(PSG_PV_CLK) $(PSG_PV_ARGS)

# Exercise the compact PREVIEW schedule's foreground-SFX takeover/retrigger/
# release contract at the console clock. The synthetic image keeps the gate
# self-contained; the frozen Celeste image covers the exact reported mix.
PSG_RECOVERY_CLK ?= 3506580
PSG_RECOVERY_AUDIO ?= build/p8ref/celeste-audio.hex
PSG_BUDGET_PV = build/obj_psg_budget_pv_$(PSG_RECOVERY_CLK)/Vpsg_budget_tb

$(PSG_BUDGET_PV): rtl/psg_budget_tb.sv $(PSG_RTL) rtl/dsigma.sv
	verilator --binary --timing -j 4 -Irtl \
	  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-PINMISSING \
	  rtl/psg_budget_tb.sv rtl/psg.sv rtl/dsigma.sv \
	  --top-module psg_budget_tb -GCLKHZ_P=$(PSG_RECOVERY_CLK) -GPREVIEW_P=1 \
	  --Mdir build/obj_psg_budget_pv_$(PSG_RECOVERY_CLK)

test-psg-preview-recovery: $(PSG_BUDGET_PV)
	@test -f "$(PSG_RECOVERY_AUDIO)" || { \
	  echo "missing Celeste audio image: $(PSG_RECOVERY_AUDIO)"; \
	  echo "override with PSG_RECOVERY_AUDIO=<readmemh-audio.hex>"; exit 2; }
	$(PSG_BUDGET_PV) +recovery
	$(PSG_BUDGET_PV) +recovery +recovery_audio="$(abspath $(PSG_RECOVERY_AUDIO))"

# Deterministic regression for the transition artifact reported on Celeste's
# jump SFX. Exercise the selected /6 hardware schedule and the console-clock
# PREVIEW schedule separately, then require the unchanged click-v1 detector to
# find no isolated discontinuities in either four-second render.
PSG_CLICK_AUDIO ?= build/p8ref/celeste-audio.bin
PSG_CLICK_SFX ?= 10
PSG_CLICK_SAMPLES ?= 88200
PSG_CLICK_HW_CLK ?= 18750000
PSG_CLICK_PREVIEW_CLK ?= 3506580
PSG_CLICK_DIR ?= build/psg_clicks/regression

test-psg-clicks:
	@test -f "$(PSG_CLICK_AUDIO)" || { \
	  echo "missing Celeste audio image: $(PSG_CLICK_AUDIO)"; exit 2; }
	@mkdir -p "$(PSG_CLICK_DIR)"
	python3 tools/psg_oracle_render.py --audio "$(PSG_CLICK_AUDIO)" \
	  --sfx $(PSG_CLICK_SFX) --mask 15 --samples $(PSG_CLICK_SAMPLES) \
	  --clock $(PSG_CLICK_HW_CLK) --out "$(PSG_CLICK_DIR)/hardware.wav"
	$(MAKE) PSG_PV_CLK=$(PSG_CLICK_PREVIEW_CLK) \
	  build/obj_psg_pv_$(PSG_CLICK_PREVIEW_CLK)/psg_wav
	build/obj_psg_pv_$(PSG_CLICK_PREVIEW_CLK)/psg_wav \
	  --audio "$(PSG_CLICK_AUDIO)" --sfx $(PSG_CLICK_SFX) --mask 15 \
	  --samples $(PSG_CLICK_SAMPLES) --clk $(PSG_CLICK_PREVIEW_CLK) \
	  --out "$(PSG_CLICK_DIR)/preview.wav"
	python3 tools/audio_analysis.py wav inspect "$(PSG_CLICK_DIR)/hardware.wav"
	python3 tools/audio_analysis.py wav inspect "$(PSG_CLICK_DIR)/preview.wav"

psg-wav: $(PSG_WAV)
	@test -n "$(CART)" || { echo "usage: make psg-wav CART=<cart.p8.png> [MUSIC=n|SFX=n]"; exit 1; }
	@mkdir -p build
	@python3 -c "import sys; sys.path.insert(0,'tools'); \
	  from p8_audio import rom_from_png; \
	  open('build/psg_audio.bin','wb').write(rom_from_png('$(CART)')[0x3100:0x4300])"
	$(PSG_WAV) --audio build/psg_audio.bin --mask $(MASK) --seconds $(SECONDS) \
	  $(if $(SFX),--sfx $(SFX),--music $(MUSIC)) --out $(WAV)

# Unified row-by-row energy and stable-note pitch analysis against the cart's
# own SFX data. Localises a bad render to a row, waveform, volume, or effect.
#   make psg-analyze CART=... SFX=8
psg-analyze: $(PSG_WAV)
	@test -n "$(CART)" || { echo "usage: make psg-analyze CART=<cart.p8.png> SFX=n"; exit 2; }
	@test -n "$(SFX)" || { echo "usage: make psg-analyze CART=<cart.p8.png> SFX=n"; exit 2; }
	@$(MAKE) -s psg-wav CART=$(CART) SFX=$(SFX) SECONDS=$(SECONDS) WAV=build/psg_sfx.wav
	python3 tools/audio_analysis.py sfx analyze build/psg_sfx.wav --cart "$(CART)" --sfx "$(SFX)"

# Inspect the two schedules themselves - the walk's micro-phase timetable and
# the tick sequencer's FSM - rather than a render of them running. Everything
# is read out of the RTL and the control-store generator, so the picture tracks
# the source instead of becoming a stale drawing.
#   make psg-viz && open build/psg_viz.html
#   make psg-viz PSG_VIZ_FLAGS='--trace build/walk.jsonl'
PSG_VIZ_OUT ?= build/psg_viz.html
PSG_VIZ_FLAGS ?=
psg-viz: tools/psg_viz.py tools/psg_viz.html rtl/psg_walk.sv rtl/psg_seq.sv \
         tools/gen_psg_ctrl.py tools/psg_mul_model.py rtl/psg_mulsvc.sv
	python3 tools/psg_viz.py --out $(PSG_VIZ_OUT) $(PSG_VIZ_FLAGS)

# Prove a multiply mode/width change before the RTL moves. A narrower mode only
# makes a product ready earlier; fixed control-store phases still elapse until
# they are separately retimed. The mode also selects the accumulator SLICE, so
# this gate says whether two configurations are bit-identical on all three
# result ports before any schedule experiment.
#   make test-psg-mul
test-psg-mul:
	python3 tools/psg_mul_model.py

# Exhaustively prove the serial fold's exact base-256 /5 decomposition over
# every reachable excess and every signed-int16 pair sum.
test-psg-fold:
	python3 tools/psg_hw_forms.py mix

# Prove the visit-local detune coefficient identity in Python, then exercise
# every coefficient/input pair and the terminal-cycle chained-request contract
# in the synthesizable radix-4 service under Icarus.
test-psg-dq:
	python3 tools/psg_dq_model.py
	mkdir -p build
	iverilog -g2012 -s psg_dqsvc_tb -o build/psg_dqsvc_tb \
	  rtl/psg_dqsvc_tb.sv rtl/psg_dqsvc.sv
	vvp build/psg_dqsvc_tb

# Fidelity against PICO-8 as a REGRESSION gate, not an absolute one. The track
# gate above passes anything inside its tolerance band, so a change that moved
# music 20's lock from 0.83 to 0.73 still went green; this compares the same
# measurements against a committed baseline and fails when one gets worse.
#   make test-psg-pico8 CART=<celeste.p8.png>
#   make test-psg-pico8 CART=... RECORD=1     # re-baseline, and say why
test-psg-pico8:
	@test -n "$(CART)" || { echo "usage: make test-psg-pico8 CART=<celeste.p8.png> [RECORD=1]"; exit 2; }
	python3 tools/psg_pico8_fidelity.py --cart "$(CART)" \
	  --reference-dir "$(PSG_REFERENCE_DIR)" $(if $(RECORD),--record,) \
	  $(if $(ENTRIES),--entries $(ENTRIES),) $(if $(CLK),--clock $(CLK),)

# Register live ranges in the sample walk, and which pairs could share one.
# Lifetime retirement is the campaign's most reliable small lever and its
# least predictable one, so this derives the part that must be exactly right -
# the live ranges - from the RTL rather than from reading.
#   make psg-lifetimes
psg-lifetimes: tools/psg_lifetimes.py rtl/psg_walk.sv tools/gen_psg_ctrl.py
	python3 tools/psg_lifetimes.py

.PHONY: test-psg-celeste-tracks test-psg-preview-recovery test-psg-clicks psg-analyze \
	psg-viz test-psg-mul test-psg-fold test-psg-dq test-psg-pico8 psg-lifetimes

# ------------------------------------------------------------------------------
# Simulation / testbenches
# ------------------------------------------------------------------------------
bin/sim_${SIM_TOP}: ${SIM_FILES}
	mkdir -p bin
	${IVERILOG} ${IVERILOG_FLAGS} -o $@ ${SIM_FILES}

bin/sim_debug_${SIM_TOP}: ${SIM_FILES}
	mkdir -p bin
	${IVERILOG} ${IVERILOG_FLAGS} -DSIMULATION -DDEBUG -o $@ ${SIM_FILES}

sim: bin/sim_${SIM_TOP}
	${VVP} bin/sim_${SIM_TOP}

debug: bin/sim_debug_${SIM_TOP}
	${VVP} bin/sim_debug_${SIM_TOP}

# The PSG's own regression suite. It had stopped building under iverilog (two
# declaration-after-use / cast issues Verilator tolerates), so it had not run
# since the datapath refold. Kept as a target so that cannot happen quietly.
test-psg: test-psg-fidelity test-psg-fold test-psg-dq
	python3 tools/test_audio_analysis.py
	python3 tools/test_psg_viz.py
	verilator --binary --timing -Irtl -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
	  -Wno-PINMISSING -o psg_tb_bin rtl/psg_tb.sv rtl/psg.sv rtl/dsigma.sv \
	  --Mdir build/obj_psgtb
	build/obj_psgtb/psg_tb_bin

test-clocks:
	mkdir -p build
	verilator --binary --timing -Irtl -Wall -Wno-DECLFILENAME \
	  -Wno-UNUSEDSIGNAL -Wno-BLKSEQ -Wno-PROCASSINIT \
	  -o clocks_tb_bin rtl/clocks_tb.sv \
	  --Mdir build/obj_clockstb
	build/obj_clockstb/clocks_tb_bin

# ------------------------------------------------------------------------------
# PPU: golden-frame regression net, and its resource/timing report
# ------------------------------------------------------------------------------
# Ten scenes, each exercising a different path through the compositor, each
# compared bit-for-bit against a committed reference frame under rtl/golden/,
# plus the per-line cycle budget as a committed number. Non-zero exit on
# failure - `make test` used to exit 0 whether it passed or not.
#
#   make ppu-check                  check against the committed references
#   make ppu-check PPUARGS=+regen   regenerate them. A deliberate act: commit
#                                   the new frames WITH the change that moved
#                                   them, so the diff shows which pixels moved
#   make ppu-check PPUARGS=+inject  flip one pixel, to prove the net still bites
#   make ppu-synth                  logic, block RAM and Fmax for the PPU alone
#
# sprite_compositor.sv `include`s its submodules, the way chip.sv includes it,
# so the tools are handed one file. PPU_RTL is the wildcard that make watches
# for rebuilds; the testbench is the one rtl/ppu_*.sv that is not design source.
PPU_TOP = rtl/sprite_compositor.sv
PPU_RTL = $(PPU_TOP) $(filter-out rtl/ppu_golden_tb.sv,$(wildcard rtl/ppu_*.sv))
PPUARGS ?=

# The old binary is removed first and iverilog's exit status is checked, not
# the pipeline's: piping through `grep -v sorry:` to hide iverilog's
# unsupported-construct notices also hides its exit code, and a compile error
# then silently re-runs the PREVIOUS build - which passes, and means nothing.
build/ppu_golden.vvp: rtl/ppu_golden_tb.sv $(PPU_RTL) rtl/sprite_pattern.bin
	@mkdir -p build
	@rm -f $@
	@iverilog -g2012 -I. -Irtl -o $@ rtl/ppu_golden_tb.sv $(PPU_TOP) \
	   > build/ppu_iverilog.log 2>&1; \
	 status=$$?; grep -v 'sorry:' build/ppu_iverilog.log; exit $$status

ppu-check: ppu-lint build/ppu_golden.vvp
	@mkdir -p rtl/golden
	vvp build/ppu_golden.vvp $(PPUARGS)

# Verilator's width checking, which iverilog does not do and which the golden
# frames cannot: a truncation that happens to be equivalent still passes every
# pixel, and then breaks `make run` at the next build. Caught exactly that
# during the module split, so it runs before the frames now.
ppu-lint:
	@verilator --lint-only -Irtl -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
	   -Wno-VARHIDDEN --top-module sprite_compositor $(PPU_TOP)

# What the engine actually spends a scanline on, while a real game runs. The
# three optimisations in section 4 of the change are each gated on a number
# from here rather than on the reading of the FSM that suggested them.
#
#   make ppu-probe GAME=nemo FRAMES=400
#   make ppu-probe GAME=celeste FRAMES=400 WARMUP=150 KEYS=30:x,60:o
#
# WARMUP skips the opening frames, which matters: celeste's title screen is
# nearly empty and measuring it says the engine is idle when gameplay runs at
# 87% of the line budget.
WARMUP ?= 8
PPU_PROBE = build/obj_probe/ppu_probe
# Same established width-warning pair as the console rule above: without it a
# clean rebuild of this top_simulator.sv build fatals on the three known
# WIDTHTRUNC warnings. -Wno-MULTIDRIVEN is confined to this rule:
# --public-flat-rw defeats the inlining that lets Verilator attribute a task's
# NBA writes to its single calling always_ff, so the PSG's task-factored
# writes read as multidriven here while every non-public build of the same
# RTL is MULTIDRIVEN-clean.
$(PPU_PROBE): sim/ppu_probe.cpp rtl/*.sv rtl/*.bin rtl/*.hex
	verilator --cc rtl/top_simulator.sv --top-module top -Irtl -O2 \
		--public-flat-rw --x-assign fast --x-initial fast -Wno-DEFOVERRIDE \
		-Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-MULTIDRIVEN \
		--exe $(abspath sim/ppu_probe.cpp) -o ppu_probe --build -j 8 \
		-Mdir build/obj_probe -CFLAGS "-O2"

# nextpnr's placement is seed-dependent, and the spread on this design is about
# 5 MHz - wider than most of the deltas this change produces. A single Fmax
# number therefore cannot support "timing did not regress", so this places the
# same netlist SEEDS times and reports the range. Run `make ppu-synth` first.
#
#   make ppu-timing            5 seeds
#   make ppu-timing SEEDS=12   tighter, and slower
SEEDS ?= 5
ppu-timing:
	@test -f build/ppu/ppu.json || { echo "run 'make ppu-synth' first"; exit 1; }
	@for s in $$(seq 1 $(SEEDS)); do \
	   nextpnr-ice40 --hx8k --package tq144:4k --json build/ppu/ppu.json \
	     --asc /dev/null --freq 50 --seed $$s 2>&1 | \
	     grep 'Max frequency for clock' | tail -1 | \
	     sed -E 's/.*: ([0-9.]+) MHz.*/\1/'; \
	 done | sort -n | awk '{a[NR]=$$1} END { \
	   printf "  Fmax over %d seeds: min %.2f  median %.2f  max %.2f MHz\n", \
	          NR, a[1], a[int((NR+1)/2)], a[NR] }'

ppu-probe: hex ${FONT_HEX}
	@$(MAKE) -s $(PPU_PROBE)
	@echo "=== $(GAME) ==="
	@$(PPU_PROBE) --frames $(FRAMES) --warmup $(WARMUP) \
	  $(if $(KEYS),--keys $(KEYS),) | grep -v '^CPU Reset\|^Clocks:\|^RAM:'

ppu-synth: $(PPU_RTL)
	@mkdir -p build/ppu
	yosys -p "read_verilog -Irtl -sv $(PPU_TOP); synth_ice40 -top sprite_compositor -json build/ppu/ppu.json" > build/ppu/synth.log 2>&1
	@python3 tools/ppu_bram.py build/ppu/ppu.json
	@nextpnr-ice40 --hx8k --package tq144:4k --json build/ppu/ppu.json \
	  --asc build/ppu/ppu.asc --freq 50 --seed 1 > build/ppu/pnr.log 2>&1
	@grep -E 'ICESTORM_LC:|ICESTORM_RAM:' build/ppu/pnr.log | sed 's/^Info:/ /'
	@grep 'Max frequency for clock' build/ppu/pnr.log | tail -1 | sed 's/^Info:/ /'
	@echo "  critical path (source -> sink):"
	@awk '/Critical path report for clock/,/ns logic/' build/ppu/pnr.log | \
	  grep 'Source ' | head -1 | sed 's/^Info: */    /'
	@awk '/Critical path report for clock/,/ns logic/' build/ppu/pnr.log | \
	  grep 'Sink ' | tail -1 | sed 's/^Info: */    /'

test_ram: rtl/ram_test_tb.v rtl/ram_async.sv rtl/ram.hex
	@echo "Running RAM testbench..."
	iverilog -g2012 -o ram_test.vvp rtl/ram_test_tb.v rtl/ram_async.sv
	vvp ram_test.vvp

# The reset-vector check. It $fatal's on failure instead of printing "TEST
# FAILED" and exiting 0 (task 1.1), and it elaborates again: ram_async.sv now
# declares its parameters before the ports that use them, and the enum casts
# iverilog objected to went out with the core that had them.
#
# `make test-65x02` is the real net; this is a smoke test.
test:
	iverilog -DSIMULATION -g2012 -I rtl -y ./rtl -s cpu6502_tb rtl/cpu6502_core.sv rtl/ram_async.sv rtl/cpu6502_tb.sv && ./a.out

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
# `hex`, not `build/celeste.bin`: the $(GAME_BIN) rule is the ca65/ld65 chain,
# and celeste is on customasm now. `hex` emits the binary, the symbols and a
# ca65-format .lbl (via tools/sym_to_lbl.py) so this test tool is unchanged.
test-celeste:
	$(MAKE) GAME=celeste hex
	python3 tools/test_celeste.py build/celeste.bin build/celeste.lbl

metrics:
	python3 tools/isa_metrics.py

# ------------------------------------------------------------------------------
tools: ${FONT_CONVERT}

font: ${FONT_HEX}

# Achieved Fmax comes from nextpnr, which is the tool that knows the placement;
# icetime re-derives it from the .asc and is kept as a second opinion. Exits
# non-zero when the achieved frequency misses TARGET_FREQ (task 2.2).
#
# NOTE: this cannot run today. The whole chip does not place - rtl/ram_async.sv
# models the 64 KB main memory as an on-chip array and the hx8k has 16 KB of
# BRAM in total, so yosys emits ~1.7 M AND gates and never finishes. That is a
# memory-abstraction problem, not a CPU one; see docs/cpu-baseline.json.
# `make cpu-fmax` measures a core on its own in the meantime.
timing: bin/toplevel.asc
	@nextpnr-ice40 --${FPGA_TYPE} --package ${FPGA_PKG} --freq ${TARGET_FREQ} \
	    --json bin/toplevel.json --pcf ${FPGA_PCF} --asc /dev/null 2>&1 \
	  | tee bin/timing.log | grep -E "Max frequency|Critical path report|Info: +[0-9]+\.[0-9]+ ns" || true
	@icetime -tmd ${FPGA_TYPE} -c ${TARGET_FREQ} -p ${FPGA_PCF} -P ${FPGA_PKG} bin/toplevel.asc
	@grep -q "FAIL at" bin/timing.log && { echo "timing: achieved Fmax misses TARGET_FREQ=${TARGET_FREQ}"; exit 1; } || true

# Fmax and area for ONE core, against a real BRAM with ram_async's timing and
# no arbiter in the loop, so a difference between runs is a difference between
# cores. This is the only timing measurement available until the memory map is
# abstracted behind an interface the board's external RAM can back.
#
#   make cpu-fmax
cpu-fmax: rtl/cpu_fmax_top.sv $(SST_SRC)
	@mkdir -p build/fmax
	yosys -q -p "read_verilog -Irtl -sv rtl/cpu_fmax_top.sv; \
	    synth_ice40 -top cpu_fmax_top -json build/fmax/cpu.json" \
	    > build/fmax/cpu.yosys.log 2>&1
	@nextpnr-ice40 --${FPGA_TYPE} --package ${FPGA_PKG} --freq ${TARGET_FREQ} \
	    --json build/fmax/cpu.json --asc build/fmax/cpu.asc \
	    > build/fmax/cpu.pnr.log 2>&1 || true
	@grep -E "Max frequency for clock|ICESTORM_LC:|ICESTORM_RAM:" \
	    build/fmax/cpu.pnr.log | tail -4

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
        sim debug test_ram test-nemo test-celeste test-psg test-psg-track metrics \
        ppu-check ppu-lint ppu-synth ppu-probe ppu-timing

# ------------------------------------------------------------------------------
# 65x02 conformance suite (openspec/changes/refactor-cpu-core)
#
# Per-opcode golden tests from SingleStepTests/65x02, run against whichever
# 6502 core rtl/cpu6502_sst.sv selects. Tiers 1 and 2 gate; tier 3 is a
# diagnostic and never affects the exit code - the new core is expected to use
# FEWER cycles than NMOS, not the same ones.
#
#   make test-65x02                 fast subset (CASES per opcode), 151 opcodes
#   make test-65x02 CASES=0         the full 1.51 M sweep (~17 s)
#   make test-65x02 OPCODE=91       one opcode
#   make test-65x02 TIER3=1         report cycle activity too
#   make cpu-timing                 rewrite docs/cpu-timing-$(SST_CORE).json
#
# The suite is 1,082 MB of JSON and is never vendored: it is cloned sparsely at
# a pinned commit into $(SST_CACHE), then packed once into a 162 MB binary
# fixture that the harness mmaps. Both live outside the tree.
# ------------------------------------------------------------------------------
SST_COMMIT   = 2f6980a2d95757486c7bee24355c360e40e2a224
SST_CACHE    = $(HOME)/.cache/65x02
SST_FIXTURE  = $(HOME)/.cache/65x02-fixture/6502-v1.fx
SST_BIN      = build/obj_65x02/harness
SST_DEFS     =
SST_SRC      = rtl/cpu6502_sst.sv rtl/cpu6502_core.sv rtl/cpu6502_decode.sv
CASES       ?= 100
OPCODE      ?=
TIER3       ?=
# Opcodes whose failures are already understood and written up in
# docs/cpu-core.md. Empty, and expected to stay empty - the one entry it ever
# had was the BRK defect in the core that was replaced.
SST_KNOWN   ?=
# STALL=N drops RDY for 1..3 cycles, one chance in N per cycle, and requires
# every case to come out identical (gate T7).
STALL       ?=
SST_FLAGS    = --fixture $(SST_FIXTURE) --cases $(CASES) \
               $(if $(OPCODE),--opcode $(OPCODE),) $(if $(TIER3),--tier3,) \
               $(if $(STALL),--stall $(STALL),) \
               $(if $(SST_KNOWN),--known-failures $(SST_KNOWN),)

$(SST_CACHE)/6502/v1/ff.json:
	@echo "fetching SingleStepTests/65x02 at $(SST_COMMIT) (sparse, 6502/v1 only)"
	rm -rf $(SST_CACHE).tmp
	git clone --filter=blob:none --no-checkout --sparse \
	    https://github.com/SingleStepTests/65x02 $(SST_CACHE).tmp
	cd $(SST_CACHE).tmp && git sparse-checkout set 6502/v1 && \
	    git checkout -q $(SST_COMMIT)
	rm -rf $(SST_CACHE) && mv $(SST_CACHE).tmp $(SST_CACHE)

$(SST_FIXTURE): tools/65x02/pack.py $(SST_CACHE)/6502/v1/ff.json
	python3 tools/65x02/pack.py $(SST_CACHE)/6502/v1 $@ --commit $(SST_COMMIT)

$(SST_BIN): tools/65x02/harness.cpp $(SST_SRC)
	verilator --cc rtl/cpu6502_sst.sv --top-module cpu6502_sst -Irtl -O3 \
	    --x-assign fast --x-initial fast $(SST_DEFS) \
	    -Wno-DEFOVERRIDE -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
	    --exe $(abspath tools/65x02/harness.cpp) -o harness --build -j 8 \
	    -Mdir build/obj_65x02 -CFLAGS "-O2"

# docs/opcodes.md is the ISA programme's registry and the thing gate G2 checks
# against. Generated from the decode table so it cannot claim an instruction the
# hardware does not have; the allocation policy lives in the generator.
opcodes:
	python3 tools/65x02/gen_opcodes_md.py

# Cost a 6502 idiom on this core and on NMOS, so gate G4 can be re-scored. The
# slices were written against NMOS timing and this core is cheaper in places.
#   make isa-seq SEQ="lda zp ; sta zp"
SEQ ?= lda zp ; sta zp
isa-seq:
	@python3 tools/65x02/isa_seq.py "$(SEQ)"

# The decode table and the opcode registry must agree before any result from
# the harness means anything (task 3.2).
check-decode:
	python3 tools/65x02/check_decode.py

test-65x02: $(SST_BIN) $(SST_FIXTURE) check-decode
	$(SST_BIN) $(SST_FLAGS)

# Dormann's 6502_functional_test: ~30 M instructions of self-checking coverage
# of every documented behaviour, decimal mode included. Timing-independent, so
# it is the right check after a core swap (refactor-cpu-core gate T2).
FUNCTEST_DIR = $(HOME)/.cache/6502-functional-test
FUNCTEST_BIN = $(FUNCTEST_DIR)/6502_functional_test.bin
FUNCTEST_URL = https://github.com/Klaus2m5/6502_65C02_functional_tests/raw/master/bin_files

$(FUNCTEST_BIN):
	@mkdir -p $(FUNCTEST_DIR)
	curl -sfL -o $@ $(FUNCTEST_URL)/6502_functional_test.bin

# Directed test for the ISA extensions. The 65x02 suite predates them, so this
# is their conformance net. It is verified to be able to fail: inverting one
# comparison stops it at that check's own trap instead of at `pass`.
test-ext: $(SST_BIN)
	@mkdir -p build
	$(CUSTOMASM) tools/65x02/ext_test.asm -t 10 --color=off --legacy=off \
	    -f symbols -o build/ext_test.sym -- -f binary -o build/ext_test.bin
	@$(SST_BIN) --fixture $(SST_FIXTURE) --functest build/ext_test.bin \
	    --functest-load 0400 --functest-start 0400 \
	    --functest-pass $$(awk -F'0x' '/^pass = /{print $$2}' build/ext_test.sym)

# A migrated corpus must behave EXACTLY like its original. celeste's own suite
# passed a build whose jumps were a third of their proper height, because it
# checks that physics happens rather than that it is unchanged.
#   make migrate-check BEFORE=... BEFORE_LBL=... AFTER=... AFTER_LBL=...
migrate-check:
	python3 tools/65x02/migrate_check.py $(BEFORE) $(BEFORE_LBL) $(AFTER) $(AFTER_LBL)

# Pseudo-instructions (src/isa/pseudo.asm) expand to exactly the sequence they
# replace, so adopting them must leave the binary BIT-IDENTICAL. That is a
# stronger guarantee than any differential and it is worth keeping true: this
# rebuilds each corpus with the pseudo-op layer stubbed out - by rewriting each
# use back into its expansion - and diffs the images.
#
#   make pseudo-check              both corpora
#   make pseudo-report             sites and the pre-silicon projection
pseudo-report:
	@python3 tools/65x02/migrate_ext.py src/main.asm build/breakout.sym --pseudo
	@python3 tools/65x02/migrate_ext.py src/celeste  build/celeste.sym  --pseudo

pseudo-check:
	@mkdir -p build
	@python3 tools/65x02/pseudo_check.py

# The same check for breakout, which has no functional suite of its own - only a
# screenshot, and a screenshot cannot tell a timing artefact from a defect. The
# reference is the last pre-ISA build, rebuilt from git so this stays runnable.
# See tools/65x02/corpus_diff.py.
BREAKOUT_REF_COMMIT = f5be1c7
corpus-diff-breakout: hex
	@rm -rf build/ref && mkdir -p build/ref
	@git show $(BREAKOUT_REF_COMMIT):src/main.asm > build/ref/main.asm
	@ln -sf $(CURDIR)/src/isa build/ref/isa
	@for f in breakout_data breakout_tables breakout_sfx; do \
	   ln -sf $(CURDIR)/src/$$f.asm build/ref/$$f.asm; done
	@${CUSTOMASM} build/ref/main.asm -t 10 --color=off --legacy=off \
	  -f binary -o build/ref/pre.bin -- -f symbols -o build/ref/pre.sym >/dev/null
	@python3 tools/sym_to_lbl.py build/ref/pre.sym build/ref/pre.lbl >/dev/null
	python3 tools/65x02/corpus_diff.py \
	  build/ref/pre.bin build/ref/pre.lbl \
	  build/breakout.bin build/breakout.lbl --frames $(or $(FRAMES),200) \
	  --autopilot "$(BREAKOUT_AUTOPILOT)"

# Without this the run serves once, misses, and sits in the serve state for
# every remaining frame - which is how a binary `add` inside a `sed` block
# survived a clean differential. With it the paddle tracks the ball, rallies
# continue and the BCD score counter actually carries.
BREAKOUT_AUTOPILOT = ball=0x05,pad=0x0C,state=0x0D,play=1,left=0x01,right=0x02,fire=0x20

test-functional: $(SST_BIN) $(FUNCTEST_BIN)
	$(SST_BIN) --fixture $(SST_FIXTURE) --functest $(FUNCTEST_BIN)

# The cycle table is a RECORD of what the core does, not a target it has to
# hit: fewer cycles than NMOS is the point of the rebuild.
cpu-timing: $(SST_BIN) $(SST_FIXTURE)
	$(SST_BIN) --fixture $(SST_FIXTURE) --cases 0 --tier3 --max-report 0 \
	    --timing docs/cpu-timing-v2.json

# Static mean CPI over a corpus, weighted by the instructions it contains.
# Assembles to a listing directly rather than through `hex`, so it never
# re-stamps rtl/ram.hex out from under whatever game is resident.
# Where the cycles go, and what more bus bandwidth would buy. The question
# behind add-cpu-prefetch: pipelining is worth nothing if every cycle is
# already a byte crossing a one-byte-per-cycle bus.
cpu-bandwidth: build/$(GAME).lst
	python3 tools/65x02/bandwidth.py build/$(GAME).lst docs/cpu-timing-v2.json

cpu-static-cpi: build/$(GAME).lst
	python3 tools/65x02/static_cpi.py build/$(GAME).lst \
	    docs/cpu-timing-arlet.json docs/cpu-timing-v2.json

build/$(GAME).lst: $(GAME_SRC) $(GAME_DEPS)
	@mkdir -p build
	$(CUSTOMASM) $(GAME_SRC) -t 10 --color=off --legacy=off \
	    -f annotated -o $(abspath build/$(GAME).lst)

.PHONY: test-65x02 cpu-timing check-decode cpu-static-cpi cpu-fmax test-functional cpu-bandwidth opcodes isa-seq test-ext migrate-check

# ------------------------------------------------------------------------------
# Per-subsystem synthesis targets (openspec/changes/refactor-build-targets)
#
# Four independently compilable top-level circuits, so a subsystem's area and
# timing can be measured without the other two - and without the whole console
# having to fit, which it does not:
#
#   make synth-cpu            CPU in its real bus (arbiter + DMA + RAM)
#   make synth-psg            the PSG, and a CPU that can drive it
#   make synth-ppu            the PPU, and a CPU that can drive it
#   make synth-soc            the whole console
#   make synth-all            all four, as one table
#   make synth-psg SYNTH_SEEDS=5   report Fmax over 5 placements, not one
#
# Each rtl/target_*.sv is one instantiation of the SAME chip.sv that top.sv and
# top_simulator.sv use, with subsystems switched off by parameter - so these
# measure the shipping design and cannot drift from it. That is the whole point;
# see rtl/target_harness.sv.
#
# Why this is not called `<unit>-synth`: `ppu-synth` already exists above and
# means the compositor ALONE, with baselines committed in
# openspec/changes/refactor-ppu-core/design.md. Re-pointing it would leave every
# command working while changing what the numbers mean. Both are kept.
#
# WHAT THIS FOUND: the PSG closes at 28.24 MHz and rtl/clocks.sv drives it at
# 112.5. See docs/hardware-gaps.md.
# ------------------------------------------------------------------------------
SYNTH_UNITS = cpu psg ppu soc
SYNTH_DIR   = build/targets
# Private to this block: `SEEDS` above belongs to ppu-timing and defaults to 5.
SYNTH_SEEDS ?= 1

# The PSG has two independently constrained related-clock domains: the full
# datapath stays at 18.75 MHz while only the multi-pumped multiplier closes at
# the 112.5 MHz PLL rate. Its closed-loop bundled-data CDC makes inter-domain
# paths false for single-cycle timing; nextpnr's --ignore-rel-clk excludes
# those paths while the SDC retains both same-domain requirements.
SYNTH_TIMING_cpu = --freq $(TARGET_FREQ)
SYNTH_TIMING_psg = --sdc rtl/target_psg.sdc --ignore-rel-clk
SYNTH_TIMING_ppu = --freq $(TARGET_FREQ)
SYNTH_TIMING_soc = --freq $(TARGET_FREQ)

# router1 repeatedly plateaus with 1,000 unresolved arcs on the 97%-full PSG,
# including both the pre-R.74 baseline and the smaller R.74 candidate. router2
# completes the same seed and is therefore part of the reproducible PSG flow,
# not an ad-hoc post-processing command.
SYNTH_ROUTER_psg = --router router2

# Floor on logic cells per target. A subsystem whose outputs all fold to
# constants is trimmed to nothing and still reports a PASS with a spectacular
# Fmax - it is measuring the empty space where the design used to be. That
# happened three times while building these targets: 193 MHz with the critical
# path inside the video timing generator, then 103 cells after an
# observability tie-off replicated one bit across a bus that the probe
# XOR-reduces back to a constant. Both looked like results.
#
# These are floors, not targets: set well below the real figure, they only
# catch collapse.
SYNTH_MIN_LC_cpu = 800
SYNTH_MIN_LC_psg = 4000
SYNTH_MIN_LC_ppu = 2500
SYNTH_MIN_LC_soc = 6000
# Every design file, so a change anywhere re-synthesises. The target tops pull
# what they need through `include, the way chip.sv does.
SYNTH_DEPS  = $(wildcard rtl/*.sv) $(wildcard rtl/*.v) $(wildcard rtl/*.hex) \
              $(wildcard rtl/*.bin)

# Reports utilisation whether or not placement succeeded: `soc` is expected to
# fail until add-memory-subsystem lands, and "139% of the device" is a result,
# not an error. nextpnr's exit status is therefore not the gate here.
define SYNTH_RULES
$(SYNTH_DIR)/$(1).json: rtl/target_$(1).sv $$(SYNTH_DEPS)
	@mkdir -p $(SYNTH_DIR)
	@yosys -p "read_verilog -Irtl -sv rtl/target_$(1).sv; \
	    synth_ice40 -top target_$(1) -json $$@" \
	  > $(SYNTH_DIR)/$(1).synth.log 2>&1 \
	  || { echo "synth-$(1): yosys FAILED, see $(SYNTH_DIR)/$(1).synth.log"; \
	       tail -5 $(SYNTH_DIR)/$(1).synth.log; exit 1; }

synth-$(1): $(SYNTH_DIR)/$(1).json
	@echo "=== $(1) ==="
	@# A number without an RTL fingerprint is not reproducible across revisions.
	@# Quote the fingerprint whenever a measurement is recorded. rtl/pll.v is
	@# generated (gitignored) - excluded, or identical trees fingerprint apart.
	@printf "  rtl %s @ %s\n" \
	  "$$$$(cat rtl/*.sv $$$$(ls rtl/*.v 2>/dev/null | grep -v '^rtl/pll\.v$$$$') 2>/dev/null | shasum | cut -c1-12)" \
	  "$$$$(git rev-parse --short HEAD 2>/dev/null || echo no-git)"
	@nextpnr-ice40 --$(FPGA_TYPE) --package $(FPGA_PKG) \
	    --json $(SYNTH_DIR)/$(1).json --asc $(SYNTH_DIR)/$(1).asc \
	    $$(SYNTH_TIMING_$(1)) $$(SYNTH_ROUTER_$(1)) --seed 1 \
	    > $(SYNTH_DIR)/$(1).pnr.log 2>&1 || true
	@# Anchor on the "N/M" shape of the utilisation table. A bare
	@# 'ICESTORM_LC:' also matches the placer's per-iteration log lines
	@# ("type ICESTORM_LC: wirelen solved = 55"), which silently replaced the
	@# utilisation figures with placer noise.
	@grep -E '(ICESTORM_LC|ICESTORM_RAM|SB_IO): +[0-9]+/' $(SYNTH_DIR)/$(1).pnr.log \
	  | tail -3 | sed 's/^Info:/ /'
	@# nextpnr reports Fmax twice per clock (after placement, after routing);
	@# keep the LAST figure for each clock name, which is the routed one.
	@grep 'Max frequency for clock' $(SYNTH_DIR)/$(1).pnr.log \
	  | awk '{ last[$$$$6] = $$$$0 } END { for (c in last) print " " last[c] }' \
	  | sed 's/Info://' || true
	@# nextpnr calls BOTH "could not place" and "missed the frequency target"
	@# an ERROR. Only the first means the design does not fit, and conflating
	@# them reports a placed-but-slow design as unbuildable.
	@lc=$$$$(grep -E 'ICESTORM_LC: +[0-9]+/' $(SYNTH_DIR)/$(1).pnr.log \
	        | tail -1 | sed -E 's#.*ICESTORM_LC: +([0-9]+)/.*#\1#'); \
	 if [ -n "$$$$lc" ] && [ "$$$$lc" -lt "$(SYNTH_MIN_LC_$(1))" ]; then \
	   echo "  *** TRIMMED: $$$$lc logic cells is below the floor of $(SYNTH_MIN_LC_$(1))."; \
	   echo "  *** The design folded to constants - this measures nothing."; \
	   echo "  *** Check that every subsystem has a non-constant path to the probe."; \
	   exit 1; \
	 fi
	@if grep '^ERROR' $(SYNTH_DIR)/$(1).pnr.log | grep -qv 'Max frequency'; then \
	   echo "  DOES NOT PLACE:"; \
	   grep '^ERROR' $(SYNTH_DIR)/$(1).pnr.log | grep -v 'Max frequency' \
	     | head -2 | sed 's/^/    /'; \
	 else \
	   echo "  critical path (source -> sink):"; \
	   awk '/Critical path report for clock/,/ns logic/' $(SYNTH_DIR)/$(1).pnr.log \
	     | grep 'Source ' | head -1 | sed 's/^Info: */    /'; \
	   awk '/Critical path report for clock/,/ns logic/' $(SYNTH_DIR)/$(1).pnr.log \
	     | grep 'Sink ' | tail -1 | sed 's/^Info: */    /'; \
	 fi
	@if [ "$(SYNTH_SEEDS)" != "1" ]; then $$(MAKE) -s synth-seeds-$(1); fi

# Placement is seed-dependent with about a 5 MHz spread on this design - wider
# than most deltas worth chasing - so a single number cannot support "timing did
# not regress".
synth-seeds-$(1): $(SYNTH_DIR)/$(1).json
	@for s in $$$$(seq 1 $(SYNTH_SEEDS)); do \
	   nextpnr-ice40 --$(FPGA_TYPE) --package $(FPGA_PKG) \
	     --json $(SYNTH_DIR)/$(1).json --asc /dev/null \
	     $$(SYNTH_TIMING_$(1)) $$(SYNTH_ROUTER_$(1)) --seed $$$$s 2>&1 | \
	     grep 'Max frequency for clock' | tail -1 | \
	     sed -E 's/.*: ([0-9.]+) MHz.*/\1/'; \
	 done | sort -n | awk 'NF{a[++n]=$$$$1} END { if (n) \
	   printf "  Fmax over %d seeds: min %.2f  median %.2f  max %.2f MHz\n", \
	          n, a[1], a[int((n+1)/2)], a[n]; \
	   else print "  Fmax over seeds: design does not place" }'
endef

$(foreach u,$(SYNTH_UNITS),$(eval $(call SYNTH_RULES,$(u))))

synth-all: $(foreach u,$(SYNTH_UNITS),synth-$(u))

.PHONY: synth-all $(foreach u,$(SYNTH_UNITS),synth-$(u) synth-seeds-$(u))

# ------------------------------------------------------------------------------
# PSG candidate gates
# ------------------------------------------------------------------------------
# Two commands for the two questions an area candidate has to answer, in the
# order that costs least. `area-psg` is one build and decides whether the
# candidate is a measurement at all; `gates-psg` is ~20 minutes and only makes
# sense once it is.
#
#   make area-psg RECORD=1     capture the accepted tree as the baseline
#   make area-psg              measure a candidate and apply the band rule
#   make gates-psg CART=...    the correctness battery, fail-fast
#   make gates-psg CART=... GATES_FROM=oracle    resume after a fix
#
# Running the battery before the area verdict is the expensive mistake here: a
# candidate that turns out to be inside the naming band has then paid twenty
# minutes plus the cost of reading every log, to learn nothing. See
# .claude/skills/fpga-area-reduction/ for the full funnel and the band rule.
GATES_FROM ?=

area-psg:
	@tools/psg_area_gate.sh $(if $(RECORD),record,)

gates-psg:
	@tools/psg_gates.sh $(if $(CART),--cart $(CART),) \
	  $(if $(GATES_FROM),--from $(GATES_FROM),)

.PHONY: area-psg gates-psg

# ------------------------------------------------------------------------------
# Board: Sipeed Tang Nano 20K (Gowin GW2AR-LV18QN88C8/I7)
#
# The second board this design targets. Everything above builds for the myStorm
# BlackIce MX (iCE40 HX8K) through icestorm; this block builds for the Tang
# Nano 20K through the Gowin open-source chain, from the SAME RTL. Only the
# top, the PLL primitive and the constraints differ - rtl/top_tangnano20k.sv,
# rtl/pll_gowin.v, rtl/tangnano20k.cst.
#
#   make boards               what the two boards are, and what they cost
#   make tangnano20k          bin/toplevel.fs, the bitstream
#   make tangnano20k-synth    area report only, no place-and-route
#   make tangnano20k-prog     load into SRAM (volatile, gone at power-off)
#   make tangnano20k-flash    write to the onboard 64 Mbit flash (persistent)
#
# GAME selects the program exactly as it does everywhere else, because the
# bitstream depends on `hex`:
#
#   make tangnano20k GAME=nemo
#
# Toolchain (none of it is the icestorm chain):
#
#   yosys                 synth_gowin, same yosys as the iCE40 path
#   nextpnr-himbaechel    place and route, with the gowin uarch
#   gowin_pack            bitstream, from Project Apicula (pip install apycula)
#   openFPGALoader        programming, over the onboard BL616 debugger
#
# The easiest way to get a matched set on macOS or Linux is the YosysHQ
# oss-cad-suite tarball, which ships all four. See docs/boards.md.
# ------------------------------------------------------------------------------
GOWIN_TOP     = rtl/top_tangnano20k.sv
GOWIN_CST     = rtl/tangnano20k.cst
# The part as nextpnr names it, the die as apicula names it. The GW2AR-18C is
# the GW2A-18C die with 64 Mbit of SDRAM in the package, so the chipdb and the
# packer both want the plain GW2A-18C.
GOWIN_DEVICE  = GW2AR-LV18QN88C8/I7
GOWIN_FAMILY  = GW2A-18C
GOWIN_DIE     = GW2A-18C
NEXTPNR_GOWIN = nextpnr-himbaechel
GOWIN_PACK    = gowin_pack
OFL           = openFPGALoader
OFL_BOARD     = tangnano20k

# Placer seed. Exposed because this nextpnr-himbaechel build can SEGFAULT while
# routing, deterministically for a given placement, in the fallback path it
# takes after "Failed to route net ... using dedicated routing" (a CE/LSR net
# that would not fit on the dedicated resource). Another seed places those nets
# elsewhere and the crash goes away:
#
#   make tangnano20k GOWIN_SEED=2
#
# It is a tool bug, not a design error - the same design routes cleanly on other
# seeds - so treat a segfault as "try the next seed", not as something to fix in
# the RTL. Worth re-testing against a newer nextpnr before chasing it further.
GOWIN_SEED   ?= 1

# Not INCLUDE_FILES: that is `rtl/**/*.v`, and make does not know `**`, so it
# globs to `rtl/*/*.v` and then demands a rule for the literal `rtl/golden/*.v`
# when no file matches. The design is one flat directory, so say so.
GOWIN_SRC = $(wildcard rtl/*.sv) $(wildcard rtl/*.v) \
            $(wildcard rtl/*.hex) $(wildcard rtl/*.bin)

# `delete t:$print` strips the $display cells yosys keeps out of the `initial`
# blocks in ram_async.sv and clocks.sv. They are simulation artifacts with no
# hardware meaning, and handing them to a place-and-route tool is asking it to
# find a cell type it has no bel for.
build/gowin/top.json: ${GOWIN_TOP} ${GOWIN_SRC} ${FONT_HEX} hex
	@mkdir -p build/gowin
	yosys -p "read_verilog -Irtl -sv ${GOWIN_TOP}; \
	          synth_gowin -top top -json $@; \
	          delete t:\$$print; \
	          write_json $@" > build/gowin/synth.log 2>&1

# Area against the datasheet's numbers, with block RAM broken down by consumer
# - which is the interesting column, because block RAM is what this device is
# nearly out of (45 of 46) and logic is not (42%).
tangnano20k-synth: build/gowin/top.json
	@python3 tools/gowin_stat.py $<

build/gowin/top_pnr.json: build/gowin/top.json ${GOWIN_CST}
	${NEXTPNR_GOWIN} --json $< --write $@ \
	    --device ${GOWIN_DEVICE} \
	    --vopt family=${GOWIN_FAMILY} \
	    --vopt cst=${GOWIN_CST} \
	    --seed ${GOWIN_SEED} > build/gowin/pnr.log 2>&1
	@grep -E '(LUT4|ALU|DFF|BSRAM|MULT18X18|rPLL|IOB): +[0-9]+/' build/gowin/pnr.log \
	  | sed 's/^Info:/ /' || true
	@# nextpnr is run WITHOUT a frequency target, on purpose. `--freq` applies one
	@# number to every unconstrained domain, and this design has three that differ
	@# by 32x - constraining cpuclk at the PSG's 112.5 MHz would report a domain
	@# with 14x of margin as failing. So take the per-domain Fmax nextpnr reports
	@# anyway and check each against what the design actually asks of it
	@# (rtl/clocks.sv). Fmax is printed twice per clock, after placement and after
	@# routing; keep the LAST, which is the routed one.
	@echo "  timing, against what rtl/clocks.sv asks of each domain:"
	@grep 'Max frequency for clock' build/gowin/pnr.log \
	  | sed "s/.*clock *'//; s/': */ /; s/ MHz.*//" \
	  | awk '{ f[$$1] = $$2 } END { \
	      need["pllclk"] = 112.5; need["cpuclk"] = 3.515625; \
	      for (c in f) if (c in need) \
	        printf "    %-9s %8.2f MHz achieved, %10.4f needed   %s\n", \
	               c, f[c], need[c], (f[c] >= need[c] ? "ok" : "*** SHORT ***"); \
	      else printf "    %-9s %8.2f MHz achieved   (derived clock, no target)\n", c, f[c] }'

bin/toplevel.fs: build/gowin/top_pnr.json
	@mkdir -p bin
	${GOWIN_PACK} -d ${GOWIN_DIE} -o $@ $<

tangnano20k: bin/toplevel.fs

# SRAM, not flash: this is the one to use while iterating, and the board comes
# back up with whatever is in flash after a power cycle.
tangnano20k-prog: bin/toplevel.fs
	${OFL} -b ${OFL_BOARD} bin/toplevel.fs

tangnano20k-flash: bin/toplevel.fs
	${OFL} -b ${OFL_BOARD} -f bin/toplevel.fs

boards:
	@echo "Boards this design targets:"
	@echo
	@printf '  %-14s %s\n' 'blackice' 'myStorm BlackIce MX - iCE40 HX8K, 25 MHz  [default]'
	@printf '  %-14s %s\n' ''         '  make all / make upload'
	@printf '  %-14s %s\n' ''         '  8 KB RAM only: 64 KB does not fit, so it cannot run a game'
	@echo
	@printf '  %-14s %s\n' 'tangnano20k' 'Sipeed Tang Nano 20K - Gowin GW2AR-18C, 27 MHz'
	@printf '  %-14s %s\n' ''           '  make tangnano20k / make tangnano20k-prog'
	@printf '  %-14s %s\n' ''           '  the full 64 KB RAM, in 32 of the 46 block RAMs'
	@echo
	@echo "  make tangnano20k-synth       area report, no place-and-route"
	@echo "  See docs/boards.md for the toolchain and the pin map."

.PHONY: boards tangnano20k tangnano20k-synth tangnano20k-prog tangnano20k-flash

# Standalone Tang Nano 20K audio image. This proves the board-specific pieces
# without needing an LCD: the Celeste audio image is staged through the 64 Mbit
# SiP SDRAM, verified byte-for-byte, uploaded to the PSG, and music 0 is sent
# to the onboard MAX98357A speaker amplifier.
GOWIN_PSG_TOP = rtl/top_tangnano20k_psg.sv
GOWIN_PSG_CST = rtl/tangnano20k_psg.cst
GOWIN_PSG_DIR = build/gowin_psg
GOWIN_PSG_FS  = bin/tangnano20k-psg.fs

$(GOWIN_PSG_DIR)/celeste-audio.hex: src/celeste/audio.inlay.asm
	@mkdir -p $(GOWIN_PSG_DIR)
	@awk '/^[[:space:]]*#d8 / { for (i = 2; i <= NF; i++) \
	  print tolower(substr($$i, 2, 2)) }' $< > $@
	@test "$$(wc -l < $@ | tr -d ' ')" = 4608 || { \
	  echo "error: expected 4608 Celeste audio bytes in $@"; exit 1; }

$(GOWIN_PSG_DIR)/top.json: $(GOWIN_PSG_TOP) $(GOWIN_SRC) \
                           $(GOWIN_PSG_DIR)/celeste-audio.hex
	@mkdir -p $(GOWIN_PSG_DIR)
	yosys -p "read_verilog -Irtl -sv $(GOWIN_PSG_TOP); \
	          synth_gowin -top top_psg -json $@; \
	          delete t:\$$print; write_json $@" \
	  > $(GOWIN_PSG_DIR)/synth.log 2>&1

$(GOWIN_PSG_DIR)/top_pnr.json: $(GOWIN_PSG_DIR)/top.json $(GOWIN_PSG_CST)
	$(NEXTPNR_GOWIN) --json $< --write $@ \
	    --device $(GOWIN_DEVICE) --vopt family=$(GOWIN_FAMILY) \
	    --vopt cst=$(GOWIN_PSG_CST) --seed $(GOWIN_SEED) \
	    > $(GOWIN_PSG_DIR)/pnr.log 2>&1
	@grep -E '(LUT4|ALU|DFF|BSRAM|MULT18X18|rPLL|IOB): +[0-9]+/' \
	  $(GOWIN_PSG_DIR)/pnr.log | sed 's/^Info:/ /' || true
	@grep 'Max frequency for clock' $(GOWIN_PSG_DIR)/pnr.log | tail -8 || true

$(GOWIN_PSG_FS): $(GOWIN_PSG_DIR)/top_pnr.json
	@mkdir -p bin
	$(GOWIN_PACK) -d $(GOWIN_DIE) -o $@ $<

tangnano20k-psg: $(GOWIN_PSG_FS)

tangnano20k-psg-prog: $(GOWIN_PSG_FS)
	$(OFL) -b $(OFL_BOARD) $<

tangnano20k-psg-flash: $(GOWIN_PSG_FS)
	$(OFL) -b $(OFL_BOARD) -f $<

.PHONY: tangnano20k-psg tangnano20k-psg-prog tangnano20k-psg-flash

# ------------------------------------------------------------------------------
# Inlay Assembly frontend and maintained Celeste port
#
# The portable C core owns layout semantics. The host shell emits customasm;
# customasm remains the instruction encoder while the native encoder is
# deferred. Celeste's checked-in Inlay entry owns its object layout and typed
# modules; the direct customasm entry remains an independent equivalence oracle.
# ------------------------------------------------------------------------------
INLAY_CC               ?= cc
INLAY_HOST              = build/inlay/inlay
INLAY_CORE_TEST         = build/inlay/test_inlay
INLAY_MODULE_TEST       = build/inlay/test_modules
LAASM_COMPAT            = build/laasm/laasm
CELESTE_INLAY_DIR       = build/inlay
CELESTE_INLAY_SOURCE    = src/celeste/main.inlay.asm
CELESTE_INLAY_DEPS      = $(filter-out $(CELESTE_INLAY_SOURCE),$(celeste_DEPS)) \
                          $(wildcard src/isa/*.asm)
CELESTE_INLAY_ASM       = $(CELESTE_INLAY_DIR)/celeste.asm
CELESTE_INLAY_MAP       = $(CELESTE_INLAY_DIR)/celeste.map.json

$(INLAY_HOST): tools/inlay/inlay.h tools/inlay/inlay_core.c \
               tools/inlay/inlay_modules.c tools/inlay/inlay_host.c
	@mkdir -p $(@D)
	$(INLAY_CC) -std=c99 -pedantic -Wall -Wextra -Werror \
	  tools/inlay/inlay_core.c tools/inlay/inlay_modules.c \
	  tools/inlay/inlay_host.c -o $@

$(INLAY_CORE_TEST): tools/inlay/inlay.h tools/inlay/inlay_core.c \
                    tools/inlay/test_inlay.c
	@mkdir -p $(@D)
	$(INLAY_CC) -std=c89 -pedantic -Wall -Wextra -Werror \
	  tools/inlay/inlay_core.c tools/inlay/test_inlay.c -o $@

$(INLAY_MODULE_TEST): tools/inlay/inlay.h tools/inlay/inlay_core.c \
                      tools/inlay/inlay_modules.c tools/inlay/test_modules.c
	@mkdir -p $(@D)
	$(INLAY_CC) -std=c89 -pedantic -Wall -Wextra -Werror \
	  tools/inlay/inlay_core.c tools/inlay/inlay_modules.c \
	  tools/inlay/test_modules.c -o $@

$(LAASM_COMPAT): $(INLAY_HOST) tools/inlay/laasm-compat.sh
	@mkdir -p $(@D)
	cp tools/inlay/laasm-compat.sh $@
	chmod +x $@

$(CELESTE_INLAY_ASM): $(INLAY_HOST) $(CELESTE_INLAY_SOURCE) \
                      $(CELESTE_INLAY_DEPS) $(celeste_DEPS)
	@mkdir -p $(@D)
	$(INLAY_HOST) --target console6502 --output $@ \
	  --map $(CELESTE_INLAY_MAP) $(CELESTE_INLAY_SOURCE)

test-inlay: $(INLAY_HOST) $(LAASM_COMPAT) $(INLAY_CORE_TEST) $(INLAY_MODULE_TEST)
	$(INLAY_CORE_TEST)
	$(INLAY_MODULE_TEST)
	python3 tools/inlay/test_modules_host.py $(INLAY_HOST)
	sh tools/inlay/check_portable.sh
	python3 tools/inlay/test_conformance.py

test-celeste-inlay-equivalence: $(INLAY_HOST) $(LAASM_COMPAT)
	python3 tools/inlay/test_conformance.py

# Compatibility aliases; canonical output and test labels use Inlay.
test-layout-asm: test-inlay
test-celeste-layout-equivalence: test-celeste-inlay-equivalence

# Multiple rules add prerequisites without replacing the existing recipes.
test: test-inlay
test-celeste: test-celeste-inlay-equivalence

# Opt Celeste into the checked-in frontend source while preserving the existing
# customasm command, output formats, symbol conversion and source dependencies.
ifeq ($(GAME),celeste)
GAME_SRC := $(CELESTE_INLAY_ASM)
hex: $(CELESTE_INLAY_ASM)
endif

.PHONY: test-inlay test-celeste-inlay-equivalence test-layout-asm \
        test-celeste-layout-equivalence
