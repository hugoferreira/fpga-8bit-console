## 1. The regression net (nothing else starts until this is green)

- [x] 1.1 Golden-frame harness in `rtl/ppu_golden_tb.sv` — a new file rather
      than the demo testbench, which keeps rendering its 96 animated frames and
      is not a regression net. Ten fixed scenes, `frame_pix` compared
      bit-for-bit against `rtl/golden/ppu_N_name.txt`, first difference reported
      as scene, coordinate and both colours
- [x] 1.2 The scene set exercises every path: 1/2/3/4 bpp, all 16 palette
      bases, both flips at every depth, the behind-split, repeat runs of 2-8
      cells (including off the right edge and unaligned), the clip rectangle
      straddled on all four edges, values 0/3/7 transparent, overlay set and
      clear, camera at x&7=3 and y&7=5 with world wrap. Plus two checks that are
      not frames: register readback (including the DMA port) and the overrun
      probe
- [x] 1.3 Reference frames committed under `rtl/golden/`, regenerated only by
      `make ppu-check PPUARGS=+regen`. `rtl/golden/README.md` states the rule:
      an intended behaviour change regenerates them in the same commit
- [x] 1.4 Per-line cycle accounting: the engine must be idle at `line_start`,
      and the worst-case occupancy per scene is itself committed
      (`rtl/golden/ppu_cycles.txt`), so a change that spends line budget fails
      rather than passing quietly
- [x] 1.5 `make ppu-check` — exits 0 on pass, 2 on failure (`$fatal`)
- [x] 1.6 Baseline recorded in `design.md` §Measurements: 1846 LUT4, 340 carry,
      678 FF, 2623 logic cells, 16 of 32 BRAM, Fmax 64.73 MHz at seed 1, and the
      critical path `entry_q` → line-buffer write data. Also recorded: the
      ±6 LUT4 noise floor that comes from the yosys file list alone, so small
      deltas are not over-read
- [x] 1.7 `make ppu-check PPUARGS=+inject` flips one pixel and the net fails,
      naming `(x=93, y=57)` and both colours, exit 2. Kept as a permanent mode
      rather than a one-off edit, so the net can be re-proved at any time

## 2. Measurements that decide the rest of the plan

- [x] 2.1 Block RAM by consumer, via `tools/ppu_bram.py` off the yosys netlist
      (`make ppu-synth`). The four "unaccounted" blocks are the sprite list (3,
      omitted from the estimate entirely) and the line buffer's second block.
      Eleven of sixteen are capacity-forced, five are width-forced, and **neither
      width-forced consumer is recoverable** without a behaviour change — both
      alternatives are costed in `design.md`. 16 is the floor
- [x] 2.2 Pattern reuse between consecutive entries, measured on all three
      ports with `make ppu-probe`: **94.8% nemo, 41.7% breakout, 21.1%
      celeste**, worth up to 57.0 / 17.5 / 9.0 clocks a line. Task 4.1 is worth
      building — with the caveat that celeste, the game under the most line
      pressure, benefits least
- [x] 2.3 `disp_slot` stalls: **8.04 clocks per line worst case** (celeste),
      3.66 breakout, 1.00 nemo — 1.7% of the 483-clock budget at worst. Task 4.4
      is answered "no" before it starts
- [x] 2.4 **Answered: the chip does not place, and cannot.** `ram_async` is
      64 KB = 512 kbit against the hx8k's 128 kbit total — 4x over on its own,
      before logic. yosys extracts 1,727,297 AND gates for a 7680-cell device
      and `rtl/top.pcf` has no external memory bus, so the model is
      simulation-only and no bitstream has ever been built. Per-module figures
      are the only meaningful ones. Also measured: `rtl/psg.sv` takes 16 blocks,
      not the 9 assumed, so PPU + PSG is already 32 of 32
- [x] 2.5 Recorded in `design.md` §Measurements, with the tooling that
      reproduces each number

## 3. The split (behaviour-preserving, one module at a time)

Each step: split, run `make ppu-check`, record the resource delta. A step that
costs logic without buying clarity gets reverted.

Deltas below are LUT4 against the 1846 baseline, cumulative, measured with
`make ppu-synth` after each step. `make ppu-check` was green at every one.

- [x] 3.1 `ppu_regs` — `$00-$3F`, staging registers, DMA port, readback, no
      datapath. **1835 (-11).** The sheet, the list and both palettes are
      memories read by other stages, so they leave as write strobes and stay
      with their readers; three forms of palette port were measured before that
      one, and the note in `ppu_regs.sv` records what each cost
- [x] 3.2 `ppu_line` — the double-banked buffer, the bank swap, and the
      display-wins read arbitration. **1847 (+1).** Nothing outside it knows
      which bank is which any more; both sides address by lane
