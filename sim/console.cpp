// Console runner: Verilated model + SDL2 window, replacing the Rust flow.
// One process, no FFI seams: the frame loop drives the model directly and
// paces to a locked 60 fps.
#include "Vtop.h"
#include "verilated.h"
#include <SDL.h>
#include <chrono>
#include <thread>
#include <cstdio>
#include <vector>

static const int W = 160, H = 121, SCALE = 4;
static const int CLKS_PER_PIXEL = 3;

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtop* tb = new Vtop;

    // Reset
    tb->rst_i = 1;
    for (int i = 0; i < 10; i++) { tb->clk_i = !tb->clk_i; tb->eval(); }
    tb->rst_i = 0;

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) != 0) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }
    SDL_Window* win = SDL_CreateWindow("Console (ESC to exit)",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        W * SCALE, H * SCALE, SDL_WINDOW_ALLOW_HIGHDPI);
    SDL_Renderer* ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED);
    SDL_AudioSpec want = {}, have = {};
    want.freq = 44100;
    want.format = AUDIO_U8;
    want.channels = 1;
    want.samples = 1024;
    SDL_AudioDeviceID adev = SDL_OpenAudioDevice(nullptr, 0, &want, &have, 0);
    if (adev) SDL_PauseAudioDevice(adev, 0);
    else fprintf(stderr, "audio disabled: %s\n", SDL_GetError());
    SDL_Texture* tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_ARGB8888,
        SDL_TEXTUREACCESS_STREAMING, W, H);
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "nearest");

    std::vector<uint32_t> fb(W * H, 0);
    std::vector<uint8_t> abuf;
    abuf.reserve(1024);
    long aerr = 0;                        // 735 samples per 19481 pixels
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
        }

        if (vs && !vblank) {
            vblank = true;
            vpos = 0;
            frame++;

            // --- once per frame: input, present, pace ---
            SDL_Event ev;
            while (SDL_PollEvent(&ev))
                if (ev.type == SDL_QUIT) running = false;
            const Uint8* k = SDL_GetKeyboardState(nullptr);
            if (k[SDL_SCANCODE_ESCAPE]) running = false;
            uint8_t b = 0;
            if (k[SDL_SCANCODE_LEFT])  b |= 0x01;
            if (k[SDL_SCANCODE_RIGHT]) b |= 0x02;
            if (k[SDL_SCANCODE_UP])    b |= 0x04;
            if (k[SDL_SCANCODE_DOWN])  b |= 0x08;
            if (k[SDL_SCANCODE_Z])     b |= 0x10;
            if (k[SDL_SCANCODE_X])     b |= 0x20;
            tb->buttons = b;

            if (adev) {
                if (SDL_GetQueuedAudioSize(adev) < 4 * 735)
                    SDL_QueueAudio(adev, abuf.data(), (Uint32)abuf.size());
                abuf.clear();
            }
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

    if (adev) SDL_CloseAudioDevice(adev);
    SDL_DestroyTexture(tex);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
    delete tb;
    return 0;
}
