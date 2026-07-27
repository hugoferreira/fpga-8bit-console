#!/usr/bin/env python3
"""Reference model of the PICO-8 binary's integer audio pipeline.

Implements the exact integer forms recovered in
/Applications/PICO-8.app/Contents/MacOS/pico8-psg-re.md and spot-verified
against pico8.x86_64.asm (see openspec/changes/adopt-pico8-integer-audio).
The model is the gate for that change: RTL stages must match it exactly,
and the model itself must match the stored PICO-8 exports byte-for-byte
on deterministic cases (task 1.3).

Scope: deterministic paths (waves 0-5 and 8, effects 0-7, the per-tick
64-sample crossfade, single-voice soft_add mixing). Noise and phaser are
excluded pending their own verification tasks; noise is sequence-inexact
in principle (shared RNG).

Usage:
  psg_binary_model.py render <case.bin> --ticks N [--sfx N] --out out.wav
  psg_binary_model.py compare <case.bin> --ticks N <reference.wav>
"""

from __future__ import annotations

import argparse
import struct
import sys
import wave
from pathlib import Path

TICK_SAMPLES = 183
BLEND_SAMPLES = 64

# Thirteen entries: _get_dx_for_note_fine reads dx[chromatic + 1], and the
# binary's table carries the octave wrap (1046) for it.
NOTE_DX = [523, 554, 587, 622, 659, 698,
           740, 784, 831, 880, 932, 984, 1046]


def tz(a: int, d: int) -> int:
    """Signed integer division truncated toward zero."""
    q = abs(a) // d
    return -q if a < 0 else q


def u16(x: int) -> int:
    return x & 0xFFFF


# --- phase increments -------------------------------------------------------

def dx_for_note(semitone: int) -> int:
    """_get_dx_for_note: 16-bit oscillator increment for an integer pitch."""
    octave, chromatic = divmod(semitone, 12)
    dp = ((NOTE_DX[chromatic] << 16) * 0x2F8DF18F) >> 44
    return dp >> (3 - octave) if octave < 3 else dp << (octave - 3)


