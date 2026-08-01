// PPU engine probe: what the compositor actually spends a scanline on, while
// a real game is running.
//
// refactor-ppu-core proposes three optimisations - a pattern-reuse cache, a
// tile-pass prefetch, and removing the display-slot stalls - and each one is
// supposed to be measured against the per-line budget before it is built. This
// is the measurement. It runs a game headless and watches the engine's own
// state register, so the numbers are the engine's behaviour on real scenes
// rather than a model of it.
//
//   make ppu-probe GAME=nemo FRAMES=120
//   make ppu-probe GAME=celeste FRAMES=240 KEYS=30:x,90:r
//
// It reads registers only (est, entry_q, line_y, hpos_q, hpos), so it does not
// depend on any wire surviving optimisation - which is also why it keeps
// working across the module split, as long as those names still exist.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <vector>
#include <map>
#include "Vtop.h"
#include "Vtop___024root.h"

// Engine states, in the order sprite_compositor.sv declares them
enum { E_IDLE, E_CLEAR, E_TMAP, E_SCAN, E_FETCH, E_RD0, E_RD1, E_WR0, E_WR1 };

static const int H_DISPLAY = 160;
static const int CLKS_PER_PIXEL = 3;
static const int BUDGET = 161 * CLKS_PER_PIXEL;

struct KeyEvent { int frame; uint8_t mask; };

