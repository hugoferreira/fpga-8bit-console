// Console runner: Verilated model + SDL2 window, replacing the Rust flow.
// One process, no FFI seams: the frame loop drives the model directly and
// paces to a locked 60 fps.
#include "Vtop.h"
#include "verilated.h"
#include <SDL.h>
#include <chrono>
#include <thread>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <vector>
#include <map>
#include <string>
#include <fstream>
#include <sstream>

static const int W = 160, H = 121, SCALE = 4;
static const int CLKS_PER_PIXEL = 3;

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
    for (int i = 0; i < 10; i++) { tb->clk_i = !tb->clk_i; tb->eval(); }
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
    win = SDL_CreateWindow("Console (ESC to exit)",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        W * SCALE, H * SCALE, SDL_WINDOW_ALLOW_HIGHDPI);
    ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED);
    SDL_AudioSpec want = {}, have = {};
    want.freq = 44100;
    want.format = AUDIO_U8;
    want.channels = 1;
    want.samples = 1024;
    adev = SDL_OpenAudioDevice(nullptr, 0, &want, &have, 0);
    if (adev) SDL_PauseAudioDevice(adev, 0);
    else fprintf(stderr, "audio disabled: %s\n", SDL_GetError());
    tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_ARGB8888,
        SDL_TEXTUREACCESS_STREAMING, W, H);
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "nearest");
    }

    std::vector<uint32_t> fb(W * H, 0);
    std::vector<uint8_t> abuf;
    abuf.reserve(1024);
    long aerr = 0;                        // 735 samples per 19481 pixels
    long asamples = 0, anonzero = 0;      // headless audio activity check
    int amin = 255, amax = 0;
    long fsum = 0, fn = 0;                // per-frame audio energy for --audio-trace
    int fmin = 255, fmax = 0;
    uint32_t hpos = 0, vpos = 0, frame = 0;
    bool vblank = true, hblank = false;

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

        // sample the PSG's 22050 Hz PCM at 44100 Hz (Bresenham across the
        // frame) - a natural 2x zero-order hold of the chip's native rate
        aerr += 735;
        if (aerr >= 19481) {
            aerr -= 19481;
            abuf.push_back(tb->audio);
            asamples++;
            if (tb->audio != 0x80 && tb->audio != 0) anonzero++;
            if (tb->audio < amin) amin = tb->audio;
            if (tb->audio > amax) amax = tb->audio;
            int d = tb->audio - 128;
            fsum += (d < 0 ? -d : d);
            fn++;
            if (tb->audio < fmin) fmin = tb->audio;
            if (tb->audio > fmax) fmax = tb->audio;
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

            if (audio_trace && fn) {
                printf("frame %u audio mean|dev| %.1f range %d..%d\n",
                       frame, (double)fsum / fn, fmin, fmax);
                fflush(stdout);
            }
            fsum = 0; fn = 0; fmin = 255; fmax = 0;

            if (max_frames && (long)frame >= max_frames) running = false;

            if (adev) {
                if (SDL_GetQueuedAudioSize(adev) < 4 * 735)
                    SDL_QueueAudio(adev, abuf.data(), (Uint32)abuf.size());
                abuf.clear();
            }
            if (!headless) {
            SDL_UpdateTexture(tex, nullptr, fb.data(), W * 4);
            SDL_RenderClear(ren);
            SDL_RenderCopy(ren, tex, nullptr, nullptr);
            SDL_RenderPresent(ren);

            // Lock to 60 fps: coarse sleep, spin the last stretch
            auto target = t0 + std::chrono::microseconds(16667LL * frame);
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
            if (hs && !hblank) { hpos = 0; hblank = true; vpos++; }
            else hpos++;
            if (!hs && hblank) hblank = false;
            if (!hblank && vpos < H && hpos < W)
                fb[vpos * W + hpos] = 0xFF000000u | (tb->rgb & 0xFFFFFFu);
        }
    }

    if (headless)
        printf("audio: %ld samples, %ld off-centre (%.1f%%), range %d..%d\n",
               asamples, anonzero,
               asamples ? 100.0 * anonzero / asamples : 0.0, amin, amax);
    if (shot) write_ppm(shot, fb, W, H);
    if (adev) SDL_CloseAudioDevice(adev);
    if (tex) SDL_DestroyTexture(tex);
    if (ren) SDL_DestroyRenderer(ren);
    if (win) SDL_DestroyWindow(win);
    if (!headless) SDL_Quit();
    delete tb;
    return 0;
}
