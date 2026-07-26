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

# Reads Y. `ldy #d / lda (p),y` -> `lda (p), #d` leaves Y unchanged where the
# original left Y = d, so the rewrite needs Y dead afterwards.
READS_Y = {"sty", "tya", "cpy", "iny", "dey", "pha"}
KILLS_Y = {"ldy", "tay", "ply"}

# Reads A, so a preceding `lda` whose value we removed would be observable.
READS_A = {"sta", "cmp", "adc", "sbc", "and", "ora", "eor", "bit",
           "tax", "tay", "pha", "add", "sub"}
# Overwrites A without reading it: past here the old A is unobservable.
KILLS_A = {"lda", "pla", "txa", "tya"}
# Reads the N or Z flag.
READS_NZ = {"bpl", "bmi", "bne", "beq", "php"}
# Sets N and Z from its own result.
KILLS_NZ = {"lda", "ldx", "ldy", "and", "ora", "eor", "adc", "sbc", "cmp",
            "cpx", "cpy", "inc", "dec", "inx", "dex", "iny", "dey", "asl",
            "lsr", "rol", "ror", "bit", "tax", "txa", "tay", "tya", "tsx",
            "pla", "plp", "add", "sub"}
CONTROL = {"jmp", "jsr", "rts", "rti", "brk", "bpl", "bmi", "bvc", "bvs",
           "bcc", "bcs", "bne", "beq"}

MNEMONICS = {l.split()[1].lower()
             for l in open("tools/65x02/opcodes.txt")
             if l.strip() and not l.startswith("#")}


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


def dead_after(corpus, start, need_a, need_nz, need_y=False):
    """Are the named values dead on every path from `start`? Unknown = no."""
    seen = set()
    budget = [NODE_BUDGET]
    # each work item: position, a_dead, nz_dead, y_dead, return-address stack
    stack = [(start, not need_a, not need_nz, not need_y, ())]
    while stack:
        i, a_dead, nz_dead, y_dead, ret = stack.pop()
        while True:
            if budget[0] <= 0:
                return False, "analysis budget exhausted"
            budget[0] -= 1
            key = (i, a_dead, nz_dead, y_dead, len(ret))
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
            if not nz_dead and ln.mn in READS_NZ:
                return False, f"N/Z read by {ln.mn}"
            if not y_dead and (ln.mn in READS_Y or
                               re.search(r",\s*[yY]$", ln.operand)):
                return False, f"Y read by {ln.mn}"
            if ln.mn in KILLS_A:
                a_dead = True
            if ln.mn in KILLS_NZ:
                nz_dead = True
            if ln.mn in KILLS_Y:
                y_dead = True
            if a_dead and nz_dead and y_dead:
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
                stack.append((t, a_dead, nz_dead, y_dead, ret))   # taken edge
                i += 1                                      # fall-through
                continue
            if ln.mn in ("rti", "brk"):
                return False, f"{ln.mn}"
            i += 1
    return True, ""


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
        """Resolve a bare symbol or literal to an address, or None if unknown."""
        op = op.strip()
        if op.startswith("<"):
            op = op[1:].strip()
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

    # index of the code lines only, so "adjacent" ignores blanks and comments
    code = [i for i, ln in enumerate(lines) if ln.mn or ln.label]

    out = dict()          # line index -> replacement text, or None to delete
    did = Counter()
    skipped = Counter()

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
                ok, why = dead_after(corpus, rest, False, False, True)
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
            if idx_x:
                # $23 is MOV zp, abs+X: the destination must be zero page, and
                # the source must be a true absolute or the wrapping changes.
                if not is_zp_operand(b.operand):
                    skipped["MOV zp,abs+X has no absolute-destination form"] += 1
                    continue
                if not is_abs_operand(idx_x.group(1)):
                    skipped["source is zero page - lda zp,x wraps, abs,x does not"] += 1
                    continue
            ok, why = dead_after(corpus, rest, True, True)
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