int main(int argc, char** argv) {
    int frames = 120, warmup = 8;
    std::vector<KeyEvent> script;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--frames") && i + 1 < argc) frames = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--warmup") && i + 1 < argc) warmup = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--keys") && i + 1 < argc) {
            char* s = strdup(argv[++i]);
            for (char* tok = strtok(s, ","); tok; tok = strtok(nullptr, ",")) {
                char* colon = strchr(tok, ':');
                if (!colon) continue;
                *colon = 0;
                uint8_t m = 0;
                for (char* c = colon + 1; *c; c++)
                    switch (*c) {
                        case 'l': m |= 0x01; break;
                        case 'r': m |= 0x02; break;
                        case 'u': m |= 0x04; break;
                        case 'd': m |= 0x08; break;
                        case 'o': m |= 0x10; break;
                        case 'x': m |= 0x20; break;
                    }
                script.push_back({atoi(tok), m});
            }
        }
    }

    Vtop* tb = new Vtop;
    auto* r = tb->rootp;

    tb->rst_i = 1;
    for (int i = 0; i < 20; i++) { tb->clk_i = !tb->clk_i; tb->eval(); }
    tb->rst_i = 0;

    // Per-line accounting, accumulated over every composited line
    long lines = 0, overruns = 0;
    long busy_total = 0, busy_max = 0;
    long clear_clocks = 0, tile_clocks = 0, scan_clocks = 0;
    long fetch_clocks = 0, rd_clocks = 0, wr_clocks = 0;
    long stall_clocks = 0;                 // RD0/RD1 waiting on a display slot
    long fetches = 0, reuse_full = 0, reuse_row = 0;
    long busy_hist[16] = {0};              // busy clocks, in 32-clock buckets

    int prev_est = E_IDLE;
    long busy = 0;
    bool have_prev_key = false;
    uint32_t prev_base = 0, prev_rowi = 0, prev_bpp = 0;

    int frame = 0;
    bool vblank = true;
    long clocks = 0;

    while (frame < frames) {
        // Everything is sampled BEFORE the edge: that is the state the design
        // is in *during* this clock, which is what the FSM is reacting to.
        // Reading hpos_q after the edge would always agree with hpos, because
        // the edge is where `hpos_q <= hpos` happens.
        // g_ppu: the compositor sits inside chip.sv's `generate if (HAS_PPU)`
        // block (refactor-build-targets), so the Verilated path gained a level.
        int est = r->top__DOT__chip__DOT__g_ppu__DOT__s0__DOT__est;
        uint8_t hpos = r->top__DOT__hpos;
        uint8_t hpos_q = r->top__DOT__chip__DOT__g_ppu__DOT__s0__DOT__hpos_q;
        uint64_t entry_q = r->top__DOT__chip__DOT__g_ppu__DOT__s0__DOT__entry_q;
        uint32_t liney = r->top__DOT__chip__DOT__g_ppu__DOT__s0__DOT__line_y;

        tb->clk_i = 1; tb->eval();
        tb->clk_i = 0; tb->eval();
        clocks++;

        bool hpos_changed = (hpos != hpos_q);
        bool disp_slot = hpos_changed && (hpos < H_DISPLAY);
        bool line_start = hpos_changed && (hpos == 0);

        bool measuring = frame >= warmup;

        if (line_start) {
            if (measuring) {
                lines++;
                busy_total += busy;
                if (busy > busy_max) busy_max = busy;
                busy_hist[busy / 32 < 15 ? busy / 32 : 15]++;
                if (est != E_IDLE) overruns++;
            }
            busy = 0;
            have_prev_key = false;                  // reuse never spans a line
        } else if (est != E_IDLE) {
            busy++;
            if (measuring) {
                switch (est) {
                    case E_CLEAR: clear_clocks++; break;
                    case E_TMAP: tile_clocks++; break;
                    case E_SCAN:  scan_clocks++; break;
                    case E_FETCH: fetch_clocks++; break;
                    case E_RD0: case E_RD1:
                        rd_clocks++;
                        if (disp_slot) stall_clocks++;   // waiting for the port
                        break;
                    case E_WR0: case E_WR1: wr_clocks++; break;
                }
            }
        }

        // A fetch begins on the first clock of E_FETCH; entry_q already holds
        // the entry (E_SCAN loaded it, E_TMAP1 synthesised it in the same
        // cycle it jumped here), so the pattern key is readable now.
        if (est == E_FETCH && prev_est != E_FETCH) {
            uint64_t e = entry_q;
            uint32_t base  = (e >> 15) & 0xFF;
            uint32_t ey    = (e >> 8) & 0x7F;
            uint32_t yf    = (e >> 24) & 1;
            uint32_t bpp   = ((e >> 25) & 3) + 1;
            uint32_t rowi  = ((liney - ey) & 7) ^ (yf ? 7 : 0);
            if (measuring) {
                fetches++;
                if (have_prev_key && base == prev_base && rowi == prev_rowi) {
                    reuse_row++;
                    if (bpp == prev_bpp) reuse_full++;
                }
            }
            prev_base = base; prev_rowi = rowi; prev_bpp = bpp;
            have_prev_key = true;
        }
        prev_est = est;

        if (tb->vsync && !vblank) {
            vblank = true;
            frame++;
            uint8_t b = 0;
            for (const KeyEvent& e : script)
                if (frame >= e.frame && frame < e.frame + 8) b |= e.mask;
            tb->buttons = b;
        } else if (!tb->vsync) {
            vblank = false;
        }
    }

    long measured_frames = frames - warmup;
    if (lines == 0) { fprintf(stderr, "no lines measured\n"); return 1; }

    long engine_total = clear_clocks + tile_clocks + scan_clocks +
                        fetch_clocks + rd_clocks + wr_clocks;

    printf("frames measured        %ld (after %d warm-up)\n", measured_frames, warmup);
    printf("scanlines              %ld\n", lines);
    printf("budget                 %d clocks per line (161 pixels x %d)\n",
           BUDGET, CLKS_PER_PIXEL);
    printf("engine busy            mean %.1f, worst %ld, %.1f%% of budget\n",
           (double)busy_total / lines, busy_max, 100.0 * busy_max / BUDGET);
    printf("lines that overran     %ld (%.2f%%)\n", overruns, 100.0 * overruns / lines);
    printf("\nwhere the clocks go    per line   share\n");
    struct { const char* n; long v; } part[] = {
        {"clear", clear_clocks}, {"tile walk", tile_clocks}, {"list scan", scan_clocks},
        {"pattern fetch", fetch_clocks}, {"line-buffer read", rd_clocks},
        {"line-buffer write", wr_clocks},
    };
    for (auto& p : part)
        printf("  %-20s %7.2f   %5.1f%%\n", p.n, (double)p.v / lines,
               engine_total ? 100.0 * p.v / engine_total : 0.0);
    printf("  %-20s %7.2f   %5.1f%%   TOTAL\n", "", (double)engine_total / lines, 100.0);

    printf("\ndisplay-slot stalls    %.2f clocks per line, %.1f%% of the budget\n",
           (double)stall_clocks / lines, 100.0 * stall_clocks / lines / BUDGET);
    printf("                       %.1f%% of the read clocks were a wait\n",
           rd_clocks ? 100.0 * stall_clocks / rd_clocks : 0.0);

    printf("\npattern fetches        %ld (%.2f per line)\n", fetches, (double)fetches / lines);
    printf("  same (base,row) as the previous entry   %ld  %.1f%%\n",
           reuse_row, fetches ? 100.0 * reuse_row / fetches : 0.0);
    printf("  ... and the same bpp, so fully skippable %ld  %.1f%%\n",
           reuse_full, fetches ? 100.0 * reuse_full / fetches : 0.0);
    printf("  upper bound on a reuse cache: %.2f of %.2f fetch clocks per line\n",
           fetches ? (double)fetch_clocks / lines * reuse_full / fetches : 0.0,
           (double)fetch_clocks / lines);

    printf("\nbusy-clock distribution (32-clock buckets, %% of lines)\n  ");
    for (int i = 0; i < 16; i++)
        if (busy_hist[i]) printf("%d-%d:%.1f%%  ", i * 32, i * 32 + 31,
                                 100.0 * busy_hist[i] / lines);
    printf("\n");

    delete tb;
    return 0;
}