def dx_for_note_fine(p_1616: int) -> int:
    """_get_dx_for_note_fine, instruction-exact: the TABLE entries are
    interpolated by the 16-bit fraction, then the shared reciprocal
    multiply and octave shift follow - not interpolation of final dx
    values. Verified against pico8.x86_64.asm L249743."""
    frac = p_1616 & 0xFFFF
    semi = p_1616 >> 16
    octave = tz(semi + 48, 12) - 4
    s = semi
    if p_1616 < 0:
        s += 12 * ((-semi) // 12) + 12
    chromatic = s % 12
    blended = ((0x10000 - frac) * NOTE_DX[chromatic]
               + frac * NOTE_DX[chromatic + 1])
    dp = (blended * 0x2F8DF18F) >> 44
    return dp >> (3 - octave) if octave < 3 else dp << (octave - 3)


def dx_clamped(p_1616: int) -> int:
    return max(8, min(32768, dx_for_note_fine(p_1616)))


# --- waveforms (exact integer forms) ----------------------------------------

def tri_raw(x: int) -> int:
    return 3 * x - 49152 if x < 32768 else 147456 - 3 * x


def skew0(x: int) -> int:
    if x < 57344:
        return (24572 * x) // 57344 - 12286
    return (24572 * (65535 - x)) // 8192 - 12286


def tri_alt(x: int) -> int:
    return skew0(x) + 3 * tz(tri_raw(x), 4)


def tilt(x: int, t_break: int = 57344) -> int:
    if x < t_break:
        return (24572 * x) // t_break - 12286
    return (24572 * (65535 - x)) // (65536 - t_break) - 12286


def saw(x: int) -> int:
    return tz(x - 32768, 4)


def square_at(x: int, threshold: int) -> int:
    return -6143 if x < threshold else 6143


def organ(x: int) -> int:
    if x < 16384:
        return x - 8192
    if x < 32768:
        return 24576 - x
    if x < 49152:
        return tz(2 * (x - 32768), 3) - 8192
    return tz(2 * (65536 - x), 3) - 8192


def saw_alt(x: int) -> int:
    return tz(tz(x - 32768, 4) + tz((x // 2) - 32768, 4), 2)


CUSTOM_SHIFT = 7


def custom_wave(table: list[int], x: int) -> int:
    """The 64-entry custom waveform: 10-fractional-bit lerp, arithmetic
    final shift (floor). Table entries are the record's signed bytes at
    the engine's load scale."""
    i = (x >> 10) & 63
    f = x & 1023
    w0 = table[i] << CUSTOM_SHIFT
    w1 = table[(i + 1) & 63] << CUSTOM_SHIFT
    return (w0 * 1024 + (w1 - w0) * f) >> 10


def wave_pair(w: int, p: int, q0: int, mode: int, alt: bool = False) -> int:
    """The pre-scale oscillator value: primary plus half-weight secondary.
    `alt` is the BUZZ/alternate flag at oscillator-state +0x54."""
    q = u16(q0 << (1 if mode == 2 else 0))
    if w == 0 or w == 7:                      # phaser shares the triangle core
        f = tri_alt if alt and w == 0 else tri_raw
        return tz(f(p), 4) + tz(f(u16(q0)), 8)
    if w == 1:
        t_break = 61440 if alt else 57344
        return tilt(p, t_break) + tz(tilt(q, t_break), 2)
    if w == 2:
        f = saw_alt if alt else saw
        return f(p) + tz(f(q), 2)
    if w == 3:
        th = 0x9800 if alt else 0x8000
        return square_at(p, th) + tz(square_at(q, th), 2)
    if w == 4:
        th = 0xC800 if alt else 0xB000
        return square_at(p, th) + tz(square_at(q, th), 2)
    if w == 5:
        if alt:
            return organ(p) + (-3071 if q < 32768 else 3071)
        return organ(p) + tz(organ(q), 2)
    raise ValueError(f"wave {w} not in the deterministic model")


def scale(g: int, z: int) -> int:
    return tz(g * z, 3072)


# --- SFX record parsing ------------------------------------------------------

class Sfx:
    def __init__(self, blob: bytes):
        self.raw = blob[:64]          # the 64 note bytes, wavetable source
        self.notes = []
        for i in range(32):
            lo, hi = blob[2 * i], blob[2 * i + 1]
            self.notes.append({
                "pitch": lo & 0x3F,
                "wave": ((hi & 1) << 2) | (lo >> 6),
                "vol": (hi >> 1) & 0x07,
                "fx": (hi >> 4) & 0x07,
                "custom": hi >> 7,
            })
        self.filters = blob[64]
        self.speed = max(1, blob[65])
        self.loop_start = blob[66]
        self.loop_end = blob[67]
        # Filter byte: noiz = bit 1, buzz = bit 2, and the top five bits are
        # base-3 digits detune / reverb / dampen (the RTL's fdec convention,
        # matching the +0x50/+0x54 stores in _calculate_osc_state).
        self.noiz = (self.filters >> 1) & 1
        self.buzz = (self.filters >> 2) & 1
        f3 = self.filters >> 3
        self.detune = f3 % 3
        self.reverb = (f3 // 3) % 3
        self.dampen = (f3 // 9) % 3


def load_sfx(bin_path: Path, index: int) -> Sfx:
    blob = bin_path.read_bytes()
    return Sfx(blob[256 + 68 * index: 256 + 68 * (index + 1)])


# --- oscillator/effect state -------------------------------------------------

class OscState:
    """Everything _mix_osc_tick_new consumes for one tick's render."""

    __slots__ = ("wave", "dp", "dq", "g", "p", "q0", "mode", "alt",
                 "table", "bass")

    def __init__(self):
        self.wave = 0
        self.dp = 0
        self.dq = 0
        self.g = 0
        self.p = 0
        self.q0 = 0
        self.mode = 0
        self.alt = False
        self.table = None
        self.bass = False

    def copy(self) -> "OscState":
        o = OscState()
        for f in self.__slots__:
            setattr(o, f, getattr(self, f))
        return o

    def render(self, n: int) -> list[int]:
        out = []
        for _ in range(n):
            if self.g == 0:
                out.append(0)
            else:
                if self.wave == 8:
                    q = u16(self.q0 << (1 if self.mode == 2 else 0))
                    z = (custom_wave(self.table, self.p)
                         + tz(custom_wave(self.table, q), 2))
                else:
                    z = wave_pair(self.wave, self.p, self.q0,
                                  self.mode, self.alt)
                out.append(scale(self.g, z))
                self.p = u16(self.p + self.dp)
                self.q0 = (self.q0 + self.dq) & 0x1FFFF
        return out


def dq_for(wave: int, mode: int, dp: int) -> int:
    """The per-wave/per-mode secondary increment map, decoded from
    _calculate_osc_state's +0x10 stores and its wave/mode tails."""
    if wave == 0:
        k = {0: 256, 1: 193, 2: 384}[mode]
    elif wave == 7:
        k = {0: 254, 1: 250, 2: 508}[mode]
    else:
        k = 256 if mode == 0 else 255
    return tz(dp * k, 256)


class InsState:
    """The custom/meta-instrument playhead riding a note."""

    def __init__(self):
        self.on = False
        self.ins_id = -1
        self.pos = 0
        self.prev_pitch = 24
        self.prev_vol = 0
        self.done = False
        self.last_row = 0
        self.last_row_pitch = 24
        self.last_row_vol = 0


def ins_row_of(ins: Sfx, pos: int) -> tuple[int, bool]:
    """The instrument's row for playhead pos, honoring its loop rules.
    Returns (row, done)."""
    d = ins.speed
    n = tz(pos, d)
    if ins.loop_start < ins.loop_end:
        span = ins.loop_end
        if n >= span:
            body = ins.loop_end - ins.loop_start
            n = ins.loop_start + (n - ins.loop_start) % body
        return n, False
    length = (min(ins.loop_start, 32) if ins.loop_start > 0
              and ins.loop_end == 0 else 32)
    if n >= length:
        return 0, True
    return n, False


def calc_tick_state(sfx: Sfx, pos: int, prev: OscState,
                    ins: InsState = None, get_sfx=None) -> OscState:
    """_calculate_osc_state: basic instruments, dispatching custom notes
    to the meta-instrument path."""
    d = sfx.speed
    n = tz(pos, d)
    t = pos - n * d
    if n >= 32:
        st = prev.copy()
        st.g = 0
        return st
    note = sfx.notes[n]
    if note["custom"] and get_sfx is not None:
        return calc_tick_custom(sfx, get_sfx, pos, prev, ins, note, n, t)
    if ins is not None:
        ins.on = False
    p0 = note["pitch"] << 16
    a0 = note["vol"] << 8
    fx = note["fx"]

    p_1616, a = p0, a0
    if fx == 1:                               # slide
        if n == 0:
            ps, a_s = 24 << 16, a0
        else:
            pn = sfx.notes[n - 1]
            ps, a_s = pn["pitch"] << 16, pn["vol"] << 8
        p_1616 = tz((d - t) * ps + t * p0, d)
        a = tz((d - t) * a_s + t * a0, d)
    elif fx == 4:                             # fade in
        a = tz(a0 * t, d)
    elif fx == 5:                             # fade out
        a = tz(a0 * (d - t), d)
    elif fx in (6, 7):                        # arpeggios
        q_div = (2 if fx == 6 else 4) if sfx.speed <= 8 else (4 if fx == 6 else 8)
        sel = (n & 0x1C) + (tz(pos, q_div) % 4)
        p_1616 = sfx.notes[sel]["pitch"] << 16

    dp = dx_clamped(p_1616)
    if fx == 2:                               # vibrato, post-clamp
        m = [128, 129, 130, 129, 128, 127, 126, 127][(pos >> 1) & 7]
        dp = (dx_clamped(p0) * m) >> 7
    elif fx == 3:                             # drop, post-clamp
        dp = tz(dx_clamped(p0) * (d - t), d)

    st = OscState()
    st.wave = note["wave"]
    st.dp = dp
    st.mode = sfx.detune
    st.alt = bool(sfx.buzz)
    st.dq = dq_for(st.wave, st.mode, dp)
    # Detuned voices of waves 0..5 get the binary's amplitude boost
    # a = tz(5a/4) before G (the +0x1c rewrite at 0x1000f1bbb).
    if st.mode > 0 and st.wave <= 5:
        a = tz(5 * a, 4)
    st.g = tz(3 * a, 2)
    if st.g == 0:
        # A zero-amplitude tick is not an inaudible running oscillator:
        # the next nonzero tick starts from the canonical phase again
        # (exposed by speed-2 fade-in rows, whose audible ticks the binary
        # exports byte-identically).
        st.p, st.q0 = 0, 0
    else:
        st.p, st.q0 = prev.p, prev.q0         # phase continues across ticks
    return st


def pclamp(v: int) -> int:
    return max(0, min(63, v))


def effect_pitch_amp(notes, n: int, t: int, d: int, pos: int,
                     prev_pitch: int, prev_vol: int) -> tuple[int, int, int]:
    """The pitch/amplitude half of the effect dispatch for a note list in
    its own timing context. Returns (p_1616, a, fx)."""
    note = notes[n]
    p0 = note["pitch"] << 16
    a0 = note["vol"] << 8
    fx = note["fx"]
    p_1616, a = p0, a0
    if fx == 1:
        ps = (24 << 16) if n == 0 else (prev_pitch << 16)
        a_s = a0 if n == 0 else (prev_vol << 8)
        p_1616 = tz((d - t) * ps + t * p0, d)
        a = tz((d - t) * a_s + t * a0, d)
    elif fx == 4:
        a = tz(a0 * t, d)
    elif fx == 5:
        a = tz(a0 * (d - t), d)
    elif fx in (6, 7):
        q_div = (2 if fx == 6 else 4) if d <= 8 else (4 if fx == 6 else 8)
        sel = (n & 0x1C) + (tz(pos, q_div) % 4)
        p_1616 = notes[sel]["pitch"] << 16
    return p_1616, a, fx


def calc_tick_custom(sfx: Sfx, get_sfx, pos: int, prev: OscState,
                     ins: InsState, note, n: int, t: int) -> OscState:
    """The meta-instrument path: the note plays through instrument SFX
    note.wave, whose row supplies waveform/pitch-offset/volume-multiplier
    and whose filter byte joins the note's."""
    d = sfx.speed
    iid = note["wave"] & 0x07
    irec = get_sfx(iid)

    # Retrigger at note-row boundaries: new instrument, pitch change,
    # silent previous row, or effect 3 (which means retrigger, not drop).
    if t == 0:
        row_prev_pitch = 24 if n == 0 else sfx.notes[n - 1]["pitch"]
        row_prev_vol = 0 if n == 0 else sfx.notes[n - 1]["vol"]
        if (not ins.on or ins.ins_id != iid
                or note["pitch"] != row_prev_pitch
                or row_prev_vol == 0
                or note["fx"] == 3):
            ins.on = True
            ins.ins_id = iid
            ins.pos = 0
            ins.prev_pitch = 24
            ins.prev_vol = 0
            ins.done = False
        else:
            ins.pos += 1
    else:
        ins.pos += 1

    wavetable = bool(irec.loop_start & 0x80)
    st = OscState()

    if wavetable:
        st.wave = 8
        st.table = [b - 256 if b >= 128 else b for b in irec.raw]
        # Octave-down when the speed byte's bit 0 is CLEAR: the
        # waveform-instrument export (speed 1) runs at full rate, twice the
        # halved guess - measured, not assumed.
        st.bass = not (irec.speed & 1)
        np_1616, a, _ = effect_pitch_amp(
            sfx.notes, n, t, d, pos,
            24 if n == 0 else sfx.notes[n - 1]["pitch"],
            0 if n == 0 else sfx.notes[n - 1]["vol"])
        dp = dx_clamped(np_1616)
        if st.bass:
            dp = tz(dp, 2)
        st.dp = dp
        st.dq = dp
        st.mode = sfx.detune
        st.alt = bool(sfx.buzz)
        st.g = tz(3 * a, 2)
    else:
        irow, ins.done = ins_row_of(irec, ins.pos)
        if irow != ins.last_row:
            ins.prev_pitch = ins.last_row_pitch
            ins.prev_vol = ins.last_row_vol
            ins.last_row = irow
        inote = irec.notes[irow]
        ins.last_row_pitch = inote["pitch"]
        ins.last_row_vol = inote["vol"]
        d_ins = irec.speed
        t_ins = ins.pos - tz(ins.pos, d_ins) * d_ins

        nfx = 0 if note["fx"] == 3 else note["fx"]
        use_ins_fx = (nfx == 0 and inote["fx"] != 0)

        if use_ins_fx:
            ip, ia, ifx = effect_pitch_amp(
                irec.notes, irow, t_ins, d_ins, ins.pos,
                ins.prev_pitch, ins.prev_vol)
            comp_pitch = pclamp(note["pitch"] + (ip >> 16) - 24)
            p_1616 = (comp_pitch << 16) | (ip & 0xFFFF)
            a = tz((note["vol"] << 8) * (ia >> 8), 7)
            fx_ctx = (ifx, d_ins, t_ins, ins.pos)
        else:
            np_1616, na, nfx2 = effect_pitch_amp(
                sfx.notes, n, t, d, pos,
                24 if n == 0 else sfx.notes[n - 1]["pitch"],
                0 if n == 0 else sfx.notes[n - 1]["vol"])
            comp_pitch = pclamp((np_1616 >> 16) + inote["pitch"] - 24)
            p_1616 = (comp_pitch << 16) | (np_1616 & 0xFFFF)
            a = tz(na * inote["vol"], 7)
            fx_ctx = (nfx2, d, t, pos)

        if ins.done:
            a = 0

        st.wave = inote["wave"]
        dp = dx_clamped(p_1616)
        fx, dd, tt, ppos = fx_ctx
        if fx == 2:
            m = [128, 129, 130, 129, 128, 127, 126, 127][(ppos >> 1) & 7]
            dp = (dx_clamped((p_1616 >> 16) << 16) * m) >> 7
        elif fx == 3:
            dp = tz(dx_clamped(p_1616) * (dd - tt), dd)
        st.dp = dp
        st.mode = sfx.detune
        st.alt = bool(sfx.buzz)
        st.dq = dq_for(st.wave, st.mode, dp)
        if st.mode > 0 and st.wave <= 5:
            a = tz(5 * a, 4)
        st.g = tz(3 * a, 2)

    if st.g == 0:
        st.p, st.q0 = 0, 0
    else:
        st.p, st.q0 = prev.p, prev.q0
    return st


def render_voice(sfx: Sfx, ticks: int, get_sfx=None) -> list[int]:
    """_mix_sfx_tick: per tick, render new state, blend 64 samples of old.

    The eight-slot history comb the RE notes describe for waveform 7 (and
    reverb) is deliberately ABSENT: the wave-7-phaser export matches the
    comb-free stream byte-for-byte across all 5,696 samples, so the ring is
    empty throughout the export path - the comb belongs to live playback,
    a stage the export renderer (and therefore every oracle reference)
    never runs. This is a documented model boundary alongside the shared
    RNG; the phaser's export-visible identity is the triangle core with
    its 254/256-detuned secondary."""
    out: list[int] = []
    cur = OscState()                          # silent pre-trigger state
    ins = InsState()
    for pos in range(ticks):
        old = cur.copy()
        cur = calc_tick_state(sfx, pos, cur, ins, get_sfx)
        new_samples = cur.render(TICK_SAMPLES)
        old_samples = old.render(BLEND_SAMPLES)
        for i in range(BLEND_SAMPLES):
            new_samples[i] = tz(
                i * new_samples[i] + (BLEND_SAMPLES - i) * old_samples[i],
                BLEND_SAMPLES)
        out.extend(new_samples)
    return out


# --- mixing and output ---------------------------------------------------

SOFT_TH = 24576


def soft_add(a: int, b: int) -> int:
    s = a + b
    if s >= SOFT_TH:
        return SOFT_TH + tz((s - SOFT_TH) * 52429, 1 << 18)
    if s <= -SOFT_TH:
        return -SOFT_TH - tz((-SOFT_TH - s) * 52429, 1 << 18)
    return s


def mix_tree(leaves: list[list[int]]) -> list[int]:
    """The fixed 8-leaf pairwise reduction:
    (0+1)(2+3)(4+5)(6+7) -> (01+23)(45+67) -> final."""
    n = max(len(l) for l in leaves if l) if any(leaves) else 0
    out = []
    for i in range(n):
        v = [l[i] if l and i < len(l) else 0 for l in leaves]
        l1 = [soft_add(v[0], v[1]), soft_add(v[2], v[3]),
              soft_add(v[4], v[5]), soft_add(v[6], v[7])]
        l2 = [soft_add(l1[0], l1[1]), soft_add(l1[2], l1[3])]
        out.append(soft_add(l2[0], l2[1]))
    return out


def mix_single(voice: list[int]) -> list[int]:
    """A lone voice through the tree: three soft_adds against zeros."""
    return [soft_add(soft_add(soft_add(v, 0), 0), 0) for v in voice]


def render_case(bin_path: Path, ticks: int) -> list[int]:
    """Music-launch pattern 0: each enabled channel c plays its SFX on
    music slot 4+c, i.e. tree leaves 4..7."""
    blob = bin_path.read_bytes()
    leaves: list[list[int]] = [[] for _ in range(8)]
    for c in range(4):
        b = blob[c]
        if not (b & 0x40):
            leaves[4 + c] = render_voice(
                load_sfx(bin_path, b & 0x3F), ticks,
                get_sfx=lambda i: load_sfx(bin_path, i))
    return mix_tree(leaves)


def write_wav(path: Path, samples: list[int]) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        clipped = [max(-32768, min(32767, s)) for s in samples]
        w.writeframes(struct.pack(f"<{len(clipped)}h", *clipped))


def read_wav(path: Path) -> list[int]:
    with wave.open(str(path), "rb") as w:
        n = w.getnframes()
        return list(struct.unpack(f"<{n}h", w.readframes(n)))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["render", "compare"])
    ap.add_argument("bin", type=Path)
    ap.add_argument("reference", type=Path, nargs="?")
    ap.add_argument("--ticks", type=int, required=True)
    ap.add_argument("--sfx", type=int, default=0)
    ap.add_argument("--out", type=Path)
    args = ap.parse_args()

    sfx = load_sfx(args.bin, args.sfx)
    samples = mix_single(render_voice(sfx, args.ticks))

    if args.mode == "render":
        write_wav(args.out or Path("model.wav"), samples)
        print(f"wrote {len(samples)} samples")
        return 0

    ref = read_wav(args.reference)
    n = min(len(ref), len(samples))
    diffs = [(i, samples[i], ref[i]) for i in range(n) if samples[i] != ref[i]]
    print(f"model {len(samples)} vs reference {len(ref)} samples; "
          f"{len(diffs)} differ")
    if diffs:
        for i, m, r in diffs[:8]:
            print(f"  [{i:5d}] model {m:7d}  ref {r:7d}  (tick {i // 183}, "
                  f"sample {i % 183})")
        return 1
    print("BYTE-EXACT")
    return 0


if __name__ == "__main__":
    sys.exit(main())
