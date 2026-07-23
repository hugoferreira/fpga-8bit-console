// Batched pixel step: 3 clocks (one pixel at the simulator's 3-clk/px
// timing) per FFI call instead of 12 calls. Returns packed
// {vsync[25], hsync[24], rgb[23:0]}.
#include "Vtop.h"
extern "C" unsigned int top_pixel3(Vtop* t) {
    for (int i = 0; i < 3; i++) {
        t->clk_i = 1; t->eval();
        t->clk_i = 0; t->eval();
    }
    unsigned int s = t->rgb & 0xFFFFFFu;
    if (t->hsync) s |= 0x1000000u;
    if (t->vsync) s |= 0x2000000u;
    return s;
}

// macOS schedules spawned threads on efficiency cores by default; the sim
// thread needs a performance core to hold 60 fps.
#include <pthread/qos.h>
extern "C" void sim_thread_boost() {
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
}
