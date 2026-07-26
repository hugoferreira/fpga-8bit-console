#!/usr/bin/env python3
"""Rewrite a corpus to use the add-isa-core-ergonomics instructions, safely.

    python3 tools/65x02/migrate_ext.py src/main.asm            # report only
    python3 tools/65x02/migrate_ext.py src/celeste --apply     # a whole corpus

None of these rewrites is unconditionally safe, which is the whole point of
this file:

  lda #k / sta v   ->  mov v, #k       The original leaves A = k and sets N
  lda t,x / sta v  ->  mov v, t + x    and Z. MOV touches neither. So the
                                       rewrite is only valid where A *and* the
                                       N/Z flags are dead afterwards.

  clc / adc m      ->  add m           Identical in A, N, V, Z and C, so valid
  sec / sbc m      ->  sub m           wherever the pair is genuinely adjacent.

  lda v / add u /                      add-isa-word-ops. AB is A:B with A the
  sta v / lda v+1 /                    high byte and a zero-page operand is
  adc u+1 / sta v+1                    little-endian, so this maps straight
    -> ldab v /                        onto the pair convention the corpus
       addw u / stab v                 already used. 12 bytes and 18 cycles
                                       become 6 and 12. A ends up holding the
  lda s / sta d /                      high byte either way, and N, C and V
  lda s+1 / sta d+1                    match, so the ONLY condition is that Z
    -> ldab s / stab d                 is dead: the word ops set it from both
                                       halves, the byte pair from the high one.

Two hazards this file exists to remember, both learned the hard way:

  DECIMAL. ADD, SUB and every word op are binary by design; ADC and SBC are
  not. Slice 1 rewrote breakout's `clc / adc #$10` between a `sed` and a `cld`
  into `add #$10` and silently turned the BCD score counter binary. Nothing
  caught it, because the corpus differential's scripted input never scored.
  `decimal_region` now bounds every `sed` and no arithmetic rewrite may enter
  one.

  THE TOOL'S OWN OUTPUT. Each slice's output becomes the next slice's input,
  and each time it has confused the analysis: slice 1's `mov`/`add` were
  invisible to a mnemonic list built from the NMOS 151 (it corrupted celeste's
  neg16), and slice 2's `sta (zp), #d` looked like a plain store to the MOV
  pass, which emitted `mov (pObj), #O_HBX, #1` - an instruction that does not
  exist. Mnemonics come from the decode table, unknown ones are refused, and
  every rewrite checks that its operand form is one the hardware actually has.

Liveness is decided by a walk over the corpus's control-flow graph. A site is
rewritten only if A and the N/Z flags are dead on EVERY path leaving it:

  - `jmp` and branches follow their target, and a branch follows both edges;
  - `jsr` walks into the callee and `rts` returns to the caller, so a value
    that a subroutine overwrites counts as dead at the call site;
  - `rts` with no known caller is unsafe, because the return value may be read;
  - a label is entered from elsewhere, which is fine: what matters is whether
    anything READS the value, not how it got there.

Loops are handled by a visited set over (position, what is already dead), and
the walk gives up - conservatively, as unsafe - past a node budget. A rejected
site is not a site that is unsafe; it is one this tool declines to prove safe.
Every rejection is counted and categorised.

Not done, deliberately: `lda #k / sta a / sta b` -> two MOVs. It is neutral in
bytes and cycles for two stores and WORSE for three or more, and the corpus
contains runs of 16 and 18 stores. It would trade real size for an instruction
count, which is the metric gaming the gates warn about.
"""

import os
import re
import sys
from collections import Counter

DECODE_TABLE = "rtl/cpu6502_decode.sv"

# Reads Y. `ldy #d / lda (p),y` -> `lda (p), #d` leaves Y unchanged where the
# original left Y = d, so the rewrite needs Y dead afterwards.
READS_Y = {"sty", "tya", "cpy", "iny", "dey", "pha"}
KILLS_Y = {"ldy", "tay", "ply"}

# Reads A, so a preceding `lda` whose value we removed would be observable.
READS_A = {"sta", "cmp", "adc", "sbc", "and", "ora", "eor", "bit",
           "tax", "tay", "pha", "add", "sub",
           # accumulator-mode shifts read A as well as write it. They were
           # missing here, which is a second latent hole in the same analysis.
           "asl", "lsr", "rol", "ror",
           "stab", "addw", "subw", "cmpw"}
