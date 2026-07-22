## Context

Display is 160x120, one pixel per master clock (simulator timing), so the compositor has a hard budget of ~160 cycles per scanline. All sprites share one 8x8 1bpp pattern; only position and flip flags vary per instance.

## Goals / Non-Goals

- Goals: max sprite count per frame with no per-scanline flicker limit up to the cycle budget; free X/Y flip; CPU/DMA-writable pattern and list; drop-in replacement for `sprite.sv` in `chip.sv`.
- Non-Goals: multiple distinct patterns, per-sprite palettes, rotation/scaling, Y-bucketed lists (documented as future scaling knobs).

## Decisions

- **Scanline compositor over per-sprite comparators**: per-sprite cost becomes one 17-bit list entry + 1 clock/line, instead of a full comparator engine. 128 sprites fit one iCE40 4Kbit BRAM.
- **FF-based line buffers (2 x 160 bits)**: enables single-cycle clear and single-cycle 8-bit OR-insert at arbitrary X via a barrel shift. Cost is ~320 FFs plus the shifter; acceptable on hx8k, and the shifter can be replaced by an 8-cycle pixel-serial blit if LUT budget becomes tight.
- **Pipelined list scan (1 entry/clock)**: list entry i+1 is fetched while entry i is processed, so 128 entries complete in ~130 of the 160 available cycles per line.
- **Indexed register interface** ($4008 index, $4009 X, $400A Y, $400B flags/commit with auto-increment, $400C count): keeps the existing 4-bit sprite address window; the CPU streams entries with 3 writes each.
- **Flips as index arithmetic**: row = pattern[dy ^ {3{yflip}}]; X flip reverses the row's bit order combinationally. Zero cycles, near-zero LUTs.

## Risks / Trade-offs

- Barrel shifter (~160-bit << 8-bit) costs roughly 1.3k LUT4s on iCE40 → fallback documented: pixel-serial blit (8 cycles/hit, ~19 overlapping sprites/line).
- Sprites wrap vertically modulo 128 rather than clipping at Y=120; visible only for Y in 120..127. Accepted for simplicity.
- List updates race the beam (no write buffering); a mid-frame rewrite can tear by one line. Accepted, matches 8-bit-era behavior.

## Migration Plan

`chip.sv` swaps `sprite s0` for `sprite_compositor s0` with the same port shape. Old `$4008/$4009` X/Y registers are replaced by the indexed interface; `src/main.asm` code that pokes those addresses will move sprite 0 only (index register resets to 0).

## Integration Notes (added during SDL-runner bring-up)

Getting the compositor visible in the Verilator/minifb runner (`make run`) surfaced pre-existing breakage that had to be fixed:

- **Working tree had a non-functional CPU**: uncommitted debug edits in `cpu6502_arlet.sv` had deleted the entire instruction-decode state machine (replaced with a BRK0-BRK6 debug chain referencing nonexistent enum states). Restored from HEAD (broken version preserved in session scratchpad).
- **Multi-billion-cycle resets**: uncommitted `por.sv` and `top_simulator.sv` held reset for 0xFFFFFFFF cycles (minutes-to-hours of wall clock before anything drew). Both restored from HEAD.
- **`top_simulator.sv` timing**: the committed design runs the pixel clock at clk/4 (`hvsync_generator` on `clk_4`); the uncommitted rewrite used 1-clock pixels, which broke the textbuffer's 4-state-per-pixel renderer and the Rust runner's 4-clock sampling. Restored from HEAD. The compositor keys only off `hpos`, so it works at either pixel rate; `next_line` uses `>=` so the vsync line composes line 0 instead of clobbering it.
- **Combinational loop fixed in `memory_arbiter.sv`**: `cpu_data_in` was muxed by the *live* chip-selects while all memories return *registered* (one-cycle-delayed) data, creating both a data/select mismatch and a comb loop (cpu_addr -> cs -> cpu_data_in -> Arlet AB -> cpu_addr) that made Verilator's settle loop diverge (DIDNOTCONVERGE). The mux selects are now registered, matching the data timing and the Arlet CPU's synchronous-memory contract.
- **Vblank shadow-copy DMA disabled** (`ENABLE_SHADOW_COPY = 0` in `dma_controller.sv`): the copy reads $F000+/$4000+, which the arbiter decodes back to the video devices themselves (self-copy), and address truncation made it zero the attribute RAM every frame, blacking out all text. Re-enable once it sources from a real system-RAM shadow.
- **Verilator 5 compat**: `REDEFMACRO` lint-off no longer covers macro redefinition (now fatal `DEFOVERRIDE`); the ``define VERILATOR`` in `top_simulator.sv` is now guarded by `ifndef`.
- **`src/main.asm` rewritten** for the new interface: clears the text screen, programs the pattern, then streams all 128 sprites (move + bounce + direction-following flips) every loop, ~3 register writes per sprite.

## Open Questions

- Whether to add per-scanline Y-buckets to scale past ~150 sprites (needs CPU-side sort or DMA support).
