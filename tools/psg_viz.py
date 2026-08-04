#!/usr/bin/env python3
"""Visualise the PSG's two schedules: the sample walk and the tick sequencer.

This renders the MACHINE - the micro-phase schedule the walk executes every
sample, and the FSM the tick sequencer runs every tick - by reading
rtl/psg_walk.sv, rtl/psg_seq.sv, rtl/psg_mulsvc.sv and the control-store
generator. Optional JSON, JSONL, CSV, or key=value runtime traces overlay what
actually executed without replacing the nominal structure. Phase numbers,
action names, request guards, service shapes and encoding capacities are
source-derived, so ordinary schedule and datapath changes move the chart
without requiring a matching visualizer edit.

  python3 tools/psg_viz.py --out build/psg_viz.html
  python3 tools/psg_viz.py --json          # the extracted model, for diffing
  python3 tools/psg_viz.py --trace build/walk.jsonl

The walk has TWO schedules selected by the REALTIME_PREVIEW parameter, and
both are extracted: the full hardware schedule that the oracle and the board
run, and the compact preview schedule that `make run` plays. They are
different machines, and the preview half has historically been the one nothing
looked at.
"""
import argparse
import csv
import io
import itertools
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WALK_SV = os.path.join(ROOT, "rtl", "psg_walk.sv")
SEQ_SV = os.path.join(ROOT, "rtl", "psg_seq.sv")
PSG_SV = os.path.join(ROOT, "rtl", "psg.sv")
MULSVC_SV = os.path.join(ROOT, "rtl", "psg_mulsvc.sv")
MULMP_SV = os.path.join(ROOT, "rtl", "psg_mulmp.sv")
COMMON_SVH = os.path.join(ROOT, "rtl", "psg_common.svh")
STATE_MEM_SV = os.path.join(ROOT, "rtl", "psg_state_mem.sv")
WAVE_SV = os.path.join(ROOT, "rtl", "psg_wave.sv")


def read(path):
    with open(path) as f:
        return f.read().split("\n")


def scalar_bool(value, default=True):
    """Interpret the bool spellings emitted by simulators and CSV writers."""
    if value is None or value == "":
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    text = str(value).strip().lower()
    if text in ("0", "false", "off", "no", "idle"):
        return False
    if text in ("1", "true", "on", "yes", "active"):
        return True
    return default


def scalar_int(value):
    """Parse decimal or 0x-prefixed trace scalars without guessing X/Z."""
    if isinstance(value, bool) or value is None or value == "":
        return None
    if isinstance(value, int):
        return value
    text = str(value).strip().replace("_", "")
    try:
        return int(text, 0)
    except ValueError:
        return None


def trace_rows(path):
    """Load records plus file-level metadata from common trace containers.

    A record needs only `pph` (or `phase`). Optional fields are `cycle`,
    `prun`/`active`, `schedule`/`variant`, and `sst`. JSON may be a list, a
    single record, or `{records: [...], ...metadata}`. Plain simulator logs
    are accepted when a line contains key=value fields including `pph`.
    """
    with open(path) as f:
        text = f.read()
    stripped = text.lstrip()
    meta = {}
    if not stripped:
        return [], meta

    if stripped[0] in "[{":
        try:
            value = json.loads(text)
        except json.JSONDecodeError:
            value = None
        if value is not None:
            if isinstance(value, list):
                return value, meta
            if not isinstance(value, dict):
                raise RuntimeError(f"trace {path} is JSON but not an object/list")
            if isinstance(value.get("records"), list):
                return value["records"], {
                    k: v for k, v in value.items() if k != "records"
                }
            return [value], meta

    lines = [line for line in text.splitlines() if line.strip()]
    jsonl = []
    try:
        for line in lines:
            jsonl.append(json.loads(line))
    except json.JSONDecodeError:
        jsonl = []
    if jsonl and all(isinstance(row, dict) for row in jsonl):
        return jsonl, meta

    first = lines[0].lower()
    if "," in lines[0] and any(key in first for key in ("pph", "phase")):
        return list(csv.DictReader(io.StringIO(text))), meta

    rows = []
    for line in lines:
        fields = dict(re.findall(
            r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^\s,]+)", line))
        if "pph" in fields or "phase" in fields or "walk_phase" in fields:
            rows.append(fields)
    if not rows:
        raise RuntimeError(
            f"trace {path} has no JSON/CSV/key=value records containing pph")
    return rows, meta


def trace_row_stream(path, eager_limit=16 * 1024 * 1024):
    """Return an iterable of trace rows without materialising large traces."""
    if os.path.getsize(path) <= eager_limit:
        rows, meta = trace_rows(path)
        return iter(rows), meta

    def rows():
        with open(path) as stream:
            first = next((line for line in stream if line.strip()), "")
            if not first:
                return
            lower = first.lower()
            if first.lstrip().startswith("{"):
                for line in itertools.chain([first], stream):
                    if line.strip():
                        value = json.loads(line)
                        if not isinstance(value, dict):
                            raise RuntimeError(
                                f"trace {path} JSONL row is not an object")
                        yield value
                return
            if "," in first and any(key in lower for key in ("pph", "phase")):
                yield from csv.DictReader(itertools.chain([first], stream))
                return
            for line in itertools.chain([first], stream):
                fields = dict(re.findall(
                    r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^\s,]+)", line))
                if ("pph" in fields or "phase" in fields
                        or "walk_phase" in fields):
                    yield fields

    return rows(), {}


def normalize_trace_records(rows, default_variant="hw"):
    """Normalize loose simulator field names into the visualization contract."""
    out = []

    def pick(row, *names):
        for name in names:
            if name in row:
                return row[name]
        return None

    for ordinal, row in enumerate(rows):
        if not isinstance(row, dict):
            continue
        pph = scalar_int(pick(row, "pph", "phase", "walk_phase"))
        cycle = scalar_int(pick(row, "cycle", "clock", "clk", "time"))
        variant = str(pick(row, "schedule", "variant") or
                      default_variant).lower()
        if variant not in ("hw", "preview"):
            variant = default_variant
        out.append({
            "ordinal": ordinal,
            "cycle": cycle,
            "pph": pph,
            "active": scalar_bool(pick(row, "prun", "walk_active", "active")),
            "variant": variant,
            "sst": pick(row, "sst", "state", "seq_state"),
        })
    return out


def summarise_trace(records, schedules):
    """Count visits, repeats and control-flow jumps for each schedule."""
    state = {}
    for variant, schedule in schedules.items():
        n = schedule["n"]
        state[variant] = {
            "n": n, "counts": [0] * n, "stalls": [0] * n,
            "skipped": [0] * n, "unknown": {}, "jumps": {},
            "visits": 0, "wraps": 0, "active_clocks": 0,
            "previous": None,
        }

    for row in records:
        variant = row["variant"]
        if variant not in state:
            continue
        current = state[variant]
        if not row["active"] or row["pph"] is None:
            current["previous"] = None
            continue
        pph, n = row["pph"], current["n"]
        current["active_clocks"] += 1
        if 0 <= pph < n:
            current["counts"][pph] += 1
        else:
            current["unknown"][pph] = current["unknown"].get(pph, 0) + 1

        previous = current["previous"]
        contiguous = previous is not None
        if contiguous and previous["cycle"] is not None and row["cycle"] is not None:
            contiguous = row["cycle"] == previous["cycle"] + 1
        if not contiguous:
            current["visits"] += 1
        else:
            before = previous["pph"]
            if pph == before:
                if 0 <= pph < n:
                    current["stalls"][pph] += 1
            elif pph == 0 and before != 0:
                current["wraps"] += 1
                current["visits"] += 1
            elif pph != before + 1:
                key = (before, pph)
                current["jumps"][key] = current["jumps"].get(key, 0) + 1
                if before < pph:
                    for missed in range(max(0, before + 1), min(n, pph)):
                        current["skipped"][missed] += 1
        current["previous"] = row

    by_variant = {}
    for variant, current in state.items():
        if not current["active_clocks"]:
            continue
        by_variant[variant] = {
            "active_clocks": current["active_clocks"],
            "visits": current["visits"],
            "wraps": current["wraps"],
            "counts": current["counts"],
            "stalls": current["stalls"],
            "skipped": current["skipped"],
            "unknown": [{"pph": pph, "count": count}
                        for pph, count in sorted(current["unknown"].items())],
            "jumps": [{"from": pair[0], "to": pair[1], "count": count}
                      for pair, count in sorted(current["jumps"].items())],
            "max_count": max(current["counts"], default=0),
        }
    return by_variant


def load_trace(spec, schedules):
    """Load `[name=]path`; `preview=path` also selects the default schedule."""
    label, path = None, spec
    if "=" in spec:
        candidate, remainder = spec.split("=", 1)
        if remainder:
            label, path = candidate, remainder
    default_variant = label if label in ("hw", "preview") else "hw"
    rows, meta = trace_row_stream(path)
    default_variant = str(meta.get("schedule", meta.get("variant",
                                                        default_variant))).lower()
    if default_variant not in schedules:
        default_variant = "hw"
    record_count = 0

    def records():
        nonlocal record_count
        for row in rows:
            normalized = normalize_trace_records([row], default_variant)
            if normalized:
                record_count += 1
                yield normalized[0]

    schedules_summary = summarise_trace(records(), schedules)
    return {
        "name": str(meta.get("name") or label or os.path.basename(path)),
        "source": os.path.abspath(path),
        "records": record_count,
        "schedules": schedules_summary,
    }


def indent_of(line):
    return len(line) - len(line.lstrip())


def strip_comment(line):
    """Drop a trailing // comment, ignoring none-of-our-code string cases."""
    i = line.find("//")
    return line if i < 0 else line[:i]


def compact_expr(expr):
    """Canonical whitespace for comparing small SystemVerilog expressions."""
    return re.sub(r"\s+", " ", expr).strip()


def strip_outer_parens(expr):
    """Remove only parentheses which enclose an entire expression."""
    out = expr.strip()
    while out.startswith("(") and out.endswith(")"):
        depth = 0
        closes_at_end = False
        for i, ch in enumerate(out):
            depth += ch == "("
            depth -= ch == ")"
            if depth == 0:
                closes_at_end = i == len(out) - 1
                break
        if not closes_at_end:
            break
        out = out[1:-1].strip()
    return out


