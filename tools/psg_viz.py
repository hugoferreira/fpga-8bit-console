#!/usr/bin/env python3
"""Visualise the PSG's two schedules: the sample walk and the tick sequencer.

Not a trace. This renders the MACHINE - the micro-phase schedule the walk
executes every sample, and the FSM the tick sequencer runs every tick - by
reading rtl/psg_walk.sv, rtl/psg_seq.sv and tools/gen_psg_ctrl.py. Nothing is
transcribed by hand, so the picture cannot drift from the RTL the way a drawn
diagram does: if a phase moves, the chart moves with it.

  python3 tools/psg_viz.py --out build/psg_viz.html
  python3 tools/psg_viz.py --json          # the extracted model, for diffing

The walk has TWO schedules selected by the REALTIME_PREVIEW parameter, and
both are extracted: the 109-phase hardware schedule that the oracle and the
board run, and the 24-phase compact one that `make run` plays. They are
different machines, and the preview half has historically been the one nothing
looked at.
"""
import argparse
import html
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WALK_SV = os.path.join(ROOT, "rtl", "psg_walk.sv")
SEQ_SV = os.path.join(ROOT, "rtl", "psg_seq.sv")
TIMING_SV = os.path.join(ROOT, "rtl", "psg_timing.sv")


def read(path):
    with open(path) as f:
        return f.read().split("\n")


def indent_of(line):
    return len(line) - len(line.lstrip())


def strip_comment(line):
    """Drop a trailing // comment, ignoring none-of-our-code string cases."""
    i = line.find("//")
    return line if i < 0 else line[:i]


def lead_comment(lines, idx, min_indent=0):
    """The comment block immediately above `idx`, as prose.

    The RTL's per-step commentary is the actual documentation of what a phase
    or a state does, so it is lifted verbatim rather than paraphrased.
    """
    out = []
    j = idx - 1
    while j >= 0:
        s = lines[j].strip()
        if s.startswith("//"):
            out.append(s[2:].strip())
            j -= 1
        elif not s:
            break
        else:
            break
    out.reverse()
    # Drop rule-off separators like "-------".
    out = [c for c in out if set(c) - set("- =") or not c]
    return "\n".join(out).strip()


# ----------------------------------------------------------------------
# The walk's control store: import the generator rather than re-deriving it.
# ----------------------------------------------------------------------
def load_ctrl():
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import gen_psg_ctrl as g
    return g


def parse_walk_params(lines):
    """PLOSC/PWORK/PFOLD/PSTOR/PLAST for both REALTIME_PREVIEW arms."""
    params = {}
    pat = re.compile(
        r"localparam\s+int\s+(PLOSC|PWORK|PFOLD|PSTOR|PLAST)\s*=\s*"
        r"REALTIME_PREVIEW\s*\?\s*(\d+)\s*:\s*([A-Z_0-9]+)\s*;")
    for ln in lines:
        m = pat.search(ln)
        if m:
            name, prev, hw = m.group(1), int(m.group(2)), m.group(3)
            params[name] = {"preview": prev, "hw": hw}
    return params


def parse_cap_enum(lines):
    """CAP_* opcode name -> numeric value."""
    text = "\n".join(lines)
    m = re.search(r"CAP_NONE\s*=\s*0\s*,(.*?);", text, re.S)
    if not m:
        return {}
    out = {"CAP_NONE": 0}
    for name, val in re.findall(r"(CAP_[A-Z0-9_]+)\s*=\s*(\d+)", m.group(1)):
        out[name] = int(val)
    return out


def trim_trailing_comments(body):
    """Drop the comment block that introduces the NEXT arm.

    An arm's text runs to the next label, which sweeps up the commentary
    written above that label. Left in, every state's body ends with the
    documentation of its successor - and that text is already the successor's
    own `doc`, so it would appear twice and belong to neither.
    """
    out = list(body)
    while out and (not out[-1].strip() or out[-1].strip().startswith("//")):
        out.pop()
    return out


def arm_body(lines, start, end, arm_re):
    """A case arm's text: everything up to the next arm at the same indent.

    Not a `begin..end` scan. Arms like `7'd4: if (REALTIME_PREVIEW) ... else
    ...` carry no `begin`, and stopping at the first line would have hidden
    each one's hardware half - which is exactly the schedule the board runs.
    """
    ind = indent_of(lines[start])
    out = [lines[start]]
    for i in range(start + 1, end):
        ln = lines[i]
        if not ln.strip():
            out.append(ln)
            continue
        if indent_of(ln) <= ind:
            s = ln.strip()
            if arm_re.match(ln) or s.startswith("default") or \
               s.startswith("endcase"):
                break
        out.append(ln)
    return trim_trailing_comments(out)


def block_body(lines, start, open_indent):
    """Lines of a `begin ... end` (or single-statement) body starting at `start`."""
    first = lines[start]
    if "begin" not in strip_comment(first):
        return [first]
    depth = 0
    out = []
    for i in range(start, len(lines)):
        code = strip_comment(lines[i])
        out.append(lines[i])
        depth += len(re.findall(r"\bbegin\b", code))
        depth += len(re.findall(r"\bcase\b", code))
        depth -= len(re.findall(r"\bend\b(?!case)", code))
        depth -= len(re.findall(r"\bendcase\b", code))
        if depth <= 0 and i > start:
            break
    return out


def parse_cap_arms(lines):
    """Each CAP_* case arm: its body and the commentary that explains it."""
    arms = {}
    for i, ln in enumerate(lines):
        m = re.match(r"\s*(CAP_[A-Z0-9_]+):", ln)
        if not m:
            continue
        name = m.group(1)
        body = block_body(lines, i, indent_of(ln))
        arms[name] = {
            "line": i + 1,
            "doc": lead_comment(lines, i),
            "body": "\n".join(body),
            "inline": (ln.split("//", 1)[1].strip() if "//" in ln else ""),
        }
    return arms


def parse_pph_events(lines, lo, hi, label):
    """`pph == 7'(EXPR)` sites outside the capture decode.

    These are the schedule's other half: the oscillator load steps, the
    write-back sites, the reverb ring taps and the rollover. A phase chart
    that showed only the control store would be a chart of half the machine.
    """
    events = []
    for i in range(lo, min(hi, len(lines))):
        code = strip_comment(lines[i])
        for m in re.finditer(r"pph\s*==\s*7'\(([^)]*)\)", code):
            events.append({
                "expr": m.group(1).strip(),
                "line": i + 1,
                "src": lines[i].strip(),
                "doc": lead_comment(lines, i),
                "where": label,
            })
    return events


ARM_RE = re.compile(r"\s*7'(?:d(\d+)|\(([^)]*)\))\s*:")


def enclosing_variant(lines, i):
    """Which schedule a `case (pph)` block belongs to.

    The preview arms live inside `if (REALTIME_PREVIEW) begin` and the
    control-store decode inside its `else`; the two load cases sit above both
    and serve each schedule. Reading the guard rather than assuming keeps the
    two machines from being drawn as one.
    """
    ind = indent_of(lines[i])
    for k in range(i - 1, max(0, i - 200), -1):
        if not lines[k].strip() or indent_of(lines[k]) >= ind:
            continue
        s = strip_comment(lines[k]).strip()
        if re.search(r"if \(REALTIME_PREVIEW\)\s*begin", s):
            return "preview"
        if re.search(r"if \(!REALTIME_PREVIEW\)\s*begin", s):
            return "hw"
        ind = indent_of(lines[k])
    return "both"


def arm_variant(body):
    """Whether an arm's body applies to one schedule or both."""
    has_p = re.search(r"if \(REALTIME_PREVIEW\)", body)
    has_h = re.search(r"if \(!REALTIME_PREVIEW\)", body)
    if has_h and not has_p:
        return "hw"
    if has_p and not has_h:
        return "preview" if not re.search(r"\belse\b", body) else "both"
    return "both"


def parse_pph_cases(lines):
    """Every `case (pph)` block: the load steps and the preview schedule.

    The control store covers only the hardware work phases. The oscillator
    record load, the parameter load and the whole preview schedule are plain
    `case (pph)` arms, and a phase chart without them would show a machine
    that spends its first fourteen phases doing nothing.
    """
    blocks = []
    for i, ln in enumerate(lines):
        if not re.match(r"\s*case \(pph\)\s*$", ln):
            continue
        variant = enclosing_variant(lines, i)
        arms = []
        depth = 1
        j = i + 1
        while j < len(lines) and depth > 0:
            code = strip_comment(lines[j])
            depth += len(re.findall(r"\bcase\b", code))
            depth -= len(re.findall(r"\bendcase\b", code))
            if depth == 0:
                break
            m = ARM_RE.match(lines[j])
            if m and depth == 1:
                key = m.group(1) if m.group(1) else m.group(2).strip()
                body = "\n".join(arm_body(lines, j, len(lines), ARM_RE))
                arms.append({
                    "key": key,
                    "line": j + 1,
                    "doc": lead_comment(lines, j),
                    "body": body,
                    "variant": arm_variant(body),
                })
            j += 1
        if arms:
            blocks.append({
                "line": i + 1,
                "variant": variant,
                "doc": lead_comment(lines, i),
                "arms": arms,
            })
    return blocks