# Overwrites A without reading it: past here the old A is unobservable.
KILLS_A = {"lda", "pla", "txa", "tya", "ldab"}
# Reads the N or Z flag. Kept apart because the word ops need the distinction:
# ADDW/SUBW set N, C and V exactly as the `adc`/`sbc` on the high byte did, but
# set Z over BOTH halves rather than the high one. So a 16-bit rewrite is legal
# wherever Z is dead, even if N is live - and N live after a 16-bit add is the
# common case (`bpl`/`bmi` on the sign). Merging them would decline those.
READS_N = {"bpl", "bmi", "php"}
READS_Z = {"bne", "beq", "php"}
READS_NZ = READS_N | READS_Z
# Sets N and Z from its own result.
KILLS_NZ = {"ldab", "stab", "addw", "subw", "cmpw",
            "lda", "ldx", "ldy", "and", "ora", "eor", "adc", "sbc", "cmp",
            "cpx", "cpy", "inc", "dec", "inx", "dex", "iny", "dey", "asl",
            "lsr", "rol", "ror", "bit", "tax", "txa", "tay", "tya", "tsx",
            "pla", "plp", "add", "sub"}
CONTROL = {"jmp", "jsr", "rts", "rti", "brk", "bpl", "bmi", "bvc", "bvs",
           "bcc", "bcs", "bne", "beq"}

# Every mnemonic the hardware implements, documented and extension alike, read
# from the decode table so it cannot fall behind it.
#
# This was the NMOS-151 registry alone, and that was a serious defect: once
# slice 1 put `mov`, `add` and `sub` into the corpus, those lines became
# INVISIBLE to this tool. A `lda #0` and a `sta w0` separated by an unseen
# `sub w0` looked adjacent, and were rewritten into a `mov` that discarded the
# subtraction. It corrupted celeste's neg16 and with it every jump in the game.
# The tool became unsafe the moment its own output entered the corpus.
MNEMONICS = {l.split()[1].lower()
             for l in open("tools/65x02/opcodes.txt")
             if l.strip() and not l.startswith("#")}
MNEMONICS |= {m.group(1).lower() for m in
              re.finditer(r"//\s*([A-Z]{3,4})\b", open(DECODE_TABLE).read())}


class Line:
    __slots__ = ("raw", "label", "label_name", "mn", "operand", "idx")

    def __init__(self, raw, idx):
        self.raw, self.idx = raw, idx
        body = raw.split(";")[0].rstrip()
        m = re.match(r"^\s*([.A-Za-z_@][\w.@]*)\s*:", body)
        self.label_name = m.group(1) if m else None
        self.label = bool(m)
        t = re.sub(r"^[A-Za-z_.@][\w.@]*\s*:\s*", "", body.strip())
        p = t.split(None, 1)
        self.mn = p[0].lower() if p and p[0].lower() in MNEMONICS else None
        self.operand = (p[1].strip() if len(p) > 1 else "") if self.mn else ""


BRANCHES = {"bpl", "bmi", "bvc", "bvs", "bcc", "bcs", "bne", "beq"}
NODE_BUDGET = 4000


class Corpus:
    """Every line of every file, with the label map needed to follow a jump."""

    def __init__(self, paths):
        self.lines = []           # flat list of Line
        self.owner = []           # index -> file index
        self.files = paths
        self.globals = {}         # name -> index
        self.locals = {}          # (enclosing global, name) -> index
        for fi, p in enumerate(paths):
            for raw in open(p).read().splitlines():
                self.lines.append(Line(raw, len(self.lines)))
                self.owner.append(fi)
            self.lines.append(Line("", len(self.lines)))     # file boundary
            self.owner.append(fi)
        cur = None
        for i, ln in enumerate(self.lines):
            if not ln.label_name:
                continue
            if ln.label_name.startswith("."):
                self.locals[(cur, ln.label_name)] = i
            else:
                cur = ln.label_name
                self.globals[ln.label_name] = i
        self.enclosing = []
        cur = None
        for ln in self.lines:
            if ln.label_name and not ln.label_name.startswith("."):
                cur = ln.label_name
            self.enclosing.append(cur)

    def target(self, i, operand):
        """Resolve a branch/jump/call operand to a line index, or None."""
        t = operand.strip().split(",")[0].strip()
        t = t.lstrip("(").rstrip(")")
        if not re.match(r"^[.A-Za-z_][\w.@]*$", t):
            return None
        if t.startswith("."):
            return self.locals.get((self.enclosing[i], t))
        return self.globals.get(t)


