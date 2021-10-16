INCLUDE_FILES = rtl/**/*.v rtl/**/*.sv rtl/**/*.hex rtl/**/*.bin
TOP_LEVEL = rtl/top.sv
PCF_FILE = rtl/top.pcf
PLL_FILE = rtl/pll.v

TARGET_FREQ = 50

${PLL_FILE}:
	icepll -q -i 25 -o ${TARGET_FREQ} -m -f ${PLL_FILE}
	sed -i '' -e 's/PLLOUTCORE/PLLOUTGLOBAL/g' ${PLL_FILE}

bin/toplevel.bin: bin/toplevel.asc
	icepack bin/toplevel.asc bin/toplevel.bin

bin/toplevel.asc: ${PCF_FILE} bin/toplevel.json
	nextpnr-ice40 -q --freq ${TARGET_FREQ} --hx8k --package tq144:4k \
				  --json bin/toplevel.json --pcf ${PCF_FILE} \
				  --asc bin/toplevel.asc --opt-timing

bin/toplevel.json: ${TOP_LEVEL} ${INCLUDE_FILES} ${PLL_FILE}
	mkdir -p bin
	yosys -q -p "read_verilog -Irtl -sv ${TOP_LEVEL}; synth_ice40 -abc9 -dsp -top top -json bin/toplevel.json" 

rust/rtl:
	cd rust && ln -s ../rtl rtl 

.PHONY: stat
stat: bin/toplevel.asc
	icebox_stat -v bin/toplevel.asc

.PHONY: timing
timing: bin/toplevel.bin
	icetime -tmd hx8k -c ${TARGET_FREQ} -p ${PCF_FILE} -P tq144:4k bin/toplevel.asc

.PHONY: upload
upload: bin/toplevel.bin
	stty -f /dev/cu.usbmodem00000000001A1 raw 
	cat bin/toplevel.bin >/dev/cu.usbmodem00000000001A1

.PHONY: run
run: rust/rtl
	cp rtl/*.hex rust/
	cp rtl/*.bin rust/
	cd rust && cargo run --release

.PHONY: clean
clean:
	rm -rf ${PLL_FILE} bin rust/rtl rust/*.hex rust/*.bin
	cd rust && cargo clean