def resolve_pph(key, params):
    """`7'd4` / `7'(PWORK + 3)` -> a concrete phase number for one schedule."""
    expr = key.strip()
    if re.fullmatch(r"\d+", expr):
        return int(expr)
    try:
        return int(eval(expr, {"__builtins__": {}}, dict(params)))
    except Exception:
        return None


MUL_ITERS = {0: 8, 1: 10, 2: 12}       # psg_mulsvc: mul_start_mode -> m_cnt

# ----------------------------------------------------------------------
# Per-arm dependency audit (non-wavetable profile), done by reading the RTL.
#
# A flow-insensitive taint pass was tried first and rejected: CAP_W26 writes
# `smp_b <= wt_z` (product-derived) but ONLY under `if (s_snd_wt)`, and a pass
# that cannot see the guard marks smp_b - and therefore z_new_c and
# z_old_sel - as product-derived on every path. That single blind spot turns
# two independent chains into one false serial chain, which is the whole
# question this audit exists to answer.
#
# `after` is the arm whose product this one consumes; None means its operands
# come from outside the multiply service entirely.
MUL_DEPS = {
    "CAP_W4": {"after": None, "a": "z_new_c", "b": "g_live",
         "why": "z_new_c = smp_a + smp_b, both written from z_eval (the wave "
                "cone) at CAP_W1/W3/W4; g_live comes from s_eff_a in the "
                "record. Neither is a product — this is a chain head."},
    "CAP_W17": {"after": "CAP_W4", "a": "m_res12[26:10]", "b": "341",
         "why": "reads the service output directly: arm 1's product, hi limb."},
    "CAP_W28": {"after": "CAP_W4", "a": "gz_s1_r", "b": "171",
         "why": "gz_s1_r was captured from m_res12 at CAP_W17 (the same phase "
                "arm 3 launches), so this is arm 1's product too — a SIBLING "
                "of arm 3, not its successor."},
    "CAP_W39": {"after": None, "a": "z_old_sel", "b": "s_old_G",
         "why": "z_old_sel = z_old_c = smp_b, holding the old-state wave "
                "sample accumulated at CAP_W4/W5 from z_eval; s_old_G is a "
                "record word. CAP_W26's product-derived write to smp_b is "
                "guarded by s_snd_wt and does not apply here. Independent of "
                "arms 1/3/5 — a second chain head."},
    "CAP_W52": {"after": "CAP_W39", "a": "m_res12[26:10]", "b": "341",
         "why": "arm 6's product, hi limb, read straight off the service."},
    "CAP_W63": {"after": "CAP_W39", "a": "gz_s1_r", "b": "171",
         "why": "gz_s1_r captured from m_res12 at CAP_W52 — arm 6's product. "
                "Sibling of arm 9."},
    "CAP_W75": {"after": "both", "a": "blend_diff", "b": "bl_cnt[5:0]",
         "why": "blend_diff = cmb_new - cmb_old, and those descend from mx_new "
                "(the new chain) and mx_old (the old chain). Joins both."},
}


def product_consumers(lines, cap_arms):
    """Which capture steps read a multiply result, directly or through a wire.

    `CAP_W74` never names m_res - it reads `gz_old_scaled`, which is a wire
    over `m_res_wide`. Scanning for the port alone therefore misses real
    consumers and makes a tight schedule look slack, so the search runs over
    the combinational closure of the three result ports instead.
    """
    txt = "\n".join(lines)
    defs = {}
    for m in re.finditer(r"^\s*(?:wire|assign)\s+(?:signed\s*)?"
                         r"(?:\[[^\]]*\]\s*)?([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.*?);\s*$",
                         txt, re.M | re.S):
        defs.setdefault(m.group(1), []).append(m.group(2))
    closure = {"m_res", "m_res_wide", "m_res12"}
    for _ in range(len(defs) + 1):
        grew = False
        for name, rhs in defs.items():
            if name in closure:
                continue
            body = " ".join(rhs)
            if any(re.search(r"\b" + re.escape(s) + r"\b", body) for s in closure):
                closure.add(name)
                grew = True
        if not grew:
            break
    out = set()
    for name, a in cap_arms.items():
        if any(re.search(r"\b" + re.escape(s) + r"\b", a["body"]) for s in closure):
            out.add(name)
    return out


def signal_widths(lines):
    """Declared widths of the walk's own signals, for operand sizing."""
    w = {}
    for ln in lines:
        # `logic [9:0] wt_pf, wt_qf;` declares BOTH at that width - taking only
        # the first name silently loses the second and makes its operand
        # unmeasurable.
        m = re.match(r"\s*(?:logic|wire|reg)\s+(?:signed\s+)?"
                     r"\[\s*(\d+)\s*:\s*(\d+)\s*\]\s*(.+)", ln)
        if m:
            width = int(m.group(1)) - int(m.group(2)) + 1
            for nm in re.findall(r"([a-zA-Z_][a-zA-Z0-9_]*)\s*(?:\[[^\]]*\])?\s*(?:[,;=]|$)",
                                 m.group(3).split("=")[0]):
                w.setdefault(nm, width)
        else:
            m = re.match(r"\s*(?:logic|wire|reg)\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*[;,=]", ln)
            if m:
                w.setdefault(m.group(1), 1)
    return w


def operand_width(expr, widths):
    """How many bits the multiplier operand B actually needs.

    A constant is exact and therefore provable. A signal is only its DECLARED
    width, which bounds but does not establish the range - so the two are
    reported as different kinds of claim rather than pooled into one number.
    """
    e = expr.strip().rstrip(";")
    m = re.fullmatch(r"\d*'d(\d+)", e)
    if m:
        return int(m.group(1)).bit_length(), "constant", int(m.group(1))
    if re.fullmatch(r"\{.*\}", e):                 # concatenation
        total, known = 0, True
        for part in re.split(r",(?![^{]*\})", e[1:-1]):
            part = part.strip()
            mm = re.fullmatch(r"(\d+)'b0+", part) or re.fullmatch(r"(\d+)'d0", part)
            if mm:
                continue                           # zero padding adds no bits
            mm = re.fullmatch(r"([a-zA-Z_][a-zA-Z0-9_]*)\[\s*(\d+)\s*:\s*(\d+)\s*\]", part)
            if mm:
                total += int(mm.group(2)) - int(mm.group(3)) + 1
                continue
            mm = re.fullmatch(r"([a-zA-Z_][a-zA-Z0-9_]*)", part)
            if mm and mm.group(1) in widths:
                total += widths[mm.group(1)]
                continue
            known = False
        return (total, "signal", None) if known else (None, "unknown", None)
    # `12'(g_live)` truncates a 13-bit signal to 12: the cast bounds the
    # operand, so the smaller of the two is what reaches the multiplier.
    m = re.fullmatch(r"(\d+)'\(([a-zA-Z_][a-zA-Z0-9_]*)\)", e)
    if m:
        cast = int(m.group(1))
        sig = widths.get(m.group(2))
        return (min(cast, sig) if sig else cast), "signal", None
    if e in widths:
        return widths[e], "signal", None
    return None, "unknown", None


def parse_mul_arms(lines):
    """Each multiply arm's guard and the iteration count(s) it launches.

    psg_mulsvc loads m_cnt with 8, 10 or 12 by mode and decrements once per
    clock, so a request issued in phase p leaves m_busy high through
    p+iters and the product is readable in p+iters+1. That is the whole
    latency model, and psg_walk.sv states it independently for the preview
    path: "launch at PWORK+2, product not ready until 23" - 8 iterations
    plus one.
    """
    txt = "\n".join(lines)
    # The request mux was keyed by a dedicated MUL_SEL field until the arm
    # selection was folded onto CAP_SEL (control-word bits [8:5] are now
    # spare). Find the `case` that actually drives wmul_start rather than
    # assuming either shape - a tool whose whole claim is that it tracks the
    # RTL must not break when the RTL moves.
    s = None
    for key in ("case (ctrl_cap)", "case (ctrl_mul)"):
        for m in re.finditer(re.escape(key), txt):
            blk = txt[m.start():]
            blk = blk[:blk.index("endcase")]
            if "wmul_start" in blk:
                s = blk
                break
        if s:
            break
    if s is None:
        return {}
    label = r"(?:CAP_[A-Z0-9_]+|4'd\d+)"
    arms = {}
    for blk in re.finditer(rf"((?:{label}\s*,?\s*)+):(.*?)(?=\n\s+(?:{label}\s*[,:]|default))",
                           s, re.S):
        ids = re.findall(r"CAP_[A-Z0-9_]+", blk.group(1)) or \
              [int(x) for x in re.findall(r"4'd(\d+)", blk.group(1))]
        body = blk.group(2)
        head = strip_comment(body.split("\n")[0]).strip()
        cond = ""
        if head.startswith("if"):
            mm = re.match(r"if\s*\((.*?)\)\s*begin", head)
            if mm:
                cond = re.sub(r"\s+", " ", mm.group(1)).strip()
        # Mode per branch. The default assignment at the top of the mux is
        # 2'd0, so an arm that never writes wmul_mode launches an 8-iteration
        # product rather than none.
        branches = []
        for bm in re.finditer(r"if\s*\((s_snd_wt|!s_snd_wt)\)(.*?)"
                              r"(?=\belse\b|$)", body, re.S):
            md = re.findall(r"wmul_mode\s*=\s*2'd(\d+)", bm.group(2))
            if md:
                branches.append((bm.group(1), int(md[0])))
        modes = [int(x) for x in re.findall(r"wmul_mode\s*=\s*2'd(\d+)", body)]
        bs = [b.strip() for b in re.findall(r"wmul_b\s*=\s*(.*?);", body, re.S)]
        as_ = [a.strip() for a in re.findall(r"wmul_a\s*=\s*(.*?);", body, re.S)]
        for i in ids:
            arms[i] = {"cond": cond,
                       "modes": modes or [0],
                       "branches": branches,
                       "b_exprs": bs,
                       "a_exprs": as_}
    return arms


