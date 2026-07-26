#!/usr/bin/env python3
"""Assert that every pseudo-instruction is byte-identical to its expansion.

    make pseudo-check

Each rule in `src/isa/pseudo.asm` claims to emit exactly the instruction
sequence it replaces. This assembles both forms - the pseudo-op, and the
component instructions written out - and compares the bytes.

That per-rule property is what makes adopting an instruction before its
hardware exists free of risk: if `cbne v, #k, t` emits what `lda v / cmp #k /
bne t` emits, then a corpus using it assembles to the same image, and no
differential, liveness proof or test run is needed to believe it. Checking the
rules is also strictly better than re-checking each corpus, because it holds
for corpora that have not been written yet.

What it does NOT check is the swap to real hardware. That is the step where
behaviour can change - see the contract notes in `src/isa/pseudo.asm` - and it
is deliberately one edit in one file so it can be reviewed once rather than at
every site.
"""

import os
import re
import subprocess
import sys
import tempfile

PSEUDO = "src/isa/pseudo.asm"
HEAD = '#include "isa/nmos6502.asm"\n#include "isa/memmap.asm"\n' \
       '#include "isa/pseudo.asm"\n#bank ram\n#addr 0x0300\n'


def rules():
    """[(mnemonic, arity, instantiation, expansion-lines)] from pseudo.asm."""
    text = open(PSEUDO).read()
    out = []
    # The body cannot be matched with a non-greedy `\{(.*?)\}`: it contains
    # `{v}` and friends, so the first `}` closes a substitution rather than the
    # block. Find `asm {` and count braces.
    pat = re.compile(
        r"^\s{4}([a-z][a-z0-9_]*)\s+\{v: u8\}\s*,\s*(#\{[km]: u8\}\s*,\s*)?"
        r"\{t: u16\}\s*=>\s*asm \{", re.M)
    for m in pat.finditer(text):
        mn, has_imm = m.group(1), bool(m.group(2))
        i, depth = m.end() - 1, 0
        while True:
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = text[m.end():i]
        lines = [l.strip() for l in body.splitlines() if l.strip()]
        vals = {"v": "0x10", "k": "5", "m": "5", "t": "tgt"}
        exp = []
        for l in lines:
            for key, val in vals.items():
                l = l.replace("{" + key + "}", val)
            exp.append(l)
        use = (f"{mn} 0x10, #5, tgt" if has_imm else f"{mn} 0x10, tgt")
        out.append((mn, use, exp))
    return out


def assemble(tmp, name, body):
    src = os.path.join(tmp, name + ".asm")
    out = os.path.join(tmp, name + ".bin")
    open(src, "w").write(HEAD + body + "\ntgt:\n    nop\n")
    r = subprocess.run(["customasm", src, "-t", "10", "--color=off",
                        "--legacy=off", "-f", "binary", "-o", out],
                       capture_output=True, text=True, cwd=os.getcwd())
    if r.returncode != 0:
        return None, r.stderr
    return open(out, "rb").read(), ""


def main():
    rs = rules()
    if not rs:
        print(f"read no rules from {PSEUDO} - the parser and the file have "
              f"drifted apart", file=sys.stderr)
        return 1
    bad = 0
    with tempfile.TemporaryDirectory(dir="build") as tmp:
        # customasm resolves `#include "isa/..."` relative to the source file,
        # so the scratch directory needs the same view of src/
        os.symlink(os.path.abspath("src/isa"), os.path.join(tmp, "isa"))
        for mn, use, exp in rs:
            a, ea = assemble(tmp, mn + "_p", "    " + use)
            b, eb = assemble(tmp, mn + "_e", "\n".join("    " + l for l in exp))
            if a is None or b is None:
                print(f"  {mn:<7} FAILED TO ASSEMBLE")
                print((ea or eb)[-800:])
                bad = 1
                continue
            same = a == b
            bad |= not same
            print(f"  {mn:<7} {'ok  ' if same else 'DIFFERS'} "
                  f"{use:<22} == {' / '.join(exp)}")
            if not same:
                print(f"          {a.hex()}  vs  {b.hex()}")
    print("  every pseudo-instruction is byte-identical to its expansion"
          if not bad else "  MISMATCH - a pseudo-op does not emit what it claims")
    return bad


if __name__ == "__main__":
    sys.exit(main())
