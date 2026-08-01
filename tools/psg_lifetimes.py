#!/usr/bin/env python3
"""Register live ranges in the sample walk, and which pairs could share one.

Lifetime retirement has been the campaign's most reliable small lever and its
least predictable one - the SAME transformation measured -38 placed cells once
and +24 another time - so the two things worth automating are the part that
must be exactly right (the live ranges) and the part that must not be guessed
(which pairs are even candidates). This derives both from the RTL.

  make psg-lifetimes

A register is retirable INTO another when their live ranges are disjoint, the
host is at least as wide, and neither is exported through a port. The report
ranks candidates by the flops they would save. It does NOT predict whether a
candidate pays: fanout entanglement decides that, and only synthesis knows.
Measure every one on PLACED cells and the flop count - never on the
pre-mapping census, which has been wrong about this in both directions.

What this does not model, and so what a candidate still has to be read for:
  - the fold engine, which runs across the visit boundary into the next slot;
  - the preview lowering (REALTIME_PREVIEW), removed at elaboration here;
  - reads by another module through a port - those are marked EXPORTED and
    excluded, because psg_wave sees them combinationally on every cycle;
  - a register whose value must SURVIVE the visit (record-loaded state), which
    is live from its load to its store and is marked STREAMED.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gen_psg_ctrl as C                                    # noqa: E402

WALK = os.path.join(ROOT, "rtl", "psg_walk.sv")


def phase_map(src):
    """CAP_* name -> absolute pph, from the RTL's one-hot indices and the
    generator's offsets. Two sources that must agree; if they ever stop
    agreeing this raises rather than reporting a fiction."""
    m = re.search(r"localparam int\s+(CAP_W[^;]+);", src, re.S)
    if not m:
        raise SystemExit("psg_walk: cannot find the CAP_* one-hot indices")
    bits = {k: int(v) for k, v in re.findall(r"(CAP_W\d+)\s*=\s*(\d+)",
                                             m.group(1))}
    by_bit = {b: off for off, b in C.CAPS.items()}
    out = {}
    for name, bit in bits.items():
        if bit not in by_bit:
            raise SystemExit(f"{name} = bit {bit} has no offset in "
                             f"gen_psg_ctrl.CAPS")
        out[name] = C.PWORK + by_bit[bit]
    for extra, ph in (("PNZ_OLD", None), ("PNZ_LIVE", None)):
        mm = re.search(rf"localparam int\s+{extra}\s*=\s*(\d+)", src)
        if mm:
            out[extra] = int(mm.group(1))
    return out


def hardware_block(src):
    """The non-preview arm of the walk's always_ff - the last one in the file,
    from its one-hot step decode to the end of the module."""
    i = src.rindex("always_ff @(posedge clk) begin")
    j = src.index("cap[CAP_W0]", i)
    return src[j:src.rindex("endmodule")]


def strip_preview(text):
    """Model elaboration: REALTIME_PREVIEW is 0 for the hardware target, so
    its arms are not there. Without this, fold_launch's preview half makes
    `sa_hold` look like a live hardware register to retire things into - and
    it does not exist."""
    text = re.sub(r"REALTIME_PREVIEW\s*\?[^:]*:", "", text)
    out, i = [], 0
    while True:
        m = re.compile(r"if \(REALTIME_PREVIEW\)\s*begin").search(text, i)
        if not m:
            out.append(text[i:])
            break
        out.append(text[i:m.start()])
        depth, j = 1, m.end()
        while depth and j < len(text):
            nxt = re.compile(r"\b(begin|end)\b").search(text, j)
            if not nxt:
                break
            depth += 1 if nxt.group(1) == "begin" else -1
            j = nxt.end()
        rest = text[j:]
        em = re.match(r"\s*else\b", rest)
        i = j + em.end() if em else j          # keep the else arm, drop the if
    return "".join(out)


def inline_tasks(src, body):
    """Splice task bodies into the arms that call them.

    stage_leaf, fold_launch and noise_filt_step do most of the walk's register
    writing, and a live range that misses them is not conservative - it is
    wrong in the direction that proposes an unsafe retirement.
    """
    tasks = dict(re.findall(r"task\s+(?:automatic\s+)?(\w+)\s*\([^;]*\);"
                            r"(.*?)endtask", src, re.S))
    for name, tbody in tasks.items():
        body = re.sub(rf"\b{name}\s*\([^;]*\);", strip_preview(tbody), body)
    return strip_preview(body)


def arms(block, phases):
    """(label, phase, body) for each phase-keyed arm in the hardware block."""
    out = []
    pat = re.compile(r"^(\s+)(?:cap\[(CAP_W\d+)\]|if \(pph == 7'\((PNZ_\w+|PLAST)\)\))"
                     r"\s*:?\s*(begin)?", re.M)
    marks = [(m.start(), m.group(2) or m.group(3), len(m.group(1)))
             for m in pat.finditer(block)]
    for idx, (pos, label, _) in enumerate(marks):
        end = marks[idx + 1][0] if idx + 1 < len(marks) else len(block)
        ph = phases.get(label)
        if label == "PLAST":
            ph = C.PLAST
        if ph is not None:
            out.append((label, ph, block[pos:end]))
    return out


def streamed_ranges(src):
    """Record-streamed state is live from its LOAD phase to its STORE phase.

    This is the part that makes the difference between a useful report and a
    dangerous one: the action arms are not where these registers are written
    and read. The walk streams a slot's record in over pph 1..PLOSC+4 and
    writes it back over PSTOR..PSTOR+PLOSC-1, plus two late dampen cycles, and
    a register retired into one of these windows would corrupt saved state.
    """
    ff = src[src.rindex("always_ff @(posedge clk) begin"):]
    # the record streaming lives BEFORE the preview/hardware split; the
    # preview branch has its own pph 0 arm and would otherwise mark scratch
    # registers as record state
    ff = ff[:ff.index("if (REALTIME_PREVIEW) begin")]
    load = {}
    for body, ph_expr in ((m.group(2), m.group(1)) for m in re.finditer(
            r"^\s+7'(?:d(\d+)|\(PLOSC \+ (\d+)\)):(.*?)(?=^\s+7'(?:d\d+|\(PLOSC)|^\s+default)",
            ff, re.M | re.S)):
        pass
    for m in re.finditer(r"^\s+7'd(\d+):(.*?)(?=^\s+7'd\d+:|^\s+default)",
                         ff, re.M | re.S):
        for r in re.findall(r"([a-z_]\w*)\s*(?:\[[^\]]*\])?\s*<=", m.group(2)):
            load.setdefault(r, []).append(int(m.group(1)))
    for m in re.finditer(r"^\s+7'\(PLOSC \+ (\d+)\):(.*?)(?=^\s+7'\(PLOSC|^\s+default)",
                         ff, re.M | re.S):
        for r in re.findall(r"([a-z_]\w*)\s*(?:\[[^\]]*\])?\s*<=", m.group(2)):
            load.setdefault(r, []).append(C.PLOSC + int(m.group(1)))
    # the oscillator write-back: word k is read at PSTOR + k
    store = {}
    sw = src[src.index("always_comb begin", src.index("wire [3:0] s_stw")):]
    sw = sw[:sw.index("\n  end")]
    for m in re.finditer(r"4'd(\d+):\s*sosc_wd\s*=\s*([^;]+);", sw):
        for r in re.findall(r"\b([a-z_]\w*)\b", m.group(2)):
            store.setdefault(r, []).append(C.PSTOR + int(m.group(1)))
    # The low word is written on PLAST-1; word 14 (including s_lp's sign)
    # shares PLAST with slot close and fold launch.
    store.setdefault("s_lp", []).extend((C.PLAST - 1, C.PLAST))
    for r in ("old_mode_r", "s_brown"):
        store.setdefault(r, []).append(C.PLAST)
    return load, store


def combinational_closure(src, seeds):
    """Every net whose value depends on one of `seeds`, transitively."""
    defs = {}
    for m in re.finditer(r"^\s*(?:wire|assign)\s+(?:signed\s*)?"
                         r"(?:\[[^\]]*\]\s*)?([a-zA-Z_]\w*)\s*=\s*(.*?);\s*$",
                         src, re.M | re.S):
        defs.setdefault(m.group(1), []).append(m.group(2))
    closure = set(seeds)
    for _ in range(len(defs) + 1):
        grew = False
        for name, rhs in defs.items():
            if name in closure:
                continue
            body = " ".join(rhs)
            if any(re.search(r"\b" + re.escape(s) + r"\b", body)
                   for s in closure):
                closure.add(name)
                grew = True
        if not grew:
            break
    return closure


def main():
    src = open(WALK).read()
    phases = phase_map(src)
    block = hardware_block(src)
    all_arms = [(lbl, ph, inline_tasks(src, body))
                for lbl, ph, body in arms(block, phases)]

    exported = set(re.findall(r"^\s*(?:input|output)\s+(?:logic|bit)\s*"
                              r"(?:signed\s*)?(?:\[[^\]]*\]\s*)?(\w+)",
                              src[:src.index("logic [6:0]  pph")], re.M))
    widths, regs = {}, []
    for m in re.finditer(r"^\s*logic\s+(?:signed\s+)?(?:\[(\d+):(\d+)\]\s*)?"
                         r"([a-z_]\w*(?:\s*,\s*[a-z_]\w*)*)\s*;", src, re.M):
        w = int(m.group(1)) - int(m.group(2)) + 1 if m.group(1) else 1
        for nm in (x.strip() for x in m.group(3).split(",")):
            widths[nm] = w
            regs.append(nm)

    load, store = streamed_ranges(src)
    # a macro-packed store word names the macro, not its members
    for macro, members in re.findall(r"`define (PSG_OSC_W\d+)\s+\{([^}]*)\}",
                                     open(os.path.join(ROOT, "rtl",
                                                       "psg_common.svh")).read(),
                                     re.S):
        if macro in store:
            for mem in re.findall(r"\b([a-z_]\w*)\b", members):
                store.setdefault(mem, []).extend(store[macro])
    live = {}
    for r in regs:
        if r in exported or r == "pph":
            continue
        wr = sorted({ph for _, ph, body in all_arms
                     if re.search(rf"\b{re.escape(r)}\b\s*(?:\[[^\]]*\])?\s*<=",
                                  body)} | set(load.get(r, [])))
        if not wr:
            continue
        clos = combinational_closure(src, {r})
        rd = sorted({ph for _, ph, body in all_arms
                     if any(re.search(r"\b" + re.escape(n) + r"\b", body)
                            for n in clos)} | set(store.get(r, [])))
        live[r] = (wr, rd, r in load or r in store)

    print(f"walk visit is {C.PLAST + 1} phases (0..{C.PLAST}); "
          f"PWORK {C.PWORK}, PSTOR {C.PSTOR}\n")
    print(f"{'register':<16}{'bits':>5}  {'writes':<22}{'reads':<24}live")
    rows = []
    for r, (wr, rd, is_streamed) in sorted(live.items()):
        lo, hi = min(wr), max(rd) if rd else max(wr)
        wraps = bool(rd) and min(rd) < lo
        rows.append((r, widths.get(r, 1), wr, rd, lo, hi,
                     wraps or is_streamed))
        mark = "  WRAPS" if wraps else ""
        note = "  STREAMED (record state - excluded)" if is_streamed else ""
        print(f"  {r:<14}{widths.get(r,1):>5}  {str(wr):<22}{str(rd):<24}"
              f"{lo}..{hi}{mark}{note}")

    print("\ncandidate pairs - guest fits inside host's dead window:")
    found = []
    for g, gw, _, _, glo, ghi, gwrap in rows:
        if gwrap:
            continue
        for h, hw, _, _, hlo, hhi, hwrap in rows:
            if h == g or hwrap or hw < gw:
                continue
            if ghi < hlo or glo > hhi:          # disjoint, no wrap either side
                margin = hlo - ghi if ghi < hlo else glo - hhi
                found.append((gw, g, h, glo, ghi, hlo, hhi, margin))
    for gw, g, h, glo, ghi, hlo, hhi, margin in sorted(found, reverse=True)[:14]:
        print(f"  retire {g:<14} ({gw:>2} flops, live {glo}..{ghi}) into "
              f"{h:<14} (live {hlo}..{hhi}), {margin} phases clear")
    if not found:
        print("  none")


if __name__ == "__main__":
    main()