# The guard forms this tool understands. An arm whose guard is not on this
# list is treated as ALWAYS firing, which overstates the busy window and so
# understates slack - the safe direction for a tool that must not invent an
# opportunity.
PROFILES = [
    {"key": "nowt", "label": "non-wavetable voice, blending",
     "true": ["!s_snd_wt", "bl_cnt != 7'd64"]},
    {"key": "nowt_nb", "label": "non-wavetable voice, not blending",
     "true": ["!s_snd_wt"]},
    {"key": "wt", "label": "wavetable voice, blending",
     "true": ["s_snd_wt", "bl_cnt != 7'd64"]},
    {"key": "wt_nb", "label": "wavetable voice, not blending",
     "true": ["s_snd_wt"]},
]
KNOWN_GUARDS = {"", "s_snd_wt", "!s_snd_wt", "bl_cnt != 7'd64"}


def mul_timeline(phases, mul_arms):
    """Per phase, which profiles have the multiply service iterating.

    This is the measurement that separates a forced latency shadow from
    genuine slack: if the service is provably busy, the phase cannot be
    reclaimed on that path; if it is provably idle, it can.
    """
    unknown = set()
    for p in phases:
        p["mul_busy"] = []
        p["mul_launch"] = []
    for p in phases:
        arm = mul_arms.get(p["mul"])
        if not p["mul"] or not arm:
            continue
        if arm["cond"] not in KNOWN_GUARDS:
            unknown.add(arm["cond"])
        for prof in PROFILES:
            fires = (arm["cond"] in ("", *prof["true"])
                     or arm["cond"] not in KNOWN_GUARDS)
            if not fires:
                continue
            # Pick the branch matching this profile; when the arm's mode is
            # branch-dependent and nothing matches, take the LONGEST, which
            # can only make the busy window larger.
            iters = None
            for cond, mode in arm["branches"]:
                if cond in prof["true"]:
                    iters = MUL_ITERS[mode]
            if iters is None:
                iters = max(MUL_ITERS[m] for m in arm["modes"])
            p["mul_launch"].append({"profile": prof["key"], "iters": iters})
            for k in range(p["pph"] + 1, min(p["pph"] + iters + 1, len(phases))):
                phases[k]["mul_busy"].append(prof["key"])
    return unknown


def describe_arm(arm):
    """A short label for a product launch, from its own operands.

    The generator used to carry a comment naming each MUL_SEL arm; folding the
    selection onto CAP_SEL retired that list, so the description now comes
    from the multiplicands themselves.
    """
    if not arm:
        return ""
    a = (arm.get("a_exprs") or [""])[0]
    b = (arm.get("b_exprs") or [""])[0]
    clean = lambda e: re.sub(r"\s+", " ", re.sub(r"\d+'\(|\{8'b0, |\}|\)$", "",
                                                 e)).strip(" ,")
    return f"{clean(a)} × {clean(b)}" if a and b else ""


def extract_walk():
    lines = read(WALK_SV)
    g = load_ctrl()
    raw_params = parse_walk_params(lines)
    caps = parse_cap_enum(lines)
    cap_by_val = {v: k for k, v in caps.items()}
    arms = parse_cap_arms(lines)
    blocks = parse_pph_cases(lines)

    words = g.build()
    # The generator's names for the multiply arms, so the chart can label a
    # product request with what it computes rather than an opcode number.
    mul_doc = {}
    for ln in read(os.path.join(ROOT, "tools", "gen_psg_ctrl.py")):
        for m in re.finditer(r"(\d+)\s+W(\d+)\s+\(([^)]*)\)", ln):
            mul_doc[int(m.group(1))] = f"W{m.group(2)}: {m.group(3)}"

    params = {
        "hw": {"PLOSC": g.PLOSC, "PWORK": g.PWORK, "PFOLD": g.PFOLD,
               "PSTOR": g.PSTOR, "PLAST": g.PLAST},
        "preview": {k: v["preview"] for k, v in raw_params.items()},
    }
    # The RTL's hardware arm names a constant; the generator holds its value.
    # If those ever disagree the chart is drawing a schedule nothing runs.
    for k, v in raw_params.items():
        want = params["hw"].get(k)
        if v["hw"] not in ("PSG_SOSC",) and want is not None:
            try:
                if int(v["hw"]) != want:
                    print(f"warning: {k} is {v['hw']} in psg_walk.sv but "
                          f"{want} in gen_psg_ctrl.py", file=sys.stderr)
            except ValueError:
                pass

    events = parse_pph_events(lines, 0, len(lines), "walk")

    mul_arms = parse_mul_arms(lines)
    consumers = product_consumers(lines, arms)

    schedules = {}
    for variant in ("hw", "preview"):
        pm = params[variant]
        n = pm["PLAST"] + 1
        phases = [{"pph": p, "off": p - pm["PWORK"], "load": [], "sched": [],
                   "events": [], "cap": None, "mul": 0, "mul_doc": "",
                   "flags": [], "word": None} for p in range(n)]

        # The control store drives only the hardware schedule's work phases.
        if variant == "hw":
            for p in range(n):
                w = words[p] if p < len(words) else 0
                cap_v, mul_v = w & 0x1F, (w >> 5) & 0xF
                name = cap_by_val.get(cap_v, "CAP_NONE")
                ph = phases[p]
                ph["word"] = w
                # A phase launches a product if its capture opcode appears in
                # the request mux (current encoding), or if the legacy MUL_SEL
                # field is non-zero (older control words).
                ph["mul"] = (name if name in mul_arms
                             else (mul_v if mul_v else None))
                ph["mul_doc"] = mul_doc.get(mul_v, "") or (
                    describe_arm(mul_arms.get(ph["mul"])) if ph["mul"] else "")
                if name != "CAP_NONE":
                    ph["cap"] = name
                    ph["sched"].append({"kind": "cap", "label": name,
                                        "detail": arms.get(name, {})})
                for bit, flag in ((9, "ISS_SEC"), (10, "ISS_OLDMAIN"),
                                  (11, "ISS_OLDSEC"), (12, "DQ_OLD"),
                                  (13, "SYN_A"), (14, "SYN_B")):
                    if w & (1 << bit):
                        ph["flags"].append(flag)

        for blk in blocks:
            if blk["variant"] not in ("both", variant):
                continue
            for arm in blk["arms"]:
                if arm["variant"] not in ("both", variant):
                    continue
                p = resolve_pph(arm["key"], pm)
                if p is None or not (0 <= p < n):
                    continue
                lane = "load" if blk["variant"] == "both" else "sched"
                phases[p][lane].append({
                    "kind": "arm", "key": arm["key"], "line": arm["line"],
                    "doc": arm["doc"], "body": arm["body"],
                })

        for e in events:
            p = resolve_pph(e["expr"], pm)
            if p is not None and 0 <= p < n:
                phases[p]["events"].append(e)

        schedules[variant] = {"params": pm, "phases": phases,
                              "n": n}

    unknown_guards = set()
    for s in schedules.values():
        unknown_guards |= mul_timeline(s["phases"], mul_arms)
        for p in s["phases"]:
            p["consumes"] = p["cap"] in consumers if p["cap"] else False

    # The guard comes from the same mux parse as the operands, so the two
    # cannot disagree about which arm is which.
    mul_guards = {k: {"cond": v["cond"]} for k, v in mul_arms.items()}
    for s in schedules.values():
        for p in s["phases"]:
            if p["mul"]:
                p["mul_guard"] = mul_arms.get(p["mul"], {}).get("cond", "")

    return {"params": params, "caps": caps, "arms": arms,
            "blocks": blocks, "schedules": schedules, "mul_doc": mul_doc,
            "mul_guards": mul_guards, "mul_arms": mul_arms,
            "signal_widths": signal_widths(lines),
            "consumers": sorted(consumers), "profiles": PROFILES,
            "unknown_guards": sorted(unknown_guards),
            "mul_iters": MUL_ITERS}


