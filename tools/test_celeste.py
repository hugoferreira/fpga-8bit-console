#!/usr/bin/env python3
"""End-to-end test of the Celeste port, driven from the reset vector.

Runs the assembled binary under tools/sim6502.py with the PPU registers faked,
so the object list, the collision, the 8.8 movement and the room machinery are
all exercised the way the console would exercise them.

The interesting checks are the ones a screenshot cannot make: that the
sub-pixel remainder actually accumulates, that the player lands on the tile the
room data says is solid, and that a spike kills.

Usage: test_celeste.py build/celeste.bin build/celeste.lbl
"""
import hashlib
import re
import sys

from sim6502 import Sim6502

# object record layout, from src/celeste/layout.inlay.asm
O_TYPE, O_SPR, O_X, O_Y = 0, 1, 2, 3
O_SPDX, O_SPDY, O_REMX, O_REMY = 4, 6, 8, 10
O_FLAGS, O_STATE, O_DJUMP, O_GRACE = 17, 18, 20, 21
O_SIZE, OBJ_MAX, OBJPOOL = 64, 16, 0x5000
T_PLAYER, T_SPAWN, T_SMOKE, T_TITLE = 1, 2, 3, 4

# zero page
FRAMES, SECONDS, DEATHS, FREEZE, SHAKE = 0x30, 0x31, 0x33, 0x35, 0x36
LEVEL, CAMERA_Y, ROOM_SLOT = 0x3D, 0x3E, 0x3B
ROOMTILES = 0x5400

BTN_L, BTN_R, BTN_U, BTN_D, BTN_JUMP, BTN_DASH = 1, 2, 4, 8, 0x10, 0x20

FAIL = []

VISUAL_CHECKPOINTS = {
    "title":
        "9f6d80ffa88c5b2833c95c6a9b36553133d5e0bd3ea9fc24f66cbcf91d43b53c",
    "first-room-play":
        "f6baa171ed5e6f3d4b9689316cc397b50d40436fedf16a9ce0096d71176ed993",
    "hud":
        "654a80be192ffa148acc3a9924c4f9b7660671b2a7b017cc239fd0ce8a7c303f",
    "room-transition":
        "7520f38e450645c502cfdecdf9668522ee4db7e6b2bac37af8137653a3f29091",
}
AUDIO_TRACE_SHA256 = (
    "0f40c1e74d5de88e5fa973794285010fd20cfdd02e7317451e7ae3f3f0a74ca8"
)


def chk(cond, msg):
    print(f"  {'ok  ' if cond else 'FAIL'} {msg}")
    if not cond:
        FAIL.append(msg)


def s8(v):
    return v - 256 if v > 127 else v


def s16(v):
    return v - 65536 if v > 32767 else v


def visual_digest(rig):
    state = bytearray(rig.map_lo)
    state.extend(rig.map_hi)
    state.extend(rig.ovl)
    for sprite in getattr(rig, "last_sprites", []):
        for key in ("i", "x", "y", "base", "flags"):
            state.append(sprite.get(key, 0))
    return hashlib.sha256(state).hexdigest()


def checkpoint_visual(rig, name):
    actual = visual_digest(rig)
    expected = VISUAL_CHECKPOINTS.get(name)
    chk(expected is None or actual == expected,
        f"{name} visual checkpoint {actual}")


