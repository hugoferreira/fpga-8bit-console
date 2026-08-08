// Console runner: Verilated model + SDL2 window, replacing the Rust flow.
// One process, no FFI seams: the frame loop drives the model directly and
// paces to a locked 60 fps.
#include "Vtop.h"
#include "Vtop___024root.h"
#include "verilated.h"
#include <SDL.h>
#include <chrono>
#include <thread>
#include <cstdio>
#include <cmath>
#include <cstring>
#include <cstdlib>
#include <vector>
#include <map>
#include <algorithm>
#include <string>
#include <fstream>
#include <sstream>

static const int W = 160, H = 120, SCALE = 4;   // V_DISPLAY is 120

// MUST MATCH rtl/top_simulator.sv's PSGSIMDIV. The Makefile sets both from one
// variable (-GPSGSIMDIV= to verilator, -DPSGSIMDIV= here); this default only
// applies to a hand-built model.
#ifndef PSGSIMDIV
#define PSGSIMDIV 1
#endif

// Three core clocks per pixel. At PSGSIMDIV=1 the model's input clock IS the
// core clock, so a pixel is three input-clock cycles; at 2 the RTL divides by
// two for the core and a pixel is six. Emulated video time is identical either
// way, which is why the 44100 Hz audio Bresenham below still lines up.
//
// This number is half what it was, and that is the single largest simulation
// speed-up available here: every clock pair costs two eval() calls, and at
// PSGSIMDIV=1 half of them were producing a core-clock negedge that nothing is
// sensitive to. See the comment on the divider in rtl/top_simulator.sv.
static const int CLKS_PER_PIXEL = 3 * PSGSIMDIV;

// Scripted input for headless runs: hold `mask` for HOLD frames from `frame`.
struct KeyEvent { uint32_t frame; uint8_t mask; };
static const uint32_t HOLD = 4;

static uint8_t key_of(const char* name) {
    if (!strcmp(name, "left")  || !strcmp(name, "l")) return 0x01;
    if (!strcmp(name, "right") || !strcmp(name, "r")) return 0x02;
    if (!strcmp(name, "up")    || !strcmp(name, "u")) return 0x04;
    if (!strcmp(name, "down")  || !strcmp(name, "d")) return 0x08;
    if (!strcmp(name, "o")     || !strcmp(name, "z")) return 0x10;
    if (!strcmp(name, "x"))                           return 0x20;
    fprintf(stderr, "unknown key '%s'\n", name);
    return 0;
}

// build/<game>.sym (customasm `-f symbols`: one `NAME = 0xVALUE` per line) so
// traces and the future TRAP instruction can print names rather than
// addresses. No PC signal is currently exposed through Vtop's top-level
// ports, so this is reached via --resolve rather than a live instruction
// trace; see docs/assembler.md.
static std::map<uint32_t, std::string> g_symbols;

static bool load_symbols(const char* path) {
    std::ifstream f(path);
    if (!f) { fprintf(stderr, "cannot open symbol file %s\n", path); return false; }
    std::string line;
    while (std::getline(f, line)) {
        size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        std::string name = line.substr(0, eq);
        while (!name.empty() && isspace((unsigned char)name.back())) name.pop_back();
        std::string value = line.substr(eq + 1);
        uint32_t addr = (uint32_t)strtoul(value.c_str(), nullptr, 0);
        g_symbols[addr] = name;
    }
    return true;
}

// Nearest preceding label plus offset, e.g. "start+0x12", or the bare hex
// address if it precedes every known symbol (or none were loaded).
static std::string resolve_symbol(uint32_t addr) {
    char hex[8];
    snprintf(hex, sizeof hex, "$%04X", addr);
    if (g_symbols.empty()) return hex;
    auto it = g_symbols.upper_bound(addr);
    if (it == g_symbols.begin()) return hex;
    --it;
    uint32_t off = addr - it->first;
    if (off == 0) return it->second;
    char buf[128];
    snprintf(buf, sizeof buf, "%s+0x%x (%s)", it->second.c_str(), off, hex);
    return buf;
}

