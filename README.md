# 8-bit Console on FPGA

A complete 8-bit console implementation on FPGA, featuring a 6502 CPU, video system, and memory architecture. The project supports both simulation through Verilator and deployment on BlackIce MX (Lattice Ice40) FPGA.

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

## Building and Running

### Simulation
```bash
make run
```
This will:
1. Compile the RTL through Verilator
2. Generate Rust bindings
3. Run the simulation with real-time display
4. Show a 160x121 window with 4x scaling

### FPGA Deployment
```bash
make upload
```
This will:
1. Synthesize the design for BlackIce MX
2. Generate the bitstream
3. Upload to the FPGA

## Project Structure
```
.
├── rtl/              # RTL source files
│   ├── cpu6502.sv   # 6502 CPU implementation
│   ├── lcd.sv       # LCD controller
│   ├── sprite.sv    # Sprite system
│   └── ...
├── rust/            # Simulation environment
│   ├── src/         # Rust source code
│   └── build.rs     # Build script
└── bin/             # Binary files and resources
```

## Memory Map
- 0x0000-0x0FFF: Main RAM
- 0x1000-0x1FFF: Text buffer
- 0x2000-0x2FFF: Sprite memory
- 0x3000-0x3FFF: I/O space

## Contributing
Pull requests are welcome! The project particularly needs:
- Additional display driver support
- Performance optimizations
- Documentation improvements
- Test coverage

## License
This project is open source. Feel free to use it in any project (commercial or not), as long as you keep the copyright notice and this message. The code is provided "as is", without any warranties of any kind.