def split_top(expr, operator):
    """Split a boolean expression on a top-level operator."""
    out, start, depth = [], 0, 0
    i = 0
    while i < len(expr):
        ch = expr[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0 and expr.startswith(operator, i):
            out.append(expr[start:i].strip())
            i += len(operator)
            start = i
            continue
        i += 1
    out.append(expr[start:].strip())
    return out


def expression_dnf(expr):
    """Return a small &&/|| expression as disjunctive lists of atoms.

    Request selectors use only conjunction, disjunction and parentheses.  We
    deliberately keep comparisons as opaque atoms: the visualizer needs to
    know when a request fires, not evaluate arbitrary SystemVerilog.
    """
    expr = strip_outer_parens(compact_expr(expr))
    ors = split_top(expr, "||")
    if len(ors) > 1:
        return [term for part in ors for term in expression_dnf(part)]
    ands = split_top(expr, "&&")
    if len(ands) > 1:
        terms = [[]]
        for part in ands:
            terms = [a + b for a in terms for b in expression_dnf(part)]
        return terms
    return [[strip_outer_parens(expr)]]


# The width prefix may be a literal (`7'`) or a named localparam width
# (`PPH_W'`): phase widths are sized by the schedule (sizing audit), and the
# phase VALUE inside the cast is what this tool needs.
PPH_VALUE_RE = re.compile(
    r"pph\s*==\s*(?:\w+\s*)?'\s*(?:\(([^)]*)\)|d\s*(\d+))")


def pph_exprs(text):
    """All phase expressions in equality tests, independent of cast width."""
    return [(m.group(1) if m.group(1) is not None else m.group(2)).strip()
            for m in PPH_VALUE_RE.finditer(text)]


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
    text = "\n".join(strip_comment(line) for line in lines)
    pat = re.compile(
        r"localparam\s+int\s+(PLOSC|PWORK|PFOLD|PSTOR|PLAST)\s*=\s*"
        r"REALTIME_PREVIEW\s*\?\s*([^:;]+)\s*:\s*([^;]+)\s*;")
    for m in pat.finditer(text):
        name, preview, hw = m.group(1), compact_expr(m.group(2)), compact_expr(m.group(3))
        params[name] = {"preview": preview, "hw": hw}
    return params


def parse_integer_params(lines):
    """Resolvable integer localparams used by phase expressions."""
    text = "\n".join(strip_comment(line) for line in lines)
    pending = {}
    for m in re.finditer(r"localparam\s+int\s+([A-Z_][A-Z0-9_]*)\s*=\s*([^;]+);",
                         text):
        if "?" not in m.group(2):
            pending[m.group(1)] = compact_expr(m.group(2))
    values = {}
    for _ in range(len(pending) + 1):
        grew = False
        for name, expr in pending.items():
            if name in values:
                continue
            try:
                values[name] = int(eval(expr, {"__builtins__": {}}, values))
                grew = True
            except (NameError, SyntaxError, TypeError, ValueError):
                pass
        if not grew:
            break
    return values


def parse_cap_enum(lines):
    """CAP_* name -> its number, however the RTL currently spells the list.

    Matches any declaration form - a `typedef enum` of opcodes or a
    `localparam int` of one-hot bit indices - because the walk has used both
    and the number means something different in each. What the number MEANS is
    settled by cap_decoder(), not here.
    """
    text = "\n".join(lines)
    out = {}
    for m in re.finditer(r"(CAP_[A-Z0-9_]+)\s*=\s*(\d+)", text):
        out.setdefault(m.group(1), int(m.group(2)))
    return out


def cap_decoder(lines, words, caps):
    """word -> the action names it selects, derived rather than assumed.

    The control word has been an encoded 5-bit opcode and is now a 16-bit
    one-hot field; the tool must not care which. Decide from the evidence:
    if every non-zero word the generator emits is a power of two AND the RTL
    indexes the word (`cap[CAP_ACTION]`), the numbers are BIT POSITIONS. Otherwise
    they are opcode values in the low field.

    Getting this wrong is not a crash, it is a plausible wrong picture - every
    phase labelled with the wrong action - so it is decided from two
    independent signals rather than one.
    """
    text = "\n".join(lines)
    nonzero = [w for w in words if w]
    one_hot = bool(nonzero) and all(w & (w - 1) == 0 for w in nonzero)
    indexed = bool(re.search(r"\bcap\s*\[\s*CAP_", text))
    by_num = {}
    for name, num in caps.items():
        by_num.setdefault(num, name)

    if one_hot and indexed:
        width = max([1, *(w.bit_length() for w in words),
                     *(num + 1 for num in caps.values())])
        def decode(w):
            return [by_num[b] for b in range(width)
                    if (w >> b) & 1 and b in by_num]
        return decode, "one-hot"

    def decode(w):
        field_bits = max(1, max(caps.values()).bit_length())
        name = by_num.get(w & ((1 << field_bits) - 1))
        return [name] if name and name != "CAP_NONE" else []
    return decode, "encoded"


def parse_cap_flags(lines, caps):
    """Which named signals each action drives, e.g. CAP_ACTION -> issue_signal.

    The control word used to carry six explicit flag bits (ISS_SEC, SYN_A...).
    One-hot made them ALIASES - each sits on a phase that already carries an
    action - so the bits were removed and the signals are now driven straight
    off `cap[CAP_Wn]`. Reading those assignments keeps the wave-pipe and
    audio-RAM lanes populated without a transcribed bit list.
    """
    # Statement-wise, not line-wise: a conditional assignment often wraps, and
    # matching per line then picks up whichever identifier starts a continuation
    # identifier happens to start the continuation (`pph`) instead of the
    # signal being assigned.
    text = "\n".join(strip_comment(ln) for ln in lines)
    out = {}
    for stmt in text.split(";"):
        if "cap[" not in stmt.replace(" ", ""):
            continue
        m = re.search(r"(?:assign\s+|wire\s+(?:\[[^\]]*\]\s*)?)"
                      r"([a-zA-Z_][a-zA-Z0-9_]*)\s*=", stmt)
        if not m:
            continue
        for cap_name in re.findall(r"\bcap\s*\[\s*(CAP_[A-Z0-9_]+)\s*\]", stmt):
            if cap_name in caps:
                out.setdefault(cap_name, []).append(m.group(1))

    # Signals set inside an `if (... cap[CAP_Wn])` arm rather than by a
    # continuous assignment - syn_rd, the wavetable read strobe, is driven
    # this way. Without this the audio-RAM lane is silently empty, which reads
    # as "this phase issues no read" instead of "the tool did not look here".
    for i, ln in enumerate(lines):
        code = strip_comment(ln)
        if not re.search(r"\bif\s*\(.*cap\s*\[", code):
            continue
        names = [c for c in re.findall(r"\bcap\s*\[\s*(CAP_[A-Z0-9_]+)\s*\]", code)
                 if c in caps]
        if not names:
            continue
        depth = 0
        for j in range(i, min(i + 12, len(lines))):
            body = strip_comment(lines[j])
            depth += len(re.findall(r"\bbegin\b", body))
            depth -= len(re.findall(r"\bend\b(?!case)", body))
            for sig in re.findall(r"^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*(?:<=|=)\s*1'b1",
                                  body):
                for c in names:
                    out.setdefault(c, []).append(sig)
            if j > i and depth <= 0:
                break
    return {k: sorted(set(v)) for k, v in out.items()}


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
        # Both spellings: an encoded arm is `CAP_ACTION:`, while a one-hot arm
        # indexes the word as `cap[CAP_ACTION]:`.
        m = re.match(r"\s*(?:cap\s*\[\s*)?(CAP_[A-Z0-9_]+)\s*\]?\s*:", ln)
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
    """`pph == WIDTH'(EXPR)` sites outside the capture decode.

    These are the schedule's other half: the oscillator load steps, the
    write-back sites, the reverb ring taps and the rollover. A phase chart
    that showed only the control store would be a chart of half the machine.
    """
    events = []
    for i in range(lo, min(hi, len(lines))):
        code = strip_comment(lines[i])
        for expr in pph_exprs(code):
            events.append({
                "expr": expr,
                "line": i + 1,
                "src": lines[i].strip(),
                "doc": lead_comment(lines, i),
                "where": label,
            })
    return events


# Case-arm labels may cast with a literal width (`7'd4`, `7'(PWORK)`) or a
# named localparam width (`PPH_W'(4)`): the value, not the width, is the key.
ARM_RE = re.compile(r"\s*\w+'(?:d\s*(\d+)|\s*\(([^)]*)\))\s*:")


def case_signal_re(signal):
    return re.compile(r"\s*case\s*\(\s*" + re.escape(signal) + r"\s*\)\s*$")


def parse_phase_requests(lines):
    """Request signal -> phase expression for non-control-store launches.

    A request mux may be driven by a control action, a direct phase pulse, or
    both.  Direct pulses used to be named explicitly in this tool.  Recovering
    any signal whose definition compares `pph` makes renaming or adding such a
    request a source-only change.
    """
    text = "\n".join(strip_comment(line) for line in lines)
    out = {}
    for stmt in text.split(";"):
        exprs = pph_exprs(stmt)
        if not exprs:
            continue
        m = re.search(
            r"(?:^|\n)\s*(?:(?:wire|logic|reg)\b(?:\s+signed)?"
            r"(?:\s*\[[^]]*\])?\s+|assign\s+)"
            r"([a-zA-Z_][a-zA-Z0-9_]*)\s*=", stmt)
        if m and len(set(exprs)) == 1:
            out[m.group(1)] = exprs[0]
    return out


def assignment_definitions(lines):
    """Simple continuous/declaration assignments keyed by their lhs."""
    text = "\n".join(strip_comment(line) for line in lines)
    out = {}
    for stmt in text.split(";"):
        m = re.search(
            r"(?:^|\n)\s*(?:(?:wire|logic|reg)\b(?:\s+signed)?"
            r"(?:\s*\[[^]]*\])?\s+|assign\s+)"
            r"([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.*)$", stmt, re.S)
        if m:
            out[m.group(1)] = m.group(2).strip()
    return out


def signal_phase_exprs(lines, signal):
    """Phase equalities in a signal's transitive assignment cone."""
    definitions = assignment_definitions(lines)
    pending, seen, out = [signal], set(), {}
    while pending:
        name = pending.pop()
        if name in seen or name not in definitions:
            continue
        seen.add(name)
        rhs = definitions[name]
        has_hw_guard = bool(re.search(r"!\s*REALTIME_PREVIEW", rhs))
        has_preview_guard = "REALTIME_PREVIEW" in re.sub(
            r"!\s*REALTIME_PREVIEW", "", rhs)
        scope = ("hw" if has_hw_guard and not has_preview_guard
                 else "preview" if has_preview_guard and not has_hw_guard
                 else "both")
        for expr in pph_exprs(rhs):
            out[expr] = scope
        pending.extend(symbol for symbol in definitions
                       if symbol not in seen
                       and re.search(r"\b" + re.escape(symbol) + r"\b", rhs))
    return out


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
        # Common work can precede a hardware-only side effect in the same arm.
        # PLOSC+4 loads s_eff_a in both variants and s_clr_tog only in hardware.
        if "<=" in body[:has_h.start()]:
            return "both"
        return "hw"
    if has_p and not has_h:
        if "<=" in body[:has_p.start()]:
            return "both"
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
        if not case_signal_re("pph").match(ln):
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


def load_mul_contract():
    """Service arithmetic and slow-domain readiness, read from live RTL.

    This table was transcribed by hand and went stale the moment psg_mulsvc
    gained a 9-iteration mode 3 and a six-step `mul_start_short`: every
    latency the tool reported was then measured against a service that no
    longer existed. tools/psg_mul_model.py already parses the m_cnt load, so
    reuse it and let the RTL be the only source.
    """
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    try:
        import psg_mul_model as M
        psg_txt = "\n".join(read(PSG_SV))
        mp = re.search(r"psg_mulmp\s*#\s*\(\s*\.RADIX_BITS\((\d+)\)",
                       psg_txt)
        if mp:
            # The hardware walk uses the explicit multi-pumped instance. Its
            # arithmetic capacity is measured in FAST-clock steps, while its
            # schedule is bounded by the named acknowledged SLOW-clock gaps.
            radix = int(mp.group(1))
            txt = "\n".join(read(MULMP_SV))
            loads = re.search(
                r"if\s*\(RADIX_BITS\s*==\s*2\)\s*"
                r"req_steps\s*<=\s*(.*?);\s*else\s*"
                r"req_steps\s*<=\s*(.*?);", txt, re.S)
            if not loads:
                raise ValueError("cannot find radix-selected req_steps load")
            body = re.sub(r"\s+", " ", loads.group(1 if radix == 2 else 2))
            sm = re.search(r"mul_start_short\s*\?\s*\d+'d(\d+)", body)
            short = int(sm.group(1)) if sm else M.SHORT_STEPS[radix]
            iters = {int(mode): int(steps) for mode, steps in re.findall(
                r"mul_start_mode\s*==\s*2'd(\d+)\)\s*\?\s*\d+'d(\d+)",
                body)}
            tail = re.search(r":\s*\d+'d(\d+)\s*$", body)
            missing = [mode for mode in range(4) if mode not in iters]
            if not tail or len(missing) != 1:
                raise ValueError(f"cannot parse req_steps default from {body!r}")
            iters[missing[0]] = int(tail.group(1))
            iters = dict(sorted(iters.items()))
            preshift = {3: 1} if radix == 2 else {}
            normal_gap = int(re.search(
                r"localparam\s+int\s+NORMAL_CONSUME_GAP\s*=\s*(\d+)",
                txt).group(1))
            short_gap = int(re.search(
                r"localparam\s+int\s+SHORT_CONSUME_GAP\s*=\s*(\d+)",
                txt).group(1))
            service = "psg_mulmp"
        else:
            iters = {int(k): int(v) for k, v in M.parse_iters().items()}
            radix = int(M.parse_radix_bits())
            short = int(M.SHORT_STEPS[radix])
            preshift = {int(k): int(v) for k, v in M.parse_preshift().items()}
            normal_gap = max(iters.values()) + 1
            short_gap = short + 1
            service = "psg_mulsvc"
    except Exception as e:
        raise RuntimeError(
            "could not derive multiplier service contract; refusing to render "
            f"a schedule with stale latency defaults: {e}") from e
    return (iters, short, radix, preshift, normal_gap, short_gap,
            service)


(MUL_ITERS, SHORT_ITERS, MUL_RADIX_BITS, MUL_PRESHIFT,
 MUL_READY_GAP, SHORT_READY_GAP, MUL_SERVICE) = load_mul_contract()
MUL_WIDTHS = {mode: MUL_RADIX_BITS * steps - MUL_PRESHIFT.get(mode, 0)
              for mode, steps in MUL_ITERS.items()}
SHORT_WIDTH = MUL_RADIX_BITS * SHORT_ITERS


def result_closure(lines):
    """Signals and callables whose value or behavior depends on `m_res`."""
    txt = "\n".join(lines)
    defs = {}
    for m in re.finditer(r"^\s*(?:wire|assign)\s+(?:signed\s*)?"
                         r"(?:\[[^\]]*\]\s*)?([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.*?);\s*$",
                         txt, re.M | re.S):
        defs.setdefault(m.group(1), []).append(m.group(2))

    callables = {}
    start = name = None
    for i, line in enumerate(lines):
        if start is None:
            m = re.match(r"\s*(?:task|function)\b.*?"
                         r"([a-zA-Z_][a-zA-Z0-9_]*)\s*(?:\(|;|$)", line)
            if m:
                start, name = i, m.group(1)
        elif re.match(r"\s*end(?:task|function)\b", line):
            callables[name] = "\n".join(lines[start:i + 1])
            start = name = None

    closure = {"m_res"}
    for _ in range(len(defs) + len(callables) + 1):
        grew = False
        for symbol, bodies in {**defs, **{k: [v] for k, v in callables.items()}}.items():
            if symbol in closure:
                continue
            body = " ".join(bodies)
            if any(re.search(r"\b" + re.escape(source) + r"\b", body)
                   for source in closure):
                closure.add(symbol)
                grew = True
        if not grew:
            break
    return closure


def uses_any(text, symbols):
    return any(re.search(r"\b" + re.escape(symbol) + r"\b", text)
               for symbol in symbols)


def product_consumers(lines, cap_arms, closure=None):
    """Which capture steps read a multiply result, directly or through a wire.

    Scanning for the result port alone misses consumers which read a derived
    wire or call a helper task, so the search follows the combinational and
    callable closure of the result port.
    """
    closure = closure or result_closure(lines)
    out = set()
    for name, a in cap_arms.items():
        if uses_any(a["body"], closure):
            out.add(name)
    return out


def phase_product_consumers(lines, closure=None):
    """Direct phase tests which consume a product outside the CAP case."""
    closure = closure or result_closure(lines)
    out = set()
    for i, line in enumerate(lines):
        exprs = pph_exprs(strip_comment(line))
        if not exprs:
            continue
        body = [line]
        if "begin" in strip_comment(line):
            body = block_body(lines, i, indent_of(line))
        else:
            j = i + 1
            while j < len(lines) and len(body) < 8:
                body.append(lines[j])
                if ";" in strip_comment(lines[j]):
                    break
                j += 1
        # The phase expression itself may name a request signal in the
        # closure; only the statement controlled by it establishes a consume.
        controlled = "\n".join(body)[len(line):]
        inline = strip_comment(line).split(")", 1)[-1]
        if uses_any(inline + "\n" + controlled, closure):
            out.update(exprs)
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
    ternary = re.fullmatch(r".*?\?\s*(.*?)\s*:\s*(.*)", e, re.S)
    if ternary:
        branches = [operand_width(part, widths) for part in ternary.groups()]
        if all(width is not None for width, _kind, _value in branches):
            return max(width for width, _kind, _value in branches), "signal", None
        return None, "unknown", None
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


def selector_name(atom, phase_requests):
    """Canonical action/request name when an atom is a mux selector."""
    atom = strip_outer_parens(atom)
    m = re.fullmatch(r"cap\s*\[\s*(CAP_[A-Z0-9_]+)\s*\]", atom)
    if m:
        return m.group(1)
    return atom if atom in phase_requests else None


def selector_guards(label, phase_requests):
    """Selector -> guards from a boolean case label, via a tiny DNF pass."""
    out = {}
    for term in expression_dnf(label):
        selectors = [selector_name(atom, phase_requests) for atom in term]
        selectors = [name for name in selectors if name]
        if not selectors:
            continue
        guard_atoms = [strip_outer_parens(atom) for atom in term
                       if not selector_name(atom, phase_requests)]
        guard = " && ".join(guard_atoms)
        for name in selectors:
            out.setdefault(name, set()).add(guard)
    return out


def case_block(text, start):
    """One balanced SystemVerilog case block beginning at `start`."""
    depth = 0
    for token in re.finditer(r"\b(case(?:x|z)?|endcase)\b", text[start:]):
        if token.group(1) == "endcase":
            depth -= 1
            if depth == 0:
                return text[start:start + token.end()]
        else:
            depth += 1
    return None


def parse_mul_arms(lines, phase_requests=None):
    """Each multiply arm's guard and the iteration count(s) it launches.

    psg_mulsvc loads m_cnt with an explicit short count or a mode-selected
    one, all read from the RTL above, and decrements once per clock. A request
    issued in phase p therefore leaves m_busy high through p+steps and the
    product is readable in p+steps+1.
    """
    txt = "\n".join(strip_comment(line) for line in lines)
    phase_requests = phase_requests or parse_phase_requests(lines)
    # The request mux has been keyed by dedicated, encoded and one-hot control
    # selectors. Find the `case` that actually drives wmul_start rather than
    # assuming either shape - a tool whose whole claim is that it tracks the
    # RTL must not break when the RTL moves.
    # Naming the case EXPRESSION was itself a transcription, and it broke
    # twice: `case (ctrl_mul)` became `case (ctrl_cap)`, then the one-hot
    # `(* parallel_case *) case (1'b1)`. Identify the block by what it DOES -
    # drive wmul_start - which is the property that actually matters.
    s = None
    for m in re.finditer(r"\bcase\s*\(", txt):
        blk = case_block(txt, m.start())
        if blk is None:
            continue
        if "wmul_start" in blk and "wmul_a" in blk:
            s = blk
            break
    if s is None:
        return {}
    # A request mux may group phases by operand shape, so one boolean label can
    # contain several control actions and direct phase pulses.  Split it into
    # DNF terms and derive each selector's remaining guard; no request name or
    # runtime condition is transcribed here.
    slines = s.splitlines()
    heads = []
    for i, ln in enumerate(slines):
        q = strip_comment(ln).strip()
        if q.startswith("default:"):
            heads.append((i, "default", q.split(":", 1)[1]))
        elif ("cap[" in q.replace(" ", "")
              or any(re.search(r"\b" + re.escape(req) + r"\b", q)
                     for req in phase_requests)
              or re.match(r"(?:\d+'d\d+|\w+'\([^)]*\))\s*:", q)) \
                and re.search(r":\s*(?:begin|if\b.*\bbegin)\s*$", q):
            label, tail = q.split(":", 1)
            heads.append((i, label.strip(), tail.strip()))

    fragments = {}
    for h, (i, label, tail) in enumerate(heads):
        if label == "default":
            continue
        end_i = heads[h + 1][0] if h + 1 < len(heads) else len(slines)
        body = tail + "\n" + "\n".join(slines[i + 1:end_i])
        guards = selector_guards(label, phase_requests)
        ids = list(guards)
        if not ids:
            ids = [int(x) for x in re.findall(r"\d+'d(\d+)", label)]
            if not ids:
                m2 = re.fullmatch(r"\w+'\(([^)]*)\)", label.strip())
                if m2 and re.fullmatch(r"\d+", m2.group(1).strip()):
                    ids = [int(m2.group(1))]
            guards = {x: {""} for x in ids}

        # A direct label can carry its runtime guard after the colon.
        tm = re.match(r"if\s*\((.*?)\)\s*begin", tail)
        if tm:
            direct_guard = compact_expr(tm.group(1))
            for x in ids:
                guards[x] = {
                    " && ".join(v for v in (guard, direct_guard) if v)
                    for guard in guards[x]
                }

        modes = [int(x) for x in re.findall(
            r"wmul_mode\s*=\s*\d+'d(\d+)", body)] or [0]
        frag = {
            "modes": modes,
            "short": bool(re.search(r"wmul_short\s*=\s*1'b1", body)),
            "b_exprs": [b.strip() for b in re.findall(
                r"wmul_b\s*=\s*(.*?);", body, re.S)],
            "a_exprs": [a.strip() for a in re.findall(
                r"wmul_a\s*=\s*(.*?);", body, re.S)],
        }
        for x in ids:
            for guard in guards[x]:
                fragments.setdefault(x, []).append({**frag, "guard": guard})

    arms = {}
    for x, fs in fragments.items():
        variants = []
        seen = set()
        for f in fs:
            key = (f["guard"], tuple(f["modes"]), f["short"],
                   tuple(f["a_exprs"]), tuple(f["b_exprs"]))
            if key not in seen:
                variants.append(f)
                seen.add(key)
        arms[x] = {
            "variants": variants,
            # Retain flattened fields in the JSON for old consumers, but all
            # analysis below uses variants so branch-specific modes stay tied
            # to the source condition which selects them.
            "cond": " || ".join(sorted({f["guard"] for f in variants if f["guard"]})),
            "modes": [m for f in fs for m in f["modes"]],
            "branches": [(f["guard"], f["modes"][0]) for f in variants
                         if f["guard"]],
            "short": any(f["short"] for f in fs),
            "b_exprs": [e for f in fs for e in f["b_exprs"]],
            "a_exprs": [e for f in fs for e in f["a_exprs"]],
        }
    return arms


def atom_polarity(atom):
    atom = strip_outer_parens(compact_expr(atom))
    m = re.fullmatch(r"!\s*([a-zA-Z_][a-zA-Z0-9_]*)", atom)
    if m:
        return m.group(1), False
    m = re.fullmatch(r"(.*?)\s*(==|!=)\s*(.*)", atom)
    if m:
        base = f"{m.group(1).strip()} == {m.group(3).strip()}"
        return base, m.group(2) == "=="
    return atom, True


def derive_profiles(mul_arms, max_dimensions=6):
    """Enumerate runtime profiles from the guards the request mux actually uses."""
    atoms = set()
    for arm in mul_arms.values():
        for variant in arm["variants"]:
            for term in expression_dnf(variant["guard"] or "1'b1"):
                for atom in term:
                    if atom != "1'b1":
                        atoms.add(atom_polarity(atom)[0])
    dims = sorted(atoms)
    if len(dims) > max_dimensions:
        # Exponential profile growth would make the output less useful.  A
        # conservative all-active profile preserves the no-false-slack rule.
        return [{"key": "conservative", "label": "all guarded requests",
                 "values": {}, "conservative": True}], dims
    profiles = []
    for i, bits in enumerate(itertools.product((False, True), repeat=len(dims))):
        values = dict(zip(dims, bits))
        terms = [name if value else f"not ({name})"
                 for name, value in values.items()]
        profiles.append({"key": f"p{i}", "label": ", ".join(terms) or "unconditional",
                         "values": values, "conservative": False})
    return profiles, []


def guard_fires(guard, profile):
    if not guard or profile.get("conservative"):
        return True
    for term in expression_dnf(guard):
        if all(profile["values"].get(atom_polarity(atom)[0])
               == atom_polarity(atom)[1] for atom in term):
            return True
    return False


def active_variants(arm, profile):
    return [variant for variant in arm["variants"]
            if guard_fires(variant["guard"], profile)]


def variant_iters(variant):
    if variant["short"]:
        return {SHORT_ITERS}
    return {MUL_ITERS[mode] for mode in variant["modes"]}


def request_iters(arm, profile=None):
    variants = arm["variants"] if profile is None else active_variants(arm, profile)
    return {iters for variant in variants for iters in variant_iters(variant)}


def variant_ready_gap(variant):
    """Acknowledged slow-clock request-to-consume gap for one request."""
    return SHORT_READY_GAP if variant["short"] else MUL_READY_GAP


def request_ready_gaps(arm, profile=None):
    variants = arm["variants"] if profile is None else active_variants(arm, profile)
    return {variant_ready_gap(variant) for variant in variants}


def variant_products(variant):
    """(A, B, mode, iterations) products described by one guarded arm."""
    modes = variant["modes"] or [0]
    a_exprs = variant["a_exprs"] or [""]
    b_exprs = variant["b_exprs"] or [""]
    count = max(len(a_exprs), len(b_exprs))
    for i in range(count):
        mode = modes[i] if len(modes) == count else max(modes, key=MUL_ITERS.get)
        yield (a_exprs[min(i, len(a_exprs) - 1)],
               b_exprs[min(i, len(b_exprs) - 1)], mode,
               SHORT_ITERS if variant["short"] else MUL_ITERS[mode])


def mul_timeline(phases, mul_arms, profiles):
    """Per phase, which profiles await acknowledged multiply completion.

    This is the measurement that separates a forced latency shadow from
    genuine slack: if the service is provably busy, the phase cannot be
    reclaimed on that path; if it is provably idle, it can.
    """
    for p in phases:
        p["mul_busy"] = []
        p["mul_launch"] = []
    for p in phases:
        arm = mul_arms.get(p["mul"])
        if not p["mul"] or not arm:
            continue
        for prof in profiles:
            active = active_variants(arm, prof)
            if not active:
                continue
            # Parallel-case selectors are mutually exclusive at a phase.  If
            # source conditions overlap, use the longest active latency: that
            # can only understate slack, never invent it.
            iters = max(i for variant in active for i in variant_iters(variant))
            ready_gap = max(variant_ready_gap(variant) for variant in active)
            p["mul_launch"].append({"profile": prof["key"], "iters": iters,
                                    "ready_gap": ready_gap})
            for k in range(p["pph"] + 1,
                           min(p["pph"] + ready_gap, len(phases))):
                phases[k]["mul_busy"].append(prof["key"])
    return phases


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


def load_voice_count():
    """Number of playback slots, from the shared RTL contract."""
    count = parse_integer_params(read(COMMON_SVH)).get("PSG_NV")
    if not isinstance(count, int) or count <= 0:
        raise RuntimeError("could not derive PSG_NV from rtl/psg_common.svh")
    return count


def extract_walk():
    lines = read(WALK_SV)
    g = load_ctrl()
    raw_params = parse_walk_params(lines)
    integer_params = parse_integer_params(lines)
    caps = parse_cap_enum(lines)
    missing = sorted({"PLOSC", "PWORK", "PFOLD", "PSTOR", "PLAST"}
                     - set(raw_params))
    if missing:
        raise RuntimeError("could not extract walk parameters: "
                           + ", ".join(missing))
    if not caps:
        raise RuntimeError("could not extract any CAP_* control actions")
    decode_cap, encoding = cap_decoder(lines, g.build(), caps)
    cap_flags = parse_cap_flags(lines, caps)
    arms = parse_cap_arms(lines)
    blocks = parse_pph_cases(lines)
    phase_requests = parse_phase_requests(lines)
    extra_write_exprs = signal_phase_exprs(lines, "state_sample_we")

    words = g.build()
    # The generator's names for the multiply arms, so the chart can label a
    # product request with what it computes rather than an opcode number.
    mul_doc = {}
    for ln in read(os.path.join(ROOT, "tools", "gen_psg_ctrl.py")):
        for m in re.finditer(r"(\d+)\s+W(\d+)\s+\(([^)]*)\)", ln):
            mul_doc[int(m.group(1))] = f"W{m.group(2)}: {m.group(3)}"

    preview_params = {name: resolve_pph(value["preview"], integer_params)
                      for name, value in raw_params.items()}
    if any(value is None for value in preview_params.values()):
        bad = sorted(name for name, value in preview_params.items() if value is None)
        raise RuntimeError("could not resolve preview walk parameters: "
                           + ", ".join(bad))
    params = {
        "hw": {"PLOSC": g.PLOSC, "PWORK": g.PWORK, "PFOLD": g.PFOLD,
               "PSTOR": g.PSTOR, "PLAST": g.PLAST},
        "preview": preview_params,
    }
    # The RTL's hardware arm names a constant; the generator holds its value.
    # If those ever disagree the chart is drawing a schedule nothing runs.
    for k, v in raw_params.items():
        want = params["hw"].get(k)
        source_value = resolve_pph(v["hw"], integer_params)
        if source_value is not None and want is not None and source_value != want:
            print(f"warning: {k} is {v['hw']} in psg_walk.sv but "
                  f"{want} in gen_psg_ctrl.py", file=sys.stderr)

    events = parse_pph_events(lines, 0, len(lines), "walk")

    mul_arms = parse_mul_arms(lines, phase_requests)
    if not mul_arms:
        raise RuntimeError("could not find the walk multiplier request mux")
    phase_requests = {name: expr for name, expr in phase_requests.items()
                      if name in mul_arms}
    profiles, profile_overflow = derive_profiles(mul_arms)
    for arm in mul_arms.values():
        if profiles and all(active_variants(arm, profile) for profile in profiles):
            arm["cond"] = ""
    closure = result_closure(lines)
    consumers = product_consumers(lines, arms, closure)
    direct_consumers = phase_product_consumers(lines, closure)

    schedules = {}
    for variant in ("hw", "preview"):
        pm = params[variant]
        phase_env = {**integer_params, **pm}
        n = pm["PLAST"] + 1
        phases = [{"pph": p, "off": p - pm["PWORK"], "load": [], "sched": [],
                   "events": [], "cap": None, "mul": 0, "mul_doc": "",
                   "flags": [], "word": None} for p in range(n)]

        # The control store drives only the hardware schedule's work phases.
        if variant == "hw":
            for p in range(n):
                w = words[p] if p < len(words) else 0
                names = decode_cap(w)
                mul_v = (w >> 5) & 0xF if encoding == "encoded" else 0
                ph = phases[p]
                ph["word"] = w
                name = names[0] if names else None
                # A phase launches a product if one of its actions appears in
                # the request mux; the legacy MUL_SEL field is the fallback for
                # older control words.
                launcher = next((nm for nm in names if nm in mul_arms), None)
                ph["mul"] = launcher or (mul_v if mul_v else None)
                ph["mul_doc"] = mul_doc.get(mul_v, "") or (
                    describe_arm(mul_arms.get(ph["mul"])) if ph["mul"] else "")
                if name:
                    ph["cap"] = name
                    for nm in names:
                        ph["sched"].append({"kind": "cap", "label": nm,
                                            "detail": arms.get(nm, {})})
                # The six explicit flag bits became aliases when the word went
                # one-hot; the signals each action drives are read from the
                # RTL instead of from a transcribed bit list.
                for nm in names:
                    ph["flags"].extend(cap_flags.get(nm, []))

            # Direct phase requests live outside the control ROM but occupy
            # the same physical service. Their signal definitions provide the
            # phase, so adding or renaming one needs no visualizer edit.
            for name, expr in phase_requests.items():
                if name not in mul_arms:
                    continue
                p = resolve_pph(expr, phase_env)
                if p is None:
                    raise RuntimeError(
                        f"could not resolve direct request {name} at {expr}")
                if 0 <= p < n:
                    phases[p]["mul"] = name
                    phases[p]["mul_doc"] = describe_arm(mul_arms[name])

        for blk in blocks:
            if blk["variant"] not in ("both", variant):
                continue
            for arm in blk["arms"]:
                if arm["variant"] not in ("both", variant):
                    continue
                p = resolve_pph(arm["key"], phase_env)
                if p is None or not (0 <= p < n):
                    continue
                lane = "load" if blk["variant"] == "both" else "sched"
                phases[p][lane].append({
                    "kind": "arm", "key": arm["key"], "line": arm["line"],
                    "doc": arm["doc"], "body": arm["body"],
                })

        for e in events:
            p = resolve_pph(e["expr"], phase_env)
            if p is not None and 0 <= p < n:
                phases[p]["events"].append(e)

        schedules[variant] = {"params": pm, "phases": phases,
                              "n": n,
                              "write_phases": sorted(
                                  set(range(pm["PSTOR"],
                                            min(pm["PSTOR"] + pm["PLOSC"], n)))
                                  | {phase for expr, scope in extra_write_exprs.items()
                                     if scope in ("both", variant)
                                     if (phase := resolve_pph(expr, phase_env))
                                     is not None and 0 <= phase < n})}

    for variant, s in schedules.items():
        mul_timeline(s["phases"], mul_arms, profiles)
        phase_env = {**integer_params, **s["params"]}
        direct = {resolve_pph(expr, phase_env) for expr in direct_consumers}
        for p in s["phases"]:
            p["consumes"] = ((p["cap"] in consumers if p["cap"] else False)
                              or p["pph"] in direct)

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
            "consumers": sorted(consumers), "profiles": profiles,
            "profile_overflow": profile_overflow,
            "phase_requests": phase_requests,
            "encoding": encoding, "mul_iters": MUL_ITERS,
            "mul_service": MUL_SERVICE,
            "mul_radix_bits": MUL_RADIX_BITS,
            "mul_ready_gap": MUL_READY_GAP,
            "mul_short_ready_gap": SHORT_READY_GAP,
            "voice_count": load_voice_count()}