// Framebuffer -> binary PPM, so a headless run can be inspected.
// Dump the console's own audio, which is the ONLY way to hear what `make run`
// plays. sim/psg_wav.cpp renders the PSG with no CPU, no game and no video, so
// it cannot see anything the game's register writes do; the PSG oracle cannot
// see the preview schedule at all. A render that is right in both still reaches
// the speakers through this path.
static void write_wav(const char* path, const std::vector<int16_t>& pcm,
                      int rate) {
    FILE* f = fopen(path, "wb");
    if (!f) { fprintf(stderr, "cannot write %s\n", path); return; }
    uint32_t bytes = (uint32_t)(pcm.size() * sizeof(int16_t));
    auto u32 = [&](uint32_t v) { fwrite(&v, 4, 1, f); };
    auto u16 = [&](uint16_t v) { fwrite(&v, 2, 1, f); };
    fwrite("RIFF", 1, 4, f);  u32(36 + bytes);  fwrite("WAVE", 1, 4, f);
    fwrite("fmt ", 1, 4, f);  u32(16);
    u16(1);                   // PCM
    u16(1);                   // mono
    u32((uint32_t)rate);
    u32((uint32_t)rate * 2);  // byte rate
    u16(2);                   // block align
    u16(16);                  // bits
    fwrite("data", 1, 4, f);  u32(bytes);
    fwrite(pcm.data(), 1, bytes, f);
    fclose(f);
    printf("wrote %s (%zu samples, %d Hz, %.2fs)\n", path, pcm.size(), rate,
           (double)pcm.size() / rate);
}