# ----------------------------------------------------------------------
# The tick sequencer's FSM
# ----------------------------------------------------------------------
FAMILIES = [
    ("S_IDLE", "idle", "dispatch"),
    ("V_LD", "record", "record load / store"),
    ("V_ST", "record", "record load / store"),
    ("T_", "sfx", "SFX header fetch"),
    ("K_SL", "slide", "slide detour"),
    ("K_ARP", "effect", "effect unit"),
    ("K_PF", "effect", "effect unit"),
    ("K_FX", "effect", "effect unit"),
    ("K_ROT", "publish", "publication"),
    ("K_", "tick", "tick / note advance"),
    ("EA", "advance", "advance sequence"),
    ("ES", "advance", "effect staging"),
    ("P_W", "publish", "publication"),
    ("PC", "publish", "publication"),
    ("I_", "instr", "custom instrument"),
    ("W_MUS", "music", "music flow"),
    ("ML_", "music", "music flow"),
    ("MS_", "music", "music flow"),
]


def family_of(state):
    for prefix, key, label in FAMILIES:
        if state == prefix or (prefix.endswith("_") and state.startswith(prefix)) \
           or (not prefix.endswith("_") and state.startswith(prefix)
               and prefix not in ("S_IDLE", "V_LD", "V_ST", "K_ROT", "W_MUS")):
            return key, label
        if state == prefix:
            return key, label
    return "other", "other"


def parse_enum(lines):
    text = "\n".join(lines)
    m = re.search(r"typedef enum logic \[5:0\] \{(.*?)\}\s*sst_t;", text, re.S)
    if not m:
        return []
    body = re.sub(r"//[^\n]*", "", m.group(1))
    return [s.strip() for s in body.split(",") if s.strip()]


def condition_at(lines, i):
    """The full `if (...)` condition starting at line i, joined across lines."""
    buf = strip_comment(lines[i]).strip()
    depth = buf.count("(") - buf.count(")")
    j = i
    while depth > 0 and j + 1 < len(lines):
        j += 1
        nxt = strip_comment(lines[j]).strip()
        buf += " " + nxt
        depth += nxt.count("(") - nxt.count(")")
    m = re.search(r"\bif\s*\((.*)\)\s*(begin)?\s*$", buf)
    if m:
        return re.sub(r"\s+", " ", m.group(1)).strip()
    m = re.search(r"\bif\s*\((.*?)\)", buf)
    return re.sub(r"\s+", " ", m.group(1)).strip() if m else ""


def parse_fsm(lines, states):
    """Transitions out of the main `case (sst)`, with their guards.

    Guards are recovered by indentation: for each `sst <= X`, the enclosing
    if/else-if/else chain is whatever sits at a lower indent above it, up to
    the case arm label. The file is consistently indented, and the result is
    checked against the raw `sst <=` count so silent under-extraction fails
    loudly rather than drawing a plausible-but-incomplete graph.
    """
    # Locate the main case block: the one whose arms carry `sst <=`.
    start = end = None
    for i, ln in enumerate(lines):
        if re.match(r"\s*case \(sst\)\s*$", ln):
            probe_end = None
            depth = 1
            for j in range(i + 1, len(lines)):
                code = strip_comment(lines[j])
                depth += len(re.findall(r"\bcase\b", code))
                depth -= len(re.findall(r"\bendcase\b", code))
                if depth == 0:
                    probe_end = j
                    break
            chunk = "\n".join(lines[i:probe_end or i])
            if "sst <=" in chunk:
                start, end = i, probe_end
                break
    if start is None:
        return [], {}

    arm_indent = None
    for j in range(start + 1, end):
        m = re.match(r"(\s*)([A-Z][A-Z0-9_]*)\s*[,:]", lines[j])
        if m and m.group(2) in states:
            arm_indent = len(m.group(1))
            break

    # Map every line in the block to its owning case arm(s).
    owner = {}
    arm_lines = {}
    cur = None
    for j in range(start + 1, end):
        ln = lines[j]
        if indent_of(ln) == arm_indent and ln.strip():
            m = re.match(r"\s*([A-Z][A-Z0-9_]*(?:\s*,\s*[A-Z][A-Z0-9_]*)*)\s*:", ln)
            if m and all(s.strip() in states for s in m.group(1).split(",")):
                cur = [s.strip() for s in m.group(1).split(",")]
                for s in cur:
                    arm_lines.setdefault(s, {"line": j + 1,
                                             "doc": lead_comment(lines, j),
                                             "body": []})
        if cur:
            owner[j] = cur
            for s in cur:
                arm_lines[s]["body"].append(ln)

    transitions = []
    for j in range(start + 1, end):
        code = strip_comment(lines[j])
        m = re.search(r"sst\s*<=\s*([A-Z][A-Z0-9_]*)\s*;", code)
        if not m or j not in owner:
            continue
        target = m.group(1)
        guards = []
        ind = indent_of(lines[j])
        k = j - 1
        while k > start:
            if indent_of(lines[k]) >= ind or not lines[k].strip():
                k -= 1
                continue
            s = strip_comment(lines[k]).strip()
            if indent_of(lines[k]) <= arm_indent:
                break
            if re.search(r"^\}?\s*(end\s+)?else\s+if\s*\(", s) or re.match(r"^if\s*\(", s):
                guards.append(("if", condition_at(lines, k)))
                ind = indent_of(lines[k])
            elif re.match(r"^(end\s+)?else\b", s) and "if" not in s:
                guards.append(("else", ""))
                ind = indent_of(lines[k])
            elif re.search(r"\bbegin\s*$", s) and re.search(r"\bif\s*\(", s):
                guards.append(("if", condition_at(lines, k)))
                ind = indent_of(lines[k])
            k -= 1
        guards.reverse()
        for src in owner[j]:
            transitions.append({
                "from": src, "to": target, "line": j + 1,
                "guards": [{"kind": g[0], "cond": g[1]} for g in guards],
                "note": (lines[j].split("//", 1)[1].strip()
                         if "//" in lines[j] else ""),
            })
    return transitions, arm_lines


def parse_state_tables(lines, states):
    """Per-state side tables: audio-RAM offset, engine word, store address.

    These say what each state actually TOUCHES, which is the part of a state
    machine a bubble diagram always leaves out.
    """
    tables = {}

    def scan(case_head, key):
        for i, ln in enumerate(lines):
            if re.match(r"\s*case \(sst\)\s*$", ln) and case_head(lines, i):
                depth = 1
                cur = None
                for j in range(i + 1, len(lines)):
                    code = strip_comment(lines[j])
                    depth += len(re.findall(r"\bcase\b", code))
                    depth -= len(re.findall(r"\bendcase\b", code))
                    if depth == 0:
                        break
                    m = re.match(
                        r"\s*([A-Z][A-Z0-9_]*(?:\s*,\s*[A-Z][A-Z0-9_]*)*)\s*:\s*(.*)",
                        lines[j])
                    if m and all(s.strip() in states
                                 for s in m.group(1).split(",")):
                        cur = [s.strip() for s in m.group(1).split(",")]
                        txt = m.group(2).strip()
                        for s in cur:
                            tables.setdefault(s, {}).setdefault(key, [])
                            if txt and txt != "begin":
                                tables[s][key].append(txt)
                    elif cur and lines[j].strip() and \
                            not re.match(r"\s*(endcase|default)", lines[j]):
                        for s in cur:
                            tables.setdefault(s, {}).setdefault(key, [])
                            tables[s][key].append(lines[j].strip())
                break

    def near(names):
        def pred(ls, i):
            ctx = "\n".join(ls[max(0, i - 12):i])
            return any(n in ctx for n in names)
        return pred

    scan(near(["sa_off", "sa_base"]), "aram")
    scan(near(["eng_word"]), "eng_word")
    scan(near(["eng_wa", "eng_wd"]), "eng_write")
    scan(near(["pinc_addr"]), "pinc")
    scan(near(["pub_wd"]), "pub")
    return tables


def extract_seq():
    lines = read(SEQ_SV)
    states = parse_enum(lines)
    transitions, arms = parse_fsm(lines, states)
    tables = parse_state_tables(lines, states)

    # Every `sst <=` site must appear in the graph. The reset assignment is the
    # one that legitimately sits outside the case block, so it is counted
    # separately rather than being written off as rounding.
    sites = [i + 1 for i, ln in enumerate(lines)
             if re.search(r"sst\s*<=\s*[A-Z]", strip_comment(ln))]
    got = {t["line"] for t in transitions}
    outside = [ln for ln in sites if ln not in got]
    raw = len(sites)
    nodes = []
    for s in states:
        key, label = family_of(s)
        a = arms.get(s, {})
        nodes.append({
            "name": s, "family": key, "family_label": label,
            "line": a.get("line"), "doc": a.get("doc", ""),
            "body": "\n".join(trim_trailing_comments(a.get("body", []))),
            "tables": tables.get(s, {}),
        })
    return {
        "states": nodes,
        "transitions": transitions,
        "raw_assign_count": raw,
        "unplaced_lines": outside,
        "extracted_count": len(got),
    }