class Rig:
    def __init__(self, image, sym):
        self.sym = sym
        self.cpu = Sim6502(image)
        self.frame = 0
        self.buttons = 0
        self.rnd = 0
        self.sprites = []
        self.stage = {}
        self.ovl = bytearray(2400)
        self.map_lo = bytearray(512)
        self.map_hi = bytearray(512)
        self.music = []          # (pattern, fade) in call order
        self.sfx = []
        self.audio_trace = []
        self.fade = 0
        c = self.cpu
        c.readers[0x400D] = self._tick
        c.readers[0x4007] = lambda: self.buttons
        c.readers[0x400F] = self._rnd
        c.readers[0x4103] = lambda: 0
        c.writers[0x4008] = lambda v: self.stage.__setitem__("i", v)
        c.writers[0x4009] = lambda v: self.stage.__setitem__("x", v)
        c.writers[0x400A] = lambda v: self.stage.__setitem__("y", v)
        c.writers[0x400E] = lambda v: self.stage.__setitem__("base", v)
        c.writers[0x400B] = self._commit
        c.writers[0x4120] = self._music
        c.writers[0x4122] = lambda v: setattr(self, "fade", v)
        for ch in range(4):
            c.writers[0x4110 + ch] = self._sfx
        for a in range(0x4000, 0x4200):
            c.writers.setdefault(a, lambda v: None)
        for off in range(2400):
            c.writers[0xE000 + off] = self._ovl(off)
        for off in range(512):
            c.writers[0xF000 + off] = self._map(self.map_lo, off)
            c.writers[0xF200 + off] = self._map(self.map_hi, off)
        c.pc = sym["reset"]

    def _tick(self):
        self.frame = (self.frame + 1) & 0xFF
        return self.frame

    def _rnd(self):
        self.rnd = (self.rnd * 5 + 13) & 0xFF
        return self.rnd

    def _commit(self, v):
        self.sprites.append(dict(self.stage, flags=v))

    def _music(self, v):
        self.music.append((v, self.fade))
        self.audio_trace.append(("music", v, self.fade))

    def _sfx(self, v):
        self.sfx.append(v)
        self.audio_trace.append(("sfx", v))

    def _ovl(self, off):
        def w(v):
            self.ovl[off] = v
        return w

    def _map(self, arr, off):
        def w(v):
            arr[off] = v
        return w

    def frames(self, n, budget=40_000_000):
        """n game frames. main_loop runs once per two vsyncs."""
        hits = 0
        for _ in range(budget):
            self.cpu.step()
            if self.cpu.pc == self.sym["main_loop"]:
                if self.sprites:
                    self.last_sprites = self.sprites
                self.sprites = []
                hits += 1
                if hits > n:
                    return
        raise TimeoutError(f"only {hits}/{n} frames")

    def hold(self, mask, n):
        self.buttons = mask
        self.frames(n)
        self.buttons = 0

    def objects(self, kind=None):
        m = self.cpu.m
        out = []
        for i in range(OBJ_MAX):
            base = OBJPOOL + i * O_SIZE
            t = m[base + O_TYPE]
            if t and (kind is None or t == kind):
                out.append((i, base, t))
        return out

    def player(self):
        objs = self.objects(T_PLAYER)
        return objs[0][1] if objs else None

    def field(self, base, off):
        return self.cpu.m[base + off]

    def word(self, base, off):
        return s16(self.cpu.m[base + off] | self.cpu.m[base + off + 1] << 8)


