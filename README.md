# 8-bit Console on FPGA

A complete 8-bit console implementation on FPGA, featuring a 6502 CPU, video system, and memory architecture. The project supports simulation through Verilator and deployment on two boards: the BlackIce MX (Lattice iCE40 HX8K) and the Sipeed Tang Nano 20K (Gowin GW2AR-18C). Run `make boards` for the differences, or read [`docs/boards.md`](docs/boards.md) — the short version is that the 64 KB main memory only fits on the Tang Nano.

## Architecture Overview

### Core Components
- **CPU**: 6502 implementation with basic instruction set support
- **Memory System**:
  - 8KB main RAM
  - Video RAM for text and graphics
  - Sprite memory
  - Memory-mapped I/O
- **Video System**:
  - 320x240 resolution
  - 16-bit color (5-6-5 RGB)
  - Text mode with character buffer
  - Hardware sprite support
  - Multiple color palettes
- **Display Support**:
  - ST7735 LCD driver
  - ST7789 LCD driver (different resolutions)
  - Multiple initialization ROMs

### Simulation Features
- Real-time visualization through framebuffer
- 60 FPS display
- Multi-threaded architecture
- Hardware-accelerated rendering
- Debug capabilities (frame timing, VCD traces)

Audio renders, reference comparisons, composable terminal visualizations,
spectrograms, and per-SFX diagnosis share one documented tool:
[`docs/audio-analysis.md`](docs/audio-analysis.md). Its
default full-track verdict policy and checked JSON contract are explicit in
[`docs/schemas/audio-analysis-v2.schema.json`](docs/schemas/audio-analysis-v2.schema.json);
the guide includes reproducible coloured captures of the terminal panels.

## Prerequisites