# ----------------------------------------------------------------------
# Analysis: where the schedules spend themselves.
#
# Every finding here is a MEASUREMENT plus the condition that would have to
# hold for it to become a win. None of them claims a saving: the schedule is
# a timetable, and whether a phase can actually be reclaimed depends on data
# hazards this tool does not model. A number that cannot be earned must not
# be reported as one.
# ----------------------------------------------------------------------
def samples_per_tick():
    """How many samples a tick spans, from the rates psg_timing.sv states.

    Needed to turn "active for the first 64 samples after a tick" into a duty
    cycle. Read rather than assumed, so a retune of either rate moves the
    number instead of quietly invalidating it.
    """
    try:
        head = "\n".join(read(TIMING_SV)[:4])
        rate = float(re.search(r"([\d.]+)\s*Hz virtual sample rate", head).group(1))
        tick = float(re.search(r"([\d.]+)\s*Hz sequencer", head).group(1))
        return rate / tick
    except Exception:
        return None


def phase_busy(p):
    return bool(p["cap"] or p["mul"] or p["flags"] or p["load"]
                or p["sched"] or p["events"])


def idle_runs(phases):
    runs, cur = [], None
    for p in phases:
        if not phase_busy(p):
            cur = cur or [p["pph"], p["pph"]]
            cur[1] = p["pph"]
        elif cur:
            runs.append(cur)
            cur = None
    if cur:
        runs.append(cur)
    return runs


# Latencies other than the multiply, each read out of its own module.
#   psg_state_mem: `state_q <= state_m[state_ra]` - one cycle, so a word
#     landing in phase p was addressed in p-1.
#   psg_wave:      "The cone is two REGISTERED stages" - issue in p, z_eval
#     in p+2.
# Modelling these is what turns "unexplained" from a shrug into a claim.
STATE_READ_LATENCY = 1
WAVE_CONE_STAGES = 2

# Phases whose holder was established by reading the RTL rather than derived.
# Each entry carries its evidence so it can be re-checked, and anything NOT
# listed that ends up unexplained is reported - a hand annotation must not be
# able to hide a phase it no longer describes.
AUDITED = {
    ("hw", 104): {
        "holder": "combinational settling (dampen one-pole)",
        "why": "mx_prod is registered at CAP_W84 (pph 103) and captured into "
               "mx_filt at CAP_W86 (pph 105). Between them filt_y is pure "
               "combinational logic — dmp_mul -> dmp_acc -> dmp_tz -> dmp_y, "
               "three 19-bit adds deep — with no register. So the path is "
               "given two clock periods to settle rather than one.",
        "reclaimable": "This is a TIMING choice, not a data latency. Whether "
                       "the phase is needed is a question for the synthesis "
                       "timing report, not for structure: if the path closes "
                       "in one period at the target clock, the phase is free.",
    },
}


def attribute_pipelines(phases, params, variant):
    """Mark phases held by the record port or the wave cone.

    Without this the head of every visit reads as dead time, when in fact it
    is a run of serial single-port reads: the record store has exactly one
    synchronous read site, so the words can only arrive one per clock.

    The WRITE window matters just as much and is easy to miss - it carries no
    control-store opcode and no `pph ==` site, only the range compare in
    `state_sample_we`. Missing it made the preview walk's phases 16..22 look
    like six idle phases when they are the oscillator write-back.
    """
    n = len(phases)
    for p in phases:
        p["holders"] = []
    for i, p in enumerate(phases):
        if p["load"]:
            p["holders"].append("record port (word lands here)")
            j = i - STATE_READ_LATENCY
            if 0 <= j < n:
                phases[j]["holders"].append("record port (address issued here)")
        for f in p["flags"]:
            if f.startswith("ISS_") or f == "DQ_OLD":
                for k in range(i + 1, min(i + 1 + WAVE_CONE_STAGES, n)):
                    phases[k]["holders"].append(f"wave cone ({f} stage)")

    # state_sample_we: pph >= PSTOR && pph < PSTOR + PLOSC, one word a clock.
    lo, hi = params["PSTOR"], params["PSTOR"] + params["PLOSC"]
    for i in range(lo, min(hi, n)):
        phases[i]["holders"].append(
            f"record port (oscillator write-back word {i - lo})")
    if variant == "hw":
        for off in (87, 88):                 # state_lp_we, the late dampen pair
            k = params["PWORK"] + off
            if 0 <= k < n:
                phases[k]["holders"].append("record port (late dampen write-back)")

    for (v, pph), note in AUDITED.items():
        if v == variant and 0 <= pph < n:
            phases[pph]["holders"].append(note["holder"])
            phases[pph]["audit"] = note
    return phases


def attribute_ready_products(phases, mul_arms):
    """Mark fixed phases that now hold an already-completed product.

    Narrowing a multiplier mode ends `m_busy` earlier, but does not move the
    control-store consume action. Without this attribution the newly created
    ready-to-consume gap looks like mysterious empty time. It is real retiming
    potential, but the service cannot launch over it without first capturing
    the completed product that still lives in `m_p`.
    """
    consumers = sorted(p["pph"] for p in phases if p.get("consumes"))
    for p in phases:
        arm = mul_arms.get(p.get("mul"))
        if not p.get("mul") or not arm:
            continue
        for iters in sorted({MUL_ITERS[m] for m in arm["modes"]}):
            ready = p["pph"] + iters + 1
            nxt = next((c for c in consumers if c >= ready), None)
            if nxt is None:
                continue
            for k in range(ready, nxt):
                phases[k]["holders"].append(
                    f"completed {p['mul']} product held for consume at pph {nxt}")
    return phases


def classify(phases, profiles):
    """Label every phase by what is provably holding it.

    Only ONE latency is modelled here: the multiply service, whose busy window
    follows exactly from the request phase and the mode's iteration count. A
    phase the service is iterating through is forced, and that is a proof.

    The remainder is NOT proven slack. Synchronous record reads, the wave
    cone's pipeline and the fold tree all impose latencies this tool does not
    model, so "unexplained" means only that the multiply service does not
    account for the phase - an upper bound on what could be reclaimed, never a
    claim that it can be.
    """
    keys = [p["key"] for p in profiles]
    for p in phases:
        busy = set(p.get("mul_busy") or [])
        if phase_busy(p):
            p["klass"] = "work"
        elif busy >= set(keys):
            p["klass"] = "forced"          # service busy on every profile
        elif busy:
            p["klass"] = "cond"            # busy on some profiles only
        elif p.get("holders"):
            p["klass"] = "pipeline"        # record port or wave cone holds it
        else:
            p["klass"] = "unexplained"     # nothing this tool models
        p["idle_for"] = sorted(set(keys) - busy) if not phase_busy(p) else []
    return phases


