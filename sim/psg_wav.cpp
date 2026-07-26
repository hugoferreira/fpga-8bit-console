// Render the PSG to a WAV, with nothing else in the system.
//
// "The music sounds wrong" is not a debuggable statement. --psg-trace already
// answers allocation and sequencing (which SFX, on which channel, for how
// long); this answers synthesis, by producing the actual waveform so it can be
// measured against the pitches the cart data asks for - or simply listened to.
//
// Only rtl/psg.sv is instantiated: no CPU, no game, no video timing. The audio
// image is uploaded through the chip's own auto-incrementing port, exactly as
// a game's sound_init does.
//
//   psg_wav --audio build/celeste_audio.bin --music 0 --mask 7 \
//           --seconds 20 --out build/celeste_music.wav
//   psg_wav --audio build/celeste_audio.bin --sfx 3 --seconds 2 --out dash.wav
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <vector>
#include "Vpsg.h"
#include "verilated.h"

// rtl/psg.sv's compiled CLK_HZ parameter. This standalone fallback matches the
// module default; hardware-oracle builds override both it and -GCLK_HZ with the
// board's derived PSG clock. Verilator wall time is test cost, not an RTL clock
// budget. The value must match the model's -GCLK_HZ or the divider detunes.
static double    CLK_HZ = 3506580.0;
static const int RATE   = 22050;          // the PSG's virtual sample rate

static Vpsg* dut;

static void tick() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
}

// NOTE: `rw` is wired to the bus's mem_write in chip.sv, so rw HIGH is a
// WRITE. Getting that backwards produces a chip that accepts nothing and
// renders silence, which looks exactly like a synthesis bug.
static void wr(uint8_t addr, uint8_t data) {
    dut->cs = 1; dut->rw = 1; dut->addr = addr; dut->di = data;
    tick();
    dut->cs = 0; dut->rw = 0; dut->addr = 0; dut->di = 0;
    tick();
}

static void write_wav(const char* path, const std::vector<int16_t>& pcm) {
    FILE* f = fopen(path, "wb");
    if (!f) { fprintf(stderr, "cannot write %s\n", path); exit(1); }
    uint32_t n = (uint32_t)pcm.size() * 2;
    uint32_t rate = RATE;
    auto u32 = [&](uint32_t v) { fwrite(&v, 4, 1, f); };
    auto u16 = [&](uint16_t v) { fwrite(&v, 2, 1, f); };
    fwrite("RIFF", 1, 4, f); u32(36 + n); fwrite("WAVE", 1, 4, f);
    fwrite("fmt ", 1, 4, f); u32(16); u16(1); u16(1);
    u32(rate); u32(rate * 2); u16(2); u16(16);     // 16-bit signed mono
    fwrite("data", 1, 4, f); u32(n);
    fwrite(pcm.data(), 1, n, f);
    fclose(f);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    const char* audio = nullptr;
    const char* out = "build/psg.wav";
    int music = -1, sfx = -1, mask = 7;
    double seconds = 10.0;
    long samples = -1;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--audio") && i + 1 < argc)   audio = argv[++i];
        else if (!strcmp(argv[i], "--out") && i + 1 < argc) out = argv[++i];
        else if (!strcmp(argv[i], "--music") && i + 1 < argc) music = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--sfx") && i + 1 < argc)   sfx = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--mask") && i + 1 < argc)  mask = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--seconds") && i + 1 < argc) seconds = atof(argv[++i]);
        else if (!strcmp(argv[i], "--samples") && i + 1 < argc) samples = atol(argv[++i]);
        else if (!strcmp(argv[i], "--clk") && i + 1 < argc) CLK_HZ = atof(argv[++i]);
    }
    if (!audio) { fprintf(stderr, "need --audio <4608-byte image>\n"); return 1; }

    std::vector<uint8_t> img(4608, 0);
    FILE* f = fopen(audio, "rb");
    if (!f) { fprintf(stderr, "cannot read %s\n", audio); return 1; }
    size_t got = fread(img.data(), 1, img.size(), f);
    fclose(f);
    fprintf(stderr, "audio image: %zu bytes\n", got);

    dut = new Vpsg;
    dut->reset = 1; dut->cs = 0; dut->rw = 0; dut->addr = 0; dut->di = 0;
    for (int i = 0; i < 16; i++) tick();
    dut->reset = 0;
    for (int i = 0; i < 16; i++) tick();

    // Upload through the auto-incrementing data port, as sound_init does.
    wr(0x00, 0x00);
    wr(0x01, 0x31);
    for (size_t i = 0; i < img.size(); i++) wr(0x02, img[i]);

    wr(0x21, (uint8_t)mask);
    if (music >= 0) wr(0x20, (uint8_t)music);
    if (sfx >= 0)   wr(0x10, (uint8_t)sfx);

    // psg.sv's pcm is signed 16-bit as of the mixer-resolution fix; it was an
    // unsigned 8-bit sample before. Widening it is the whole point of that
    // change, so this reads the wide value and writes a 16-bit WAV.
    std::vector<int16_t> pcm;
    const long want = samples >= 0 ? samples : (long)(seconds * RATE);
    pcm.reserve((size_t)want + 16);
    int lo = 32767, hi = -32768;

    // Sample on the chip's own divider, not on round(CLK_HZ/RATE) clocks.
    // The RTL derives 22050 Hz with a Bresenham accumulator, so a fixed clock
    // count does not land on the same instants - it drifts, duplicating and
    // dropping samples. That made the *same* audio at two different CLK_HZ
    // compare as a >100% per-sample error while RMS stayed within 1%, which
    // reads exactly like a synthesis bug and is not one. Mirroring the
    // accumulator makes the captured stream independent of CLK_HZ, which is
    // what lets a faster clock (needed once a voice costs more clocks) be
    // A/B'd against a slower one at all.
    const long DEC = (long)CLK_HZ - RATE;
    long divacc = 0;
    const auto started = std::chrono::steady_clock::now();
    while ((long)pcm.size() < want) {
        tick();
        const bool strobe = (divacc >= DEC);
        divacc += strobe ? -DEC : RATE;
        if (strobe) {
            // Captured at the strobe, so this is the previous walk's fully
            // settled output rather than one being accumulated right now.
            int16_t s = (int16_t)dut->pcm;
            pcm.push_back(s);
            if (s < lo) lo = s;
            if (s > hi) hi = s;
        }
    }
    write_wav(out, pcm);
    const double elapsed = std::chrono::duration<double>(
        std::chrono::steady_clock::now() - started).count();
    fprintf(stderr,
            "wrote %s: %zu samples at %d Hz, range %d..%d "
            "(%.3f s host time; non-normative)\n",
            out, pcm.size(), RATE, lo, hi, elapsed);
    delete dut;
    return 0;
}
