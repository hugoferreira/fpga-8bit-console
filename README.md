# 8-bit console implemented on an FPGA 

## How to Run

- [Install Rust](https://www.rust-lang.org/tools/install)
    - Install a toolchain: `rustup install stable`
    - Set a default: `rustup default stable`
- [Install Verilator](https://www.veripool.org/projects/verilator/wiki/Installing)
    - Debian-based distros: `apt-get install verilator`
    - Arch-based distros: `pamac build verilator`
- Make and Run:
    - `make run` : runs in a simulated environment.
    - `make upload` : sends to FPGA
