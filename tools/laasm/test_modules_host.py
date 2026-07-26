#!/usr/bin/env python3
"""Black-box tests for the host-only laasm filesystem module adapter."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile


def run(frontend: Path, root: Path, output: Path, source_map: Path):
    return subprocess.run(
        [
            str(frontend),
            "--target",
            "console6502",
            "--output",
            str(output),
            "--map",
            str(source_map),
            str(root),
        ],
        check=False,
        text=True,
        capture_output=True,
    )


def write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="ascii")


def expect_failure(frontend: Path, directory: Path, source: str, diagnostic: str):
    root = directory / "root.la.asm"
    write(root, source)
    result = run(frontend, root, directory / "out.asm", directory / "out.json")
    assert result.returncode == 1, result.stderr
    assert f"error[{diagnostic}]" in result.stderr, result.stderr


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: test_modules_host.py LAASM")
    frontend = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="laasm-modules-") as temporary:
        base = Path(temporary)
        nested = base / "nested"
        root = nested / "root.la.asm"
        write(
            root,
            'include "types.la.asm"\n'
            '#include "raw-isa.asm"\n'
            'include "sub/../body.la.asm"\n',
        )
        write(
            nested / "types.la.asm",
            "struct Item packed\n"
            "    value : u8\n"
            "end\n"
            "location p : ptr Item\n",
        )
        (nested / "sub").mkdir()
        write(nested / "body.la.asm", "    lda [p + Item.value]\n")
        first_asm = nested / "first.asm"
        first_map = nested / "first.json"
        result = run(frontend, root, first_asm, first_map)
        assert result.returncode == 0, result.stderr
        assembly = first_asm.read_text(encoding="ascii")
        mapping = json.loads(first_map.read_text(encoding="ascii"))
        assert '#include "raw-isa.asm"' in assembly
        assert "lda (p), #" in assembly
        assert mapping["format"] == 2
        assert [source["name"] for source in mapping["sources"]] == [
            "root.la.asm",
            "types.la.asm",
            "body.la.asm",
        ]
        operation = next(
            entry
            for entry in mapping["mappings"]
            if entry["kind"] == "target-operation"
        )
        assert operation["sourceId"] == 3
        assert operation["sourceLine"] == 1

        second_asm = nested / "second.asm"
        second_map = nested / "second.json"
        result = run(frontend, root, second_asm, second_map)
        assert result.returncode == 0, result.stderr
        assert first_asm.read_bytes() == second_asm.read_bytes()
        first_json = json.loads(first_map.read_text(encoding="ascii"))
        second_json = json.loads(second_map.read_text(encoding="ascii"))
        first_json["generated"] = second_json["generated"]
        assert first_json == second_json

        missing = base / "missing"
        missing.mkdir()
        expect_failure(
            frontend, missing, 'include "absent.la.asm"\n', "module-not-found"
        )

        cycle = base / "cycle"
        cycle.mkdir()
        write(cycle / "child.la.asm", 'include "root.la.asm"\n')
        expect_failure(
            frontend, cycle, 'include "child.la.asm"\n', "module-cycle"
        )

        duplicate = base / "duplicate"
        duplicate.mkdir()
        write(duplicate / "child.la.asm", "; once\n")
        expect_failure(
            frontend,
            duplicate,
            'include "child.la.asm"\ninclude "./child.la.asm"\n',
            "module-duplicate",
        )
    print("laasm host module tests passed")


if __name__ == "__main__":
    main()
