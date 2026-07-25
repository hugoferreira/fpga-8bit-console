#!/usr/bin/env python3
"""Rewrite a corpus to use the add-isa-core-ergonomics instructions, safely.

    python3 tools/65x02/migrate_ext.py src/main.asm            # report only
    python3 tools/65x02/migrate_ext.py src/main.asm --apply

None of these rewrites is unconditionally safe, which is the whole point of
this file:

  lda #k / sta v   ->  mov v, #k       The original leaves A = k and sets N
  lda t,x / sta v  ->  mov v, t + x    and Z. MOV touches neither. So the
                                       rewrite is only valid where A *and* the
                                       N/Z flags are dead afterwards.

  clc / adc m      ->  add m           Identical in A, N, V, Z and C, so valid
  sec / sbc m      ->  sub m           wherever the pair is genuinely adjacent.

Liveness is decided by a deliberately conservative forward scan: anything that
might read A or N/Z before they are redefined rejects the site, and so does a
label, a branch, or a jump, because either means another path arrives and this
scan does not build a control-flow graph. A rejected site is not a site that is
unsafe - it is a site this tool declines to prove safe. Every rejection is
counted and categorised, so the ones worth doing by hand are visible.
"""

import re
import sys
from collections import Counter

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
    __slots__ = ("raw", "label", "mn", "operand", "idx")

    def __init__(self, raw, idx):
        self.raw, self.idx = raw, idx
        body = raw.split(";")[0].rstrip()
        self.label = bool(re.match(r"^\S+:", body.strip())) or \
                     bool(re.match(r"^[A-Za-z_.@][\w.@]*\s*:", body))
        t = re.sub(r"^[A-Za-z_.@][\w.@]*\s*:\s*", "", body.strip())
        p = t.split(None, 1)
        self.mn = p[0].lower() if p and p[0].lower() in MNEMONICS else None
        self.operand = (p[1].strip() if len(p) > 1 else "") if self.mn else ""


def dead_after(lines, start, need_a, need_nz):
    """Is A (and/or N,Z) dead from `start` onward? Conservative: unknown = no."""
    a_dead = not need_a
    nz_dead = not need_nz
    for k in range(start, len(lines)):
        ln = lines[k]
        if ln.label:
            return False, "label - another path arrives"
        if ln.mn is None:
            continue
        if not a_dead and ln.mn in READS_A:
            return False, f"A read by {ln.mn}"
        if not nz_dead and ln.mn in READS_NZ:
            return False, f"N/Z read by {ln.mn}"
        if ln.mn in KILLS_A:
            a_dead = True
        if ln.mn in KILLS_NZ:
            nz_dead = True
        if a_dead and nz_dead:
            return True, ""
        if ln.mn in CONTROL:
            return False, f"control flow ({ln.mn}) before both were redefined"
    return False, "end of file"


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
    raw = open(path).read().splitlines()
    lines = [Line(r, i) for i, r in enumerate(raw)]

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
            ok, why = dead_after(lines, rest, True, True)
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
        res = []
        for i, r in enumerate(raw):
            if i in out:
                if out[i] is not None:
                    res.append(out[i])
            else:
                res.append(r)
        open(path, "w").write("\n".join(res) + "\n")
        print(f"  written: {len(raw)} -> {len(res)} lines")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
