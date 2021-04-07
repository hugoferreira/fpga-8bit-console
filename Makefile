INCLUDE_FILES = rtl/**/*.v rtl/**/*.sv rtl/**/*.hex rtl/**/*.bin
TOP_LEVEL = rtl/top.sv
PCF_FILE = rtl/top.pcf
TARGET_FREQ = 60

bin/toplevel.bin: bin/toplevel.asc
	icepack bin/toplevel.asc bin/toplevel.bin

bin/toplevel.asc: ${PCF_FILE} bin/toplevel.json
	nextpnr-ice40 -q --freq ${TARGET_FREQ} --hx8k --package tq144:4k \
				  --json bin/toplevel.json --pcf ${PCF_FILE} \
				  --asc bin/toplevel.asc --opt-timing

bin/toplevel.json: ${TOP_LEVEL} ${INCLUDE_FILES}
	mkdir -p bin
	yosys -q -p "read_verilog -Irtl -sv ${TOP_LEVEL}; synth_ice40 -top top -json bin/toplevel.json -abc2" 

.PHONY: stat
stat: bin/toplevel.asc
	icebox_stat -v bin/toplevel.asc

.PHONY: timing
timing: bin/toplevel.bin
	icetime -tmd hx8k bin/toplevel.asc

.PHONY: upload
upload: bin/toplevel.bin
	stty -f /dev/cu.usbmodem00000000001A1 raw 
	cat bin/toplevel.bin >/dev/cu.usbmodem00000000001A1

.PHONY: clean
clean:
	rm -rf bin
