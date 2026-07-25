#!/usr/bin/env python3
"""Convert customasm's symbol output to ca65's `.lbl` format.

    python3 tools/sym_to_lbl.py build/celeste.sym build/celeste.lbl

The Python test tooling (tools/test_celeste.py, tools/test_nemo.py) reads
ca65's label files, matching `al <hex> .<name>`. Emitting that format from
customasm keeps those tools working unchanged across the assembler migration,
which matters because they belong to other corpora.
"""
import re
import sys

if len(sys.argv) < 3:
    print(__doc__.strip().splitlines()[2], file=sys.stderr)
    raise SystemExit(2)

n = 0
with open(sys.argv[2], "w") as out:
    for line in open(sys.argv[1]):
        m = re.match(r"^\s*(\S+)\s*=\s*0x([0-9a-fA-F]+)\s*$", line)
        if m:
            out.write(f"al {int(m.group(2), 16):06X} .{m.group(1)}\n")
            n += 1
print(f"{sys.argv[2]}: {n} labels")