def dead_after(corpus, start, need_a, need_n, need_z, need_y=False):
    """Are the named values dead on every path from `start`? Unknown = no."""
    seen = set()
    budget = [NODE_BUDGET]
    # each work item: position, a_dead, n_dead, z_dead, y_dead, return stack
    stack = [(start, not need_a, not need_n, not need_z, not need_y, ())]
    while stack:
        i, a_dead, n_dead, z_dead, y_dead, ret = stack.pop()
        while True:
            if budget[0] <= 0:
                return False, "analysis budget exhausted"
            budget[0] -= 1
            key = (i, a_dead, n_dead, z_dead, y_dead, len(ret))
            if key in seen:
                break                       # this path already proven
            seen.add(key)
            if i >= len(corpus.lines):
                return False, "end of corpus"
            ln = corpus.lines[i]
            if ln.mn is None:
                i += 1
                continue
            if not a_dead and ln.mn in READS_A:
                return False, f"A read by {ln.mn}"
            if not n_dead and ln.mn in READS_N:
                return False, f"N read by {ln.mn}"
            if not z_dead and ln.mn in READS_Z:
                return False, f"Z read by {ln.mn}"
            if not y_dead and (ln.mn in READS_Y or
                               re.search(r",\s*[yY]$", ln.operand)):
                return False, f"Y read by {ln.mn}"
            if ln.mn in KILLS_A:
                a_dead = True
            if ln.mn in KILLS_NZ:
                n_dead = z_dead = True
            if ln.mn in KILLS_Y:
                y_dead = True
            if a_dead and n_dead and z_dead and y_dead:
                break                       # this path is safe
            if ln.mn == "jsr":
                t = corpus.target(i, ln.operand)
                if t is None:
                    return False, "jsr to an unresolved target"
                ret = ret + (i + 1,)
                if len(ret) > 12:
                    return False, "call depth"
                i = t
                continue
            if ln.mn == "rts":
                if not ret:
                    return False, "rts with no known caller"
                i, ret = ret[-1], ret[:-1]
                continue
            if ln.mn == "jmp":
                t = corpus.target(i, ln.operand)
                if t is None:
                    return False, "jmp to an unresolved target"
                i = t
                continue
            if ln.mn in BRANCHES:
                t = corpus.target(i, ln.operand)
                if t is None:
                    return False, "branch to an unresolved target"
                stack.append((t, a_dead, n_dead, z_dead, y_dead, ret))  # taken
                i += 1                                      # fall-through
                continue
            if ln.mn in ("rti", "brk"):
                return False, f"{ln.mn}"
            i += 1
    return True, ""


def decimal_region(corpus):
    """Line indices where the D flag may be set, and any escape it found.

    ADD, SUB and every word op are binary by design - `rtl/cpu6502_core.sv`
    says so at OP_ADD: "Binary only, by design: these are for addresses and
    counters, where a decimal adjust is never wanted. ADC/SBC keep decimal."
    So none of them may replace an `adc`/`sbc` that runs with D set.

    This is not hypothetical. Slice 1 rewrote breakout's `clc / adc #$10` to
    `add #$10` between a `sed` and a `cld`, turning the BCD score counter into
    a binary one. The corpus differential missed it because the scripted input
    never destroys a brick, so nothing ever scored. Hence this analysis, and
    hence a scripted input that scores.

    Forward walk from each `sed` over the same CFG the liveness walk uses,
    stopping at `cld`. If the walk escapes - an unresolved jump, an `rts` with
    no known caller - the caller is told, and refuses to rewrite anything
    arithmetic rather than guess how far D reaches.
    """
    tainted, escapes = set(), Counter()
    for i, ln in enumerate(corpus.lines):
        if ln.mn != "sed":
            continue
        stack, seen = [(i + 1, ())], set()
        while stack:
            j, ret = stack.pop()
            while True:
                if j >= len(corpus.lines):
                    escapes["ran off the end of the corpus"] += 1
                    break
                if (j, len(ret)) in seen:
                    break
                seen.add((j, len(ret)))
                ln2 = corpus.lines[j]
                if ln2.mn is None:
                    j += 1
                    continue
                if ln2.mn == "cld":
                    break                      # D is clear from here on
                tainted.add(j)
                if ln2.mn in ("jsr", "jmp") or ln2.mn in BRANCHES:
                    t = corpus.target(j, ln2.operand)
                    if t is None:
                        escapes[f"unresolved {ln2.mn} while D is set"] += 1
                        break
                    if ln2.mn == "jsr":
                        ret = ret + (j + 1,)
                        if len(ret) > 12:
                            escapes["call depth while D is set"] += 1
                            break
                        j = t
                        continue
                    if ln2.mn == "jmp":
                        j = t
                        continue
                    stack.append((t, ret))     # branch: taken edge
                    j += 1
                    continue
                if ln2.mn == "rts":
                    if not ret:
                        escapes["rts with no known caller while D is set"] += 1
                        break
                    j, ret = ret[-1], ret[:-1]
                    continue
                if ln2.mn in ("rti", "brk"):
                    escapes[f"{ln2.mn} while D is set"] += 1
                    break
                j += 1
    return tainted, escapes


