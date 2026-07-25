## 1. Confirm the target before designing to it

- [ ] 1.1 Read the part marking on the board's SDRAM and confirm the geometry.
      The pinout implies 1M x 16, 2 banks, 2048 rows x 256 columns with `A11` as
      the bank select, but that is derived from twelve address lines and no `BA`
      pin — it is not confirmed, and the row/column split decides everything below
- [ ] 1.2 Record the part's `tRCD`, `tRP`, `tRC`, `tREF` and CAS latency at the
      chosen controller clock, in `docs/memory-subsystem.md`
- [ ] 1.3 Confirm `rclk` is a clock-capable pin for an output clock, and decide
      whether the SDRAM clock is forwarded through an SB_IO DDR primitive

## 2. The interface, and a backend that changes nothing

- [ ] 2.1 Define the memory interface: `addr`/`req`/`we`/`wdata` →
      `rdata`/`ack`/`stall`, with the one-cycle case requiring no handshake
- [ ] 2.2 Write `mem_bram`, behaviourally identical to today's `ram_async` for
      the windows that stay on-chip
- [ ] 2.3 Route `rtl/memory_arbiter.sv` through the interface, and drive the
      CPU's `RDY` from `stall`. No behaviour change yet
- [ ] 2.4 Confirm `make run`, `make shot` and `make test-nemo`/`test-celeste`
      are unaffected — this step must be invisible

## 3. Split the map

- [ ] 3.1 Pin bank 0's open row to `$0000-$01FF` — 512 bytes is exactly one row,
      so zero page and the stack never pay an activate. Measure the row-miss
      rate with and without before committing to it.
      **Not BRAM**: the PPU holds 16 of the 32 blocks and the PSG the other 16,
      measured off the netlist, so there is none spare
- [ ] 3.2 Decide where the video/PPU working set lives; it already bypasses main
      memory, so confirm rather than assume
- [ ] 3.3 Record the resulting BRAM budget against the device's 32 blocks, with
      the PSG's and PPU's existing claims itemised. Today they account for all
      32 (`tools/ppu_bram.py`), so any on-chip memory this change wants has to
      come out of one of them — state where, or use none

## 4. The SDRAM controller

- [ ] 4.1 Regenerate `rtl/pll.v` for the controller clock and **instantiate it**
      in `rtl/top.sv`, which has never happened
- [ ] 4.2 Write the initialisation sequence: power-up delay, precharge all, two
      auto-refreshes, mode register set
- [ ] 4.3 Implement auto-refresh on its own counter, with the CPU stalled for its
      duration, and prove the interval against `tREF`
- [ ] 4.4 Implement an open-row policy per bank, with precharge and activate on a
      miss
- [ ] 4.5 Handle the clock-domain crossing between the CPU and the controller
      explicitly, and state the rule
- [ ] 4.6 Byte writes through `udqm`/`ldqm`; byte reads take the half they need
- [ ] 4.7 Hold the unused half of every 16-bit read and satisfy the next
      sequential fetch from it. Measure the hit rate on the corpus before
      claiming it

## 5. Pins and bring-up

- [ ] 5.1 Add the memory pins to `rtl/top.pcf` — it has none today
- [ ] 5.2 Bring up against a memory test pattern before running a game on it
- [ ] 5.3 Run Breakout on hardware from SDRAM

## 6. Collect what this was for

- [ ] 6.1 `make bin/toplevel.asc` completes; record the wall time
- [ ] 6.2 Record whole-chip Fmax, the top-10 critical paths with owning modules,
      and utilisation in `docs/cpu-baseline.json`
      (**unblocks `refactor-cpu-core` tasks 2.1, 2.3 and 2.5, and gates T4/T5/T8**)
- [ ] 6.3 Answer `refactor-cpu-core` task 2.5 for the whole chip: is the critical
      path inside `cpu`? If it is not, that change re-scopes
- [ ] 6.4 Remove the arbiter's `cpu_rdy` workaround at
      `memory_arbiter.sv:76-85` and let `dma_request` assert freely
      (**closes `refactor-cpu-core` task 6.4**)
- [ ] 6.5 Re-measure the corpus's wall-clock frame time against the pre-SDRAM
      simulation, so the cost of external memory is stated rather than assumed