### Required Tools
- [Rust](https://www.rust-lang.org/tools/install)
  ```bash
  # MacOS
  brew install rustup-init
  rustup install stable
  rustup default stable
  ```
- [Verilator](https://www.veripool.org/projects/verilator/wiki/Installing)
  ```bash
  # MacOS
  brew install verilator
  # Debian-based
  apt-get install verilator
  # Arch-based
  pamac build verilator
  ```
- [customasm](https://github.com/hlorenzi/customasm) - 6502 assembler, `#ruledef`-based
  ```bash
  cargo install customasm --version 0.14.1
  ```
- [cc65](https://cc65.github.io/) - 6502 Assembler/Compiler, only needed for
  `nemo`/`celeste` (`make asm-ca65`; see `docs/assembler.md`), not for
  building the console's own primary software
  ```bash
  # MacOS
  brew install cc65
  # Debian-based
  apt-get install cc65
  ```

## Building and Running

### Assembly Code
```bash
make asm
```
This will:
1. Assemble `src/main.asm` with customasm, using the instruction set and
   memory map defined in `src/isa/` (replacing `src/memory.cfg`)
2. Generate a hex file (`rtl/ram.hex`) and a symbol file (`build/breakout.sym`)
   that will be loaded into the FPGA's memory / used by the simulator

See `docs/assembler.md` for the ca65 → customasm migration and syntax map.

### Simulation
```bash
make run
```
This will:
1. Build the assembly code if needed
2. Compile the RTL through Verilator
3. Generate Rust bindings
4. Run the simulation with real-time display
5. Show a 160x121 window with 4x scaling

### FPGA Deployment

BlackIce MX (iCE40 HX8K):
```bash
make upload
```
This will:
1. Build the assembly code if needed
2. Synthesize the design for BlackIce MX
3. Generate the bitstream
4. Upload to the FPGA

Note this bitstream builds the chip with an 8 KB main memory, not 64 KB, and so
cannot run a game — 64 KB does not fit in an HX8K's block RAM. See
[`docs/memory-subsystem.md`](docs/memory-subsystem.md).

Tang Nano 20K (Gowin GW2AR-18C), which does carry the full 64 KB:
```bash
make tangnano20k          # bin/toplevel.fs
make tangnano20k-prog     # load it (SRAM; -flash to persist)
make tangnano20k-synth    # area report only
make boards               # what the two boards are
```
Needs yosys, `nextpnr-himbaechel`, `gowin_pack` (Project Apicula) and
`openFPGALoader` — see [`docs/boards.md`](docs/boards.md) for the toolchain, the
pin map and what has and has not been verified on hardware.

## Project Structure
```
.
├── rtl/              # RTL source files
│   ├── cpu6502.sv    # 6502 CPU implementation
│   ├── lcd.sv        # LCD controller
│   ├── sprite.sv     # Sprite system
│   ├── ram.hex       # Generated hex file from assembly
│   └── ...
├── rust/             # Simulation environment
│   ├── src/          # Rust source code
│   └── build.rs      # Build script
├── src/              # Assembly source code
│   ├── main.asm      # Main assembly program
│   └── isa/          # Instruction set, memory map, register constants
└── bin/              # Binary files and resources
```

## Memory Map
- 0x0000-0x0FFF: Main RAM
- 0x1000-0x1FFF: Text buffer
- 0x2000-0x2FFF: Sprite memory
- 0x3000-0x3FFF: I/O space
- 0x4000-0x4FFF: Memory-mapped I/O for peripherals

## Memory Layout and Organization

The system uses a 16-bit address space, typical for 6502-based systems, allowing for a total of 64KB of addressable memory. The memory is organized as follows:

### Code Segment (0x0100-0x0FFF)
- **Reset Vector**: The 6502 CPU starts execution from the address specified in the reset vector (0xFFFC-0xFFFD)
- **Program Code**: The main assembly program is loaded starting at address 0x0100
- **Zero Page**: Addresses 0x0000-0x00FF are reserved for zero-page operations, which are more efficient on the 6502

### RAM (0x0000-0x0FFF)
- General-purpose RAM for variables, stack, and program data
- The 6502 stack operates in the range 0x0100-0x01FF

### Video Memory (0x1000-0x2FFF)
- **Text Buffer** (0x1000-0x1FFF): Stores character data for text mode
- **Sprite Memory** (0x2000-0x2FFF): Stores sprite data including positions, patterns, and attributes

### I/O Regions (0x3000-0x4FFF)
- **System I/O** (0x3000-0x3FFF): Control registers for system peripherals
- **External I/O** (0x4000-0x4FFF): Memory-mapped I/O for external devices
  - 0x4000: Example I/O port used in the demo program

### Memory Configuration
The memory layout is defined in `src/isa/memmap.asm` as customasm `#bankdef`s,
which place the assembled code at the correct addresses. The file specifies
the size and location of each memory region (zero page, stack, RAM, vectors).

### Memory Loading
At system startup:
1. The contents of `rtl/ram.hex` are loaded into the FPGA's memory using Verilog's `$readmemh` function
2. The 6502 CPU begins execution from the reset vector
3. The program in the CODE segment begins running, interacting with I/O devices through memory-mapped registers

## Assembly Build Process
The project uses [customasm](https://github.com/hlorenzi/customasm) to build
the 6502 assembly code (see `docs/assembler.md` for the full picture):

1. `customasm` assembles `src/main.asm` directly, in one command - no
   intermediate object file or linker step
2. It emits three outputs in the same invocation: `build/breakout.bin`
   (binary), `build/breakout.sym` (symbol table), and `rtl/ram.hex`
   (`$readmemh`-format hex, loaded into the FPGA's memory at startup)

`nemo` and `celeste` are unmigrated ISA corpora and still build with the
ca65/ld65/hexdump chain via `make asm-ca65 GAME=nemo`.

## Contributing
Pull requests are welcome! The project particularly needs:
- Additional display driver support
- Performance optimizations
- Documentation improvements
- Test coverage

## License
This project is open source. Feel free to use it in any project (commercial or not), as long as you keep the copyright notice and this message. The code is provided "as is", without any warranties of any kind.