# ----------------------------------------------------------------------
# The tick sequencer's FSM
# ----------------------------------------------------------------------
def cluster_hint(doc):
    """Optional semantic override embedded in a state's leading RTL comment.

    `// psg-viz: cluster publication` is deliberately the only source-side
    convention. In its absence the clusters come solely from graph topology.
    """
    match = re.search(r"(?:psg-viz|viz)\s*:\s*cluster\s+([^\n]+)",
                      doc or "", re.I)
    return compact_expr(match.group(1)) if match else ""


def parse_enum(lines):
    text = "\n".join(lines)
    m = re.search(r"typedef\s+enum\s+logic\s*"
                  r"\[\s*(\d+)\s*:\s*(\d+)\s*\]\s*"
                  r"\{(.*?)\}\s*sst_t\s*;", text, re.S)
    if not m:
        return [], None
    body = re.sub(r"//[^\n]*", "", m.group(3))
    width = abs(int(m.group(1)) - int(m.group(2))) + 1
    return [s.strip() for s in body.split(",") if s.strip()], width


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
        if case_signal_re("sst").match(ln):
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
            if case_signal_re("sst").match(ln) and case_head(lines, i):
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
    states, state_bits = parse_enum(lines)
    if not states or state_bits is None:
        raise RuntimeError("could not extract the sst_t sequencer enum")
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
        a = arms.get(s, {})
        doc = a.get("doc", "")
        nodes.append({
            "name": s, "line": a.get("line"), "doc": doc,
            "cluster_hint": cluster_hint(doc),
            "body": "\n".join(trim_trailing_comments(a.get("body", []))),
            "tables": tables.get(s, {}),
        })
    return {
        "states": nodes,
        "transitions": transitions,
        "raw_assign_count": raw,
        "unplaced_lines": outside,
        "extracted_count": len(got),
        "state_bits": state_bits,
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


def straight_runs(seq, min_length=4):
    """Maximal unconditional FSM runs, independent of enum ordering."""
    outd, ind = {}, {}
    for transition in seq["transitions"]:
        outd.setdefault(transition["from"], []).append(transition)
        ind.setdefault(transition["to"], []).append(transition)

    def extend(start):
        run = [start]
        cur = start
        while (len(outd.get(cur, [])) == 1
               and not outd[cur][0]["guards"]):
            nxt = outd[cur][0]["to"]
            if len(ind.get(nxt, [])) != 1 or nxt in run:
                break
            run.append(nxt)
            cur = nxt
        return run

    names = sorted(node["name"] for node in seq["states"])
    # A node with one unconditional predecessor is inside a run, not its
    # beginning. Starting only at graph boundaries makes the result invariant
    # to how the source enum happens to order its members.
    starts = [name for name in names
              if not (len(ind.get(name, [])) == 1
                      and not ind[name][0]["guards"])]
    seen, runs = set(), []
    for start in starts:
        if start in seen:
            continue
        run = extend(start)
        seen.update(run)
        if len(run) >= min_length:
            runs.append(run)

    # A closed unconditional cycle has no boundary. It is still a real run,
    # so cover any nodes which the boundary pass could not reach.
    for start in names:
        if start in seen:
            continue
        run = extend(start)
        seen.update(run)
        if len(run) >= min_length:
            runs.append(run)
    return sorted(runs, key=lambda run: (-len(run), tuple(run)))


# Latencies other than the multiply. These are source contracts, not defaults:
# if either module stops exposing the shape the analyser understands, rendering
# fails instead of silently classifying phases with yesterday's latency.
def state_read_latency(lines):
    assignments = [compact_expr(rhs) for rhs in re.findall(
        r"\bstate_q\s*<=\s*(.*?);", "\n".join(lines), re.S)
        if "state_m" in rhs]
    if assignments != ["state_m[state_ra]"]:
        raise RuntimeError(
            "could not derive the state-memory read latency from the direct "
            "state_q <= state_m[state_ra] register")
    return 1


def wave_pipeline_stages(lines):
    words = {"one": 1, "two": 2, "three": 3, "four": 4,
             "five": 5, "six": 6, "seven": 7, "eight": 8}
    text = "\n".join(lines)
    match = re.search(
        r"//\s*([0-9]+|one|two|three|four|five|six|seven|eight)-stage\s+"
        r"computed-wave\s+pipeline\b", text, re.I)
    if not match:
        raise RuntimeError(
            "could not derive the computed-wave pipeline depth from psg_wave")
    token = match.group(1).lower()
    return int(token) if token.isdigit() else words[token]


STATE_READ_LATENCY = state_read_latency(read(STATE_MEM_SV))
WAVE_CONE_STAGES = wave_pipeline_stages(read(WAVE_SV))

# Phases whose holder was established by reading the RTL rather than derived.
# Each entry carries its evidence so it can be re-checked, and anything NOT
# listed that ends up unexplained is reported - a hand annotation must not be
# able to hide a phase it no longer describes.
AUDITED = {}


def attribute_pipelines(phases, params, variant, write_phases):
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
            if f.lower().startswith("iss_") or f.lower().startswith("dq_old"):
                for k in range(i + 1, min(i + 1 + WAVE_CONE_STAGES, n)):
                    phases[k]["holders"].append(f"wave cone ({f} stage)")

    lo, hi = params["PSTOR"], params["PSTOR"] + params["PLOSC"]
    for i in write_phases:
        if 0 <= i < n:
            detail = (f"oscillator write-back word {i - lo}"
                      if lo <= i < hi else "additional scheduled write-back")
            phases[i]["holders"].append(f"record port ({detail})")

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
        for gap in sorted(request_ready_gaps(arm)):
            ready = p["pph"] + gap
            nxt = next((c for c in consumers if c >= ready), None)
            if nxt is None:
                continue
            for k in range(ready, nxt):
                phases[k]["holders"].append(
                    f"completed {p['mul']} product held for consume at pph {nxt}")
    return phases


def classify(phases, profiles):
    """Choose one primary visual class while retaining overlapping evidence.

    Work, multiplier occupancy and record/wave/product holders can overlap.
    `klass` supplies a single colour for the lane chart; summaries must inspect
    the underlying fields rather than treating this precedence as an activity
    count.
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


def profile_attribution(phases, profiles):
    """Action-free service-idle phases, split into held and unattributed."""
    rows = []
    for profile in profiles:
        idle = [phase for phase in phases
                if not phase_busy(phase)
                and profile["key"] not in phase.get("mul_busy", [])]
        held = [phase for phase in idle if phase.get("holders")]
        unattributed = [phase for phase in idle if not phase.get("holders")]
        rows.append({"profile": profile, "idle": idle, "held": held,
                     "unattributed": unattributed})
    return rows


SV_RESERVED = {
    "always", "always_comb", "always_ff", "assign", "begin", "case",
    "default", "else", "end", "endcase", "for", "if", "input", "logic",
    "signed", "task", "wire", "unsigned", "posedge", "negedge",
}


def sv_symbols(expr):
    """Signal-like identifiers in a small SystemVerilog expression."""
    return {token for token in re.findall(r"\b[A-Za-z_][A-Za-z0-9_$]*\b",
                                           expr or "")
            if token not in SV_RESERVED and token not in ("d", "h", "b", "x")
            and not token.startswith("CAP_") and token != "m_res"}


def statement_io(body):
    """Definitions and uses in the assignment statements of one phase arm."""
    clean = re.sub(r"//[^\n]*", "", body or "")
    definitions, uses = set(), set()
    assignment = re.compile(
        r"\b([A-Za-z_][A-Za-z0-9_$]*(?:\s*\[[^\]]+\])?)\s*"
        r"(?:<=|(?<![<>=!])=(?!=))\s*(.*?);", re.S)
    for match in assignment.finditer(clean):
        lhs = re.match(r"[A-Za-z_][A-Za-z0-9_$]*", match.group(1)).group(0)
        definitions.add(lhs)
        uses.update(sv_symbols(match.group(2)))
    return definitions, uses


def build_dependency_graph(schedule, mul_arms, profiles):
    """Build a phase-level read/compute/multiply/consume/write dataflow graph.

    Assignment edges are discovered from the bodies already extracted for the
    schedule. Multiplier result edges use the service contract, and record
    lifetime edges pair the source-derived read stream with the write window.
    """
    nodes = []
    by_phase = {}
    serial = 0
    all_profiles = [profile["key"] for profile in profiles]

    def add_node(kind, phase, label, body="", detail="", profile_keys=None):
        nonlocal serial
        definitions, uses = statement_io(body)
        node = {
            "id": f"{kind}-{phase}-{serial}",
            "kind": kind,
            "phase": phase,
            "label": label,
            "detail": detail,
            "defs": sorted(definitions),
            "uses": sorted(uses),
            "profiles": sorted(profile_keys if profile_keys is not None
                               else all_profiles),
        }
        serial += 1
        nodes.append(node)
        by_phase.setdefault(phase, []).append(node)
        return node

    for phase in schedule["phases"]:
        pph = phase["pph"]
        for entry in phase.get("load", []):
            add_node("read", pph,
                     f"record read {entry.get('key', pph)} lands",
                     entry.get("body", ""), entry.get("doc", ""))

        action_nodes = []
        for entry in phase.get("sched", []):
            if entry.get("kind") == "cap":
                detail = entry.get("detail") or {}
                body = detail.get("body", "")
                doc = detail.get("doc", "") or detail.get("inline", "")
                label = entry.get("label", f"work at {pph}")
            else:
                body = entry.get("body", "")
                doc = entry.get("doc", "")
                label = f"case {entry.get('key', pph)}"
            kind = "consume" if phase.get("consumes") else "compute"
            action_nodes.append(add_node(kind, pph, label, body, doc))

        if phase.get("mul"):
            arm = mul_arms.get(phase["mul"], {})
            operands = " ".join(arm.get("a_exprs", []) + arm.get("b_exprs", []))
            profile_keys = [launch["profile"]
                            for launch in phase.get("mul_launch", [])]
            node = add_node("multiply", pph,
                            phase.get("mul_doc") or str(phase["mul"]),
                            detail=f"request {phase['mul']}",
                            profile_keys=profile_keys or all_profiles)
            node["uses"] = sorted(sv_symbols(operands))
            node["arm"] = phase["mul"]

        if phase.get("consumes") and not action_nodes:
            add_node("consume", pph, "consume multiplier result",
                     detail="m_res result closure")

    for phase in schedule["write_phases"]:
        add_node("write", phase, "record write-back",
                 detail="source-derived state_sample_we window")

    rank = {"read": 0, "compute": 1, "multiply": 2,
            "consume": 3, "write": 4}
    nodes.sort(key=lambda node: (node["phase"], rank[node["kind"]], node["id"]))
    edges = {}

    def add_edge(source, target, kind, labels, profile_keys=None):
        if source == target:
            return
        key = (source, target, kind)
        edge = edges.setdefault(key, {
            "from": source, "to": target, "kind": kind,
            "labels": set(), "profiles": set(),
        })
        edge["labels"].update(labels if isinstance(labels, (set, list, tuple))
                              else [labels])
        edge["profiles"].update(profile_keys or all_profiles)

    last_definition = {}
    for node in nodes:
        for symbol in node["uses"]:
            if symbol in last_definition:
                add_edge(last_definition[symbol], node["id"], "data", symbol,
                         node["profiles"])
        for symbol in node["defs"]:
            last_definition[symbol] = node["id"]

    consume_nodes = [node for node in nodes if node["kind"] == "consume"]
    for node in (candidate for candidate in nodes
                 if candidate["kind"] == "multiply"):
        arm = mul_arms.get(node.get("arm"), {})
        for gap in sorted(request_ready_gaps(arm)):
            ready = node["phase"] + gap
            target = next((candidate for candidate in consume_nodes
                           if candidate["phase"] >= ready), None)
            if target:
                add_edge(node["id"], target["id"], "product",
                         f"acknowledged product ready +{gap}", node["profiles"])

    reads = [node for node in nodes if node["kind"] == "read"]
    lo = schedule["params"]["PSTOR"]
    hi = lo + schedule["params"]["PLOSC"]
    writes = [node for node in nodes if node["kind"] == "write"
              and lo <= node["phase"] < hi]
    for source, target in zip(reads[:len(writes)], writes):
        add_edge(source["id"], target["id"], "record", "record lifetime")

    packed_edges = []
    for edge in edges.values():
        packed_edges.append({
            **edge,
            "labels": sorted(edge["labels"]),
            "profiles": sorted(edge["profiles"]),
        })
    packed_edges.sort(key=lambda edge: (edge["from"], edge["to"], edge["kind"]))
    return {
        "nodes": nodes,
        "edges": packed_edges,
        "kinds": ["read", "compute", "multiply", "consume", "write"],
    }


def cycle_accounting(walk):
    """Mutually exclusive phase disposition plus the two structural floors."""
    accounting = {}
    for variant, schedule in walk["schedules"].items():
        phases = schedule["phases"]
        profiles = walk["profiles"] if any(p["mul"] for p in phases) else [{
            "key": "unconditional", "label": "unconditional",
            "values": {}, "conservative": False,
        }]
        reads = sum(bool(phase["load"]) for phase in phases)
        writes = len(schedule["write_phases"])
        rows = []
        for profile in profiles:
            mul_cost = 0
            for phase in phases:
                arm = walk["mul_arms"].get(phase["mul"])
                if not phase["mul"] or not arm:
                    continue
                gaps = request_ready_gaps(arm, profile)
                if gaps:
                    mul_cost += max(gaps)
            serial_floor = reads + max(writes, mul_cost)
            overlapped_floor = max(reads, writes, mul_cost)
            occupied, conditional, blocked, unattributed = [], [], [], []
            for phase in phases:
                if phase_busy(phase) or profile["key"] in phase.get("mul_busy", []):
                    occupied.append(phase["pph"])
                elif phase.get("holders"):
                    blocked.append(phase["pph"])
                elif phase.get("mul_busy"):
                    conditional.append(phase["pph"])
                else:
                    unattributed.append(phase["pph"])
            transformations = []
            if conditional:
                transformations.append("guarded phase jump")
            if blocked:
                transformations.append("capture or retime dependency holder")
            if unattributed:
                transformations.append("prove safe, then remove")
            if serial_floor > overlapped_floor:
                transformations.append("cross-slot load/compute pipelining")
            rows.append({
                "profile": profile,
                "scheduled": schedule["n"],
                "serial_floor": serial_floor,
                "overlapped_floor": overlapped_floor,
                "occupied": occupied,
                "conditional": conditional,
                "blocked": blocked,
                "unattributed": unattributed,
                "transformations": transformations,
            })
        accounting[variant] = rows
    return accounting


def analyse(model):
    walk, seq = model["walk"], model["seq"]
    out = []
    profiles = walk["profiles"]
    voices = walk["voice_count"]
    for variant, S in walk["schedules"].items():
        attribute_pipelines(S["phases"], S["params"], variant,
                            S["write_phases"])
        attribute_ready_products(S["phases"], walk["mul_arms"])
        classify(S["phases"], profiles)
    walk["cycle_accounting"] = cycle_accounting(walk)

    # ---- 1. request-to-consume slack, measured ------------------------
    # The one question worth asking of a latency shadow: is it longer than
    # the service needs? The multi-pumped core iterates in the fast domain,
    # but the walker may consume only after the returned acknowledge's named
    # slow-domain gap.
    S = walk["schedules"]["hw"]
    cons = sorted(p["pph"] for p in S["phases"] if p.get("consumes"))
    rows, worst = [], 0
    for p in S["phases"]:
        arm = walk["mul_arms"].get(str(p["mul"])) or walk["mul_arms"].get(p["mul"])
        if not p["mul"] or not arm:
            continue
        steps = "/".join(str(value) for value in sorted(request_iters(arm)))
        for gap in sorted(request_ready_gaps(arm)):
            ready = p["pph"] + gap
            nxt = [c for c in cons if c >= ready]
            slack = (nxt[0] - ready) if nxt else None
            worst = max(worst, slack or 0)
            rows.append((p["pph"], p["mul"], steps, gap, ready,
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
            "latency model": (f"{MUL_SERVICE} closed-loop acknowledge: "
                              f"normal request+{MUL_READY_GAP}, "
                              f"short request+{SHORT_READY_GAP}"),
            "fast iterations by mode": ", ".join(f"mode {k}={v}"
                                                 for k, v in MUL_ITERS.items()),
            "fast short iterations": SHORT_ITERS,
            "consuming phases": ", ".join(str(c) for c in cons),
            "max slack found": worst,
        },
        "body": "Each row is a request phase, its fast-core iteration count, "
                "the acknowledged slow-clock gap, the phase the product is "
                "first readable, and the phase "
                "that consumes it. The gaps in the schedule are the service "
                "and CDC handshake completing — they are not reschedulable "
                "without changing that boundary.\n\n"
                "Consumers are found over the combinational and helper-task "
                "closure of m_res; a direct-name scan would miss derived "
                "consumers and score a tight schedule as slack.",
        "table": {"label": "measured per request path",
                  "cols": ["req", "arm", "fast steps", "ready gap", "ready",
                           "consumed", "slack"],
                  "rows": [[a, b, c, d, e, "-" if f is None else f,
                            "-" if g is None else g]
                           for a, b, c, d, e, f, g in rows]},
        "refs": [{"kind": "phase", "variant": "hw", "key": r[0],
                  "label": f"pph {r[0]}"} for r in rows],
    })

    # ---- 1b. issued service shape vs operand width --------------------
    # A step retires MUL_RADIX_BITS bits, and an odd-width compatibility mode
    # may pre-shift B.  Comparing raw step counts with operand bits worked only
    # for radix-2 and silently became nonsense when the implementation moved
    # to radix-4. Derive each mode's actual capacity from the live service.
    widths = walk["signal_widths"]
    rows, failures, range_proofs, unknown = [], [], [], 0
    for p in S["phases"]:
        arm = walk["mul_arms"].get(p["mul"])
        if not p["mul"] or not arm:
            continue
        seen_products = set()
        for variant in arm["variants"]:
            for _a, expr, mode, steps in variant_products(variant):
                key = (variant["guard"], expr, mode, steps, variant["short"])
                if key in seen_products:
                    continue
                seen_products.add(key)
                bits, kind, _ = operand_width(expr, widths)
                capacity = SHORT_WIDTH if variant["short"] else MUL_WIDTHS[mode]
                margin = capacity - bits if bits is not None else None
                service = "short" if variant["short"] else f"mode {mode}"
                rows.append([p["pph"], p["mul"], variant["guard"] or "always",
                             expr[:30], bits or "?", kind, service, steps,
                             capacity, margin if margin is not None else "?"])
                if margin is None:
                    unknown += 1
                elif margin < 0:
                    target = failures if kind == "constant" else range_proofs
                    target.append((p["pph"], p["mul"], expr, margin))

    used_modes = sorted({mode for arm in walk["mul_arms"].values()
                         for variant in arm["variants"]
                         for mode in variant["modes"]})
    measure = {
        "service radix": f"{1 << MUL_RADIX_BITS} "
                         f"({MUL_RADIX_BITS} multiplier bits per step)",
        "mode shapes": ", ".join(
            f"{mode}: {MUL_ITERS[mode]} steps / {MUL_WIDTHS[mode]} bits"
            for mode in sorted(MUL_ITERS)),
        "short shape": f"{SHORT_ITERS} steps / {SHORT_WIDTH} bits",
        "issued modes": ", ".join(map(str, used_modes)),
        "operands with unknown width": unknown,
        "constant operands too wide for issued shape": len(failures),
        "declared widths needing a range proof": len(range_proofs),
    }
    out.append({
        "id": "mul-width",
        "area": "walk",
        "title": (f"{len(failures)} constant multiplier operands exceed "
                  "their issued service shape"
                  if failures else
                  f"{len(range_proofs)} multiplier operands need a range "
                  "proof below their declared width"
                  if range_proofs else
                  "every measurable multiplier operand fits its issued service shape"),
        "measure": measure,
        "body": "Capacity is radix bits times service steps, minus any B "
                "pre-shift used to preserve a legacy landing. Constants are "
                "exact; a too-wide constant is a failure. Signal rows use "
                "declared width, so a negative margin asks for a range proof "
                "rather than claiming truncation. Complex expressions stay unknown rather "
                "than being assigned a guessed width. This is a fit audit, "
                "not a claim that spare capacity can shorten the fixed schedule.",
        "table": {"label": "measured per issued product",
                  "cols": ["pph", "arm", "guard", "B operand", "bits", "kind",
                           "service", "steps", "capacity", "margin"],
                  "rows": rows},
        "refs": [{"kind": "phase", "variant": "hw", "key": r[0],
                  "label": f"pph {r[0]}"} for r in rows],
    })

    # ---- 1c. the floor: how short could the visit be? -----------------
    # A resource floor, not a wish. Two structural limits are certain:
    #   - the record store has ONE synchronous read site, so N record words
    #     cost at least N clocks;
    #   - there is ONE multiply service, so the products a profile launches
    #     cost at least their acknowledged slow-domain gaps whether or not they are
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
        writes = len(Sv["write_phases"])
        rows = []
        schedule_profiles = profiles if any(p["mul"] for p in ph) else [{
            "key": "unconditional", "label": "unconditional",
            "values": {}, "conservative": False,
        }]
        for prof in schedule_profiles:
            mul_cost = 0
            for p in ph:
                arm = walk["mul_arms"].get(p["mul"])
                if not p["mul"] or not arm:
                    continue
                gaps = request_ready_gaps(arm, prof)
                if not gaps:
                    continue
                mul_cost += max(gaps)
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
                "playback slots": voices,
                "full-path headroom vs the serial floor":
                    f"{Sv['n'] - ser} phases/slot = "
                    f"{(Sv['n']-ser)*voices} phase positions/sample",
                "full-path headroom vs the overlapped floor":
                    f"{Sv['n'] - ovl} phases/slot = "
                    f"{(Sv['n']-ovl)*voices} phase positions/sample",
                "duration scope": "nominal full path; phase jumps can shorten "
                                  "it and repeated stall cycles can lengthen it",
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
                    "tool deliberately does not answer that: proving it needs "
                    "a path-sensitive audit of where each request's operands "
                    "come from. These are phase-position bounds for the full "
                    "path, not a trace duration: control-flow jumps and cycles "
                    "which repeat under a stall sit outside this arithmetic.",
            "table": {"label": "measured per runtime profile",
                      "cols": ["profile", "reads", "writes", "multiply clocks",
                               "serial floor", "overlapped floor", "scheduled",
                               "budget (serial)", "budget (overlapped)"],
                      "rows": rows},
            "refs": [],
        })

    # ---- 2. schedule occupancy, retaining overlapping activities -------
    for variant, title in (("hw", "hardware"), ("preview", "preview")):
        S = walk["schedules"][variant]
        ph = S["phases"]
        schedule_profiles = profiles if any(p["mul"] for p in ph) else [{
            "key": "unconditional", "label": "unconditional",
            "values": {}, "conservative": False,
        }]
        action_phases = sum(phase_busy(p) for p in ph)
        mul_phases = sum(bool(p.get("mul_busy")) for p in ph)
        all_keys = {profile["key"] for profile in schedule_profiles}
        mul_all = sum(set(p.get("mul_busy", [])) >= all_keys for p in ph)
        holder_phases = sum(bool(p.get("holders")) for p in ph)
        attribution = profile_attribution(ph, schedule_profiles)
        max_unattributed = max(len(row["unattributed"])
                               for row in attribution)
        unattributed_pph = sorted({p["pph"] for row in attribution
                                   for p in row["unattributed"]})
        out.append({
            "id": f"occupancy-{variant}",
            "area": "walk",
            "title": f"{title} full path: {action_phases} action phases, "
                     f"{mul_phases} with multiplier activity, "
                     f"{holder_phases} with dependency holders, and at most "
                     f"{max_unattributed} unattributed per profile",
            "measure": {
                "full-path phase positions per slot": S["n"],
                "playback slots": voices,
                "nominal full-path phase positions/sample": S["n"] * voices,
                "phases carrying scheduled actions": action_phases,
                "phases with multiplier activity on any profile": mul_phases,
                "phases with multiplier activity on every profile": mul_all,
                "phases with record/wave/product holders": holder_phases,
                "maximum unattributed phases per profile": max_unattributed,
                "duration scope": "phase positions, not a trace; jumps shorten "
                                  "the path and stalls repeat positions",
            },
            "body": "These activity counts deliberately overlap: a phase can "
                    "write a record while the multiplier is busy, or carry an "
                    "action while a wave result advances through its pipeline. "
                    "They must not be added together.\n\n"
                    "The per-profile table asks the narrower question needed "
                    "for optimization: after removing scheduled actions and "
                    "multiplier occupancy for that path, is the phase still "
                    "held by a record, wave, or completed-product dependency? "
                    "Only the remainder is unattributed, and even that is an "
                    "upper bound rather than proven reclaimable time. Full-path "
                    "phase positions are not runtime clocks when the RTL skips "
                    "ahead or repeats a position under a stall.",
            "table": {
                "label": "attribution by runtime profile",
                "cols": ["profile", "action-free + service-idle", "held elsewhere",
                         "unattributed", "unattributed phases"],
                "rows": [[row["profile"]["label"], len(row["idle"]),
                          len(row["held"]), len(row["unattributed"]),
                          ", ".join(str(p["pph"]) for p in row["unattributed"])
                          or "none"] for row in attribution],
            },
            "refs": [{"kind": "phase", "variant": variant, "key": pph,
                      "label": f"pph {pph}"} for pph in unattributed_pph],
        })

    # ---- 2. phases whose product is runtime-gated ---------------------
    S = walk["schedules"]["hw"]
    gated = [p for p in S["phases"] if p["mul"] and p.get("mul_guard")]
    by_cond = {}
    for p in gated:
        by_cond.setdefault(p["mul_guard"], []).append(p)
    if gated:
        attribution = profile_attribution(S["phases"], profiles)
        max_unattributed = max(len(row["unattributed"])
                               for row in attribution)
        measure = {
            "guarded request phases": len(gated),
            "service steps suppressed when inactive": ", ".join(
                f"pph {p['pph']}: {max(request_iters(walk['mul_arms'][p['mul']]))}"
                for p in gated),
        }
        measure.update({f"gated on `{c}`": ", ".join(f"pph {p['pph']}" for p in v)
                        for c, v in by_cond.items()})
        if walk["profile_overflow"]:
            measure["guards conservatively collapsed"] = ", ".join(
                walk["profile_overflow"])
        out.append({
            "id": "gated-mul",
            "area": "walk",
            "title": f"{len(gated)} of "
                     f"{sum(1 for p in S['phases'] if p['mul'])} multiply "
                     "requests is runtime-gated; "
                     + (f"up to {max_unattributed} action-free service-idle "
                        "phases remain unattributed"
                        if max_unattributed else
                        "every action-free service-idle phase is held by "
                        "another dependency"),
            "measure": measure,
            "body": "The request mux gates these arms, so the multiply service "
                    "is NOT occupied when the condition is false — but the "
                    "control store is indexed by phase alone, so the phase and "
                    "the latency shadow behind it elapse either way. The "
                    "fixed timetable is the union of those guarded paths.\n\n"
                    "Service-idle is not the same as reclaimable: the record "
                    "write window, wave pipeline, or a completed product may "
                    "still hold the position. The table separates those known "
                    "holders from the genuinely unattributed remainder before "
                    "suggesting a data-dependent skip.",
            "table": {
                "label": "attribution by runtime profile",
                "cols": ["profile", "action-free + service-idle", "held elsewhere",
                         "unattributed"],
                "rows": [[row["profile"]["label"], len(row["idle"]),
                          len(row["held"]), len(row["unattributed"])]
                         for row in attribution],
            },
            "refs": [{"kind": "phase", "variant": "hw", "key": p["pph"],
                      "label": f"pph {p['pph']} — {p['mul_doc']}"}
                     for p in gated],
        })

    # ---- 3. encoding headroom ----------------------------------------
    nst = len(seq["states"])
    state_bits = seq.get("state_bits") or max(1, (nst - 1).bit_length())
    state_capacity = 1 << state_bits
    control_width = walk["signal_widths"].get("cap", max(
        [1, *(p["word"].bit_length() for p in S["phases"] if p["word"])]))
    used_control_bits = sorted({bit for p in S["phases"] if p["word"]
                                for bit in range(control_width)
                                if p["word"] & (1 << bit)})
    spare_control_bits = sorted(set(range(control_width)) - set(used_control_bits))
    launches = sum(1 for p in S["phases"] if p["mul"])
    live = walk["params"]["hw"]["PLAST"] + 1
    nonzero = sum(1 for p in S["phases"] if p["word"])
    out.append({
        "id": "encoding",
        "area": "both",
        "title": f"the FSM state register uses {nst} of {state_capacity} encodings",
        "measure": {
            "FSM states": f"{nst} (sst is {state_bits} bits, "
                          f"{state_capacity} encodings)",
            "spare state encodings": state_capacity - nst,
            "control encoding": walk["encoding"],
            "named control actions": len(walk["caps"]),
            "product launch phases": launches,
            "control-store words with any work":
                f"{nonzero} of {live} live phases",
            "control-word bits used": ", ".join(map(str, used_control_bits)) or "none",
            "control-word bits spare": ", ".join(map(str, spare_control_bits)) or "none",
        },
        "body": "Capacities and spare bits are derived from the live enum, "
                "control signal width and emitted words. They therefore track "
                "a state-width or control-encoding change without a matching "
                "edit to this visualizer.",
        "refs": [],
    })

    # ---- 4. serial chains in the FSM ---------------------------------
    chains = straight_runs(seq)
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
            "body": "These runs expose the sequencer's serialization cost. Most "
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
                    f"an encoding; the live enum currently has "
                    f"{state_capacity - nst} spare. Check first that the "
                    "two are not distinguished by something outside the arm: "
                    "these states are read by other case blocks too.",
            "refs": [{"kind": "state", "key": v[0], "label": " = ".join(v)}
                     for v in dups.values()],
        })

    # ---- 6. action-oriented disposition ------------------------------
    # These three views make the optimization boundary explicit. A known
    # holder is not "idle"; an unattributed phase is not automatically safe;
    # and a profile-only service gap still needs runtime control flow.
    for variant, rows in walk["cycle_accounting"].items():
        blocked_union = sorted({phase for row in rows for phase in row["blocked"]})
        unattributed_union = sorted({phase for row in rows
                                     for phase in row["unattributed"]})
        conditional_union = sorted({phase for row in rows
                                    for phase in row["conditional"]})
        out.append({
            "id": f"blocked-{variant}",
            "area": "walk",
            "title": (f"{variant} walk: {len(blocked_union)} phase positions "
                      "are blocked by a known dependency on at least one profile"),
            "measure": {
                "profiles analysed": len(rows),
                "blocked phase positions": len(blocked_union),
                "evidence": "record port, wave pipeline, or completed product holder",
            },
            "body": "These positions are action-free and the multiplier is "
                    "idle for the named profile, but another live value still "
                    "crosses the phase. Removing one requires capturing that "
                    "value earlier or moving its consumer; a phase jump alone "
                    "would violate the dependency.",
            "table": {
                "label": "blocked by dependency",
                "cols": ["profile", "count", "phases"],
                "rows": [[row["profile"]["label"], len(row["blocked"]),
                          ", ".join(map(str, row["blocked"])) or "none"]
                         for row in rows],
            },
            "refs": [{"kind": "phase", "variant": variant, "key": phase,
                      "label": f"pph {phase}"} for phase in blocked_union],
        })
        out.append({
            "id": f"unattributed-{variant}",
            "area": "walk",
            "title": (f"{variant} walk: {len(unattributed_union)} phase positions "
                      "remain genuinely unattributed across the analysed profiles"),
            "measure": {
                "profiles analysed": len(rows),
                "unattributed phase positions": len(unattributed_union),
                "claim boundary": "unattributed is an audit target, not proven saving",
            },
            "body": "No scheduled action, selected-profile multiplier activity, "
                    "or known dependency holder explains these positions. Zero "
                    "means the model accounts for every phase. A non-zero row "
                    "is the shortest list for a source audit before attempting "
                    "to remove anything.",
            "table": {
                "label": "genuinely unattributed",
                "cols": ["profile", "count", "phases"],
                "rows": [[row["profile"]["label"], len(row["unattributed"]),
                          ", ".join(map(str, row["unattributed"])) or "none"]
                         for row in rows],
            },
            "refs": [{"kind": "phase", "variant": variant, "key": phase,
                      "label": f"pph {phase}"} for phase in unattributed_union],
        })
        out.append({
            "id": f"transform-{variant}",
            "area": "walk",
            "title": f"{variant} walk: each gap is paired with the transformation it needs",
            "measure": {
                "conditional-only phase positions": len(conditional_union),
                "dependency-blocked phase positions": len(blocked_union),
                "unattributed phase positions": len(unattributed_union),
                "lowest structural floor": min(row["overlapped_floor"]
                                               for row in rows),
            },
            "body": "The route to fewer clocks depends on the disposition: "
                    "profile-only gaps need a guarded jump; dependency-held "
                    "gaps need capture or retiming; unattributed gaps need a "
                    "proof; and reaching the overlapped floor needs a second "
                    "streaming register set so the next slot can load while "
                    "the current slot computes.",
            "table": {
                "label": "transformation required by profile",
                "cols": ["profile", "scheduled", "serial floor",
                         "overlapped floor", "occupied", "conditional",
                         "blocked", "unattributed", "required"],
                "rows": [[row["profile"]["label"], row["scheduled"],
                          row["serial_floor"], row["overlapped_floor"],
                          len(row["occupied"]), len(row["conditional"]),
                          len(row["blocked"]), len(row["unattributed"]),
                          "; ".join(row["transformations"]) or "none"]
                         for row in rows],
            },
            "refs": [],
        })

    bucket_by_id = {
        "mul-slack": "blocked by dependency",
        "mul-width": "structural floor",
        "gated-mul": "conditionally avoidable",
        "encoding": "transformation required",
        "serial-chains": "transformation required",
        "dup-arms": "transformation required",
    }
    for finding in out:
        ident = finding["id"]
        if ident.startswith("floor-"):
            bucket = "structural floor"
        elif ident.startswith("occupancy-"):
            bucket = "currently occupied"
        elif ident.startswith("blocked-"):
            bucket = "blocked by dependency"
        elif ident.startswith("unattributed-"):
            bucket = "genuinely unattributed"
        elif ident.startswith("transform-"):
            bucket = "transformation required"
        else:
            bucket = bucket_by_id.get(ident, "transformation required")
        finding["bucket"] = bucket

    return out


NODE_W, NODE_H, ROW_GAP, COL_GAP, PAD = 116, 30, 15, 74, 34


# ----------------------------------------------------------------------
# Semantic FSM layout
#
# An unconditional transition is part of the same microprogram unless two
# explicit source annotations say otherwise. Connected components of those
# transitions produce the columns. Guarded edges then order the component
# graph from S_IDLE. No state-name prefix or enum order participates.
# ----------------------------------------------------------------------
def semantic_clusters(seq):
    names = {node["name"] for node in seq["states"]}
    hints = {node["name"]: node.get("cluster_hint", "")
             for node in seq["states"]}
    parent = {name: name for name in names}

    def find(name):
        while parent[name] != name:
            parent[name] = parent[parent[name]]
            name = parent[name]
        return name

    def union(a, b):
        a, b = find(a), find(b)
        if a != b:
            parent[max(a, b)] = min(a, b)

    for transition in seq["transitions"]:
        a, b = transition["from"], transition["to"]
        if transition["guards"] or a not in names or b not in names:
            continue
        # Two explicit, distinct labels declare an intentional boundary.
        if hints[a] and hints[b] and hints[a] != hints[b]:
            continue
        union(a, b)

    # The same annotation can deliberately join branches which have no
    # unconditional edge between them.
    by_hint = {}
    for name, hint in hints.items():
        if hint:
            if hint in by_hint:
                union(name, by_hint[hint])
            else:
                by_hint[hint] = name

    components = {}
    for name in names:
        components.setdefault(find(name), set()).add(name)
    component_of = {name: root for root, members in components.items()
                    for name in members}

    internal_out = {name: set() for name in names}
    internal_in = {name: set() for name in names}
    external_in = {name: 0 for name in names}
    external_out = {name: 0 for name in names}
    component_edges = {}
    first_line = {}
    for transition in seq["transitions"]:
        a, b = transition["from"], transition["to"]
        if a not in names or b not in names:
            continue
        ca, cb = component_of[a], component_of[b]
        if ca == cb:
            if not transition["guards"]:
                internal_out[a].add(b)
                internal_in[b].add(a)
        else:
            external_out[a] += 1
            external_in[b] += 1
            component_edges.setdefault(ca, set()).add(cb)
            key = (ca, cb)
            first_line[key] = min(first_line.get(key, transition["line"]),
                                  transition["line"])

    def member_order(root):
        members = components[root]
        entries = [name for name in members
                   if external_in[name] or not internal_in[name]]
        starts = sorted(entries,
                        key=lambda name: (-external_in[name], name))
        if "S_IDLE" in members:
            starts = ["S_IDLE"] + [name for name in starts if name != "S_IDLE"]
        if not starts:
            starts = [min(members)]
        seen, ordered = set(), []

        def visit(name):
            if name in seen:
                return
            seen.add(name)
            ordered.append(name)
            for nxt in sorted(internal_out[name],
                              key=lambda value: (-external_out[value], value)):
                visit(nxt)

        for start in starts:
            visit(start)
        for name in sorted(members):
            visit(name)
        return ordered

    ordered_members = {root: member_order(root) for root in components}

    root = component_of.get("S_IDLE")
    roots = []
    if root is not None:
        roots.append(root)
    incoming_components = {key: 0 for key in components}
    for targets in component_edges.values():
        for target in targets:
            incoming_components[target] += 1
    roots.extend(sorted(
        (key for key, count in incoming_components.items()
         if count == 0 and key not in roots),
        key=lambda key: tuple(ordered_members[key])))

    component_order, seen_components = [], set()

    def traverse(start):
        queue = [start]
        while queue:
            current = queue.pop(0)
            if current in seen_components:
                continue
            seen_components.add(current)
            component_order.append(current)
            targets = sorted(component_edges.get(current, ()),
                             key=lambda target: (
                                 first_line.get((current, target), 1 << 30),
                                 tuple(ordered_members[target])))
            queue.extend(targets)

    for start in roots:
        traverse(start)
    for start in sorted(components, key=lambda key: tuple(ordered_members[key])):
        traverse(start)

    clusters = []
    by_name = {node["name"]: node for node in seq["states"]}
    for index, component in enumerate(component_order):
        members = ordered_members[component]
        explicit = sorted({hints[name] for name in members if hints[name]})
        if explicit:
            label = " / ".join(explicit)
            source = "RTL annotation"
        elif len(members) == 1:
            label = members[0]
            source = "graph singleton"
        else:
            exits = [name for name in members if external_out[name]]
            endpoint = exits[-1] if exits else members[-1]
            label = (members[0] if members[0] == endpoint else
                     f"{members[0]} → {endpoint}")
            source = "unconditional component"
        cluster_id = f"cluster-{index}"
        clusters.append({
            "id": cluster_id,
            "label": label,
            "source": source,
            "members": members,
        })
        for name in members:
            by_name[name]["cluster"] = cluster_id
            by_name[name]["cluster_label"] = label
    seq["clusters"] = clusters
    return seq


def layout_fsm(seq):
    semantic_clusters(seq)
    by_name = {node["name"]: node for node in seq["states"]}
    cols = {cluster["id"]: [by_name[name] for name in cluster["members"]]
            for cluster in seq["clusters"]}
    order = [cluster["id"] for cluster in seq["clusters"]]

    pos = {}
    x = PAD
    col_meta = []
    cluster_meta = {cluster["id"]: cluster for cluster in seq["clusters"]}
    for ci, cluster_id in enumerate(order):
        members = cols[cluster_id]
        y = PAD + 26
        for n in members:
            pos[n["name"]] = {"x": x, "y": y, "col": ci}
            y += NODE_H + ROW_GAP
        col_meta.append({"cluster": cluster_id,
                         "label": cluster_meta[cluster_id]["label"],
                         "source": cluster_meta[cluster_id]["source"],
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
    ap.add_argument("--trace", action="append", default=[], metavar="[NAME=]PATH",
                    help="overlay JSON/JSONL/CSV/key=value records containing "
                         "pph and optional cycle, prun, schedule, and sst")
    args = ap.parse_args()

    model = {"walk": extract_walk(), "seq": layout_fsm(extract_seq())}
    model["findings"] = analyse(model)
    for schedule in model["walk"]["schedules"].values():
        schedule["dependency_graph"] = build_dependency_graph(
            schedule, model["walk"]["mul_arms"], model["walk"]["profiles"])
    model["traces"] = [load_trace(spec, model["walk"]["schedules"])
                       for spec in args.trace]

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

    # A withheld finding is an empty dict; drop it rather than render a blank.
    model["findings"] = [f for f in model["findings"] if f.get("id")]

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
