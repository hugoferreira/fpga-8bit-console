## Context

Primitives and proportional text are free-form, mostly static content: they change when the game draws, not per frame. That argues for a retained bitmap the CPU mutates, not per-frame compositing. The design questions: where the bitmap enters the pixel pipeline, its depth, and how the CPU addresses it.

## Goals / Non-Goals

- Goals: arbitrary-pitch text (4x6 and proportional fonts) and pixel primitives at zero per-frame PPU cost; no impact on the scanline compositing budget; fonts freed from the sprite sheet.
- Non-Goals: multi-color overlay (1bpp + one color register; depth can grow later at 5 EBRs per plane), hardware line/circle drawing, overlay scrolling.

## Decisions

- **Display-time mix, not an engine phase.** The display side already reads the line buffer once per pixel; the overlay BRAM has its own ports, so reading the current lane's overlay byte in parallel and muxing per pixel costs zero compositing cycles. Consequences embraced: the overlay is unconditionally the top layer (it is a HUD/text surface), and it cannot sit between tiles and sprites. An engine-phase variant (blit 20 lane-aligned bytes per line, ~45 cycles) remains possible later if z-placement is ever needed.
- **1bpp + a global color register.** 160x120x1 = 2400 bytes = 5 EBRs; each extra bitplane would cost 5 more. One settable color covers text/HUD/outlines; the register is sampled per displayed pixel, so the CPU can change it mid-frame for per-band coloring (a free raster trick, documented rather than prevented).
- **Row-major y*20+x/8 addressing.** The multiply is two shifts and two adds ((y<<4)+(y<<2)) - still table-free and deterministic. The alternative power-of-2 stride ({y, x[7:4]} style) would round the RAM up to 8 EBRs for addressing convenience; not worth 3 EBRs.
- **Write-only to the CPU, direct-addressed.** The overlay's read port belongs to the display every lane; a CPU read port would be the third. Games keep a 2400-byte shadow in main RAM (64KB is the abundant resource) and do read-modify-write there - the same convention as the tilemap. A direct $E000 window (rather than a sheet-style auto-increment port) keeps `pset` at one absolute store; the auto-increment style would cost 3-4 register writes per byte and make random access miserable.
- **Fonts leave the sheet.** Glyph source data lives in CPU ROM (6 bytes per 4x6 glyph); at 4-pixel advance two glyphs pack per overlay byte with no cross-byte shifting when text starts on an even 4-px boundary. Sheet slots 128-255 (the CP437 tiles) remain for grid-aligned text; the overlay serves dense and proportional text.

## Risks / Trade-offs

- Overlay is top-of-stack always; sprites cannot draw over the HUD. Accepted for a HUD surface.
- One global color per pixel-time; multi-color text needs either raster bands or a future second plane.
- $E960-$E9FF of the window is dead space (array is 2560 deep for a clean power-of-2-free bound check).

## Migration Plan

Single change: RTL, arbiter decode, chip wiring, testbench, golden model, main.asm land together. Nothing existing changes behavior when $4005 bit1 is 0 (reset default).

## Open Questions

- None blocking. A second bitplane (4-color overlay) and an overlay-under-sprites mode are known extensions with understood costs.
