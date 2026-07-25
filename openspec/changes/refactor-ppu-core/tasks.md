## 1. The regression net (nothing else starts until this is green)

- [ ] 1.1 Golden-frame harness in `rtl/sprite_compositor_tb.sv`: render a fixed
      scene, capture `frame_pix`, compare bit-for-bit against committed
      references, and report the first differing frame, coordinate and colour
      pair on failure. The repeat-field check added with `$4037` is the working
      prototype — generalise it
- [ ] 1.2 The scene must exercise every path, because the refactor is only as
      safe as the net: tiles at 1/2/3/4 bpp, non-zero palette base, both flips,
      the behind-split partition, repeat runs of 2+ cells, the clip rectangle at
      each edge, a non-default transparency mask, overlay set and clear, and a
      camera at a non-zero sub-cell offset on both axes
- [ ] 1.3 Commit the reference frames, and make regenerating them a deliberate
      act: an intended behaviour change regenerates them **in the same commit**,
      so the diff shows which pixels moved
- [ ] 1.4 Per-line cycle accounting: assert the engine reaches idle before
      `line_start`. An overrun is silent today — the engine restarts and the
      tail of the list is dropped — so it has to be a test failure, not
      observed flicker
- [ ] 1.5 `make ppu-check`: build, run, report pass/fail, non-zero exit on
      failure. `make test` currently exits 0 whether it passed or not; do not
      repeat that
- [ ] 1.6 Record the baseline in the change: 1846 LUT4, 340 carry, 678 FF,
      2623 logic cells, **16 of 32 BRAM**, Fmax 62.6 MHz, and the critical path
      nextpnr names (`entry_q` → `bmask` → line-buffer write data)
- [ ] 1.7 Confirm the net catches a real regression: introduce a one-pixel
      error deliberately, check it fails and names the pixel, revert. A net
      that has never failed is not known to work

## 2. Measurements that decide the rest of the plan

- [ ] 2.1 Block RAM by consumer. Declared arrays account for 12 of the 16
      placed (sheet 4, overlay 5, tilemap 2, line buffer 1). Find where the
      other **four** go and mark each as forced by capacity or by port
      width/simultaneous access — only the latter is recoverable
- [ ] 2.2 Count pattern reuse between consecutive entries in a real scene,
      across all three ports. Decides task 4.1 before any RTL is written
- [ ] 2.3 Measure the `disp_slot` stall: how many clocks per line are actually
      lost to line-buffer port contention in `E_RD0`/`E_RD1`
- [ ] 2.4 **Answer the open question: does the full chip place at all?**
      `synth_ice40` on `rtl/top.sv` expands to 1.7 M AND gates because
      `ram_async.sv` is a 64 KB array against 128 kbit of device BRAM. Either
      the board uses external SRAM and the model is simulation-only, or the
      FPGA build has not been run recently. Until this is answered, "decrease
      FPGA block counts" has no denominator
- [ ] 2.5 Record all of the above as numbers in `design.md` before restructuring

## 3. The split (behaviour-preserving, one module at a time)

Each step: split, run `make ppu-check`, record the resource delta. A step that
costs logic without buying clarity gets reverted.

- [ ] 3.1 `ppu_regs` — `$00-$3F`, staging registers, DMA port, readback. No
      datapath. Easiest first and it shrinks the file most
- [ ] 3.2 `ppu_line` — the double-banked line buffer and the bank swap, with
      the display read and engine write as explicit ports
- [ ] 3.3 `ppu_display` — line-buffer read, overlay mix, screen palette. This
      is where `hardware-gaps.md` entries 8 and 9 will land, so its interface
      is the one worth getting right
- [ ] 3.4 `ppu_blit` — pixel decode, draw palette, shift, mask, merge
- [ ] 3.5 `ppu_fetch` — the sheet, plane reads, the repeat counter
- [ ] 3.6 `ppu_map` and `ppu_scan` — both produce entries into `ppu_fetch`.
      The tile pass already synthesizes a sprite entry and pushes it through the
      shared path; making that an interface rather than a shared register is
      most of the work in this change
- [ ] 3.7 Confirm bit-identical rendering for `breakout`, `nemo` and `celeste`
      by screenshot, not just by golden frames

## 4. Pipelining and prefetch (each gated on its measurement)

- [ ] 4.1 Pattern-reuse cache: skip the fetch when `(base,row)` is unchanged
      from the previous entry. **Gated on 2.2** — build only if the reuse rate
      justifies it; record the finding either way, as the multiply gap did
- [ ] 4.2 Pipeline the blit into decode / palette / align / merge stages.
      Fmax must not regress **and** per-line clocks must not regress; assert
      both
- [ ] 4.3 Tile-pass prefetch: issue the map read for column *k+1* during column
      *k*'s blit, collapsing `E_TMAP0`/`E_TMAP1` into the blit's shadow (~21
      clocks a line, ~6% of the sprite budget)
- [ ] 4.4 Remove the `disp_slot` stalls if 2.3 shows they are worth the BRAM —
      and note that BRAM is the resource the PPU has least of
- [ ] 4.5 Re-measure Fmax and resources; record against the 1.6 baseline
- [ ] 4.6 **Record any of 4.1-4.4 that turned out not to be worth building**,
      with the number that says so. A rejected optimisation with evidence is a
      result, not a gap in the work

## 5. Closing out

- [ ] 5.1 Update `docs/hardware-gaps.md` entries 8 and 9 to point at the module
      that now owns the display path
- [ ] 5.2 Record the before/after resource and timing table in the change
- [ ] 5.3 State plainly whether the PPU is now the chip's critical path. It is
      not today — the CPU's unregistered memory path is (`refactor-cpu-core`) —
      and if that is still true afterwards, say so rather than implying the
      Fmax work bought throughput it did not
- [ ] 5.4 Note in `docs/agent-coordination.md` that the compositor has been
      restructured, since `nemo` and `breakout` render through it too
