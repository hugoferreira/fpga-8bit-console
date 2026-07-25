#!/usr/bin/env python3
"""Assemble one instruction per addressing mode in src/isa/nmos6502.asm and
check the emitted bytes against a hand-computed table. The full corpus
(src/main.asm et al.) already proves byte-identity against the ca65 build in
anger; this is a fast, standalone regression guard for the ruledef itself,
independent of any game corpus.
"""
import subprocess
import sys
import tempfile
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RULEDEF = os.path.join(ROOT, "src", "isa", "nmos6502.asm")

# (source line, expected bytes). `lbl`/`zp`/`abs16` are pre-defined below.
CASES = [
    ("adc #0x10",        [0x69, 0x10]),
    ("adc zp",           [0x65, 0x10]),
    ("adc zp, x",        [0x75, 0x10]),
    ("adc abs16",        [0x6d, 0x00, 0x20]),
    ("adc abs16, x",     [0x7d, 0x00, 0x20]),
    ("adc abs16, y",     [0x79, 0x00, 0x20]),
    ("adc (zp, x)",      [0x61, 0x10]),
    ("adc (zp), y",      [0x71, 0x10]),
    ("asl a",            [0x0a]),
    ("asl",              [0x0a]),  # this project's accumulator shorthand
    ("asl zp",           [0x06, 0x10]),
    ("asl abs16, x",     [0x1e, 0x00, 0x20]),
    ("bit abs16",        [0x2c, 0x00, 0x20]),
    ("brk",              [0x00]),
    ("jmp abs16",        [0x4c, 0x00, 0x20]),
    ("jmp (abs16)",      [0x6c, 0x00, 0x20]),
    ("jsr abs16",        [0x20, 0x00, 0x20]),
    ("ldx #0x22",        [0xa2, 0x22]),
    ("ldx zp, y",        [0xb6, 0x10]),
    ("sty zp, x",        [0x94, 0x10]),
    ("lda #<abs16",      [0xa9, 0x00]),  # this project's lo/hi immediate
    ("lda #>abs16",      [0xa9, 0x20]),
    ("nop",              [0xea]),
    ("pha",              [0x48]),
    ("rts",              [0x60]),
    ("tax",              [0xaa]),
]

PREAMBLE = """\
#bankdef ram { #addr 0x0000, #size 0x200, #outp 0 }
#bank ram
#include "nmos6502.asm"
zp = 0x10
abs16 = 0x2000
start:
"""


def main():
    failures = 0
    with tempfile.TemporaryDirectory() as td:
        with open(RULEDEF) as f:
            ruledef_text = f.read()
        with open(os.path.join(td, "nmos6502.asm"), "w") as f:
            f.write(ruledef_text)
        for line, expected in CASES:
            src_path = os.path.join(td, "case.asm")
            out_path = os.path.join(td, "case.bin")
            with open(src_path, "w") as f:
                f.write(PREAMBLE)
                f.write("    " + line + "\n")
            r = subprocess.run(
                ["customasm", src_path, "--color=off", "-f", "binary", "-o", out_path],
                capture_output=True, text=True)
            if r.returncode != 0:
                print(f"FAIL  {line!r}: assembly error\n{r.stdout}\n{r.stderr}")
                failures += 1
                continue
            with open(out_path, "rb") as f:
                got = list(f.read())
            if got != expected:
                print(f"FAIL  {line!r}: got {got}, want {expected}")
                failures += 1
            else:
                print(f"ok    {line!r} -> {['0x%02x' % b for b in got]}")

    print()
    if failures:
        print(f"{failures} of {len(CASES)} cases failed")
        return 1
    print(f"all {len(CASES)} cases passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
