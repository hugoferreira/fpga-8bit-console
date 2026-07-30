#!/usr/bin/env python3
"""Reference model of the PICO-8 binary's integer audio pipeline.

Implements the exact integer forms recovered in
/Applications/PICO-8.app/Contents/MacOS/pico8-psg-re.md and spot-verified
against pico8.x86_64.asm (see openspec/changes/adopt-pico8-integer-audio).
The model is the gate for that change: RTL stages must match it exactly,
and the model itself must match the stored PICO-8 exports byte-for-byte
on deterministic cases (task 1.3).

Scope: every deterministic path - waves 0-5, the comb-free phaser core
(7), the wavetable voice (8), effects 0-7, the detune/buzz families, the
dampen one-pole and the reverb history comb, meta-instruments, the
per-tick 64-sample crossfade, the eight-leaf soft_add tree and the
pattern-chain music flow. Wave-6 noise is the listing's legacy walk
(pico8.x86_64.asm 0x1000f08bd..0x1000f0b14) driven by the real
_codo_random; its MECHANISM is exact but its sample sequence is only
reproducible when this model is the sole RNG consumer, so noise cases
compare statistically, never byte-exactly.

Usage:
  psg_binary_model.py render <case.bin> --ticks N --out out.wav
  psg_binary_model.py compare <case.bin> <reference.wav> --ticks N
  psg_binary_model.py sweep [--only NAME ...]

`render`/`compare` run the full music player (pattern 0 launch, the real
export path). `sweep` is the durable regression harness: it drives every
deterministic case of the generated matrix (cases/manifest.json) through
render_case and requires byte-equality against the captured reference
set, aligned by the export's constant lead-in (shift search 0..220).
"""

from __future__ import annotations

import argparse
import json
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


def probe(site: str, value: int) -> None:
    """Range-observation hook at the pipeline's load-bearing intermediates.
    tools/psg_width_report.py swaps in a recorder to derive minimal RTL
    widths; the default no-op keeps the reference path pure."""


def tz(a: int, d: int) -> int:
    """Signed integer division truncated toward zero."""
    q = abs(a) // d
    return -q if a < 0 else q


def u16(x: int) -> int:
    return x & 0xFFFF


# --- the shared RNG ----------------------------------------------------------
#
# _codo_random (x86_64 L211719), verbatim: H = rol32(H,16) + L; L += H;
# R(m) = H mod m, unsigned, R(0) = 0. ONE global stream shared by every
# consumer - which is why noise sequences depend on what every other voice
# did, and why byte-exact noise against a real cart is impossible in
# principle. Seeds are the binary's static initial values.

RNG_STATE = [0xDEADBEEF, 0x01234567]        # [H, L]


