#!/usr/bin/env python3
"""Derive the MINIMAL exact buffer geometry for the adopted PSG.

`psg_hw_forms.py` priced the arithmetic; this prices the storage. The
adopted reverb comb is the only stage that needs a RAM rather than
registers, and a literal transcription of the binary's structure (eight
183-sample slots per voice, sized by the comb's 17-bit feedback fixpoint)
does not fit the iCE40's 15-EBR ceiling. Every claim below is either

  PROVED    - byte-equality over the whole 51-case deterministic oracle
              matrix, or exhaustive equality over a stated domain, or an
              arithmetic identity checked over its full reachable range
  MEASURED  - an observation about the corpus, evidence and not a bound
  note      - a derivation from the recorded reverse engineering

so a geometry that comes out PROVED can be built with no fidelity risk.
The reference model is tools/psg_binary_model.py (51/51 byte-exact against
the adopt-exact PICO-8 exports); this tool drives it through
`make_history`, so the geometry study and the reference path share one
implementation of the ring.

Sections:
  layout - what the binary allocates per voice, and which of it a replica
           must actually keep; the entry width the layout implies
  entry  - the entry width: what the corpus can discriminate, what it
           cannot, and a legal cart image that makes the difference
           observable; the comb's narrower accumulator form
  depth  - the ring as a flat sample buffer: 732 entries, not 1,464, and
           which slots of the binary's eight are never read
  count  - how many rings a replica needs, from the concurrently
           advancing playback states
  corpus - what the shipped carts actually ask for
  fit    - block cost per target against the measured EBR census, and the
           verdict per build
  synth  - the block-cost claims re-measured through yosys (slow)

Usage: psg_buffers.py [section ...] [--cases DIR] [--reference DIR]
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import psg_binary_model as M

FAILURES: list[str] = []
CASES = Path("build/psg_oracle/cases")
REFS = Path("build/psg_oracle/adopt-exact/reference")
WITNESS = Path("build/psg_buffers")

TICK = M.TICK_SAMPLES                       # 183 samples per tick
LOOKBACK = {1: 2 * TICK, 2: 4 * TICK}       # 366 / 732 samples

# iCE40 EBR: one 4 Kbit block, four legal aspect ratios. Gowin GW2AR-18C
# BSRAM: 18 Kbit. Two cost models per target: the ASPECT figure (blocks
# needed if one ratio has to cover depth x width) and the FLOOR
# (ceil(bits/capacity)). Yosys reaches the floor rather than the aspect
# figure - `memory_libmap` packs several narrow entries into one wide word
# and lane-selects with the high address bits, paying LUT4s for the mux.
# The in-tree witness is the shipping 732 x 10-bit revbuf: 7,320 bits in
# TWO blocks, which no single aspect ratio can do. The `synth` section
# measures the floor claim per candidate geometry.
ICE40 = ("iCE40 EBR", 4096, [(256, 16), (512, 8), (1024, 4), (2048, 2)])
GOWIN = ("Gowin BSRAM", 18432, [(512, 36), (1024, 18), (2048, 9),
                                (4096, 4), (8192, 2), (16384, 1)])


def report(name: str, ok: bool, detail: str) -> None:
    tag = "PROVED " if ok else "REFUTED"
    print(f"  {tag} {name:32s} {detail}")
    if not ok:
        FAILURES.append(name)


def measured(name: str, detail: str) -> None:
    print(f"  MEASURED {name:32s} {detail}")


def note(detail: str) -> None:
    print(f"  note     {detail}")


def blocks(depth: int, width: int, target) -> int:
    """Block cost: the bit floor, which is what yosys achieves."""
    return -(-depth * width // target[1])


def aspect(depth: int, width: int, target) -> tuple[int, tuple[int, int]]:
    """Blocks under one aspect ratio, and the winning ratio."""
    best = None
    for d, w in target[2]:
        n = -(-depth // d) * -(-width // w)
        if best is None or n < best[0]:
            best = (n, (d, w))
    return best


# --- ring geometries under test ---------------------------------------------

def clamp_store(bits: int | None, mode: str):
    """The storage element: what a `bits`-wide RAM cell gives back."""
    if bits is None:
        return lambda v: v
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if mode == "sat":
        return lambda v: lo if v < lo else hi if v > hi else v
    span = 1 << bits
    return lambda v: ((v - lo) % span) + lo          # two's-complement wrap


class Ring(M.SlotRing):
    """The binary's eight-slot ring with a storage width, and the choice
    of whether that width is also the voice's sample-buffer width (the
    binary's two buffers are both int16, so `ring_only=False` is the
    faithful pairing; `True` isolates the RAM question)."""

    def __init__(self, bits=None, mode="wrap", ring_only=True):
        super().__init__()
        self.cell = clamp_store(bits, mode)
        self.ring_only = ring_only

    def push(self, samples):
        out = [self.cell(v) for v in samples]
        self.slots[self.rpos] = out
        self.rpos = (self.rpos + 1) & 7
        return samples if self.ring_only else out


class FlatRing(Ring):
    """One flat circular sample buffer per voice instead of eight
    tick-quantized slots: the candidate the depth section proves."""

    def __init__(self, depth, bits=None, mode="wrap", ring_only=True):
        super().__init__(bits, mode, ring_only)
        self.buf = [0] * depth
        self.n = 0

    def tap(self, level):
        d, base = len(self.buf), self.n - LOOKBACK[level]
        return [self.buf[(base + i) % d] for i in range(TICK)]

    def push(self, samples):
        out = [self.cell(v) for v in samples]
        d = len(self.buf)
        for i, v in enumerate(out):
            self.buf[(self.n + i) % d] = v
        self.n += TICK
        return samples if self.ring_only else out


class LazyRing(Ring):
    """Writes only while the comb is enabled - the geometry a shared ring
    POOL would have (a voice with reverb off owns no storage)."""

    def __init__(self):
        super().__init__()
        self.armed = False

    def tap(self, level):
        self.armed = True
        return super().tap(level)

    def push(self, samples):
        if not self.armed:
            return samples
        self.armed = False
        return super().push(samples)


# --- the oracle matrix, driven under a geometry ------------------------------

_matrix: list[dict] | None = None
_refs: dict[str, list[int]] = {}


def matrix() -> list[dict]:
    global _matrix
    if _matrix is None:
        cases = json.loads((CASES / "manifest.json").read_text())["cases"]
        _matrix = [c for c in cases
                   if not c["long"] and not c["stochastic"]]
    return _matrix


def reference(name: str) -> list[int]:
    if name not in _refs:
        _refs[name] = M.read_wav(REFS / f"{name}.wav")
    return _refs[name]


def sweep(factory) -> tuple[int, list[str]]:
    """Render every deterministic case with `factory` as the ring and
    byte-compare against the captured exports. Returns (n, failures)."""
    prev, M.make_history = M.make_history, factory
    bad = []
    try:
        for case in matrix():
            model = M.render_case(CASES / case["audio"],
                                  case["expected_ticks"])
            _, mism, _, _ = M.aligned_diff(model, reference(case["name"]),
                                           case["alignment_max_shift"])
            if mism:
                bad.append(f"{case['name']}({mism})")
    finally:
        M.make_history = prev
    return len(matrix()), bad


def sweep_report(name: str, factory, want_exact: bool, detail: str) -> None:
    n, bad = sweep(factory)
    ok = (not bad) if want_exact else bool(bad)
    got = (f"{n - len(bad)}/{n} byte-exact"
           + (f"; breaks {', '.join(bad[:4])}" if bad else ""))
    report(name, ok, f"{detail} - {got}")


# --- witness: a legal cart the reference corpus does not reach ---------------

def witness_image(reverb: int = 2, vol: int = 7, speed: int = 4) -> bytes:
    """A 4,608-byte audio image whose voice sits at constant maximum
    amplitude: a wavetable instrument (SFX 0) whose 64 table bytes are all
    -128, played by SFX 1 at full volume with the reverb digit set.

    A DC wavetable makes the comb's delayed tap reinforce the current
    sample at EVERY lag, so the feedback runs to its fixpoint y -> 2x
    instead of averaging out against a periodic waveform. Nothing here is
    exotic cart data - it is 4,608 bytes any cartridge may contain."""
    img = bytearray(4608)
    img[0:4] = bytes([1, 0x40, 0xC0, 0x40])   # ch0 plays SFX 1, then stop
    ins = 256                                 # SFX 0: the wavetable
    img[ins:ins + 64] = bytes([0x80] * 64)    # every table entry -128
    img[ins + 64] = 0                         # no filters on the instrument
    img[ins + 65] = 1                         # speed 1: bit 0 set, no bass
    img[ins + 66] = 0x80                      # loop_start bit 7: wavetable
    trk = 256 + 68                            # SFX 1: the note track
    for r in range(32):
        img[trk + 2 * r] = 24                                   # pitch 24
        img[trk + 2 * r + 1] = 0x80 | (vol << 1)                # custom, vol
    img[trk + 64] = (3 * reverb) << 3         # base-3 reverb digit
    img[trk + 65] = speed
    return bytes(img)


def witness_path(**kw) -> tuple[Path, int]:
    """Write the witness image and return (path, ticks)."""
    WITNESS.mkdir(parents=True, exist_ok=True)
    img = witness_image(**kw)
    p = WITNESS / "reverb-fixpoint.bin"
    p.write_bytes(img)
    return p, img[256 + 68 + 65] * 32


def render_witness(factory):
    prev, M.make_history = M.make_history, factory
    try:
        p, ticks = witness_path()
        return M.render_case(p, ticks)
    finally:
        M.make_history = prev


def observe(factory, images) -> dict[str, tuple[int, int]]:
    """Probe-recorded ranges while rendering `images` under a geometry."""
    ranges: dict[str, list[int]] = {}

    def rec(site, v):
        r = ranges.get(site)
        if r is None:
            ranges[site] = [v, v]
        elif v < r[0]:
            r[0] = v
        elif v > r[1]:
            r[1] = v

    prev_probe, M.probe = M.probe, rec
    prev, M.make_history = M.make_history, factory
    try:
        for path, ticks in images:
            M.render_case(path, ticks)
    finally:
        M.probe, M.make_history = prev_probe, prev
    return {k: (v[0], v[1]) for k, v in ranges.items()}


def reads_ring(image: Path) -> bool:
    """True when pattern 0 launches any SFX with a reverb digit - i.e. the
    case reads the ring back rather than only filling it."""
    blob = image.read_bytes()
    for c in range(4):
        b = blob[c]
        if b & 0x40:
            continue
        s = b & 0x3F
        if M.Sfx(blob[256 + 68 * s:256 + 68 * (s + 1)]).reverb:
            return True
    return False


def dbfs(delta: int) -> float:
    """A sample-domain error relative to int16 full scale."""
    return 20 * math.log10(delta / 32768) if delta else float("-inf")


def bits_for(lo: int, hi: int) -> int:
    w = 1
    while lo < -(1 << (w - 1)) or hi > (1 << (w - 1)) - 1:
        w += 1
    return w


# --- layout: what the binary allocates, and what a replica must keep --------

def sec_layout() -> None:
    print("layout: the binary's per-voice storage, and the required subset")
    fields = [
        ("+0x0000", 0x2000, "int16 PCM work buffer (4,096 samples)",
         "not required - the replica streams samples, never buffers a block"),
        ("+0x2040", 366, "current 183-sample tick buffer",
         "not required as memory - one 16-bit sample register"),
        ("+0x21ae", 8 * 366, "eight-slot phaser/history ring",
         "REQUIRED - read back 366/732 samples later by the comb"),
        ("+0x2d30", 0x160, "oscillator and current-note state",
         "registers/state words, already in the RTL's slot records"),
    ]
    for off, size, what, verdict in fields:
        print(f"  {off:8s} {size:6,d} B  {what}")
        print(f"           {'':6s}     -> {verdict}")
    note("the record stride is 0x3700 B x 16 records = 220 KB; the RE notes' "
         "compatibility table already rules the 16-record array unobservable")

    # The two independent statements in the notes - the layout table's byte
    # count and the phaser section's "183 signed 16-bit samples per slot" -
    # agree on the entry width only at 16 bits. Same for the tick buffer.
    report("layout.entry_width_16",
           8 * TICK * 2 == 8 * 366 and TICK * 2 == 366,
           f"8 slots x {TICK} samples x 2 B = {8 * TICK * 2:,d} B = the "
           "recorded 8 x 366 B: entries are int16")
    note("so the comb's 17-bit feedback fixpoint (psg_hw_forms bound) is the "
         "ACCUMULATOR width, not the storage width - the binary stores the "
         "comb's result in an int16 cell and reads that cell back")


# --- entry: the storage width ------------------------------------------------

def sec_entry() -> None:
    print("entry: the ring cell's width")

    # The comb in its stored form. 4x + 2h = 2(2x + h), and tz halves that
    # exactly, so the hardware accumulator is 2x + h - one bit narrower
    # than the transcribed 4x + 2h.
    x_max, h_max = 26_880, 1 << 15
    a_max = 2 * x_max + h_max
    ok = all(M.tz(2 * a, 4) == M.tz(a, 2) for a in range(-a_max, a_max + 1))
    report("entry.comb_acc_narrower", ok,
           f"tz((4x+2h)/4) == tz((2x+h)/2) exhaustively over every "
           f"reachable accumulator value |2x+h| <= {a_max:,d} "
           f"({bits_for(-a_max, a_max)} bits, was "
           f"{bits_for(-2 * a_max, 2 * a_max)})")

    # A pre-halved cell would save a bit; it does not survive the rounding.
    bad = [(x, h) for x in range(-8, 9) for h in range(-8, 9)
           if M.tz(2 * x + h, 2) != x + M.tz(h, 2)]
    report("entry.lsb_load_bearing", bool(bad),
           f"storing tz(h/2) instead of h is NOT equivalent - "
           f"{len(bad)} counterexamples in |x|,|h| <= 8, first "
           f"x={bad[0][0]} h={bad[0][1]}: "
           f"{M.tz(2 * bad[0][0] + bad[0][1], 2)} vs "
           f"{bad[0][0] + M.tz(bad[0][1], 2)}; 16 bits is the floor")

    obs = observe(M.SlotRing, [(CASES / c["audio"], c["expected_ticks"])
                               for c in matrix()])
    lo, hi = obs["ring.entry"]
    measured("entry.corpus_range",
             f"ring entries written over all {len(matrix())} deterministic "
             f"cases: [{lo:,d}, {hi:,d}] = {bits_for(lo, hi)} bits")
    revcases = [c for c in matrix() if reads_ring(CASES / c["audio"])]
    ro = observe(M.SlotRing, [(CASES / c["audio"], c["expected_ticks"])
                              for c in revcases])
    rlo, rhi = ro["ring.entry"]
    measured("entry.readback_range",
             f"of those, the {len(revcases)} cases that READ the ring "
             f"({', '.join(c['name'] for c in revcases)}) stay in "
             f"[{rlo:,d}, {rhi:,d}] = {bits_for(rlo, rhi)} bits")

    # What width does the 51-case gate actually discriminate? Only the cases
    # that read the ring back can notice, so the gate is blind well below
    # the width the content itself needs.
    floor = None
    for w in range(bits_for(lo, hi), 3, -1):
        _, bad_cases = sweep(lambda w=w: Ring(w, "wrap"))
        if bad_cases:
            floor = w + 1
            break
    measured("entry.corpus_floor",
             f"the corpus stays {len(matrix())}/{len(matrix())} byte-exact "
             f"down to a {floor}-bit ring cell and breaks at {floor - 1} - "
             "the deterministic gate CANNOT size this RAM. Sizing it from "
             "the gate would ship a cell too narrow for the corpus's own "
             f"{bits_for(lo, hi)}-bit content, silent until a cart reads "
             "back a loud voice")
    sweep_report("entry.16b_exact", lambda: Ring(16, "wrap"),
                 True, "the binary's int16 cell")
    sweep_report("entry.17b_exact", lambda: Ring(17, "wrap"),
                 True, "a 17-bit cell (the fixpoint width)")
    note("both pass, so the corpus does not discriminate 16 from 17 either. "
         "The binary's layout does, and 16 is a quarter cheaper per ring "
         "(3 iCE40 blocks against 4) - the wider cell buys nothing but a "
         "different wrong answer at the fixpoint")

    # The witness: a legal image that drives the comb to its fixpoint, where
    # the cell width IS observable.
    p, ticks = witness_path()
    obs_w = observe(M.SlotRing, [(p, ticks)])
    wlo, whi = obs_w["ring.entry"]
    xlo, xhi = obs_w["wave.z.w8"]
    measured("entry.witness_range",
             f"{p}: DC wavetable at full volume through reverb-2 drives "
             f"ring entries to [{wlo:,d}, {whi:,d}] = {bits_for(wlo, whi)} "
             f"bits (z pinned at {xlo:,d}), overflowing int16 by "
             f"{max(-wlo - (1 << 15), whi - ((1 << 15) - 1)):,d}")
    free = render_witness(M.SlotRing)
    variants = [("wrap", lambda: Ring(16, "wrap", ring_only=False)),
                ("sat", lambda: Ring(16, "sat", ring_only=False))]
    for label, factory in variants:
        got = render_witness(factory)
        diff = [i for i in range(len(free)) if free[i] != got[i]]
        worst = max(abs(free[i] - got[i]) for i in diff)
        measured(f"entry.witness_{label}",
                 f"int16 {label} store diverges from the unbounded model on "
                 f"{len(diff):,d}/{len(free):,d} samples, first at "
                 f"{diff[0]} (tick {diff[0] // TICK}), max output delta "
                 f"{worst:,d} counts ({dbfs(worst):.0f} dBFS)")
    note("saturation is the survivable failure and wrapping is not: the "
         "soft_add compressor absorbs a saturated leaf almost entirely, "
         "while a wrapped leaf flips sign. The overflow SEMANTIC (wrap, "
         "saturate, or a clamp upstream) is the one storage question no "
         "captured reference answers - every deterministic case stays a "
         "factor of two below it. Capturing this witness from PICO-8 closes "
         "it; until then the RTL saturates and the model records the gap")


# --- depth: the ring as a flat sample buffer --------------------------------

def sec_depth() -> None:
    print("depth: slots versus a flat sample buffer")

    # Which slot ages does the comb ever read? Writes advance rpos by one
    # per tick, so slot (rpos + k) & 7 was last written 8 - k ticks ago.
    ages = {lvl: set() for lvl in LOOKBACK}
    for rpos in range(8):
        for lvl in LOOKBACK:
            tap = (rpos + 4 + 2 * (lvl == 1)) & 7
            ages[lvl].add((rpos - tap) % 8)
    read = sorted(set().union(*ages.values()))
    never = [a for a in range(8) if a > max(read)]
    report("depth.dead_slots", read == [2, 4] and never == [5, 6, 7],
           f"reads land only at ages {read} ticks (levels "
           f"{ {k: sorted(v) for k, v in ages.items()} }); ages "
           f"{never} are written and NEVER read - {len(never)}/8 of the "
           "transcribed ring is dead")
    note(f"retention is therefore ages 0..{max(read)} = {max(read) + 1} "
         f"slots = {(max(read) + 1) * TICK:,d} samples; as a flat buffer the "
         f"requirement collapses to the lookback itself, "
         f"{LOOKBACK[2]:,d} samples")

    sweep_report("depth.flat_732_exact", lambda: FlatRing(LOOKBACK[2]),
                 True, f"flat {LOOKBACK[2]}-entry circular buffer replaces "
                       f"8 x {TICK} slots")
    sweep_report("depth.flat_731_breaks", lambda: FlatRing(LOOKBACK[2] - 1),
                 False, f"{LOOKBACK[2] - 1} entries")
    sweep_report("depth.flat_366_breaks", lambda: FlatRing(LOOKBACK[1]),
                 False, f"{LOOKBACK[1]} entries (level-1 lookback only)")
    n, bad = sweep(lambda: FlatRing(LOOKBACK[1]))
    note(f"the {LOOKBACK[1]}-entry buffer breaks exactly the level-2 cases "
         f"({', '.join(b.split('(')[0] for b in bad)}) and nothing else, so "
         f"a build restricted to reverb level 1 is exact at half the depth")
    note(f"at exactly {LOOKBACK[2]} entries the level-2 read address equals "
         f"the write address (n-732 == n mod 732), so the RTL must read "
         f"before write on that port; {LOOKBACK[2] + 1} entries removes the "
         "collision, and block quantization gives 768 anyway (see fit)")
    saved = 8 * TICK - LOOKBACK[2]
    report("depth.halves_the_ring", saved == LOOKBACK[2],
           f"{8 * TICK:,d} -> {LOOKBACK[2]:,d} entries per voice: exactly "
           f"2x, {saved:,d} entries of pure waste retired")


# --- count: how many rings ---------------------------------------------------

def sec_count() -> None:
    print("count: how many rings a replica needs")
    note("RE notes, normal-mode callback rule: 16 records render, but "
         "classic PSG playback uses 8 - a foreground and a music state per "
         "logical channel; slots 8..15 serve the generic sound player")
    note("'the hidden music state continues to advance while replaced' and "
         "rendering advances 'oscillator phase, SFX row/effect position, "
         "PHASER HISTORY' - a muted music voice keeps filling its ring, and "
         "reads it back when the foreground SFX ends, so audibility does "
         "NOT bound the ring count")
    note("the four-audible invariant (psg_hw_forms bound.mix_never_clips) "
         "bounds the mix bus, not storage: 8 concurrently advancing states "
         "means 8 rings for unconditional exactness")

    # Does any reference discriminate a pool sized by reverb-carrying
    # voices - i.e. is the write really unconditional?
    sweep_report("count.pool_undiscriminated", LazyRing, True,
                 "writing only while the comb is enabled")
    note("so no captured case distinguishes 'every voice maintains history' "
         "from 'only reverb-carrying voices do'. Under the second reading a "
         "shared pool of K rings is exact whenever at most K voices carry a "
         "reverb digit at once - K=1 for every cart in the corpus (see "
         "corpus). The discriminating capture is a cart that enables reverb "
         "mid-SFX: unconditional writes give it 732 samples of pre-armed "
         "echo, a pool gives it silence")


# --- corpus: what the shipped carts ask for ---------------------------------

def sec_corpus() -> None:
    print("corpus: filters in the shipped cart audio")
    for name in ("celeste_audio.bin", "nemo_audio.bin"):
        p = Path("build") / name
        if not p.exists():
            note(f"{p} absent (make psg-wav CART=... builds it) - skipped")
            continue
        blob = p.read_bytes()
        used = rev = damp = det = other = 0
        for s in range(64):
            sfx = M.Sfx(blob[256 + 68 * s:256 + 68 * (s + 1)])
            if any(n["vol"] for n in sfx.notes):
                used += 1
            rev += sfx.reverb > 0
            damp += sfx.dampen > 0
            det += sfx.detune > 0
            other += sfx.noiz or sfx.buzz
        worst = 0
        for pat in range(64):
            live = [blob[4 * pat + c] for c in range(4)]
            worst = max(worst, sum(
                1 for b in live if not b & 0x40
                and M.Sfx(blob[256 + 68 * (b & 0x3F):
                               256 + 68 * ((b & 0x3F) + 1)]).reverb))
        measured(f"corpus.{name.split('_')[0]}",
                 f"{used} sounding SFX; reverb {rev}, dampen {damp}, "
                 f"detune {det}, noiz/buzz {other}; max simultaneous "
                 f"reverb channels over all 64 patterns: {worst}")
    note("the shipped corpus enables no filter at all, so REVERB=0 on the "
         "iCE40 target costs zero fidelity on the content that ships - the "
         "ring buys capability for other carts, not parity for ours")


# --- fit: block-quantized cost ----------------------------------------------

CANDIDATES = [
    (f"transcribed 8x{TICK} slots x 17b", 8 * TICK, 17, 1),
    (f"transcribed 8x{TICK} slots x 16b", 8 * TICK, 16, 1),
    ("flat 732 x 17b", LOOKBACK[2], 17, 1),
    ("flat 732 x 16b   <- MINIMAL EXACT", LOOKBACK[2], 16, 1),
    ("flat 733 x 16b (no r/w collision)", LOOKBACK[2] + 1, 16, 1),
    ("flat 366 x 16b (level-1 only)", LOOKBACK[1], 16, 1),
    ("minimal x 4 voices", LOOKBACK[2], 16, 4),
    ("minimal x 8 voices", LOOKBACK[2], 16, 8),
]


def ebr_census() -> dict[str, int] | None:
    """The measured per-array EBR census of the shipping target_psg, from
    the netlist yosys already produced (make synth-psg)."""
    p = Path("build/targets/psg.json")
    if not p.exists():
        return None
    net = json.loads(p.read_text())
    out: dict[str, int] = {}
    for mod in net["modules"].values():
        for name, cell in mod.get("cells", {}).items():
            if "RAM40" in cell["type"]:
                arr = name.split(".")
                out[arr[-3] if len(arr) >= 3 else name] = \
                    out.get(arr[-3] if len(arr) >= 3 else name, 0) + 1
    return out


def sec_fit() -> None:
    print("fit: block cost of every candidate geometry, per target")
    print(f"  {'geometry':36s} {'bits':>8s} {'iCE40':>7s} {'aspect':>7s} "
          f"{'Gowin':>6s}")
    for label, depth, width, n in CANDIDATES:
        b = depth * width * n
        ni = n * blocks(depth, width, ICE40)
        na, ra = aspect(depth, width, ICE40)
        ng = n * blocks(depth, width, GOWIN)
        print(f"  {label:36s} {b:8,d} {ni:7d} {n * na:3d} @{ra[0]}x{ra[1]:<2d}"
              f" {ng:6d}")
    note("the iCE40 column is the bit floor (yosys lane-packs to it, "
         "measured by the synth section); the aspect column is what a single "
         "aspect ratio would cost. The floor is why the 16-bit cell wins: "
         f"{blocks(LOOKBACK[2], 16, ICE40)} blocks against "
         f"{blocks(LOOKBACK[2], 17, ICE40)} for 17 bits, and "
         f"{blocks(8 * TICK, 17, ICE40)} for the transcribed ring - the "
         "minimal geometry is 2.3x cheaper than the literal reading of the "
         "binary")

    print()
    census = ebr_census()
    if census is None:
        note("build/targets/psg.json absent (make synth-psg) - skipping the "
             "measured census")
        return
    print("  measured EBR census, target_psg (REVERB=1, seed-1 netlist):")
    for name, n in sorted(census.items(), key=lambda kv: -kv[1]):
        print(f"    {name:16s} {n:2d}")
    total = sum(census.values())
    freed = census.get("wrom", 0) + census.get("revbuf", 0)
    base = total - freed
    ceiling = 15
    ring = blocks(LOOKBACK[2], 16, ICE40)
    print(f"    {'total':16s} {total:2d}  (the {ceiling}-block ceiling "
          "recorded in reduce-psg-ice40-area: the PPU already owns sixteen "
          "of the HX8K's 32)")
    note(f"adoption retires wrom (waves compute) and the shared post-mix "
         f"revbuf (design 7 relocates the filters): {freed} blocks back, "
         f"{base} committed")
    note("aram's 9 blocks are not reducible: it is CPU-visible memory behind "
         "$00/$01/$02 that must read back what the cart wrote, byte for byte, "
         "whether or not the synthesizer reads every bit (the filter byte's "
         "bit 0 never reaches the pipeline, and no digit combination uses the "
         "top of the byte - dead bits in a store that still has to keep them)")
    for rings in (0, 1, 2, 4, 8):
        cost = base + rings * ring
        verdict = ("fits" if cost <= ceiling else
                   "over budget" if cost <= 32 else "over the HX8K device")
        exact = {0: "no reverb at all (today's iCE40 build)",
                 1: "byte-exact while at most ONE voice carries reverb",
                 2: "two concurrent reverb voices",
                 4: "the four music slots",
                 8: "unconditional: all 8 advancing states"}[rings]
        print(f"    {rings} ring(s): {cost:2d} blocks - {verdict:20s} {exact}")
    note(f"the headline: ONE exact ring costs {base + ring} blocks - the same "
         f"{ceiling} the shipping build already spends - and it REPLACES the "
         "10-bit shared post-mix approximation. Exactness for a single "
         "reverb-carrying voice is free on iCE40; the second voice is not")
    g_tables = (blocks(4608, 8, GOWIN) + blocks(256, 16, GOWIN)
                + blocks(256, 16, GOWIN) + blocks(8 * 32, 16, GOWIN))
    g_rings = 8 * blocks(LOOKBACK[2], 16, GOWIN)
    print(f"  Gowin GW2AR-18C (46 BSRAM, floor estimate - that flow is "
          f"separate): aram+crom+recip+state_m ~{g_tables}, 8 exact rings "
          f"{g_rings} = {g_tables + g_rings} of 46. Unconditional exactness "
          "fits the Tang Nano 20K, which is the board the console actually "
          "ships on (docs/build-targets.md: the soc does not place on the "
          "HX8K at all)")


# --- synth: measure the floor claim -----------------------------------------

def sec_synth() -> None:
    print("synth: measured iCE40 block cost per geometry (needs yosys)")
    import shutil
    import subprocess
    if not shutil.which("yosys"):
        note("yosys not on PATH - skipped")
        return
    WITNESS.mkdir(parents=True, exist_ok=True)
    src = WITNESS / "geometry.sv"
    for label, depth, width, n in CANDIDATES:
        arrays = "".join(f"  logic signed [{width - 1}:0] m{i}[0:{depth - 1}];"
                         f"\n  logic signed [{width - 1}:0] q{i};\n"
                         for i in range(n))
        body = "".join(f"    q{i} <= m{i}[ra % {depth}];\n"
                       f"    if (we[{i}]) m{i}[wa % {depth}] <= din;\n"
                       for i in range(n))
        src.write_text(
            f"module geometry(input clk, input [15:0] wa, ra,\n"
            f"    input signed [{width - 1}:0] din, input [{n - 1}:0] we,\n"
            f"    output signed [{width - 1}:0] dout);\n{arrays}"
            f"  always_ff @(posedge clk) begin\n{body}  end\n"
            f"  assign dout = {' ^ '.join(f'q{i}' for i in range(n))};\n"
            f"endmodule\n")
        out = subprocess.run(
            ["yosys", "-p", f"read_verilog -sv {src}; "
             "synth_ice40 -top geometry -json /dev/null"],
            capture_output=True, text=True).stdout
        ebr = [int(m) for m in re.findall(r"^\s+(\d+)\s+SB_RAM40_4K$",
                                         out, re.M)]
        lut = [int(m) for m in re.findall(r"^\s+(\d+)\s+SB_LUT4$", out, re.M)]
        want = n * blocks(depth, width, ICE40)
        got = ebr[-1] if ebr else 0
        report(f"synth.{depth}x{width}x{n}", got <= want,
               f"{label}: {got} EBR (floor {want}), "
               f"{lut[-1] if lut else 0} LUT4 for the lane muxing")


SECTIONS = {"layout": sec_layout, "entry": sec_entry, "depth": sec_depth,
            "count": sec_count, "corpus": sec_corpus, "fit": sec_fit,
            "synth": sec_synth}


def main() -> int:
    global CASES, REFS
    ap = argparse.ArgumentParser()
    ap.add_argument("sections", nargs="*", default=[])
    ap.add_argument("--cases", type=Path, default=CASES)
    ap.add_argument("--reference", dest="refs", type=Path, default=REFS)
    args = ap.parse_args()
    CASES, REFS = args.cases, args.refs

    for name in (args.sections or list(SECTIONS)):
        SECTIONS[name]()
        print()
    if FAILURES:
        print(f"REFUTED: {', '.join(FAILURES)}")
        return 1
    print("every geometry claim holds on its stated domain")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
