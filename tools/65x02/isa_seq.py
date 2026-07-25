#!/usr/bin/env python3
"""Cost a 6502 idiom on THIS core, and on NMOS, so gate G4 can be re-scored.

Every slice of the ISA programme was written when the console ran a
cycle-accurate NMOS core, so its "replaced sequence" cycle counts are NMOS's.
This core is not NMOS: no read-modify-write dummy write, no page-cross penalty,
no dummy stack access, so pulls, pushes, RTS, RTI, RMW and taken branches are
all cheaper. Wherever that is true the replaced sequence got cheaper, the bar
for the instruction replacing it went UP, and G4 has to be re-checked.

    python3 tools/65x02/isa_seq.py "lda zp; sta zp"  "lda # ; cmp # ; bne rel"

Prints bytes and cycles for each idiom on both cores, and the one-port bus
floor a fused replacement could not beat - bytes + data accesses - so a slice
can see immediately whether a proposed instruction still has headroom.
"""
import json
import re
import sys

REGISTRY = "tools/65x02/opcodes.txt"
DECODE = "rtl/cpu6502_decode.sv"
TIMING = "docs/cpu-timing-v2.json"


def load():
    by_key, nbytes = {}, {}
    for line in open(REGISTRY):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        p = line.split()
        op = int(p[0], 16)
        by_key[(p[1].lower(), p[2].lower())] = op
        nbytes[op] = int(p[3])
    am = {}
    pat = re.compile(r"8'h([0-9A-F]{2}):\s*d\s*=\s*row\(\s*(AM_\w+)")
    for line in open(DECODE):
        m = pat.search(line)
        if m:
            am[int(m.group(1), 16)] = m.group(2)
    return by_key, nbytes, am, json.load(open(TIMING))["opcodes"]


ALIASES = {"#": "imm", "": "imp", "a": "acc", "rel": "rel"}


def resolve(tok, by_key):
    parts = tok.split()
    mn = parts[0].lower()
    mode = ALIASES.get(" ".join(parts[1:]).strip().lower(),
                       " ".join(parts[1:]).strip().lower()) or "imp"
    if (mn, mode) in by_key:
        return by_key[(mn, mode)], mn, mode
    for (m2, md2), op in by_key.items():          # branches: any rel form
        if m2 == mn and (mode in ("rel", "imp") and md2 == "rel"):
            return op, m2, md2
    raise SystemExit(f"unknown instruction: '{tok}' (mnemonic '{mn}', mode '{mode}')")


def main(argv):
    by_key, nbytes, am, cyc = load()
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[7], file=sys.stderr)
        return 2
    print(f"{'idiom':<34}{'bytes':>6}{'now':>7}{'NMOS':>7}{'delta':>7}")
    print("-" * 61)
    for idiom in argv[1:]:
        toks = [t.strip() for t in idiom.split(";") if t.strip()]
        b = mine = nmos = 0
        for t in toks:
            op, mn, mode = resolve(t, by_key)
            b += nbytes[op]
            mine += cyc[f"{op:02X}"]["cpi_mean"]
            nmos += cyc[f"{op:02X}"]["nmos_mean"]
        d = mine - nmos
        mark = "" if abs(d) < 0.005 else f"{d:+.2f}"
        print(f"{idiom[:33]:<34}{b:>6}{mine:>7.2f}{nmos:>7.2f}{mark:>7}")
    print("-" * 61)
    print("A fused replacement cannot go below its own bus floor:")
    print("  bytes it must fetch + data accesses it must make.")
    print("G4 needs it at or below the 'now' column, not the 'NMOS' column.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