static void write_ppm(const char* path, const std::vector<uint32_t>& fb,
                      int w, int h) {
    FILE* f = fopen(path, "wb");
    if (!f) { fprintf(stderr, "cannot write %s\n", path); return; }
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    for (int i = 0; i < w * h; i++) {
        uint32_t p = fb[i];
        fputc((p >> 16) & 0xFF, f);
        fputc((p >> 8) & 0xFF, f);
        fputc(p & 0xFF, f);
    }
    fclose(f);
    printf("wrote %s (%dx%d)\n", path, w, h);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // Opt-in batch mode. Without these flags behaviour is unchanged: an
    // interactive SDL window paced to 60 fps.
    bool headless = false;
    long max_frames = 0;                  // 0 = run until quit
    const char* shot = nullptr;
    bool audio_trace = false;             // per-frame audio energy to stdout
    const char* audio_wav = nullptr;      // dump what the console actually plays
    bool psg_trace = false;               // per-frame PSG channel state
    long peek_addr = -1;                  // RAM byte whose change cadence to report
    long profile_from = -1;               // sample the CPU PC from this frame on
    const char* sym_path = nullptr;
    const char* resolve_addr = nullptr;
    std::vector<KeyEvent> script;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--headless")) headless = true;
        else if (!strcmp(argv[i], "--frames") && i + 1 < argc)
            max_frames = atol(argv[++i]);
        else if (!strcmp(argv[i], "--shot") && i + 1 < argc)
            shot = argv[++i];
        else if (!strcmp(argv[i], "--audio-trace")) audio_trace = true;
        else if (!strcmp(argv[i], "--audio-wav") && i + 1 < argc)
            audio_wav = argv[++i];
        else if (!strcmp(argv[i], "--psg-trace")) psg_trace = true;
        else if (!strcmp(argv[i], "--peek") && i + 1 < argc)
            peek_addr = strtol(argv[++i], nullptr, 0);
        else if (!strcmp(argv[i], "--profile-from") && i + 1 < argc)
            profile_from = atol(argv[++i]);
        else if (!strcmp(argv[i], "--sym") && i + 1 < argc)
            sym_path = argv[++i];
        else if (!strcmp(argv[i], "--resolve") && i + 1 < argc)
            resolve_addr = argv[++i];
        else if (!strcmp(argv[i], "--keys") && i + 1 < argc) {
            char* spec = strdup(argv[++i]);
            for (char* tok = strtok(spec, ","); tok; tok = strtok(nullptr, ",")) {
                char* colon = strchr(tok, ':');
                if (!colon) continue;
                *colon = 0;
                script.push_back({(uint32_t)atol(tok), key_of(colon + 1)});
            }
            free(spec);
        }
    }

    if (sym_path && !load_symbols(sym_path)) return 1;

    if (resolve_addr) {
        uint32_t addr = (uint32_t)strtoul(resolve_addr, nullptr, 0);
        printf("%s\n", resolve_symbol(addr).c_str());
        return 0;
    }

    Vtop* tb = new Vtop;

    // Reset
    tb->rst_i = 1;
    // Prime the model out of X with exactly THREE core-clock posedges,
    // whichever way coreclk is derived - 6 input toggles when the input is the
    // core clock, 10 when it is divided. Getting this count wrong is not a
    // crash: it shifts the reset phase, the game diverges a few frames later,
    // and the rendered frame differs by ~0.2% of pixels. Measured.
    const int prime = (PSGSIMDIV == 1) ? 6 : 10;
    for (int i = 0; i < prime; i++) { tb->clk_i = !tb->clk_i; tb->eval(); }
    tb->rst_i = 0;

    SDL_Window* win = nullptr;
    SDL_Renderer* ren = nullptr;
    SDL_Texture* tex = nullptr;
    SDL_AudioDeviceID adev = 0;
    if (!headless) {
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) != 0) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }
    // The runner consumes raw scancodes only. SDL enables desktop text input
    // implicitly; on macOS that also enables the press-and-hold accent picker,
    // which steals a held/repeated Z dash input from the game window.
    SDL_StopTextInput();
    if (SDL_IsTextInputActive()) {
        fprintf(stderr, "SDL text input remained active\n");
        SDL_Quit();
        return 1;
    }
    win = SDL_CreateWindow("Console (ESC to exit)",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        W * SCALE, H * SCALE, SDL_WINDOW_ALLOW_HIGHDPI);
    ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED);
    SDL_AudioSpec want = {}, have = {};
    want.freq = 44100;
    want.format = AUDIO_S16SYS;      // the PSG is 16-bit now
    want.channels = 1;
    want.samples = 1024;
    adev = SDL_OpenAudioDevice(nullptr, 0, &want, &have, 0);
    if (adev) {
        // Prime the queue with four frames of silence so the steady-state
        // level sits away from the dry line instead of starting on it.
        static const int16_t prime_buf[4 * 735] = {0};
        SDL_QueueAudio(adev, prime_buf, sizeof prime_buf);
        SDL_PauseAudioDevice(adev, 0);
    }
    else fprintf(stderr, "audio disabled: %s\n", SDL_GetError());
    tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_ARGB8888,
        SDL_TEXTUREACCESS_STREAMING, W, H);
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "nearest");
    }

    std::vector<uint32_t> fb(W * H, 0);
    std::vector<int16_t> abuf;
    abuf.reserve(1024);
    std::vector<int16_t> wavbuf;          // every sample the console produced
    long adropped = 0, aqueued = 0;       // frames handed to SDL, and thrown away
    long aunderrun = 0;                   // frames with under 2 frames queued
    long adry = 0;                        // frames where the device truly starved
    long aerr = 0;                        // 735 samples per 19481 pixels
    long asamples = 0, anonzero = 0;      // headless audio activity check
    int amin = 32767, amax = -32768;
    std::vector<uint8_t> aseen(65536, 0);  // distinct sample values, a direct
    long adistinct = 0;                    // read on effective resolution
    long fsum = 0, fn = 0;                // per-frame audio energy for --audio-trace
    int fmin = 32767, fmax = -32768;
    uint32_t hpos = 0, vpos = 0, frame = 0;
    bool vblank = true, hblank = false;

    // --peek: watch one RAM byte once per display frame and report the
    // distribution of change intervals. Pointing it at a counter the game
    // bumps once per game tick (Celeste: game.frames at $30) separates
    // emulated slowdown from host slowdown: a healthy 30 Hz game changes it
    // every 2 display frames; 3+ means the game overran its CPU budget,
    // whatever the host fps says.
    uint8_t peek_last = 0;
    uint32_t peek_last_frame = 0;
    long peek_hist[9] = {0};              // interval 1..8, [0] collects >8

    // --profile-from: sample the emulated CPU's PC once per pixel (one sample
    // per three CPU clocks) and attribute wall time to the nearest preceding
    // symbol from --sym. Stalled cycles (DMA, psg_hold) accumulate at the
    // stalled instruction, which is the correct attribution for a budget.
    std::vector<uint64_t> prof, prof_late;
    if (profile_from >= 0) {
        prof.assign(65536, 0);
        // With --peek also active, samples taken while the watched counter is
        // overdue (its tick is in a 3rd-or-later display frame) land in a
        // second histogram: the work profile of exactly the overrun ticks.
        if (peek_addr >= 0) prof_late.assign(65536, 0);
    }

    using clockk = std::chrono::steady_clock;
    auto t0 = clockk::now();
    bool running = true;

    while (running) {
        // --- advance the model one pixel ---
        for (int i = 0; i < CLKS_PER_PIXEL; i++) {
            tb->clk_i = 1; tb->eval();
            tb->clk_i = 0; tb->eval();
        }
        bool vs = tb->vsync, hs = tb->hsync;

        if (profile_from >= 0 && (long)frame >= profile_from) {
            uint16_t pc = tb->rootp->top__DOT__chip__DOT__cpu0__DOT__core__DOT__pc;
            prof[pc]++;
            if (peek_addr >= 0 && frame - peek_last_frame >= 2)
                prof_late[pc]++;
        }

        // sample the PSG's 22050 Hz PCM at 44100 Hz (Bresenham across the
        // frame) - a natural 2x zero-order hold of the chip's native rate
        aerr += 735;
        if (aerr >= 19481) {
            aerr -= 19481;
            // Verilator exposes a 16-bit port as an unsigned type, so the
            // sign has to be put back explicitly.
            int16_t smp = (int16_t)tb->audio;
            abuf.push_back(smp);
            if (audio_wav) wavbuf.push_back(smp);
            asamples++;
            if (smp != 0) anonzero++;
            if (smp < amin) amin = smp;
            if (smp > amax) amax = smp;
            if (!aseen[(uint16_t)smp]) { aseen[(uint16_t)smp] = 1; adistinct++; }
            int d = smp;
            fsum += (d < 0 ? -d : d);
            fn++;
            if (smp < fmin) fmin = smp;
            if (smp > fmax) fmax = smp;
        }

        if (vs && !vblank) {
            vblank = true;
            vpos = 0;
            frame++;

            // --- once per frame: input, present, pace ---
            uint8_t b = 0;
            if (headless) {
                for (const KeyEvent& e : script)
                    if (frame >= e.frame && frame < e.frame + HOLD) b |= e.mask;
            } else {
                SDL_Event ev;
                while (SDL_PollEvent(&ev))
                    if (ev.type == SDL_QUIT) running = false;
                const Uint8* k = SDL_GetKeyboardState(nullptr);
                if (k[SDL_SCANCODE_ESCAPE]) running = false;
                if (k[SDL_SCANCODE_LEFT])  b |= 0x01;
                if (k[SDL_SCANCODE_RIGHT]) b |= 0x02;
                if (k[SDL_SCANCODE_UP])    b |= 0x04;
                if (k[SDL_SCANCODE_DOWN])  b |= 0x08;
                if (k[SDL_SCANCODE_Z])     b |= 0x10;
                if (k[SDL_SCANCODE_X])     b |= 0x20;
            }
            tb->buttons = b;

            if (psg_trace) {
                // Layout matches rtl/psg.sv's dbg bus. Printed in the same
                // shape as PICO-8's stat(46..49) so the two can be diffed:
                // one line per frame, sfx id per channel, -1 when idle.
                uint64_t d = tb->psg_dbg;
                int play = (d >> 8) & 0xF, owned = (d >> 12) & 0xF;
                int id[4] = {(int)((d >> 16) & 0x3F), (int)((d >> 22) & 0x3F),
                             (int)((d >> 28) & 0x3F), (int)((d >> 34) & 0x3F)};
                printf("@@%u", frame);
                for (int c = 0; c < 4; c++)
                    printf(" %d", (play >> c & 1) ? id[c] : -1);
                // rows: the note index within each channel's SFX, directly
                // comparable with PICO-8's stat(50..53)
                for (int c = 0; c < 4; c++)
                    printf(" %d", (play >> c & 1)
                           ? (int)((d >> (40 + 6 * c)) & 0x3F) : -1);
                printf(" %d mus=%d own=%x\n", (int)(d & 0x3F),
                       (int)((d >> 7) & 1), owned);
                fflush(stdout);
            }
            if (audio_trace && fn) {
                printf("frame %u audio mean|dev| %.1f range %d..%d\n",
                       frame, (double)fsum / fn, fmin, fmax);
                fflush(stdout);
            }
            fsum = 0; fn = 0; fmin = 32767; fmax = -32768;

            if (peek_addr >= 0) {
                uint8_t v = tb->rootp
                    ->top__DOT__chip__DOT__ram__DOT__mem[peek_addr & 0xFFFF];
                if (v != peek_last) {
                    uint32_t dt = frame - peek_last_frame;
                    peek_hist[(dt >= 1 && dt <= 8) ? dt : 0]++;
                    peek_last = v;
                    peek_last_frame = frame;
                }
            }

            if (max_frames && (long)frame >= max_frames) running = false;

            if (adev) {
                // The queue running dry is what a listener hears as crackle:
                // the device plays silence until the next frame arrives. The
                // drop on the other side is silent too - the frame's samples
                // are discarded, not deferred, so the music skips forward.
                // The cap is 8 frames (133 ms of latency headroom): the old
                // 4-frame cap held the operating level against the dry line,
                // so every pacing wobble crossed it.
                Uint32 queued = SDL_GetQueuedAudioSize(adev);
                if (queued < (Uint32)(2 * 735 * 2)) aunderrun++;
                if (queued == 0 && frame > 60) adry++;
                if (queued < 8 * 735 * 2) {
                    SDL_QueueAudio(adev, abuf.data(),
                                   (Uint32)(abuf.size() * sizeof(int16_t)));
                    aqueued++;
                } else {
                    adropped++;
                }
                abuf.clear();
            }
            if (!headless) {
            SDL_UpdateTexture(tex, nullptr, fb.data(), W * 4);
            SDL_RenderClear(ren);
            SDL_RenderCopy(ren, tex, nullptr, nullptr);
            SDL_RenderPresent(ren);

            // Lock to 60 fps: coarse sleep, spin the last stretch. When the
            // sim falls more than two frames behind the absolute schedule,
            // SLIP the schedule instead of sprinting to catch up - the
            // sprint produced audio faster than the device drains it, so
            // the catch-up frames were queued into a full buffer and
            // dropped: an audible skip bought with extra work.
            auto target = t0 + std::chrono::microseconds(16667LL * frame);
            auto now0 = clockk::now();
            if (now0 > target + std::chrono::microseconds(2 * 16667LL))
                t0 += now0 - target;
            for (;;) {
                auto now = clockk::now();
                if (now >= target) break;
                auto rem = target - now;
                if (rem > std::chrono::milliseconds(2))
                    std::this_thread::sleep_for(rem - std::chrono::milliseconds(2));
            }
            }

            if (frame % 300 == 0) {
                double s = std::chrono::duration<double>(clockk::now() - t0).count();
                printf("frame %u  %.2f fps\n", frame, frame / s);
                fflush(stdout);
            }
        }
        if (!vs && vblank) vblank = false;

        if (!vblank) {
            // Store at the CURRENT hpos, then advance. The previous order
            // incremented first, so the first visible pixel of every line
            // landed in column 1, column 0 was never written and the last
            // column was dropped - a one-pixel right shift across the whole
            // image, in the live window as well as --shot.
            if (hs && !hblank) { hpos = 0; hblank = true; vpos++; }
            if (!hs && hblank) hblank = false;
            if (!hblank) {
                if (vpos < H && hpos < W)
                    fb[vpos * W + hpos] = 0xFF000000u | (tb->rgb & 0xFFFFFFu);
                hpos++;
            }
        }
    }

    if (headless)
        printf("audio: %ld samples, %ld off-centre (%.1f%%), range %d..%d, "
               "%ld distinct levels (%.1f effective bits)\n",
               asamples, anonzero,
               asamples ? 100.0 * anonzero / asamples : 0.0, amin, amax,
               adistinct, adistinct > 1 ? log2((double)adistinct) : 0.0);
    if (adev) {
        // 44100 Hz consumed against 735 samples per EMULATED frame: a sim that
        // does not hold 60 fps cannot keep the device fed, however correct the
        // samples are.
        double secs = std::chrono::duration<double>(clockk::now() - t0).count();
        printf("audio delivery: %ld frames queued, %ld dropped (queue full), "
               "%ld frames with the queue near-dry, %ld truly starved; "
               "produced %.0f samples/s for a %d Hz device (%.0f%% of real time)\n",
               aqueued, adropped, aunderrun, adry,
               secs > 0 ? asamples / secs : 0.0,
               44100, secs > 0 ? 100.0 * asamples / secs / 44100 : 0.0);
    }
    if (profile_from >= 0) {
        // Aggregate samples by nearest preceding symbol and print the ranking.
        auto report = [&](const char* title, std::vector<uint64_t>& h, size_t top) {
            std::map<std::string, uint64_t> by_sym;
            uint64_t total = 0;
            for (uint32_t a = 0; a < 65536; a++) {
                if (!h[a]) continue;
                total += h[a];
                std::string sym;
                auto it = g_symbols.upper_bound(a);
                if (it == g_symbols.begin()) { char hx[8]; snprintf(hx, sizeof hx, "$%04X", a); sym = hx; }
                else { --it; sym = it->second; }
                by_sym[sym] += h[a];
            }
            std::vector<std::pair<uint64_t, std::string>> rank;
            for (auto& kv : by_sym) rank.push_back({kv.second, kv.first});
            std::sort(rank.rbegin(), rank.rend());
            printf("%s: %llu PC samples from frame %ld\n", title,
                   (unsigned long long)total, profile_from);
            for (size_t i = 0; i < rank.size() && i < top; i++)
                printf("  %6.2f%%  %llu  %s\n", 100.0 * rank[i].first / total,
                       (unsigned long long)rank[i].first, rank[i].second.c_str());
        };
        report("profile", prof, 40);
        if (peek_addr >= 0) report("overrun-tick profile", prof_late, 20);
    }
    if (peek_addr >= 0) {
        long ticks = 0;
        for (int i = 0; i < 9; i++) ticks += peek_hist[i];
        printf("peek $%04lX: %ld changes; interval histogram (display frames):",
               peek_addr & 0xFFFF, ticks);
        for (int i = 1; i <= 8; i++)
            if (peek_hist[i]) printf(" %d:%ld", i, peek_hist[i]);
        if (peek_hist[0]) printf(" >8:%ld", peek_hist[0]);
        printf("\n");
    }
    if (audio_wav) write_wav(audio_wav, wavbuf, 44100);
    if (shot) write_ppm(shot, fb, W, H);
    if (adev) SDL_CloseAudioDevice(adev);
    if (tex) SDL_DestroyTexture(tex);
    if (ren) SDL_DestroyRenderer(ren);
    if (win) SDL_DestroyWindow(win);
    if (!headless) SDL_Quit();
    delete tb;
    return 0;
}