def analyse(model):
    walk, seq = model["walk"], model["seq"]
    out = []
    profiles = walk["profiles"]
    for variant, S in walk["schedules"].items():
        attribute_pipelines(S["phases"], S["params"], variant)
        attribute_ready_products(S["phases"], walk["mul_arms"])
        classify(S["phases"], profiles)

    # ---- 1. request-to-consume slack, measured ------------------------
    # The one question worth asking of a latency shadow: is it longer than
    # the service needs? Product ready at request + iters + 1; consumed at
    # the next capture step that reads the result closure.
    S = walk["schedules"]["hw"]
    cons = sorted(p["pph"] for p in S["phases"] if p.get("consumes"))
    rows, worst = [], 0
    for p in S["phases"]:
        arm = walk["mul_arms"].get(str(p["mul"])) or walk["mul_arms"].get(p["mul"])
        if not p["mul"] or not arm:
            continue
        for iters in sorted({MUL_ITERS[m] for m in arm["modes"]}):
            ready = p["pph"] + iters + 1
            nxt = [c for c in cons if c >= ready]
            slack = (nxt[0] - ready) if nxt else None
            worst = max(worst, slack or 0)
            rows.append((p["pph"], p["mul"], iters, ready,
                         nxt[0] if nxt else None, slack))
    out.append({
        "id": "mul-slack",
        "area": "walk",
        "title": (f"every multiply request is consumed the phase its product "
                  f"becomes readable — measured slack {worst}")
                 if worst == 0 else
                 (f"multiply requests carry up to {worst} phases of slack"),
        "measure": {
            "requests measured": len(rows),
            "latency model": "request + iters + 1 (m_cnt loads 8/10/12 and "
                             "decrements once per clock)",
            "iterations by mode": ", ".join(f"mode {k}={v}"
                                            for k, v in MUL_ITERS.items()),
            "consuming phases": ", ".join(str(c) for c in cons),
            "max slack found": worst,
        },
        "body": "Each row is a request phase, the iteration count its mode "
                "loads, the phase the product is first readable, and the phase "
                "that consumes it. The gaps in the schedule are the service "
                "iterating — they are not reschedulable, and shortening them "
                "means a wider multiplier, not a tighter timetable.\n\n"
                "Consumers are found over the combinational closure of "
                "m_res/m_res12/m_res_wide, because steps like CAP_W74 read the "
                "product through a wire (gz_old_scaled) and a direct-name scan "
                "would score a tight schedule as slack.",
        "table": {"cols": ["req", "arm", "iters", "ready", "consumed", "slack"],
                  "rows": [[a, b, c, d, "-" if e is None else e,
                            "-" if f is None else f] for a, b, c, d, e, f in rows]},
        "refs": [{"kind": "phase", "variant": "hw", "key": r[0],
                  "label": f"pph {r[0]}"} for r in rows],
    })

    # ---- 1b. iterations charged vs bits the operand actually needs ----
    # The current chain is the sum of the multiply latencies (slack is zero
    # above). A narrower mode creates schedule slack; it does NOT remove a
    # phase by itself because the control-store request and consume phases are
    # fixed. A phase is recoverable only after those later actions are retimed.
    # m_cnt is set by the MODE, and a mode only fits operands up to its width -
    # so an operand narrower than its mode is charged for bits it does not have.
    widths = walk["signal_widths"]
    rows, provable, declared = [], [], []
    for p in S["phases"]:
        arm = walk["mul_arms"].get(p["mul"])
        if not p["mul"] or not arm:
            continue
        for expr in arm["b_exprs"]:
            bits, kind, val = operand_width(expr, widths)
            charged = max(MUL_ITERS[m] for m in arm["modes"])
            fits = [it for it in sorted(set(MUL_ITERS.values()))
                    if bits is not None and it >= bits]
            best = fits[0] if fits else None
            excess = (charged - best) if best is not None else None
            # Two different claims: what an EXISTING mode already recovers,
            # and what the operand's true width would allow if a mode for it
            # existed. Only the first needs no new encoding.
            ideal = (charged - bits) if bits is not None else None
            rows.append([p["pph"], p["mul"], expr[:26], bits or "?", kind,
                         charged, best if best is not None else "?",
                         excess if excess is not None else "?",
                         ideal if ideal is not None else "?"])
            if kind == "constant" and excess:
                provable.append((p["pph"], val, bits, charged, best, excess))
            elif bits is not None and ideal:
                declared.append((p["pph"], expr, bits, charged, kind, ideal))

    measure = {
        "iteration ladder": ", ".join(f"mode {k} = {v}"
                                      for k, v in MUL_ITERS.items()),
        "mode encodings used": f"{len(set(MUL_ITERS))} of 4 "
                               "(wmul_mode is 2 bits — one spare)",
    }
    for val in sorted({r[1] for r in provable}):
        sites = [r for r in provable if r[1] == val]
        p0 = sites[0]
        measure[f"constant {val} — needs {p0[2]} bits, charged {p0[3]}"] = (
            f"fits mode with {p0[4]} iterations: {p0[5]} recoverable at "
            f"{len(sites)} sites (" + ", ".join(f"pph {s[0]}" for s in sites)
            + ") with no new encoding")
    for pph, e, b, c, kind, ideal in declared:
        measure[f"pph {pph}  {e[:24]}"] = (
            f"{b} bits{' (declared)' if kind == 'signal' else ''} vs {c} "
            f"charged — {ideal} would need a {b}-iteration mode")

    # The upper bound after a successful retiming. Slack is zero today and each
    # profile's requests form a serial chain, so the sum of narrower-mode
    # deltas bounds how much a correspondingly compressed chain could save.
    # Report it as potential, never as a saving caused by the mode change.
    ladder = sorted(set(MUL_ITERS.values()))
    for prof in walk["profiles"]:
        delta = 0
        for p in S["phases"]:
            arm = walk["mul_arms"].get(p["mul"])
            if not p["mul"] or not arm:
                continue
            if arm["cond"] not in ("", *prof["true"]):
                continue
            for expr in arm["b_exprs"]:
                bits, kind, _ = operand_width(expr, widths)
                if kind != "constant" or bits is None:
                    continue
                charged = max(MUL_ITERS[m] for m in arm["modes"])
                fits = [it for it in ladder if it >= bits]
                if fits and fits[0] < charged:
                    delta += fits[0] - charged
                    break
        if delta:
            measure[f"retiming potential for a {prof['label']}"] = (
                f"up to {abs(delta)} phases = {abs(delta)*8} clocks/sample; "
                "zero until request/consume actions are moved")

    out.append({
        "id": "mul-width",
        "area": "walk",
        "title": "some multiplier operands are charged more iterations than "
                 "they have bits",
        "measure": measure,
        "body": "m_cnt is loaded from the mode, and each iteration consumes one "
                "bit of B. An operand narrower than its mode still pays the "
                "mode's full count. Using a narrower mode only makes the "
                "product ready earlier; it does not change the control-store "
                "phase numbers, so by itself it saves zero walker clocks. To "
                "remove a phase, every dependent request and consume action "
                "must be safely retimed and the shortened schedule verified."
                "\n\n"
                "Constants are provable: 171 needs 8 bits and mode 0 gives "
                "exactly 8. 341 needs 9 and would truncate at mode 0 — it needs "
                "a 9-iteration mode, and wmul_mode has one spare encoding. "
                "Signal operands are only DECLARED widths here; narrowing one "
                "needs a range argument this tool cannot make.\n\n"
                "Changing a mode moves the accumulator slice as well as the "
                "count, so equivalence is not obvious and must be checked "
                "against the service, not assumed. The retained mode-only "
                "×171 change is exact and frees service iterations for later "
                "work or retiming, but maps 24 placed cells larger and does "
                "not shorten the current fixed walk.",
        "table": {"cols": ["pph", "arm", "B operand", "bits", "kind",
                           "charged", "fits mode", "excess now", "if exact"],
                  "rows": rows},
        "refs": [{"kind": "phase", "variant": "hw", "key": r[0],
                  "label": f"pph {r[0]}"} for r in rows],
    })

    # ---- 1b2. what the dependency audit buys -------------------------
    # With `after` known, the multiply cost stops being a sum and becomes a
    # longest path. Three numbers, all from the same graph: one service (what
    # runs today), one per chain, and unlimited.
    S = walk["schedules"]["hw"]
    iters_of = {}
    for p in S["phases"]:
        arm = walk["mul_arms"].get(p["mul"])
        if p["mul"] and arm and p["mul"] in MUL_DEPS:
            nowt = [c for c, mode in arm["branches"] if c == "!s_snd_wt"]
            iters_of[p["mul"]] = (
                MUL_ITERS[dict(arm["branches"])["!s_snd_wt"]] if nowt
                else max(MUL_ITERS[m] for m in arm["modes"]))

    def cost(a):
        return iters_of.get(a, 0) + 1

    chain_new = ['CAP_W4', 'CAP_W17', 'CAP_W28']
    chain_old = ['CAP_W39', 'CAP_W52', 'CAP_W63']
    one_service = sum(cost(a) for a in iters_of)
    # Two services: each chain on its own, the limbs still serialising there.
    two_service = max(sum(cost(a) for a in chain_new),
                      sum(cost(a) for a in chain_old)) + cost('CAP_W75')
    # Unlimited: the true data depth - head, then the deeper of its siblings.
    unlimited = (max(cost('CAP_W4') + max(cost('CAP_W17'), cost('CAP_W28')),
                     cost('CAP_W39') + max(cost('CAP_W52'), cost('CAP_W63'))) + cost('CAP_W75'))
    out.append({
        "id": "mul-deps",
        "area": "walk",
        "title": f"the multiply chain's data depth is {unlimited} clocks; one "
                 f"service makes it {one_service}",
        "measure": {
            "one service (today)": f"{one_service} clocks",
            "one per chain": f"{two_service} clocks "
                             f"(−{one_service - two_service})",
            "unlimited services (data floor)":
                f"{unlimited} clocks (−{one_service - unlimited})",
            "the two chain heads": "CAP_W4 (new voice) and CAP_W39 (old "
                                   "continuation) — neither reads a product",
            "the sibling pairs": "W17 ∥ W28 both consume W4; W52 ∥ W63 "
                                 "both consume W39",
            "the join": "CAP_W75 (blend) needs both chains",
        },
        "body": "Audited by reading the RTL, arm by arm, for the "
                "non-wavetable profile. The result is that the walk's "
                "multiply work is not one serial chain but TWO independent "
                f"ones that meet at the blend — so most of the {one_service} "
                "clocks is "
                "contention for the single shift-add service, not data "
                "dependence.\n\n"
                "A flow-insensitive taint pass was tried first and rejected. "
                "CAP_W26 writes smp_b from the wavetable lerp product, but "
                "only under `if (s_snd_wt)`; a pass blind to that guard marks "
                "smp_b — and through it z_new_c and z_old_sel — as "
                "product-derived everywhere, collapsing both chain heads into "
                "false dependents. That is the one distinction this whole "
                "question turns on.\n\n"
                "What this does NOT establish: that a second service is worth "
                "its area, or that the schedule can be rewritten to exploit "
                "the parallelism without new hazards. It establishes only that "
                "the data permits it.",
        "table": {"cols": ["arm", "consumes", "A operand", "B operand",
                           "clocks", "evidence"],
                  "rows": [[a, str(MUL_DEPS[a]["after"]), MUL_DEPS[a]["a"],
                            MUL_DEPS[a]["b"], cost(a), MUL_DEPS[a]["why"]]
                           for a in sorted(MUL_DEPS)]},
        "refs": [{"kind": "phase", "variant": "hw", "key": p["pph"],
                  "label": f"arm {p['mul']} @ pph {p['pph']}"}
                 for p in S["phases"] if p["mul"] in MUL_DEPS],
    })

    # ---- 1c. the floor: how short could the visit be? -----------------
    # A resource floor, not a wish. Two structural limits are certain:
    #   - the record store has ONE synchronous read site, so N record words
    #     cost at least N clocks;
    #   - there is ONE multiply service, so the products a profile launches
    #     cost at least sum(iters + 1) clocks whether or not they are
    #     data-dependent on each other.
    # Those two can overlap in principle, so the floor is their MAXIMUM, and
    # the budget is what the schedule spends above it.
    for variant in ("hw", "preview"):
        Sv = walk["schedules"][variant]
        ph = Sv["phases"]
        words = sum(1 for p in ph if p["load"])
        # The write-back window is a second, independent port occupancy: the
        # store does one read AND one write per clock, so writes overlap
        # compute - but only if there IS compute long enough to hide them.
        writes = Sv["params"]["PLOSC"] + (2 if variant == "hw" else 0)
        rows = []
        for prof in profiles:
            mul_cost = 0
            for p in ph:
                arm = walk["mul_arms"].get(p["mul"])
                if not p["mul"] or not arm:
                    continue
                if arm["cond"] not in ("", *prof["true"]):
                    continue
                iters = None
                for cond, mode in arm["branches"]:
                    if cond in prof["true"]:
                        iters = MUL_ITERS[mode]
                if iters is None:
                    iters = max(MUL_ITERS[m] for m in arm["modes"])
                mul_cost += iters + 1
            # Two floors, because they name two different changes. Inside one
            # visit the record load must PRECEDE the work that uses it, so the
            # costs add. They only overlap if the next slot's load is hidden
            # under this slot's arithmetic - which is a real transformation
            # (software-pipelining the slots), not a free assumption.
            serial = words + max(mul_cost, writes)
            overlapped = max(words, writes, mul_cost)
            rows.append([prof["label"], words, writes, mul_cost, serial,
                         overlapped, Sv["n"], Sv["n"] - serial,
                         Sv["n"] - overlapped])
        ser = max(r[4] for r in rows)
        ovl = max(r[5] for r in rows)
        out.append({
            "id": f"floor-{variant}",
            "area": "walk",
            "title": f"{variant} walk: {Sv['n']} phases scheduled against a "
                     f"serial floor of {ser} and an overlapped floor of {ovl}",
            "measure": {
                "record words per visit": f"{words} read, {writes} written "
                                          f"(one read site and one write site, "
                                          f"so the two overlap each other)",
                "budget vs the serial floor":
                    f"{Sv['n'] - ser} phases = {(Sv['n']-ser)*8} clocks/sample",
                "budget vs the overlapped floor":
                    f"{Sv['n'] - ovl} phases = {(Sv['n']-ovl)*8} clocks/sample",
                "what the second one costs":
                    "hiding the next slot's record load under this slot's "
                    "arithmetic — a second set of streaming registers",
            },
            "body": "The budget is the distance between the schedule and a "
                    "limit that cannot be argued away, which is what makes it "
                    "a plan rather than a guess.\n\n"
                    "Both limits are RESOURCE limits: one record read port, "
                    "one multiply service. The serial floor is what the visit "
                    "costs as it is structured now — load, then work. The "
                    "overlapped floor is what it costs if slot N+1's load runs "
                    "under slot N's arithmetic; the gap between the two is the "
                    "prize for software-pipelining the slots, and its price is "
                    "a duplicate set of streaming registers.\n\n"
                    "The multiply column assumes every product serialises on "
                    "the single service — true today regardless of data "
                    "dependence. Whether a SECOND service could go below it "
                    "depends on whether the requests are independent, and this "
                    "tool does not answer that: it needs a per-arm audit of "
                    "where each request's operands come from. A flow-"
                    "insensitive taint pass was tried and rejected — it marked "
                    "z_new_c as product-derived when it comes from the wave "
                    "path.",
            "table": {"cols": ["profile", "reads", "writes", "multiply clocks",
                               "serial floor", "overlapped floor", "scheduled",
                               "budget (serial)", "budget (overlapped)"],
                      "rows": rows},
            "refs": [],
        })

    # ---- 2. schedule occupancy, split by what the phase is doing ------
    for variant, title in (("hw", "hardware"), ("preview", "preview")):
        S = walk["schedules"][variant]
        ph = S["phases"]
        n = {k: sum(1 for p in ph if p["klass"] == k)
             for k in ("work", "forced", "cond", "pipeline", "unexplained")}
        runs = [r for r in idle_runs(ph)
                if all(byp["klass"] == "unexplained"
                       for byp in ph[r[0]:r[1]+1])]
        uses_mul = n["forced"] + n["cond"] > 0
        out.append({
            "id": f"occupancy-{variant}",
            "area": "walk",
            "title": f"{title} walk: {n['work']} phases of work, "
                     f"{n['forced']+n['cond']} held by multiply latency, "
                     f"{n['pipeline']} holding pipeline/product state, "
                     f"{n['unexplained']} unexplained",
            "measure": {
                "phases per slot": S["n"],
                "scheduled work": n["work"],
                "multiply busy on every profile": n["forced"],
                "multiply busy on some profiles only": n["cond"],
                "pipeline or completed-product hold": n["pipeline"],
                "not explained by the multiply service": n["unexplained"],
                "clocks per sample (8 slots)": S["n"] * 8,
                "upper bound on reclaimable clocks/sample": n["unexplained"] * 8,
            },
            "body": "One micro-phase is one clock and the visit runs once per "
                    "slot per sample, so a phase costs eight clocks of every "
                    "sample. The multiply-busy rows are proofs: they follow "
                    "from each request's iteration count, and those phases "
                    "cannot be removed without changing the multiplier.\n\n"
                    "The last row is NOT proven slack. This tool models one "
                    "latency — the multiply service. Synchronous record reads, "
                    "the wave cone and the fold tree impose their own, so "
                    "'unexplained' is an upper bound on what could be "
                    "reclaimed, not a reclaimable figure."
                    + ("" if uses_mul else
                       "\n\nThis schedule does not use the multiply service at "
                       "all, so every idle phase lands here by default and the "
                       "bound says correspondingly little."),
            "refs": [{"kind": "phase", "variant": variant, "key": r[0],
                      "label": f"{r[0]}..{r[1]} ({r[1]-r[0]+1})"}
                     for r in runs],
        })

    # ---- 2. phases whose product is runtime-gated ---------------------
    S = walk["schedules"]["hw"]
    gated = [p for p in S["phases"] if p["mul"] and p.get("mul_guard")]
    by_cond = {}
    for p in gated:
        by_cond.setdefault(p["mul_guard"], []).append(p)
    if gated:
        shadow = 0
        runs = idle_runs(S["phases"])
        for p in gated:
            for a, b in runs:
                if a == p["pph"] + 1:
                    shadow += b - a + 1
        # The wavetable and non-wavetable arms are complementary: one voice
        # runs one set or the other, never both, yet the timetable carries
        # both. That partition is the finding - the raw guarded count is not.
        wt = by_cond.get("s_snd_wt", [])
        nwt = by_cond.get("!s_snd_wt", [])
        spt = samples_per_tick()
        # Measured, not inferred: for each profile, the phases carrying no
        # scheduled work where the service is provably NOT iterating. That is
        # the reclaimable set for a voice of that kind.
        measure = {}
        for prof in walk["profiles"]:
            idle = [p for p in S["phases"]
                    if not phase_busy(p) and prof["key"] in p["idle_for"]]
            measure[f"idle for a {prof['label']}"] = (
                f"{len(idle)} phases = {len(idle)*8} clocks/sample")
        measure["guarded request phases"] = len(gated)
        measure.update({f"gated on `{c}`": ", ".join(f"pph {p['pph']}" for p in v)
                        for c, v in by_cond.items()})
        if wt and nwt:
            measure["mutually exclusive"] = (
                f"{len(wt)} wavetable-only and {len(nwt)} non-wavetable-only "
                "requests; a voice takes one path, never both")
        if spt:
            measure["blend duty cycle"] = (
                f"active the first 64 samples after a tick, and a tick spans "
                f"~{spt:.0f} samples — so ~{100*64/spt:.0f}% of samples")
        if walk["unknown_guards"]:
            measure["guards not modelled"] = (
                ", ".join(walk["unknown_guards"])
                + " — treated as always firing, which understates the idle sets")
        out.append({
            "id": "gated-mul",
            "area": "walk",
            "title": f"{len(gated)} of "
                     f"{sum(1 for p in S['phases'] if p['mul'])} multiply "
                     "requests only fire under a runtime condition, but their "
                     "phases always elapse",
            "measure": measure,
            "body": "The request mux gates these arms, so the multiply service "
                    "is NOT occupied when the condition is false — but the "
                    "control store is indexed by phase alone, so the phase and "
                    "the latency shadow behind it elapse either way. The "
                    "schedule is the union of the wavetable and non-wavetable "
                    "paths, and every voice pays for both.\n\n"
                    "Whether this is reclaimable depends on a data-dependent "
                    "phase skip being safe here. The mechanism already exists: "
                    "the preview schedule jumps a silent slot straight to PFOLD "
                    "with `pph <= 7'(PFOLD)`. What this tool cannot tell you is "
                    "whether the skipped phases carry side effects the later "
                    "steps depend on — read the arms before believing it.",
            "refs": [{"kind": "phase", "variant": "hw", "key": p["pph"],
                      "label": f"pph {p['pph']} — {p['mul_doc']}"}
                     for p in gated],
        })

    # ---- 3. encoding headroom ----------------------------------------
    nst = len(seq["states"])
    capmax = max(v for v in walk["caps"].values())
    launches = sum(1 for p in S["phases"] if p["mul"])
    live = walk["params"]["hw"]["PLAST"] + 1
    nonzero = sum(1 for p in S["phases"] if p["word"])
    out.append({
        "id": "encoding",
        "area": "both",
        "title": f"the FSM state register is at {nst} of 64 encodings — one "
                 "spare",
        "measure": {
            "FSM states": f"{nst} (sst is logic [5:0], 64 encodings)",
            "spare state encodings": 64 - nst,
            "CAP_SEL opcodes": f"{capmax} used of 31 (5-bit field)",
            "product launches": f"{launches}, selected by CAP_SEL — the "
                                "separate MUL_SEL field has been retired and "
                                "control-word bits [8:5] are spare",
            "control-store words with any work":
                f"{nonzero} of {live} live phases",
            "spare control-word bits": "bit [15]",
        },
        "body": "A 64th sequencer state widens `sst` to 7 bits and every "
                "comparator and case decode that reads it — so the next state "
                "added is not free the way the previous ones were. In the "
                "other direction the control store is sparse: most live "
                "phases decode to a zero word, and the capture and multiply "
                "fields have unused encodings, so a phase-skip opcode could "
                "be added without widening the word.",
        "refs": [],
    })

    # ---- 4. serial chains in the FSM ---------------------------------
    outd, ind = {}, {}
    for t in seq["transitions"]:
        outd.setdefault(t["from"], []).append(t)
        ind.setdefault(t["to"], []).append(t)
    chains, seen = [], set()
    for n in seq["states"]:
        s = n["name"]
        if s in seen or len(ind.get(s, [])) != 1 or not ind[s][0]["guards"]:
            pass
        run = [s]
        cur = s
        while (len(outd.get(cur, [])) == 1 and not outd[cur][0]["guards"]
               and len(ind.get(outd[cur][0]["to"], [])) == 1):
            cur = outd[cur][0]["to"]
            if cur in run:
                break
            run.append(cur)
        if len(run) >= 4 and not (set(run) & seen):
            seen |= set(run)
            chains.append(run)
    chains.sort(key=len, reverse=True)
    if chains:
        out.append({
            "id": "serial-chains",
            "area": "seq",
            "title": f"{len(chains)} straight runs of 4+ states execute one "
                     "clock per step with no branch",
            "measure": {"longest run": f"{len(chains[0])} states "
                                       f"({' -> '.join(chains[0])})",
                        "states in such runs": sum(len(c) for c in chains),
                        "total FSM states": nst},
            "body": "These are the serialisation cost: the sequencer has 183 "
                    "samples of slack per tick, which is what lets it visit "
                    "one slot at a time through a single record port. Most "
                    "steps in a run are waiting on a synchronous read issued "
                    "by the step before, so they are NOT free to merge — the "
                    "read latency is real. The runs worth a second look are "
                    "the ones whose steps address the SAME record word or do "
                    "no read at all; the per-state 'record word read' panel "
                    "on the sequencer tab shows which.",
            "refs": [{"kind": "state", "key": c[0],
                      "label": " → ".join(c)} for c in chains],
        })

    # ---- 5. duplicate case arms --------------------------------------
    def norm(b):
        b = re.sub(r"//[^\n]*", "", b or "")
        b = re.sub(r"^\s*[A-Z_0-9, ]+:", "", b.strip())
        return re.sub(r"\s+", " ", b).strip()

    groups = {}
    for n in seq["states"]:
        k = norm(n.get("body"))
        if len(k) > 20:
            groups.setdefault(k, []).append(n["name"])
    dups = {k: v for k, v in groups.items() if len(v) > 1}
    if dups:
        out.append({
            "id": "dup-arms",
            "area": "seq",
            "title": f"{len(dups)} group(s) of states share an identical case "
                     "arm",
            "measure": {", ".join(v): k[:90] for k, v in dups.items()},
            "body": "Identical bodies mean the synthesiser is decoding two "
                    "state encodings into the same actions. Merging them frees "
                    "an encoding — which matters more than usual here, with "
                    "one spare below the 7-bit boundary. Check first that the "
                    "two are not distinguished by something outside the arm: "
                    "these states are read by other case blocks too.",
            "refs": [{"kind": "state", "key": v[0], "label": " = ".join(v)}
                     for v in dups.values()],
        })

    return out


