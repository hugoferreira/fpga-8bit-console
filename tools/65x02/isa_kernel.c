/* The core of a PICO-8 physics step, written as the Lua means it:
   16.16 fixed point, an object list, per-object accumulate/clamp/collide.
   This is celeste's move() plus its speed clamping, transcribed. */
typedef signed int   fx;      /* 16.16 */
typedef unsigned char u8;

#define FX(a,b) (((a)<<16)|(b))

struct obj { fx x, y, spdx, spdy; u8 type, flip, alive, pad; };
extern struct obj objs[16];
extern u8 solid(int x, int y);

fx approach(fx val, fx target, fx amount) {
    return val > target ? (val - amount > target ? val - amount : target)
                        : (val + amount < target ? val + amount : target);
}

void step(void) {
    for (int i = 0; i < 16; i++) {
        struct obj *o = &objs[i];
        if (!o->alive) continue;
        o->spdy = approach(o->spdy, FX(0,0x8000), FX(0,0x0666));   /* gravity */
        o->spdx = approach(o->spdx, 0, FX(0,0x0400));              /* friction */
        fx nx = o->x + o->spdx;
        fx ny = o->y + o->spdy;
        if (!solid(nx >> 16, o->y >> 16)) o->x = nx; else o->spdx = 0;
        if (!solid(o->x >> 16, ny >> 16)) o->y = ny; else o->spdy = 0;
    }
}