def main():
    image = open(sys.argv[1], "rb").read()
    sym = {}
    for line in open(sys.argv[2]):
        m = re.match(r"al\s+([0-9A-Fa-f]+)\s+\.?(\S+)", line)
        if m:
            sym[m.group(2)] = int(m.group(1), 16)

    r = Rig(image, sym)
    m = r.cpu.m

    print("== boot: the title screen ==")
    r.frames(2)
    chk(m[LEVEL] == 31, f"boots into the title room, level {m[LEVEL]} (cart: 31)")
    chk(r.objects() == [], f"no objects on the title screen ({len(r.objects())} found)")
    chk(r.music == [(40, 0)],
        f"plays the title theme, music(40) with no fade: {r.music}")
    nonzero = sum(1 for b in r.map_lo if b)
    # The logo is a 7x4 block of unique tiles, 28 cells. The cart draws 27 of
    # them (tile 78 carries no draw flag), and 8 of those 27 are entirely
    # transparent - since the 2bpp re-encode those cost no sheet slot and are
    # left as an empty cell, which the compositor skips. 19 carry pixels.
    chk(nonzero == 19, f"the CELESTE logo reached the tile map ({nonzero} cells "
                       f"with pixels; 28 - 1 undrawn - 8 blank)")
    lit = sum(bin(b).count("1") for b in r.ovl)
    chk(lit > 60, f"the credits are on the overlay ({lit} pixels lit)")
    chk(r.cpu.m[0x4C] == 0, "start_game is clear until a button is pressed")
    checkpoint_visual(r, "title")

    print("\n== title: jump starts the game ==")
    r.music.clear()
    r.buttons = BTN_JUMP
    r.frames(1)
    r.buttons = 0
    chk(m[0x4C] == 1, "start_game set")
    chk(s8(m[0x4D]) == 50 or s8(m[0x4D]) == 49,
        f"start_game_flash armed at {s8(m[0x4D])} (cart: 50)")
    chk(r.music == [(0x80, 0)], f"music(-1) cut it dead, no fade: {r.music}")
    chk(38 in r.sfx, f"sfx(38) played: {r.sfx[-3:]}")

    print("\n== the flash hands over to begin_game ==")
    r.music.clear()
    for _ in range(85):
        r.frames(1)
        if m[LEVEL] != 31:
            break
    chk(m[LEVEL] == 0, f"reached the first playing room, level {m[LEVEL]}")
    chk(r.music == [(0, 0)], f"the climb started: music(0), no fade: {r.music}")
    chk(m[0x4C] == 0, "start_game cleared")
    chk(m[SECONDS] == 0 and m[0x32] == 0, "the clock was reset for the run")

    print("\n== the first room ==")
    spawns = r.objects(T_SPAWN)
    chk(len(spawns) == 1, f"one player_spawn from the marker tile ({len(spawns)} found)")
    chk(len(r.objects(T_TITLE)) == 1, "a room_title exists (the cart skips it on the title)")
    if spawns:
        base = spawns[0][1]
        marker = next(i for i in range(256) if r.cpu.m[ROOMTILES + i] == 1)
        chk(r.field(base, O_X) == (marker % 16) * 8,
            f"spawn at x={r.field(base, O_X)}, the marker tile's column")

    print("\n== the spawn animation hands over to the player ==")
    r.frames(60)
    p = r.player()
    chk(p is not None, "a player object exists")
    if p is None:
        return report()
    chk(len(r.objects(T_SPAWN)) == 0, "the spawn object destroyed itself")
    py0 = s8(r.field(p, O_Y))
    chk(0 <= py0 <= 120, f"the player is inside the room (y={py0})")

    print("\n== gravity and solid ground ==")
    r.frames(20)
    p = r.player()
    py1 = s8(r.field(p, O_Y))
    spdy = r.word(p, O_SPDY)
    chk(spdy == 0, f"resting on the floor, spd.y = {spdy / 256:.3f}")
    r.frames(5)
    chk(s8(r.field(r.player(), O_Y)) == py1, "and it stays there")

    print("\n== running right accumulates a sub-pixel remainder ==")
    p = r.player()
    x0 = s8(r.field(p, O_X))
    r.buttons = BTN_R
    r.frames(1)
    p = r.player()
    spdx = r.word(p, O_SPDX)
    remx = r.word(p, O_REMX)
    chk(spdx > 0, f"spd.x accelerated to {spdx / 256:.3f} px/frame")
    chk(remx != 0 or spdx == 0, f"rem.x carries the fraction ({remx / 256:.3f})")
    r.frames(6)
    r.buttons = 0
    p = r.player()
    x1 = s8(r.field(p, O_X))
    chk(x1 > x0, f"the player moved right, x {x0} -> {x1}")
    chk(r.word(p, O_SPDX) <= 0x100, "and is capped at maxrun")

    print("\n== facing and animation ==")
    r.hold(BTN_L, 4)
    p = r.player()
    chk(r.field(p, 16) & 1 == 1, "flip.x set when running left")
    r.hold(BTN_R, 4)
    p = r.player()
    chk(r.field(p, 16) & 1 == 0, "flip.x cleared when running right")

    print("\n== jump ==")
    r.frames(10)
    p = r.player()
    ytop = y0 = s8(r.field(p, O_Y))
    r.buttons = BTN_JUMP
    r.frames(1)
    r.buttons = 0
    for _ in range(12):
        r.frames(1)
        p = r.player()
        if p:
            ytop = min(ytop, s8(r.field(p, O_Y)))
    chk(ytop < y0 - 4, f"the jump lifted the player {y0 - ytop} pixels")
    r.frames(20)
    p = r.player()
    chk(p is not None and r.word(p, O_SPDY) == 0, "and it landed again")

    print("\n== dash ==")
    p = r.player()
    m[p + O_X] = 8                      # the spawn tile, with a known wall to
    m[p + O_Y] = 96                     # its right: room 0 is solid at tx=3
    for off in (O_SPDX, O_SPDX + 1, O_SPDY, O_SPDY + 1, O_REMX, O_REMX + 1):
        m[p + off] = 0
    djump0 = r.field(p, O_DJUMP)
    r.buttons = BTN_DASH | BTN_R
    r.frames(1)
    p = r.player()
    chk(r.field(p, O_DJUMP) == djump0 - 1, "the dash spent a djump")
    chk(m[FREEZE] > 0 or m[SHAKE] > 0, "the dash froze and shook the screen")
    spdx = r.word(p, O_SPDX)
    chk(spdx >= 0x400, f"dash speed is {spdx / 256:.2f} px/frame (cart: 5)")
    r.buttons = 0
    r.frames(6)
    p = r.player()
    chk(p is not None and s8(r.field(p, O_X)) == 17,
        f"the dash ran into the wall at tile column 3 and stopped at x="
        f"{s8(r.field(p, O_X)) if p else None} (hitbox right edge = 24)")
    chk(p is not None and r.word(p, O_SPDX) == 0, "the block zeroed spd.x")
    smoke = r.objects(T_SMOKE)
    chk(len(smoke) > 0, f"the dash left smoke ({len(smoke)} puffs)")

    print("\n== smoke expires ==")
    r.frames(20)
    chk(len(r.objects(T_SMOKE)) == 0, "all smoke has gone")

    print("\n== the sprite list is staged ==")
    r.frames(1)
    st = r.last_sprites
    chk(len(st) >= 6, f"{len(st)} sprites staged (player + 5 hair)")
    chk(len({s["flags"] >> 4 for s in st}) >= 2,
        "the hair carries its own palette base, so it is recoloured")
    chk(all(s["y"] < 120 for s in st), "every sprite is on screen")
    checkpoint_visual(r, "first-room-play")

    print("\n== spikes kill ==")
    deaths0 = m[DEATHS]
    p = r.player()
    # room 0 has a downward spike (tile 17) in the floor; drop the player onto
    # one by hand rather than trying to walk there.
    spike = next((i for i in range(256) if m[ROOMTILES + i] == 17), None)
    chk(spike is not None, "the room has a spike tile")
    if spike is not None and p is not None:
        m[p + O_X] = (spike % 16) * 8
        m[p + O_Y] = (spike // 16) * 8 - 3
        m[p + O_SPDY] = 0x00
        m[p + O_SPDY + 1] = 0x01        # falling onto it
        r.frames(3)
        chk(m[DEATHS] == deaths0 + 1, f"death counted ({m[DEATHS]})")
        chk(r.player() is None, "the player was destroyed")

    print("\n== the room restarts ==")
    r.frames(20)
    chk(len(r.objects(T_SPAWN)) == 1 or r.player() is not None,
        "the room reloaded and respawned")
    chk(m[LEVEL] == 0, "into the same room")

    print("\n== the clock ticks ==")
    sec0 = m[SECONDS]
    r.frames(35)
    chk(m[SECONDS] != sec0, f"seconds advanced to {m[SECONDS]}")

    print("\n== the overlay carries the HUD ==")
    lit = sum(bin(b).count("1") for b in r.ovl)
    chk(lit > 40, f"{lit} overlay pixels lit")
    right = sum(bin(b).count("1") for y in range(120) for b in r.ovl[y * 20 + 16:y * 20 + 20])
    chk(right > 20, f"{right} of them in the HUD strip, right of the playfield")

    # Read the clock back out of the overlay bitmap and compare it against the
    # font, digit by digit. Checking `seconds` in RAM is not the same test:
    # the clock read 00:00 on screen for a while with the counter working.
    def glyph_at(px, py):
        rows = []
        for dy in range(5):
            byte = r.ovl[(py + dy) * 20 + (px >> 3)] | r.ovl[(py + dy) * 20 + (px >> 3) + 1] << 8
            rows.append((byte >> (px & 7)) & 7)
        return rows

    def font(ch):
        base = sym["font3x5"] + ch * 5
        return list(m[base:base + 5])

    for label, px, want in (("seconds tens", 142, m[SECONDS] // 10),
                            ("seconds units", 146, m[SECONDS] % 10),
                            ("deaths units", 142, None)):
        if want is None:
            continue
        chk(glyph_at(px, 11) == font(want),
            f"the HUD clock's {label} digit reads {want}")
    checkpoint_visual(r, "hud")

    print("\n== room transitions ==")
    p = r.player()
    if p is None:
        r.frames(40)
        p = r.player()
    if p is not None:
        m[p + O_Y] = 0xF0               # y = -16, above the room
        r.frames(2)
        chk(m[LEVEL] == 11, f"walking off the top loaded the next room (level {m[LEVEL]})")
        # slot 0 is the title room, so the playing rooms are slots 1..3
        chk(m[ROOM_SLOT] == 2, f"advanced to resident-room slot {m[ROOM_SLOT]}")
        chk(len(r.objects(T_SPAWN)) == 1, "which spawned its own player")
        checkpoint_visual(r, "room-transition")

        print("\n== the room-transition music cues ==")
        r.music.clear()
        p = r.player()
        if p is None:
            r.frames(40)
            p = r.player()
        if p is not None:
            m[p + O_Y] = 0xF0           # leave level 11 -> the cart cues music 20
            r.frames(2)
            chk(r.music == [(20, 31)],
                f"leaving 'old site' cues music(20) with a 500 ms fade: {r.music}")
            chk(m[LEVEL] == 20, f"and loaded level {m[LEVEL]}")
            r.music.clear()
            p = r.player()
            if p is None:
                r.frames(40)
                p = r.player()
            if p is not None:
                m[p + O_Y] = 0xF0       # leave level 20 -> music 30
                r.frames(2)
                chk(r.music == [(30, 31)],
                    f"leaving level 20 cues music(30): {r.music}")
                chk(m[LEVEL] == 0, "and wraps to the first playing room, "
                                   "never back to the title")

    encoded_trace = repr(r.audio_trace).encode("ascii")
    trace_digest = hashlib.sha256(encoded_trace).hexdigest()
    chk(AUDIO_TRACE_SHA256 is None or trace_digest == AUDIO_TRACE_SHA256,
        f"PSG command trace checkpoint {trace_digest}")
    return report()


def report():
    print()
    if FAIL:
        print(f"{len(FAIL)} FAILED:")
        for f in FAIL:
            print("  -", f)
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
