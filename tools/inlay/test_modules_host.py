#!/usr/bin/env python3
"""Black-box tests for the host-only Inlay filesystem module adapter."""

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
    root = directory / "root.inlay.asm"
    write(root, source)
    result = run(frontend, root, directory / "out.asm", directory / "out.json")
    assert result.returncode == 1, result.stderr
    assert f"error[{diagnostic}]" in result.stderr, result.stderr


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: test_modules_host.py INLAY")
    frontend = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="inlay-modules-") as temporary:
        base = Path(temporary)
        nested = base / "nested"
        root = nested / "root.inlay.asm"
        write(
            root,
            'include "types.inlay.asm"\n'
            '#include "raw-isa.asm"\n'
            'include "sub/../body.inlay.asm"\n',
        )
        write(
            nested / "types.inlay.asm",
            "struct Item packed\n"
            "    value : u8\n"
            "end\n"
            "location p : ptr Item\n",
        )
        (nested / "sub").mkdir()
        write(nested / "body.inlay.asm", "    lda [p + Item.value]\n")
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
            "root.inlay.asm",
            "types.inlay.asm",
            "body.inlay.asm",
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

        legacy = base / "legacy"
        legacy_root = legacy / "root.la.asm"
        write(
            legacy_root,
            'include "types.la.asm"\n'
            '#include "raw-isa.asm"\n'
            'include "body.la.asm"\n',
        )
        write(
            legacy / "types.la.asm",
            "struct Item packed\n"
            "    value : u8\n"
            "end\n"
            "location p : ptr Item\n",
        )
        write(legacy / "body.la.asm", "    lda [p + Item.value]\n")
        legacy_asm = legacy / "legacy.asm"
        legacy_map = legacy / "legacy.json"
        result = run(frontend, legacy_root, legacy_asm, legacy_map)
        assert result.returncode == 0, result.stderr
        assert first_asm.read_bytes() == legacy_asm.read_bytes()
        legacy_json = json.loads(legacy_map.read_text(encoding="ascii"))
        assert [source["name"] for source in legacy_json["sources"]] == [
            "root.la.asm",
            "types.la.asm",
            "body.la.asm",
        ]
        first_json["generated"] = legacy_json["generated"]
        for canonical, old in zip(
            first_json["sources"], legacy_json["sources"], strict=True
        ):
            canonical["name"] = old["name"]
        assert first_json == legacy_json

        missing = base / "missing"
        missing.mkdir()
        expect_failure(
            frontend,
            missing,
            'include "absent.inlay.asm"\n',
            "module-not-found",
        )

        cycle = base / "cycle"
        cycle.mkdir()
        write(
            cycle / "child.inlay.asm",
            'include "root.inlay.asm"\n',
        )
        expect_failure(
            frontend,
            cycle,
            'include "child.inlay.asm"\n',
            "module-cycle",
        )

        duplicate = base / "duplicate"
        duplicate.mkdir()
        write(duplicate / "child.inlay.asm", "; once\n")
        expect_failure(
            frontend,
            duplicate,
            'include "child.inlay.asm"\ninclude "./child.inlay.asm"\n',
            "module-duplicate",
        )
    print("Inlay host module tests passed")


if __name__ == "__main__":
    main()