def codo_random(m: int) -> int:
    if m == 0:
        return 0
    h, low = RNG_STATE
    h = (((h << 16) | (h >> 16)) + low) & 0xFFFFFFFF
    low = (low + h) & 0xFFFFFFFF
    RNG_STATE[0], RNG_STATE[1] = h, low
    return h % m


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
    probe("pinc.blend", blended)
    recip = blended * 0x2F8DF18F
    probe("pinc.recip", recip)
    dp = recip >> 44
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
    acc = w0 * 1024 + (w1 - w0) * f
    probe("wave.lerp_acc", acc)
    return acc >> 10


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
    prod = g * z
    probe("scale.prod", prod)
    return tz(prod, 3072)


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
                 "table", "bass", "rev",
                 "nz_r", "nz_tog", "nz_pitch", "nz_amp")

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
        # Legacy-noise walk state: the accumulator (state[0x14]) and the
        # alternating-step toggle (state[0x18]), plus the two scalar
        # parameters its output stage reads - the integer pitch
        # (state[0x24], for k's denominator) and the pre-G amplitude
        # (state[0x28], the kick's scale).
        self.nz_r = 0
        self.nz_tog = 0
        self.nz_pitch = 0
        self.nz_amp = 0
        # The history selector lives in the OSCILLATOR state (RE notes:
        # "hmode = state[0x5c]"), which is why the crossfade's copied old
        # state combs at the level the previous SFX asked for - see
        # ChannelVoice.tick.
        self.rev = 0

    def copy(self) -> "OscState":
        o = OscState()
        for f in self.__slots__:
            setattr(o, f, getattr(self, f))
        return o

    def render_noise(self, n: int) -> list[int]:
        """The legacy (mode 0) noise walk, instruction-exact from
        pico8.x86_64.asm 0x1000f08bd..0x1000f0b14. Runs even at g == 0:
        a muted noise voice keeps stepping and keeps CONSUMING the shared
        RNG (the write-up says so outright), only its kick arm is dead
        because the stored amplitude is zero.

        Per sample:
          - flip the toggle; on the samples whose OLD toggle was even,
            r += R(J) - J//2 with J = max(0, dp<79 ? 60dp-2988 : 8dp+1120)
          - kick when amp != 0 and ((p+101)(p+317)) & 8191 < (dp+500)//3:
            r += tz((R(12286)-6143) * amp / 1792)
          - the OUTPUT reads r BEFORE the clamp: y = tz((r>>6)*G*k/2048),
            arithmetic shift, k = max(16, 2048//den)+48 with den = 64
            below pitch 48 and pitch+16 above; the buffer cell is int16
            and WRAPS (movw), which big kick escapes at high pitch reach
          - the clamp to +-6143 applies to the STORED accumulator only
          - the 16-bit phase advances by dp exactly as other waves
        """
        if self.mode != 0:
            raise NotImplementedError(
                "held/interpolated noise (mode != 0) is not modelled")
        d = self.dp
        j = 60 * d - 2988 if d < 79 else 8 * d + 1120
        if j < 0:
            j = 0
        half = j >> 1
        thresh = (d + 500) // 3
        den = 64 if self.nz_pitch < 48 else self.nz_pitch + 16
        k = max(16, 2048 // den) + 48
        out = []
        for _ in range(n):
            tog = self.nz_tog
            self.nz_tog = (~tog) & 1
            if not (tog & 1):
                self.nz_r += codo_random(j) - half
            if (self.nz_amp != 0
                    and ((self.p + 101) * (self.p + 317)) & 8191 < thresh):
                self.nz_r += tz((codo_random(12286) - 6143) * self.nz_amp,
                                1792)
            r_pre = self.nz_r
            self.nz_r = max(-6143, min(6143, r_pre))
            y = tz((r_pre >> 6) * self.g * k, 2048)
            out.append(((y + 0x8000) & 0xFFFF) - 0x8000)
            self.p = u16(self.p + self.dp)
        return out

    def render(self, n: int) -> list[int]:
        if self.wave == 6 and self.table is None:
            return self.render_noise(n)
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
                probe(f"wave.z.w{self.wave}", z)
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
    st.rev = sfx.reverb
    st.alt = bool(sfx.buzz)
    st.dq = dq_for(st.wave, st.mode, dp)
    # Detuned voices of waves 0..5 get the binary's amplitude boost
    # a = tz(5a/4) before G (the +0x1c rewrite at 0x1000f1bbb).
    if st.mode > 0 and st.wave <= 5:
        a = tz(5 * a, 4)
    st.g = tz(3 * a, 2)
    # The legacy walk persists like the dampen pole: its accumulator and
    # toggle survive every tick, INCLUDING muted ones (a muted noise
    # voice keeps consuming the shared RNG). The output stage's scalars
    # are this tick's: state[0x24] = integer pitch, state[0x28] = the
    # post-boost amplitude (+0x1c's value).
    st.nz_r, st.nz_tog = prev.nz_r, prev.nz_tog
    st.nz_pitch = p_1616 >> 16
    st.nz_amp = a
    probe("amp.G", st.g)
    probe("pinc.dp", st.dp)
    probe("pinc.dq", st.dq)
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
        st.rev = sfx.reverb
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
        st.rev = sfx.reverb
        st.alt = bool(sfx.buzz)
        st.dq = dq_for(st.wave, st.mode, dp)
        if st.mode > 0 and st.wave <= 5:
            a = tz(5 * a, 4)
        st.g = tz(3 * a, 2)
        st.nz_pitch = p_1616 >> 16
        st.nz_amp = a

    st.nz_r, st.nz_tog = prev.nz_r, prev.nz_tog
    probe("amp.G", st.g)
    probe("pinc.dp", st.dp)
    probe("pinc.dq", st.dq)
    if st.g == 0:
        st.p, st.q0 = 0, 0
    else:
        st.p, st.q0 = prev.p, prev.q0
    return st


# --- mixing and output ---------------------------------------------------

SOFT_TH = 24576


def soft_add(a: int, b: int) -> int:
    s = a + b
    probe("mix.sum", s)
    if s >= SOFT_TH:
        excess = (s - SOFT_TH) * 52429
        probe("mix.excess_prod", excess)
        return SOFT_TH + tz(excess, 1 << 18)
    if s <= -SOFT_TH:
        excess = (-SOFT_TH - s) * 52429
        probe("mix.excess_prod", excess)
        return -SOFT_TH - tz(excess, 1 << 18)
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


def damp_step(y: int, x: int, level: int) -> int:
    """DAMPEN: the per-sample one-pole toward the oscillator value.
    Pinned by filter-dampen-1's exact settle (0, 4031, 6046, 7054 toward
    +/-8062, stuck one unit short by truncation) and by
    filter-dampen-impulse's decay, which reaches zero - so the truncation
    applies to the whole blend tz((x + (2^d-1)y)/2^d), not to a
    difference-form step (that one stalls at |y| = 1)."""
    d = 1 << level
    acc = x + (d - 1) * y
    probe("damp.acc", acc)
    return tz(acc, d)


class SlotRing:
    """The binary's per-voice history ring, verbatim: eight slots of 183
    signed 16-bit samples at voice-record offset +0x21ae, indexed by the
    global ring position (RE notes, waveform-7 section and the
    voice-record table).

    `store` is the one hook where a replica's storage width becomes
    visible; the default is the binary's own cell. tools/psg_buffers.py
    swaps in other widths and ring geometries to derive the minimal exact
    buffer, so the geometry study and the reference path share this
    single implementation."""

    def __init__(self):
        self.slots = [[0] * TICK_SAMPLES for _ in range(8)]
        self.rpos = 0

    def store(self, v: int) -> int:
        """The binary's cell is int16 and it WRAPS. Both the ring
        (+0x21ae) and the voice's tick buffer (+0x2040) are int16, so the
        wrap is what the mixer reads too, and
        filter-reverb-fixpoint-mid/-full convict it: at the comb's
        fixpoint the export flips sign exactly where two's-complement
        truncation does, while saturation and unbounded arithmetic both
        diverge. No deterministic case below the fixpoint can tell the
        three apart - see tools/psg_buffers.py entry."""
        return ((v + 0x8000) & 0xFFFF) - 0x8000

    def tap(self, level: int) -> list[int]:
        """The tick's delayed block: two slots back (366 samples) at
        level 1, four (732) at level 2."""
        return self.slots[(self.rpos + 4 + 2 * (level == 1)) & 7]

    def push(self, samples: list[int]) -> list[int]:
        """Write the tick's final samples and return them as stored - the
        binary keeps one int16 block per voice, so whatever the store
        does is what the mixer reads too."""
        out = [self.store(v) for v in samples]
        for v in out:
            probe("ring.entry", v)
        self.slots[self.rpos] = out
        self.rpos = (self.rpos + 1) & 7
        return out


make_history = SlotRing              # tools/psg_buffers.py swaps this


class ChannelVoice:
    """One music slot: oscillator + instrument state, a dampen one-pole
    and the history ring (the reverb comb, per voice)."""

    def __init__(self):
        self.sfx: Sfx | None = None
        self.origin = 0
        self.osc = OscState()
        self.ins = InsState()
        self.damp_y = 0
        self.hist = make_history()

    def launch(self, sfx: Sfx, tick: int):
        self.sfx = sfx
        self.origin = tick
        self.ins = InsState()

    def tick(self, pos: int, get_sfx) -> list[int]:
        if self.sfx is None:
            return [0] * TICK_SAMPLES
        old = self.osc.copy()
        self.osc = calc_tick_state(self.sfx, pos - self.origin, self.osc,
                                   self.ins, get_sfx)
        cur = self.osc
        new_samples = cur.render(TICK_SAMPLES)
        old_samples = old.render(BLEND_SAMPLES)
        # REVERB: the per-voice history-ring comb, enabled by the reverb
        # digit: tap two slots back (366 samples) at level 1, four (732)
        # at level 2; y = tz((4y + 2h)/4) with the post-comb tick written
        # back (feedback: the measured 1/2, 1/4, ... train). The ring runs
        # ONLY under the reverb digit - that is what reconciles the
        # wave-7-phaser export matching the comb-free stream on all 5,696
        # samples (its case has reverb 0) with the RE notes' description
        # of the comb. The phaser's export identity stays the triangle
        # core with its 254/256 secondary. The comb runs BEFORE dampen
        # (filter-dampen-reverb: the echo arrives one-pole-smoothed, at
        # half the dampen-first amplitude).
        #
        # The comb sits INSIDE each block's render, not after the
        # crossfade, and each block combs at its OWN state's level: the
        # selector is oscillator state (`hmode = state[0x5c]`), so the
        # copied old state carries the level the PREVIOUS SFX asked for.
        # filter-reverb-onset and filter-reverb-level convict the
        # after-the-blend order - it diverges on exactly the 64 crossfade
        # samples of every lap tick, by the half tap the old continuation
        # must not receive (2.000x at the switch, decaying with the echo).
        for block, level in ((new_samples, cur.rev), (old_samples, old.rev)):
            if not level:
                continue
            tap = self.hist.tap(level)
            for i in range(len(block)):
                acc = 4 * block[i] + 2 * tap[i]
                probe("reverb.acc", acc)
                block[i] = tz(acc, 4)
        for i in range(BLEND_SAMPLES):
            acc = (i * new_samples[i]
                   + (BLEND_SAMPLES - i) * old_samples[i])
            probe("blend.acc", acc)
            new_samples[i] = tz(acc, BLEND_SAMPLES)
        if self.sfx.dampen:
            y = self.damp_y
            for i in range(TICK_SAMPLES):
                y = damp_step(y, new_samples[i], self.sfx.dampen)
                new_samples[i] = y
            self.damp_y = y
        # The ring stores the tick's FINAL samples - post-comb AND
        # post-dampen - so a combined filter's echo train re-enters the
        # comb already smoothed (filter-dampen-reverb, hand-verified at
        # -15/-46/-89 against both single-filter orderings).
        return self.hist.push(new_samples)


def pattern_ticks(bin_path: Path, pat: int) -> int:
    """The pattern's length in ticks: the left-most launched non-looping
    channel's speed times its playable rows (length-only or 32)."""
    blob = bin_path.read_bytes()
    for c in range(4):
        b = blob[4 * pat + c]
        if b & 0x40:
            continue
        sfx = load_sfx(bin_path, b & 0x3F)
        if sfx.loop_start < sfx.loop_end:
            continue                      # looping channels cannot pace
        rows = (min(sfx.loop_start, 32)
                if sfx.loop_start > 0 and sfx.loop_end == 0 else 32)
        return sfx.speed * rows
    return 32                             # all-looping fallback


def render_case(bin_path: Path, ticks: int) -> list[int]:
    """The music player: launch pattern 0's channels on slots 4..7,
    advance patterns by the song clock, follow the stop flag."""
    blob = bin_path.read_bytes()
    voices = [ChannelVoice() for _ in range(4)]
    get_sfx = lambda i: load_sfx(bin_path, i)
    out: list[int] = []
    pat = 0
    pat_start = 0
    pat_len = None
    playing = False
    for tick in range(ticks):
        if pat_len is None:
            for c in range(4):
                b = blob[4 * pat + c]
                if not (b & 0x40):
                    voices[c].launch(get_sfx(b & 0x3F), tick)
                else:
                    voices[c].sfx = None
            pat_len = pattern_ticks(bin_path, pat)
            pat_start = tick
            playing = True
        leaves = [[0] * TICK_SAMPLES] * 4 + [
            voices[c].tick(tick, get_sfx) for c in range(4)]
        out.extend(mix_tree(leaves))
        if playing and tick - pat_start + 1 >= pat_len:
            stop = bool(blob[4 * pat + 2] & 0x80)
            if stop or pat >= 63:
                playing = False
                for v in voices:
                    v.sfx = None
                pat_len = 10 ** 9        # no further pattern loads
            else:
                pat += 1
                pat_len = None
    return out


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


def first_nonzero(xs: list[int]) -> int | None:
    for i, v in enumerate(xs):
        if v:
            return i
    return None


def aligned_diff(model: list[int], ref: list[int], max_shift: int = 220):
    """Best alignment of ref[shift:] against model[0:] over shift 0..max.

    Every export carries a constant per-case lead-in (8..160 samples), so
    the onset-derived shift is tried first and the full scan only runs on a
    mismatch. Returns (shift, mismatches, overlap, first_diff_indices)."""
    cands = list(range(max_shift + 1))
    mo, ro = first_nonzero(model), first_nonzero(ref)
    if mo is not None and ro is not None and 0 <= ro - mo <= max_shift:
        cands.remove(ro - mo)
        cands.insert(0, ro - mo)
    best = None
    for s in cands:
        n = min(len(ref) - s, len(model))
        if n <= 0:
            continue
        bad = [i for i in range(n) if model[i] != ref[s + i]]
        if best is None or len(bad) < best[1]:
            best = (s, len(bad), n, bad[:8])
        if not bad:
            break
    return best


def run_sweep(cases_dir: Path, ref_dir: Path,
              only: list[str], max_shift: int) -> int:
    matrix = json.loads((cases_dir / "manifest.json").read_text())["cases"]
    failed = []
    ran = skipped = 0
    for case in matrix:
        name = case["name"]
        if only and name not in only:
            continue
        if case["long"] and not only:
            continue                          # out of the fast matrix
        if case["stochastic"]:
            skipped += 1
            print(f"{name:44s} SKIP (stochastic: shared-RNG boundary)")
            continue
        ref_path = ref_dir / f"{name}.wav"
        if not ref_path.exists():
            failed.append(name)
            ran += 1
            print(f"{name:44s} NO-REFERENCE ({ref_path})")
            continue
        model = render_case(cases_dir / case["audio"], case["expected_ticks"])
        ref = read_wav(ref_path)
        s, mism, n, first = aligned_diff(model, ref, max_shift)
        ran += 1
        if mism == 0:
            print(f"{name:44s} BYTE-EXACT  shift={s:3d} overlap={n}")
        else:
            failed.append(name)
            print(f"{name:44s} DIFF        shift={s:3d} overlap={n} "
                  f"mismatches={mism}")
            for i in first:
                print(f"    [{i:5d}] model {model[i]:7d}  ref {ref[s + i]:7d}"
                      f"  (tick {i // 183}, sample {i % 183})")
    print(f"\n{ran - len(failed)}/{ran} byte-exact, {skipped} stochastic "
          f"skipped" + (f"; FAILED: {', '.join(failed)}" if failed else ""))
    return 1 if failed else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["render", "compare", "sweep"])
    ap.add_argument("bin", type=Path, nargs="?")
    ap.add_argument("reference", type=Path, nargs="?")
    ap.add_argument("--ticks", type=int)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--max-shift", type=int, default=220)
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--cases", type=Path,
                    default=Path("build/psg_oracle/cases"),
                    help="generated case dir (manifest.json + images)")
    ap.add_argument("--reference", dest="ref_dir", type=Path,
                    default=Path("build/psg_oracle/adopt-exact/reference"),
                    help="captured PICO-8 export dir to compare against")
    args = ap.parse_args()

    if args.mode == "sweep":
        return run_sweep(args.cases, args.ref_dir, args.only, args.max_shift)

    if args.bin is None or args.ticks is None:
        ap.error(f"{args.mode} requires <case.bin> and --ticks")
    samples = render_case(args.bin, args.ticks)

    if args.mode == "render":
        write_wav(args.out or Path("model.wav"), samples)
        print(f"wrote {len(samples)} samples")
        return 0

    ref = read_wav(args.reference)
    s, mism, n, first = aligned_diff(samples, ref, args.max_shift)
    print(f"model {len(samples)} vs reference {len(ref)} samples; "
          f"shift {s}, overlap {n}, {mism} differ")
    if mism:
        for i in first:
            print(f"  [{i:5d}] model {samples[i]:7d}  ref {ref[s + i]:7d}  "
                  f"(tick {i // 183}, sample {i % 183})")
        return 1
    print("BYTE-EXACT")
    return 0


if __name__ == "__main__":
    sys.exit(main())
