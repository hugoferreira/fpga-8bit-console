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


COUNTED = ("asl", "lsr", "rol", "ror")
COUNTED_LIMIT = 8


def counted_rules():
    """[(mnemonic, count)] declared by the pseudo_counted_shift ruledef."""
    text = open(PSEUDO).read()
    block = re.search(
        r"#ruledef pseudo_counted_shift\s*\{(.*?)\n\}", text, re.S)
    if not block:
        return []
    return [
        (m.group(1), int(m.group(2)))
        for m in re.finditer(
            r"^\s{4}([a-z]{3}) a,\s*(\d+)\s*=>", block.group(1), re.M)
    ]


def ref_shift(mn, a, c):
    """Reference model for one accumulator shift/rotate: -> (a, carry)."""
    if mn == "asl":
        return (a << 1) & 0xFF, a >> 7
    if mn == "lsr":
        return a >> 1, a & 1
    if mn == "rol":
        return ((a << 1) & 0xFF) | c, a >> 7
    return (a >> 1) | (c << 7), a & 1


def load_sim():
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "sim6502", os.path.join("tools", "sim6502.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def check_counted(tmp):
    """Byte-identity, executable flag/carry equivalence, and rejection."""
    sim_mod = load_sim()
    bad = 0
    declared = counted_rules()
    expected = {(mn, n) for mn in COUNTED
                for n in range(1, COUNTED_LIMIT + 1)}
    if set(declared) != expected:
        missing = sorted(expected - set(declared))
        extra = sorted(set(declared) - expected)
        print(f"  counted  RULE SET DRIFTED missing={missing} extra={extra}")
        return 1

    for mn, n in declared:
        a, ea = assemble(tmp, f"{mn}{n}_p", f"    {mn} a, {n}")
        b, eb = assemble(tmp, f"{mn}{n}_e",
                         "\n".join(f"    {mn}" for _ in range(n)))
        if a is None or b is None:
            print(f"  {mn} a,{n}  FAILED TO ASSEMBLE")
            print((ea or eb)[-500:])
            bad = 1
            continue
        if a != b:
            print(f"  {mn} a,{n}  DIFFERS {a.hex()} vs {b.hex()}")
            bad = 1

    # Boundary counts, executed: the bytes are identical to the expansion, so
    # this is really checking the opcode transcription against a model that
    # never consults the assembler.
    for mn in COUNTED:
        for n in (1, COUNTED_LIMIT):
            img, err = assemble(tmp, f"{mn}{n}_x", f"    {mn} a, {n}")
            if img is None:
                print(f"  {mn} a,{n}  FAILED TO ASSEMBLE")
                bad = 1
                continue
            for a0 in (0x00, 0x01, 0x80, 0xC3, 0xFF):
                for c0 in (0, 1):
                    cpu = sim_mod.Sim6502(img, reset=0x300)
                    cpu.a, cpu.c = a0, c0
                    for _ in range(n):
                        cpu.step()
                    ra, rc = a0, c0
                    for _ in range(n):
                        ra, rc = ref_shift(mn, ra, rc)
                    if (cpu.a, cpu.c) != (ra, rc):
                        print(f"  {mn} a,{n}  FLAGS a={a0:#04x} c={c0}: "
                              f"got a={cpu.a:#04x} c={cpu.c}, "
                              f"want a={ra:#04x} c={rc}")
                        bad = 1

    # Counts outside the range, and any attempt to combine a memory operand
    # with a count, must fail rather than assemble to something plausible.
    for use in (f"{m} a, {n}" for m in COUNTED for n in (0, 9, 255)):
        img, _ = assemble(tmp, "rej", f"    {use}")
        if img is not None:
            print(f"  REJECT  `{use}` assembled to {img.hex()} - it must not")
            bad = 1
    for use in ("asl 0x10, 3", "lsr 0x10, 3", "ror 0x10, 2", "rol 0x10, 2"):
        img, _ = assemble(tmp, "rejmem", f"    {use}")
        if img is not None:
            print(f"  REJECT  `{use}` assembled to {img.hex()} - a memory "
                  f"operand must never be combined with a count")
            bad = 1

    if not bad:
        print(f"  counted  ok   {len(declared)} counted shift/rotate rules "
              f"byte-identical, flags verified at n=1 and n={COUNTED_LIMIT}, "
              f"out-of-range and memory forms rejected")
    return bad


ASR_LIMIT = 8
SIGN_CASES = (0x00, 0x01, 0x02, 0x7F, 0x80, 0x81, 0xC3, 0xFE, 0xFF)


def asr_rules():
    """[(spelling, expansion-lines)] for the width-suffixed asr forms."""
    text = open(PSEUDO).read()
    block = re.search(r"#ruledef pseudo_width\s*\{(.*?)\n\}\n", text, re.S)
    if not block:
        return []
    body = block.group(1)
    out = [("asr", ["cmp #$80", "ror"])] if re.search(
        r"^\s{4}asr\s*=>", body, re.M) else []
    for m in re.finditer(r"^\s{4}asr a,\s*(\d+)\s*=>", body, re.M):
        n = int(m.group(1))
        out.append((f"asr a, {n}", ["cmp #$80", "ror"] * n))
    if re.search(r"^\s{4}asrw\s*\{", body, re.M):
        out.append(("asrw 0x10",
                    ["lda 0x11", "cmp #$80", "ror 0x11", "ror 0x10"]))
    return out


def check_width(tmp, sim_mod):
    """Byte-identity and executed sign/flag behaviour for asr and asrw."""
    bad = 0
    forms = asr_rules()
    counted = {int(m.split(",")[1]) for m, _ in forms if " a, " in m}
    if counted != set(range(1, ASR_LIMIT + 1)):
        print(f"  asr      COUNTED RANGE DRIFTED: {sorted(counted)}")
        return 1

    for use, exp in forms:
        a, ea = assemble(tmp, "w_p", "    " + use)
        b, eb = assemble(tmp, "w_e", "\n".join("    " + l for l in exp))
        if a is None or b is None:
            print(f"  {use:<14} FAILED TO ASSEMBLE")
            print((ea or eb)[-500:])
            bad = 1
            continue
        if a != b:
            print(f"  {use:<14} DIFFERS {a.hex()} vs {b.hex()}")
            bad = 1

    # asr executed: the result must be a true arithmetic shift, and the flags
    # must match what a hardware ASR would leave. This is the claim that makes
    # the byte form's contract exact rather than weaker, so it is checked
    # against a model that never consults the assembler.
    for n in (1, 3, ASR_LIMIT):
        img, err = assemble(tmp, "w_x", f"    asr a, {n}")
        if img is None:
            print(f"  asr a,{n}  FAILED TO ASSEMBLE")
            bad = 1
            continue
        for a0 in SIGN_CASES:
            for c0 in (0, 1):
                for v0 in (0, 1):
                    cpu = sim_mod.Sim6502(img, reset=0x300)
                    cpu.a, cpu.c, cpu.v = a0, c0, v0
                    for _ in range(2 * n):
                        cpu.step()
                    want, wantc = a0, c0
                    for _ in range(n):
                        wantc = want & 1          # the bit this shift drops
                        want = ((want >> 1) | (want & 0x80)) & 0xFF
                    got = (cpu.a, cpu.c, cpu.n, cpu.z, cpu.v)
                    exp = (want, wantc, (want >> 7) & 1,
                           1 if want == 0 else 0, v0)
                    if got != exp:
                        print(f"  asr a,{n}  a={a0:#04x} c={c0} v={v0}: "
                              f"got {got}, want {exp}")
                        bad = 1

    # asrw executed: assert the flags it ACTUALLY leaves (low byte, A gone),
    # so a later swap to hardware that sets them from the 16-bit result is
    # caught by this check rather than silently assumed to be compatible.
    img, err = assemble(tmp, "w_w", "    asrw 0x10")
    if img is None:
        print("  asrw         FAILED TO ASSEMBLE")
        return 1
    for hi in (0x00, 0x01, 0x7F, 0x80, 0xFF):
        for lo in (0x00, 0x01, 0x80, 0xFF):
            cpu = sim_mod.Sim6502(img, reset=0x300)
            cpu.wr(0x10, lo)
            cpu.wr(0x11, hi)
            for _ in range(4):
                cpu.step()
            word = (hi << 8) | lo
            want = ((word >> 1) | (word & 0x8000)) & 0xFFFF
            if (cpu.rd(0x10), cpu.rd(0x11)) != (want & 0xFF, want >> 8):
                print(f"  asrw         {word:#06x}: got "
                      f"{cpu.rd(0x11):02x}{cpu.rd(0x10):02x}, "
                      f"want {want:#06x}")
                bad = 1
            if cpu.a != hi:
                print(f"  asrw         must clobber A with the high byte "
                      f"({hi:#04x}), found {cpu.a:#04x}")
                bad = 1
            if cpu.z != (1 if (want & 0xFF) == 0 else 0):
                print("  asrw         Z no longer reflects the LOW byte - the "
                      "documented contract has drifted")
                bad = 1

    for use in (f"asr a, {n}" for n in (0, 9, 255)):
        img, _ = assemble(tmp, "w_r", f"    {use}")
        if img is not None:
            print(f"  REJECT  `{use}` assembled to {img.hex()} - it must not")
            bad = 1
    for use in ("asr 0x10", "asrw a", "asrw 0x10, 3"):
        img, _ = assemble(tmp, "w_rm", f"    {use}")
        if img is not None:
            print(f"  REJECT  `{use}` assembled to {img.hex()} - it must not")
            bad = 1

    if not bad:
        print(f"  asr      ok   {len(forms)} width-suffixed forms "
              f"byte-identical, asr flags match hardware ASR over "
              f"{len(SIGN_CASES)} sign cases, asrw contract holds, "
              f"invalid forms rejected")
    return bad


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
        bad |= check_counted(tmp)
        bad |= check_width(tmp, load_sim())
    print("  every pseudo-instruction is byte-identical to its expansion"
          if not bad else "  MISMATCH - a pseudo-op does not emit what it claims")
    return bad


if __name__ == "__main__":
    sys.exit(main())