- [x] 3.3 `ppu_display` — line-buffer read, overlay mix, screen palette.
      **1838 (-8).** This is where `hardware-gaps.md` entries 8 and 9 land, so
      it owns the overlay storage and its interface is a pixel, a bitmap and
      the registers that say how to combine them
- [x] 3.4 `ppu_blit` — pixel decode, draw palette, shift, mask, merge.
      **1855 (+9).** The whole critical path is now inside one module
- [x] 3.5 `ppu_fetch` — the sheet, the plane reads, the cell cursor.
      **1821 (-25)**
- [x] 3.6 `ppu_map` and `ppu_scan` — two producers of one entry stream.
      **1767 (-79).** The first attempt muxed the two producers' output
      *registers* on the consumer side and cost 10 MHz of Fmax: the list
      memory's output register folds into the scan's entry register, so the mux
      landed between a block RAM output and the blit. Latching the selected
      entry once at the producer/consumer boundary instead is both faster and
      smaller — and it is the more honest expression of a stream
- [x] 3.7 `breakout`, `nemo` and `celeste` render **byte-identically** before
      and after, over the full 160x120 frame, captured from the same key
      scripts against `git show HEAD:rtl/sprite_compositor.sv` and against the
      split. Not just the golden frames: real scenes, through `chip.sv`
- [x] 3.8 (added) `make ppu-lint` — Verilator width checking, which iverilog
      does not do and the golden frames cannot. It caught a `rowi` truncation
      that was *equivalent* and so passed every pixel, but broke `make run`.
      It runs before the frames now

## 4. Pipelining and prefetch (each gated on its measurement)

- [x] 4.1 **Built.** The reuse rate from 2.2 justified it. `ppu_fetch` keeps the
      key `(base, row, bpp)` of what `prow` currently holds; a matching entry
      skips the whole fetch and E_FETCH costs one clock instead of bpp+2. Two
      invalidations are in the RTL rather than argued: a CPU write to the sheet,
      and `line_start` (a fetch interrupted by an overrun leaves `prow`
      half-filled under a key that claims it is complete). Saved, per line:
      **breakout 16.5, nemo 38.0, celeste 6.2** fetch clocks. Cost: +34 LUT4
- [x] 4.2 **Built, and it did not raise Fmax — see 4.6.** Three stages: decode
      and palette, then align and clip, then merge. The latency is free because
      the engine already spends `E_RD0`/`E_RD1` reading the words it will merge
      into and the datapath had nothing to do during them — **per-line clocks
      are byte-identical before and after the pipelining**, which the harness
      asserts. The blit is no longer the critical path
- [x] 4.3 **Built, and it is the largest single win.** The tilemap read address
      is driven from the column cursor's NEXT value, so column k+1's read is
      always in flight while column k is decided and the state that existed
      only to wait for it is gone. **43 -> 22 clocks a line in every game**, and
      it needed no priming clock: the clock that resets the cursor is also the
      one that issues column 0's read. Cost: 0 LUT4 (the address was
      combinational either way)
- [x] 4.4 **Not built, and 2.3 is why.** Worst case across the three ports is
      8.82 clocks of a 483-clock line (celeste, 1.8%); breakout is 5.07 and
      nemo 2.03. Removing it costs a block RAM, which is the resource the PPU
      has least of and which it has none of spare (2.1). Rejected on the number
- [x] 4.5 Re-measured; the table is in `design.md` §Result
- [x] 4.6 Recorded. Two results are negative and both are in `design.md`:
      **the `disp_slot` stalls are not worth a block RAM**, and **pipelining
      the blit did not raise the PPU's Fmax** (median 62.66 -> 60.51 MHz over
      9 placement seeds — slightly *lower*, and within the 5 MHz seed spread).
      It did what it was for: the critical path moved off the blit entirely.
      What it moved to is now named — the overlay's five-block read
      multiplexer in `ppu_display`, 2.15 ns of block RAM clock-to-q and five
      LUT levels of block select — which is a fact `hardware-gaps.md` entry 9
      needs, since a second overlay plane makes that mux wider

## 5. Closing out

- [x] 5.1 `docs/hardware-gaps.md` entries 8 and 9 now point at
      `rtl/ppu_display.sv` and its mix expression, and entry 9 carries the two
      measurements it needs: there is **no spare block RAM** (PPU 16, PSG 16,
      of 32), and the overlay's five-block read multiplexer is now the PPU's
      critical path — a second plane makes that mux wider, not narrower
- [x] 5.2 Before/after resource and timing table in `design.md` §Result, with
      Fmax quoted over nine placement seeds because the spread is wider than
      the deltas
- [x] 5.3 Stated in `design.md` §Result: **no**, and it was not before either.
      Three reasons, ending with the one that settles it — the chip does not
      place at all, so there is no chip-level critical path to be on. The blit
      pipelining bought no throughput and the change says so
- [x] 5.5 (added) `docs/hardware-gaps.md` entry 11 — the palette readback bug
      the harness found, recorded rather than fixed, with the reason
