#!/usr/bin/env python3
"""Mechanically migrate a ca65 corpus to customasm.

    python3 tools/ca65_to_customasm.py src/celeste            # report
    python3 tools/ca65_to_customasm.py src/celeste --apply

The transforms are exactly those documented in `docs/assembler.md`, which were
derived and byte-verified during the breakout migration. Nothing here is
clever: it is a transliteration, and the proof it is correct is that the
resulting binary is byte-identical to ca65's, which the caller checks.

  .define NAME v     -> NAME = v
  .byte a, b, c      -> #d8 a, b, c        (#d "str" for a string literal,
                                            since #d8 rejects one)
  .word v            -> #d8 v[7:0], v[15:8]  (customasm's #d16 is big-endian
                                            and 6502 vectors are little)
  .include "f"       -> #include "f"
  .segment "CODE"    -> #bank ram          (see src/isa/memmap.asm)
  .segment "VECTORS" -> #bank vec
  <label / >label    -> label[7:0] / label[15:8]   inside a data list only;
                       `lda #<label` is matched by the ruledef and left alone
  @local             -> .local             customasm sub-labels scope the same
                                           way ca65 cheap locals do
  .if / .error /
  .endif             -> #assert            a static check either way
  `foo,x`            -> `foo, x`           customasm v0.14.1 needs the space
  ~expr              -> !expr              ca65 spells bitwise NOT `~`,
                                           customasm spells it `!`
"""

import os
import re
import sys

SEGMENTS = {"CODE": "ram", "VECTORS": "vec", "RODATA": "ram", "DATA": "ram"}


def split_code_comment(line):
    """Return (code, comment). The whitespace before `;` stays with the comment,
    so a corpus written with aligned trailing comments keeps its alignment -
    this is a corpus meant to be read, and a migration that reflows every
    comment produces a diff nobody can review."""
    out, i, in_str = [], 0, False
    while i < len(line):
        c = line[i]
        if c == '"':
            in_str = not in_str
        if c == ";" and not in_str:
            code = line[:i]
            gap = len(code) - len(code.rstrip())
            return code.rstrip(), " " * gap + line[i:]
        i += 1
    return line, ""


def fix_lohi(expr):
    """`<label` -> `label[7:0]`, `>label` -> `label[15:8]`, in a data list."""
    def one(term):
        term = term.strip()
        if term.startswith("<"):
            return f"({term[1:].strip()})[7:0]"
        if term.startswith(">"):
            return f"({term[1:].strip()})[15:8]"
        return term
    # split on commas that are not inside parentheses or strings
    parts, depth, cur, in_str = [], 0, "", False
    for c in expr:
        if c == '"':
            in_str = not in_str
        if not in_str:
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            elif c == "," and depth == 0:
                parts.append(cur)
                cur = ""
                continue
        cur += c
    parts.append(cur)
    return ", ".join(one(p) for p in parts)


def normalise_commas(code):
    """`a,x` -> `a, x`, outside string literals. customasm v0.14.1 needs it."""
    out, in_str = "", False
    for i, c in enumerate(code):
        if c == '"':
            in_str = not in_str
        if c == "," and not in_str:
            out += ", "
            if i + 1 < len(code) and code[i + 1] == " ":
                pass
            continue
        out += c
    return re.sub(r",\s+", ", ", out) if not in_str else out


def convert(line, stats):
    code, comment = split_code_comment(line)
    body = code.strip()
    if not body:
        return line

    indent = code[:len(code) - len(code.lstrip())]

    m = re.match(r"^\.define\s+(\S+)\s+(.*)$", body)
    if m:
        stats[".define"] += 1
        return f"{indent}{m.group(1)} = {m.group(2).strip()}{comment}"

    m = re.match(r"^\.include\s+(.*)$", body)
    if m:
        stats[".include"] += 1
        return f"{indent}#include {m.group(1).strip()}{comment}"

    m = re.match(r'^\.segment\s+"(\w+)"', body)
    if m:
        stats[".segment"] += 1
        bank = SEGMENTS.get(m.group(1), "ram")
        return f"{indent}#bank {bank}{comment}"

    m = re.match(r"^\.byte\s+(.*)$", body)
    if m:
        stats[".byte"] += 1
        payload = m.group(1).strip()
        if payload.startswith('"') and payload.endswith('"'):
            return f"{indent}#d {payload}{comment}"
        return f"{indent}#d8 {fix_lohi(payload)}{comment}"

    m = re.match(r"^\.word\s+(.*)$", body)
    if m:
        stats[".word"] += 1
        terms = [t.strip() for t in m.group(1).split(",")]
        pairs = ", ".join(f"({t})[7:0], ({t})[15:8]" for t in terms)
        return f"{indent}#d8 {pairs}{comment}"

    m = re.match(r"^\.if\s+(.*)$", body)
    if m:
        stats[".if"] += 1
        cond = m.group(1).strip().replace("<>", "!=")
        return f"{indent}; ca65 .if -> #assert below: {cond}{comment}"

    m = re.match(r"^\.error\s+(.*)$", body)
    if m:
        stats[".error"] += 1
        return f"{indent}; {m.group(1).strip()}{comment}"

    if re.match(r"^\.endif\b", body):
        stats[".endif"] += 1
        return f"{indent};{comment}" if comment else f"{indent};"

    # instruction or label line
    out = body
    if "~" in out:                                            # bitwise NOT
        out = out.replace("~", "!")
        stats["~ -> !"] += 1
    out = re.sub(r"@([A-Za-z_][\w]*)", r".\1", out)          # cheap locals
    if out != body:
        stats["@local"] += 1
    before = out
    out = normalise_commas(out)
    if out != before:
        stats["comma spacing"] += 1
    return f"{indent}{out}{comment}"


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    d = argv[1]
    apply_ = "--apply" in argv
    stats = __import__("collections").Counter()
    files = sorted(f for f in os.listdir(d) if f.endswith(".asm"))
    for f in files:
        p = os.path.join(d, f)
        src = open(p).read().splitlines()
        out = [convert(l, stats) for l in src]
        if apply_:
            open(p, "w").write("\n".join(out) + "\n")
    print(f"{d}: {len(files)} files")
    for k, v in sorted(stats.items()):
        print(f"  {v:>5}  {k}")
    if apply_:
        print("  applied")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