# ----------------------------------------------------------------------
# Layout: the families ARE the microprograms, so they are the columns.
#
# A rank layout from S_IDLE would spread one microprogram across the whole
# picture and interleave it with the others. Grouping by family keeps each
# microprogram legible as a unit and puts the interesting edges - the ones
# that leave a microprogram - on display as the long ones.
# ----------------------------------------------------------------------
COLUMN_ORDER = ["idle", "record", "sfx", "tick", "advance", "instr",
                "effect", "slide", "publish", "music", "other"]

NODE_W, NODE_H, ROW_GAP, COL_GAP, PAD = 116, 30, 15, 74, 34


def layout_fsm(seq):
    cols = {}
    for n in seq["states"]:
        cols.setdefault(n["family"], []).append(n)
    order = [c for c in COLUMN_ORDER if c in cols]
    order += [c for c in cols if c not in order]

    pos = {}
    x = PAD
    col_meta = []
    for ci, fam in enumerate(order):
        members = cols[fam]
        y = PAD + 26
        for n in members:
            pos[n["name"]] = {"x": x, "y": y, "col": ci}
            y += NODE_H + ROW_GAP
        col_meta.append({"family": fam,
                         "label": members[0]["family_label"],
                         "x": x, "count": len(members)})
        x += NODE_W + COL_GAP

    tallest = max(len(v) for v in cols.values())
    rows_bottom = PAD + 26 + tallest * (NODE_H + ROW_GAP)
    for n in seq["states"]:
        n.update(pos[n["name"]])
    # The return-edge band is sized in the page, where the edge count is
    # known; the layout only fixes where the node rows end.
    seq["layout"] = {"columns": col_meta, "width": x + PAD,
                     "node_rows_bottom": rows_bottom, "height": rows_bottom,
                     "node_w": NODE_W, "node_h": NODE_H, "row_gap": ROW_GAP}
    return seq


