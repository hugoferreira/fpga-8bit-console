# 8-bit console implemented on an FPGA 

## How to Run

- [Install Rust](https://www.rust-lang.org/tools/install)
    - MacOS: `brew install rustup-init`
    - Install a toolchain: `rustup install stable`
    - Set a default: `rustup default stable`
- [Install Verilator](https://www.veripool.org/projects/verilator/wiki/Installing)
    - MacOS: `brew install verilator`   
    - Debian-based distros: `apt-get install verilator`
    - Arch-based distros: `pamac build verilator`
- Make and Run:
    - `make run` : runs in a simulated environment.
    - `make upload` : sends to FPGA (currently BlackIce MX, which has a Lattice Ice40).

## Compatibility:

The simulator uses a framebuffer to display the graphics on a window. The FPGA currently has drivers for ST7735 and ST7789 (which only differ in their resolution and initialisation ROM). Pull requests are welcome :)
