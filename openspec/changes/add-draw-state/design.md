## Context

clip/palt/pal are per-draw modifiers in PICO-8. In a display-list PPU they become global pipeline state: the composite pass IS the draw, so draw-state registers apply per frame section (changeable between frames, or mid-frame for raster effects) rather than per API call. Games that need per-sprite variation already have the per-entry palette base.

## Goals / Non-Goals

- Goals: PICO-8's clip(), palt(), pal(c0,c1,0) and pal(c0,c1,1) semantics at the pipeline level; identity/reset defaults that keep all previous behavior bit-exact; zero BRAM cost.
- Non-Goals: per-entry draw state (the entry format is full), clip applied to the overlay (CPU clips its own drawing), PICO-8's fill patterns.

## Decisions

- **Ordering**: opacity = !palt_mask[raw pixel value] (pre-base, matching PICO-8, which tests the sprite's stored color); displayed color = screen_pal[draw_pal[(entry_pal + value) mod 16]]. The draw palette sits after the base add - identity base reproduces PICO-8 exactly, and the two compose rather than conflict.
- **Clip in the merge mask**: 16 comparators over the 2-word blit window ({lane,000}+k in 8-bit arithmetic, so the wrapped left-edge tile clips correctly), ANDed with the opacity mask; a line-level y compare gates whole scanlines. Constant-time - the budget math is unchanged.
- **Screen palette at the display mux**: one 16-entry lookup on the final pixel (overlay included). Sampled per pixel, so mid-frame rewrites give per-band effects, same as the overlay color register.
- **Register window widening over an index/data port**: $4000-$40FF was already decoded to the PPU with only addr[3:0] used; using addr[5:0] gives 48 new direct registers with no new decode and no indirection state machine. DMA keeps its 4-bit window (registers $0-$F only).

## Risks / Trade-offs

- Draw state is global per composite pass, not per entry; mid-frame changes shear at the line boundary (camera-latch semantics). Documented, era-authentic.
- The draw-palette lookup lengthens the blit's combinational path (adder -> LUT mux); timing is comfortable at 4 clocks per pixel.

## Migration Plan

Single change; reset defaults are identity/full-screen/value-0-transparent, so all existing software and tests behave identically until the new registers are written.

## Open Questions

- None. This completes the PICO-8 roadmap; remaining gaps to actual PICO-8 (128x128 mode, music/sfx, cart format) are out of PPU scope.