# ----------------------------------------------------------------------
# Rendering
# ----------------------------------------------------------------------
def render(model):
    payload = json.dumps(model)
    tpl_path = os.path.join(ROOT, "tools", "psg_viz.html")
    with open(tpl_path) as f:
        tpl = f.read()
    return tpl.replace("/*__MODEL__*/null", payload)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "psg_viz.html"))
    ap.add_argument("--json", action="store_true",
                    help="print the extracted model instead of rendering")
    args = ap.parse_args()

    model = {"walk": extract_walk(), "seq": layout_fsm(extract_seq())}
    model["findings"] = analyse(model)

    # A graph that quietly dropped transitions would still look convincing, so
    # the one site allowed to sit outside the case block is named explicitly
    # and anything else is reported.
    seq = model["seq"]
    lines = read(SEQ_SV)
    # A hand annotation is keyed by phase number, so a schedule change can
    # leave it describing the wrong phase. Report both directions: phases with
    # no holder at all, and annotations that now sit on a phase which has
    # other work - either one means the audit needs redoing.
    for variant, S in model["walk"]["schedules"].items():
        for p in S["phases"]:
            if p["klass"] == "unexplained":
                print(f"warning: {variant} walk pph {p['pph']}: no holder "
                      "found and no audit note — attribution is incomplete",
                      file=sys.stderr)
        for (v, pph), _ in AUDITED.items():
            if v != variant or not (0 <= pph < S["n"]):
                continue
            if phase_busy(S["phases"][pph]):
                print(f"warning: the audit note for {v} pph {pph} sits on a "
                      "phase that now carries scheduled work — recheck it",
                      file=sys.stderr)

    for ln in seq["unplaced_lines"]:
        src = lines[ln - 1].strip()
        if re.match(r"sst\s*<=\s*S_IDLE\s*;$", src):
            continue                       # the reset entry, by construction
        print(f"warning: {SEQ_SV}:{ln}: `{src}` is outside the FSM case block "
              "and is missing from the graph", file=sys.stderr)

    if args.json:
        json.dump(model, sys.stdout, indent=1)
        return

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as f:
        f.write(render(model))
    scheds = model["walk"]["schedules"]
    print(f"{args.out}: walk {scheds['hw']['n']} hardware / "
          f"{scheds['preview']['n']} preview phases, "
          f"{len(seq['states'])} FSM states, "
          f"{seq['extracted_count']} transitions")


if __name__ == "__main__":
    main()