def indent_of(raw):
    return raw[:len(raw) - len(raw.lstrip())]


def comment_of(raw):
    i = raw.find(";")
    return ("  " + raw[i:].rstrip()) if i >= 0 else ""


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    path = argv[1]
    apply_ = "--apply" in argv
    # ADD/SUB exist only in #imm and zp forms, so a `clc`/`adc` on an absolute
    # or indexed operand has no replacement. Symbol values come from the
    # assembler's own output rather than being guessed from the source.
    syms = {}
    symfile = next((a for a in argv if a.endswith(".sym")), None)
    if symfile:
        for l in open(symfile):
            m = re.match(r"^\s*(\S+)\s*=\s*0x([0-9a-fA-F]+)\s*$", l)
            if m:
                syms[m.group(1)] = int(m.group(2), 16)

    def value_of(op):
        """Resolve a bare symbol or literal to an address, or None if unknown.

        `SYM + n` is resolved too, because that is how this corpus spells the
        high half of a 16-bit variable (`ballx+1`) and the word pass decides
        what is a word by comparing addresses, never names. It has to: breakout
        contains both `add tmp / adc tmp2` and `sub tmp2 / sbc tmp`, and only
        one of those two orderings is a contiguous little-endian word.
        """
        op = op.strip()
        if op.startswith("<"):
            op = op[1:].strip()
        m = re.match(r"^([A-Za-z_.@][\w.@]*)\s*\+\s*(\d+)$", op)
        if m:
            base = syms.get(m.group(1))
            return None if base is None else base + int(m.group(2))
        m = re.match(r"^([A-Za-z_.@][\w.@]*)$", op)
        if m:
            return syms.get(m.group(1))
        m = re.match(r"^\$([0-9a-fA-F]+)$", op) or re.match(r"^0x([0-9a-fA-F]+)$", op)
        return int(m.group(1), 16) if m else None

    def is_zp_operand(op):
        """True only if this resolves to a zero-page address with no index."""
        op = op.strip()
        if re.search(r",\s*[xXyY]$", op) or op.startswith("("):
            return False
        if op.startswith("<"):
            return True
        v = value_of(op)
        return v is not None and v < 0x100

    def is_abs_operand(op):
        """True only if this resolves to an address at or above $0100.

        Required for `mov zp, src + x`: the instruction uses absolute-indexed
        addressing, and `lda zp,x` does NOT - it wraps inside page zero. A
        zero-page source would change behaviour whenever zp+X crosses $FF.
        """
        v = value_of(op)
        return v is not None and v >= 0x100
    # A corpus, not a file: `jsr` has to be followed into whichever file the
    # callee lives in, so the whole thing is loaded and indexed as one body.
    if os.path.isdir(path):
        paths = sorted(os.path.join(path, f) for f in os.listdir(path)
                       if f.endswith(".asm"))
    else:
        paths = [path]
    corpus = Corpus(paths)
    lines = corpus.lines

    # Fail loudly on a mnemonic this tool does not know, rather than silently
    # treating the line as invisible. Silence is what corrupted neg16.
    unknown = Counter()
    for ln in lines:
        body = re.sub(r"^\s*[.A-Za-z_@][\w.@]*\s*:\s*", "", ln.raw.split(";")[0]).strip()
        if not body or body.startswith(("#", ".", "@")):
            continue
        if re.match(r"^[\w.@]+\s*=", body):        # NAME = value, an equate
            continue
        head = body.split()[0].lower()
        if head not in MNEMONICS and re.match(r"^[a-z]{2,5}$", head):
            unknown[head] += 1
    if unknown:
        print("unknown mnemonics - refusing to run, since an unrecognised line "
              "would be treated as absent and could make two instructions look "
              "adjacent that are not:", file=sys.stderr)
        for k, v in unknown.most_common():
            print(f"  {v:>4}  {k}", file=sys.stderr)
        return 1

    # index of the code lines only, so "adjacent" ignores blanks and comments
    code = [i for i, ln in enumerate(lines) if ln.mn or ln.label]

    out = dict()          # line index -> replacement text, or None to delete
    did = Counter()
    skipped = Counter()

    # ADD/SUB and the word ops are binary; ADC/SBC are not. Anything reachable
    # from a `sed` is off limits to every arithmetic rewrite here.
    decimal, escapes = decimal_region(corpus)
    if escapes:
        print("the decimal-mode analysis could not bound a `sed` - refusing to "
              "rewrite arithmetic, since ADD/SUB and the word ops are binary "
              "and ADC/SBC are not:", file=sys.stderr)
        for k, v in escapes.most_common():
            print(f"  {v:>4}  {k}", file=sys.stderr)
        return 1

    # ---- add-isa-word-ops: fuse a byte-pair sequence into an AB op ----------
    #
    #   lda v / add u / sta v / lda v+1 / adc u+1 / sta v+1   (12 bytes, 18 cy)
    #     ->  ldab v / addw u / stab v                        ( 6 bytes, 12 cy)
    #   lda s / sta d / lda s+1 / sta d+1                     ( 8 bytes, 12 cy)
    #     ->  ldab s / stab d                                 ( 4 bytes,  8 cy)
    #
    # AB is A:B with A the high byte, and the zero-page operand is
    # little-endian, so both map straight onto the existing convention. After
    # the rewrite A still holds the high byte of the result, exactly as the
    # final `lda`/`adc` left it, so A needs no liveness proof at all. N, C and
    # V are identical too. The ONE difference is Z: the word ops set it from
    # both halves, the original from the high byte alone. So the whole safety
    # condition is that Z is dead afterwards.
    WORD_OP = {("add", "adc"): "addw", ("sub", "sbc"): "subw"}

    def imm16(lo, hi):
        """Recombine an `#lo` / `#hi` immediate pair into one 16-bit operand."""
        lo, hi = lo.strip(), hi.strip()
        if not (lo.startswith("#") and hi.startswith("#")):
            return None
        lo, hi = lo[1:].strip(), hi[1:].strip()
        if lo.startswith("<") and hi.startswith(">") and lo[1:].strip() == hi[1:].strip():
            return "#" + lo[1:].strip()          # #<K / #>K  ->  #K
        lv, hv = value_of(lo), value_of(hi)
        if lv is None:
            lv = int(lo) if re.match(r"^\d+$", lo) else None
        if hv is None:
            hv = int(hi) if re.match(r"^\d+$", hi) else None
        if lv is None or hv is None or not (0 <= lv < 256 and 0 <= hv < 256):
            return None
        return f"#${(hv << 8) | lv:04X}"

    def word_at(lo_op, hi_op):
        """The zero-page base of a contiguous little-endian word, or None."""
        lv, hv = value_of(lo_op), value_of(hi_op)
        if lv is None or hv is None or hv != lv + 1 or lv >= 0xFF:
            return None
        if re.search(r",\s*[xXyY]$", lo_op) or lo_op.strip().startswith("("):
            return None                       # indexed or indirect: no AB form
        if re.search(r",\s*[xXyY]$", hi_op) or hi_op.strip().startswith("("):
            return None
        return lv

    def claim(idxs, texts, tag):
        """Replace a window of lines with `texts`, deleting the rest.

        The window's first line may carry a label (`.cp: sta v`), which is a
        branch target and must survive the fusion; every comment in the window
        is carried onto the first emitted line, since the lines that explained
        the arithmetic are exactly the ones being removed.
        """
        first = lines[idxs[0]].raw
        m = re.match(r"^\s*[.A-Za-z_@][\w.@]*\s*:\s*", first)
        lead = m.group(0) if m else indent_of(first)
        body = indent_of(lines[idxs[1]].raw) or indent_of(first)
        notes = [comment_of(lines[i].raw).strip() for i in idxs
                 if comment_of(lines[i].raw)]
        tail = ("  " + " ".join(n.lstrip("; ") for n in notes if n)) if notes else ""
        if tail:
            tail = "  ; " + tail.strip()
        for k, i in enumerate(idxs):
            if k >= len(texts):
                out[i] = None
            elif k == 0:
                out[i] = lead + texts[0] + tail
            else:
                out[i] = body + texts[k]
        did[tag] += 1

    for n in range(len(code) - 3):
        idxs6 = code[n:n + 6]
        idxs4 = code[n:n + 4]
        if any(k in out for k in idxs4):
            continue
        w = [lines[k] for k in code[n:n + 6]] if n + 6 <= len(code) else None

        # A label anywhere but the first line means control can enter the
        # middle of the sequence, and a fused instruction has no middle.
        if w and not any(x.label for x in w[1:]) and all(x.mn for x in w):
            key = (w[1].mn, w[4].mn)
            if key in WORD_OP and (w[0].mn, w[2].mn, w[3].mn, w[5].mn) == \
                    ("lda", "sta", "lda", "sta"):
                if any(k in decimal for k in idxs6):
                    skipped["16-bit arithmetic inside a `sed` block - the word "
                            "ops are binary, `adc`/`sbc` are not"] += 1
                    continue
                rest = code[n + 6] if n + 6 < len(code) else len(lines)
                src = word_at(w[0].operand, w[3].operand)
                src_imm = imm16(w[0].operand, w[3].operand)
                dst = word_at(w[2].operand, w[5].operand)
                opnd = word_at(w[1].operand, w[4].operand)
                opnd_imm = imm16(w[1].operand, w[4].operand)
                if dst is None or (src is None and src_imm is None) or \
                        (opnd is None and opnd_imm is None):
                    skipped["16-bit arithmetic on something that is not a "
                            "zero-page word pair"] += 1
                    continue
                # The original stores the low half BEFORE reading either high
                # half; the fused form reads everything first. Those differ
                # only if the destination's low byte IS one of those high
                # bytes, which is the one aliasing case to decline.
                later_reads = {a + 1 for a in (src, opnd) if a is not None}
                if dst in later_reads:
                    skipped["destination low byte aliases a high byte read "
                            "later - store order is observable"] += 1
                    continue
                ok, why = dead_after(corpus, rest, False, False, True)
                if not ok:
                    skipped[f"{why} (16-bit arithmetic)"] += 1
                    continue
                load = src_imm if src is None else w[0].operand.strip()
                arg = opnd_imm if opnd is None else w[1].operand.strip()
                claim(idxs6,
                      [f"ldab {load}", f"{WORD_OP[key]} {arg}",
                       f"stab {w[2].operand.strip()}"],
                      f"6-op 16-bit {WORD_OP[key]} -> ldab/{WORD_OP[key]}/stab")
                continue

        # lda s / sta d / lda s+1 / sta d+1  ->  ldab s / stab d
        q = [lines[k] for k in idxs4]
        if any(x.label for x in q[1:]) or not all(x.mn for x in q):
            continue
        if tuple(x.mn for x in q) != ("lda", "sta", "lda", "sta"):
            continue
        rest = code[n + 4] if n + 4 < len(code) else len(lines)
        src = word_at(q[0].operand, q[2].operand)
        dst = word_at(q[1].operand, q[3].operand)
        if src is None or dst is None:
            continue                   # two unrelated byte copies, not a word
        if dst == src + 1:
            skipped["copy destination overlaps the source high byte"] += 1
            continue
        ok, why = dead_after(corpus, rest, False, False, True)
        if not ok:
            skipped[f"{why} (16-bit copy)"] += 1
            continue
        claim(idxs4,
              [f"ldab {q[0].operand.strip()}", f"stab {q[1].operand.strip()}"],
              "4-op 16-bit copy -> ldab/stab")

    for n, i in enumerate(code[:-1]):
        a, b = lines[i], lines[code[n + 1]]
        j = code[n + 1]
        if a.mn is None or b.mn is None or b.label:
            continue
        if i in out or j in out:
            continue
        rest = code[n + 2] if n + 2 < len(code) else len(lines)

        # clc / adc  ->  add        sec / sbc  ->  sub
        if a.mn in ("clc", "sec") and not a.operand:
            want = "adc" if a.mn == "clc" else "sbc"
            if b.mn == want and (i in decimal or j in decimal):
                skipped["`adc`/`sbc` inside a `sed` block - ADD/SUB are "
                        "binary only"] += 1
                continue
            if b.mn == want and not (b.operand.startswith("#") or
                                     is_zp_operand(b.operand)):
                skipped[f"{want} operand is not #imm or zp - no ADD/SUB form"] += 1
                continue
            if b.mn == want:
                new = "add" if a.mn == "clc" else "sub"
                out[i] = None
                out[j] = f"{indent_of(b.raw)}{new} {b.operand}{comment_of(b.raw)}"
                did[f"{a.mn}/{want} -> {new}"] += 1
                continue

        # ldy #d / lda (p),y   ->   lda (p), #d      (and the sta form)
        if a.mn == "ldy" and a.operand.startswith("#") and b.mn in ("lda", "sta"):
            m = re.match(r"^\(\s*([^)]+?)\s*\)\s*,\s*[yY]$", b.operand)
            if m:
                disp = a.operand[1:].strip()
                ok, why = dead_after(corpus, rest, False, False, False, True)
                if not ok:
                    skipped[f"{why} (pointer form)"] += 1
                    continue
                out[i] = None
                out[j] = (f"{indent_of(b.raw)}{b.mn} ({m.group(1)}), #{disp}"
                          f"{comment_of(b.raw)}")
                did[f"ldy #d / {b.mn} (p),y -> {b.mn} (p),#d"] += 1
                continue

        # lda #k / sta v   and   lda t,x / sta v
        if a.mn == "lda" and b.mn == "sta":
            imm = a.operand.startswith("#")
            idx_x = re.match(r"^([^,]+),\s*[xX]$", a.operand)
            if not imm and not idx_x:
                continue
            if re.match(r"^[^,]+,\s*[xXyY]$", b.operand):     # sta dst,x - no form
                skipped["sta is indexed - no MOV form"] += 1
                continue
            # MOV exists as `zp, #imm` ($03) and `abs, #imm` ($13) and nothing
            # else, so the destination has to be a plain resolvable address.
            # Slice 2's own `sta (zp), #d` put a destination in this corpus
            # that matches none of them, and without this guard the pass
            # emitted `mov (pObj), #O_HBX, #1` - which is the third time an
            # earlier slice's output has confused a later one.
            if not (is_zp_operand(b.operand) or is_abs_operand(b.operand)):
                skipped["sta destination is not a plain address - MOV has "
                        "only zp,#imm and abs,#imm"] += 1
                continue
            if idx_x:
                # $23 is MOV zp, abs+X: the destination must be zero page, and
                # the source must be a true absolute or the wrapping changes.
                if not is_zp_operand(b.operand):
                    skipped["MOV zp,abs+X has no absolute-destination form"] += 1
                    continue
                if not is_abs_operand(idx_x.group(1)):
                    skipped["source is zero page - lda zp,x wraps, abs,x does not"] += 1
                    continue
            ok, why = dead_after(corpus, rest, True, True, True)
            if not ok:
                skipped[why if why.startswith(("label", "end")) else why] += 1
                continue
            src = a.operand if imm else f"{idx_x.group(1).strip()} + x"
            out[i] = None
            out[j] = f"{indent_of(b.raw)}mov {b.operand}, {src}{comment_of(b.raw)}"
            did["lda #k / sta v -> mov" if imm else "lda t,x / sta v -> mov"] += 1

    print(f"{path}")
    print(f"  rewritten:")
    for k, v in sorted(did.items()):
        print(f"    {v:>4}  {k}")
    print(f"    {sum(did.values()):>4}  total, removing {sum(1 for v in out.values() if v is None)} instructions")
    if skipped:
        print(f"  declined (not proven safe):")
        for k, v in skipped.most_common():
            print(f"    {v:>4}  {k}")

    if apply_:
        # split the flat corpus back into its files, dropping the boundary line
        start = 0
        for fi, p in enumerate(paths):
            n = sum(1 for k in range(len(corpus.owner)) if corpus.owner[k] == fi)
            res = []
            for i in range(start, start + n - 1):        # -1: boundary sentinel
                if i in out:
                    if out[i] is not None:
                        res.append(out[i])
                else:
                    res.append(corpus.lines[i].raw)
            open(p, "w").write("\n".join(res) + "\n")
            start += n
        print(f"  written: {len(paths)} file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
