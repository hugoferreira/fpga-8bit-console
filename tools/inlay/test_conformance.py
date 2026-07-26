#!/usr/bin/env python3
"""Host-only conformance oracle for the portable Inlay C core."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INLAY = ROOT / "build/inlay/inlay"
LAASM_COMPAT = ROOT / "build/laasm/laasm"
FIXTURE = ROOT / "tests/inlay/celeste.inlay.asm"
REFERENCE = ROOT / "tests/inlay/celeste_reference.asm"
STRUCTURED_FIXTURE = ROOT / "tests/inlay/structured.inlay.asm"
STRUCTURED_REFERENCE = ROOT / "tests/inlay/structured_reference.asm"
VARIANT_FIXTURE = ROOT / "tests/inlay/variants.inlay.asm"
VARIANT_REFERENCE = ROOT / "tests/inlay/variants_reference.asm"
FULL_LAYOUT = ROOT / "src/inlay/celeste.inlay.asm"
CELESTE_MAIN = ROOT / "src/celeste/main.asm"
CELESTE_MEMMAP = ROOT / "src/celeste/memmap.asm"
PREPARE = ROOT / "tools/inlay/prepare_celeste_modules.py"
DEPRECATION = (
    "laasm: deprecated; use inlay "
    "(legacy support requires a separate removal change)\n"
)

EXPECTED_PATHS = {
    "O_TYPE": "kind",
    "O_SPR": "sprite",
    "O_X": "x",
    "O_Y": "y",
    "O_SPDX": "speed_x",
    "O_SPDY": "speed_y",
    "O_REMX": "remainder_x",
    "O_REMY": "remainder_y",
    "O_HBX": "hitbox.x",
    "O_HBY": "hitbox.y",
    "O_HBW": "hitbox.w",
    "O_HBH": "hitbox.h",
    "O_FLIP": "flip",
    "O_FLAGS": "flags",
    "O_STATE": "state",
    "O_DELAY": "delay",
    "O_DJUMP": "dash_jumps",
    "O_GRACE": "grace",
    "O_JBUF": "jump_buffer",
    "O_DASHT": "dash_time",
    "O_DASHE": "dash_effect",
    "O_PBITS": "player_bits",
    "O_SPROFF": "sprite_offset",
    "O_DTX": "dash_target_x",
    "O_DTY": "dash_target_y",
    "O_DAX": "dash_accel_x",
    "O_DAY": "dash_accel_y",
    "O_TGTX": "target_x",
    "O_TGTY": "target_y",
    "O_HAIR": "hair",
}


def run(*args: object, expect: int = 0) -> subprocess.CompletedProcess[str]:
    command = [str(arg) for arg in args]
    result = subprocess.run(
        command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=False
    )
    if result.returncode != expect:
        raise AssertionError(
            f"{' '.join(command)} returned {result.returncode}, expected "
            f"{expect}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def component(name: str) -> str:
    return f"{len(name)}_{name}"


def property_symbol(path: str) -> str:
    parts = path.split(".")
    return "__la_" + component("CelesteObject") + "".join(
        "__" + component(part) for part in parts
    ) + "__offset"


def extract_object_offsets(path: Path) -> dict[str, int]:
    values: dict[str, int] = {}
    inside = False
    ended = False
    declaration = re.compile(
        r"^\s*(O_[A-Z0-9_]+)\s*=\s*([0-9]+)\s*(?:;.*)?$"
    )
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not inside and not ended and re.match(r"^\s*O_TYPE\s*=", line):
            inside = True
        if not inside:
            continue
        if not line.strip() or line.lstrip().startswith(";"):
            continue
        match = declaration.fullmatch(line)
        if not match:
            raise AssertionError(
                f"{path}:{number}: unrecognised declaration in O_* block: "
                f"{line!r}"
            )
        name, value = match.groups()
        if name in values:
            raise AssertionError(f"{path}:{number}: duplicate {name}")
        values[name] = int(value)
        if name == "O_SIZE":
            inside = False
            ended = True
    if inside or not ended:
        raise AssertionError("authoritative O_* block is not contiguous")
    expected = set(EXPECTED_PATHS) | {"O_SIZE"}
    if set(values) != expected:
        raise AssertionError(
            f"authoritative O_* names changed: expected {sorted(expected)}, "
            f"got {sorted(values)}"
        )
    return values


def emitted_constants(path: Path) -> dict[str, int]:
    result: dict[str, int] = {}
    declaration = re.compile(r"^(__la_[A-Za-z0-9_]+)\s*=\s*([0-9]+)$")
    for line in path.read_text().splitlines():
        match = declaration.fullmatch(line)
        if match:
            result[match.group(1)] = int(match.group(2))
    return result


def translate(source: Path, output: Path, map_path: Path, stats: bool = False):
    args: list[object] = [
        INLAY, "--target", "console6502", "--output", output,
        "--map", map_path,
    ]
    if stats:
        args.append("--stats")
    args.append(source)
    return run(*args)


def check_cli(tmp: Path) -> None:
    help_text = run(INLAY, "--help").stdout
    assert help_text.startswith(
        "Inlay Assembly — Structured assembly, close to the metal.\n"
    )
    assert "usage: inlay" in help_text
    assert "--check-customasm" in help_text
    assert "-o, --output" in help_text
    assert "Exit status:" in help_text
    assert run(INLAY, "-h").stdout == help_text
    assert (
        run(INLAY, "--version").stdout.strip()
        == "inlay 0.2 language-format=1 target-format=1 map-format=2"
    )
    assert "usage: inlay" in run(INLAY, expect=2).stderr

    compat_help = run(LAASM_COMPAT, "--help")
    assert compat_help.stdout == help_text
    assert compat_help.stderr == DEPRECATION
    compat_version = run(LAASM_COMPAT, "--version")
    assert compat_version.stdout == run(INLAY, "--version").stdout
    assert compat_version.stderr == DEPRECATION

    stats_output = tmp / "compat.asm"
    stats_map = tmp / "compat.map.json"
    canonical_stats = run(
        INLAY, "--target", "console6502", "--output", stats_output,
        "--map", stats_map, "--stats", FIXTURE
    )
    compat_stats = run(
        LAASM_COMPAT, "--target", "console6502", "--output", stats_output,
        "--map", stats_map, "--stats", FIXTURE
    )
    assert json.loads(compat_stats.stdout) == json.loads(canonical_stats.stdout)
    assert compat_stats.stderr == DEPRECATION

    canonical_failure = run(
        INLAY, "--target", "missing", "--output", tmp / "x.asm",
        "--map", tmp / "x.json", FIXTURE, expect=2
    )
    compat_failure = run(
        LAASM_COMPAT, "--target", "missing", "--output", tmp / "x.asm",
        "--map", tmp / "x.json", FIXTURE, expect=2
    )
    assert compat_failure.stdout == canonical_failure.stdout
    assert compat_failure.stderr == DEPRECATION + canonical_failure.stderr

    result = run(
        INLAY, "--target", "missing", "--output", tmp / "x.asm",
        "--map", tmp / "x.json", FIXTURE, expect=2
    )
    assert "unknown target" in result.stderr
    result = run(
        INLAY, "--native", "--target", "console6502",
        "--output", tmp / "x.asm", "--map", tmp / "x.json",
        FIXTURE, expect=2
    )
    assert "native-output-deferred" in result.stderr
    result = run(
        INLAY, "--target", "console6502", "--output", FIXTURE,
        "--map", tmp / "x.json", FIXTURE, expect=2
    )
    assert "refusing to overwrite" in result.stderr
    result = run(
        INLAY, "--target", "console6502", "--output", tmp / "same",
        "--map", tmp / "same", FIXTURE, expect=2
    )
    assert "output and map must be different" in result.stderr

    input_alias = tmp / "input-alias.inlay.asm"
    input_alias.symlink_to(FIXTURE)
    result = run(
        INLAY, "--target", "console6502", "--output", input_alias,
        "--map", tmp / "alias-map.json", FIXTURE, expect=2
    )
    assert "refusing to overwrite" in result.stderr

    linked_output = tmp / "linked-output"
    linked_map = tmp / "linked-map"
    linked_output.write_text("existing\n")
    os.link(linked_output, linked_map)
    result = run(
        INLAY, "--target", "console6502", "--output", linked_output,
        "--map", linked_map, FIXTURE, expect=2
    )
    assert "output and map must be different" in result.stderr
    result = run(INLAY, "--target", expect=2)
    assert "option --target requires a value" in result.stderr

    short_output = tmp / "short.asm"
    short_map = tmp / "short.json"
    run(
        INLAY, "--target", "console6502", "-o", short_output,
        "--map", short_map, FIXTURE
    )
    assert short_output.is_file()
    assert json.loads(short_map.read_text())["format"] == 2

    invalid = tmp / "invalid.inlay.asm"
    invalid.write_text("struct\n")
    preserved_output = tmp / "preserved.asm"
    preserved_map = tmp / "preserved.json"
    preserved_output.write_text("existing assembly\n")
    preserved_map.write_text("existing map\n")
    run(
        INLAY, "--target", "console6502", "--output", preserved_output,
        "--map", preserved_map, invalid, expect=1
    )
    assert preserved_output.read_text() == "existing assembly\n"
    assert preserved_map.read_text() == "existing map\n"
    assert not list(tmp.glob("preserved.*.tmp.*"))

    canonical_source = tmp / "suffix.inlay.asm"
    legacy_source = tmp / "suffix.la.asm"
    canonical_source.write_bytes(FIXTURE.read_bytes())
    legacy_source.write_bytes(FIXTURE.read_bytes())
    canonical_output = tmp / "suffix-canonical.asm"
    legacy_output = tmp / "suffix-legacy.asm"
    canonical_map = tmp / "suffix-canonical.json"
    legacy_map = tmp / "suffix-legacy.json"
    run(
        INLAY, "--target", "console6502", "--output", canonical_output,
        "--map", canonical_map, canonical_source
    )
    run(
        INLAY, "--target", "console6502", "--output", legacy_output,
        "--map", legacy_map, legacy_source
    )
    assert canonical_output.read_bytes() == legacy_output.read_bytes()
    canonical_json = json.loads(canonical_map.read_text())
    legacy_json = json.loads(legacy_map.read_text())
    canonical_json["sources"][0]["name"] = legacy_json["sources"][0]["name"]
    canonical_json["generated"] = legacy_json["generated"]
    assert canonical_json == legacy_json


def check_negative_sources(tmp: Path) -> None:
    original = FIXTURE.read_text()
    cases = {
        "moved": (
            original.replace(
                "    hitbox : Hitbox\n    flip : u8\n",
                "    flip : u8\n    hitbox : Hitbox\n",
            ),
            "assertion-failed",
        ),
        "grown": (
            original.replace(
                "    reserved : u8[7]\n", "    reserved : u8[8]\n"
            ),
            "assertion-failed",
        ),
        "mistyped": (
            original.replace(
                "location pObj : ptr CelesteObject\n",
                "struct Other packed\n    byte : u8\nend\n"
                "location pObj : ptr Other\n",
            ),
            "location-type",
        ),
    }
    for name, (source, code) in cases.items():
        source_path = tmp / f"{name}.inlay.asm"
        source_path.write_text(source)
        result = run(
            INLAY, "--target", "console6502",
            "--output", tmp / f"{name}.asm",
            "--map", tmp / f"{name}.json",
            source_path, expect=1,
        )
        if f"error[{code}]" not in result.stderr:
            raise AssertionError(
                f"{name}: expected diagnostic {code}\n{result.stderr}"
            )


def check_downstream_diagnostics(tmp: Path) -> None:
    mapped = tmp / "mapped.inlay.asm"
    mapped.write_text("bad_instruction\n")
    result = run(
        INLAY, "--target", "console6502",
        "--output", tmp / "mapped.asm",
        "--map", tmp / "mapped.json",
        "--check-customasm", mapped, expect=1,
    )
    if f"{mapped.name}:1: customasm:" not in result.stderr:
        raise AssertionError(
            "customasm diagnostic was not mapped to original source\n"
            + result.stderr
        )

    included = tmp / "bad_include.asm"
    included.write_text("bad_instruction\n")
    unmapped = tmp / "unmapped.inlay.asm"
    unmapped.write_text('#include "bad_include.asm"\n')
    result = run(
        INLAY, "--target", "console6502",
        "--output", tmp / "unmapped.asm",
        "--map", tmp / "unmapped.json",
        "--check-customasm", unmapped, expect=1,
    )
    if "bad_include.asm" not in result.stderr:
        raise AssertionError(
            "unmapped customasm diagnostic did not retain generated/include "
            "location\n" + result.stderr
        )


def check_fixture(first: Path, second: Path) -> dict[str, int]:
    out_a = first / "generated.asm"
    out_b = second / "generated.asm"
    map_a = first / "generated.map.json"
    map_b = second / "generated.map.json"
    stats_result = translate(FIXTURE, out_a, map_a, stats=True)
    translate(FIXTURE, out_b, map_b)
    if out_a.read_bytes() != out_b.read_bytes():
        raise AssertionError("customasm output is not deterministic")
    if map_a.read_bytes() != map_b.read_bytes():
        raise AssertionError("source-map output is not deterministic")
    source_map = json.loads(map_a.read_text())
    assert source_map["format"] == 2
    assert source_map["sources"] == [{"id": 1, "name": FIXTURE.name}]
    assert source_map["generated"] == out_a.name

    authoritative = extract_object_offsets(CELESTE_MEMMAP)
    constants = emitted_constants(out_a)
    for old_name, path in EXPECTED_PATHS.items():
        actual = constants.get(property_symbol(path))
        expected = authoritative[old_name]
        if actual != expected:
            raise AssertionError(
                f"{path}: frontend offset {actual}, {old_name}={expected}"
            )
    if constants.get("__la_13_CelesteObject__size") != authoritative["O_SIZE"]:
        raise AssertionError("CelesteObject size differs from O_SIZE")

    fixture_bin = first / "fixture.bin"
    reference_bin = first / "reference.bin"
    run("customasm", out_a, "-f", "binary", "-o", fixture_bin)
    run("customasm", REFERENCE, "-f", "binary", "-o", reference_bin)
    if fixture_bin.read_bytes() != reference_bin.read_bytes():
        raise AssertionError("typed field operations differ from reference bytes")
    return json.loads(stats_result.stdout)


def check_structured_fixture(first: Path, second: Path) -> None:
    outputs = []
    maps = []
    for directory in (first, second):
        output = directory / "structured.asm"
        map_path = directory / "structured.map.json"
        translate(STRUCTURED_FIXTURE, output, map_path)
        outputs.append(output)
        maps.append(map_path)
    if outputs[0].read_bytes() != outputs[1].read_bytes():
        raise AssertionError("structured customasm output is not deterministic")
    if maps[0].read_bytes() != maps[1].read_bytes():
        raise AssertionError("structured source map is not deterministic")
    frontend = first / "structured.bin"
    reference = first / "structured-reference.bin"
    run("customasm", outputs[0], "-f", "binary", "-o", frontend)
    run("customasm", STRUCTURED_REFERENCE, "-f", "binary", "-o", reference)
    if frontend.read_bytes() != reference.read_bytes():
        raise AssertionError(
            "indexed, pool and frame output differs from reference bytes"
        )


def check_variant_fixture(first: Path, second: Path) -> None:
    outputs = []
    maps = []
    for directory in (first, second):
        output = directory / "variants.asm"
        map_path = directory / "variants.map.json"
        translate(VARIANT_FIXTURE, output, map_path)
        outputs.append(output)
        maps.append(map_path)
    if outputs[0].read_bytes() != outputs[1].read_bytes():
        raise AssertionError("layout-variant output is not deterministic")
    if maps[0].read_bytes() != maps[1].read_bytes():
        raise AssertionError("layout-variant source map is not deterministic")
    generated = outputs[0].read_text()
    required = {
        "__la_10_ObjectKind__6_player__value = 1",
        "__la_10_HeaderView__5_flags__offset = 17",
        "__la_12_AlignedShape__1_b__offset = 2",
        "__la_12_AlignedShape__size = 8",
        "__la_13_ObjectPayload__4_pair__2_hi__offset = 1",
    }
    missing = sorted(line for line in required if line not in generated)
    if missing:
        raise AssertionError(f"missing variant constants: {missing}")
    frontend = first / "variants.bin"
    reference = first / "variants-reference.bin"
    run("customasm", outputs[0], "-f", "binary", "-o", frontend)
    run("customasm", VARIANT_REFERENCE, "-f", "binary", "-o", reference)
    if frontend.read_bytes() != reference.read_bytes():
        raise AssertionError(
            "enum/layout/union/overlay output differs from reference bytes"
        )


def check_full_rom(tmp: Path) -> tuple[int, str]:
    run(
        sys.executable,
        PREPARE,
        CELESTE_MAIN.parent,
        CELESTE_MEMMAP,
        FULL_LAYOUT,
        tmp,
    )
    obj_module = (
        tmp / "modules" / "obj.inlay.asm"
    ).read_text(encoding="ascii")
    expected_signature = (
        "proc obj_ptr using console6502\n"
        "    result : ptr CelesteObject return in pObj\n"
        "    slot : u8\n"
        "begin\n"
        "    address result, objects[a]\n"
        "    ret\n"
        "end"
    )
    if obj_module.count(expected_signature) != 1:
        raise AssertionError("generated obj_ptr did not use the exact unified signature")
    generated = tmp / "celeste.asm"
    translate(
        tmp / "celeste.inlay.asm", generated, tmp / "celeste.map.json"
    )
    baseline = tmp / "baseline.bin"
    frontend = tmp / "frontend.bin"
    run(
        "customasm", CELESTE_MAIN, "-t", "10", "--color=off",
        "--legacy=off", "-f", "binary", "-o", baseline
    )
    run(
        "customasm", generated, "-t", "10", "--color=off",
        "--legacy=off", "-f", "binary", "-o", frontend
    )
    baseline_bytes = baseline.read_bytes()
    if baseline_bytes != frontend.read_bytes():
        raise AssertionError("full Celeste ROM is not byte-for-byte equivalent")
    import hashlib
    return len(baseline_bytes), hashlib.sha256(baseline_bytes).hexdigest()


def main() -> int:
    if not INLAY.exists():
        raise SystemExit(f"missing {INLAY}; build the host frontend first")
    if not LAASM_COMPAT.exists():
        raise SystemExit(
            f"missing {LAASM_COMPAT}; build the compatibility launcher first"
        )
    version = run("customasm", "--version").stdout.strip()
    if not version.startswith("customasm v0.14.1"):
        raise AssertionError(f"expected customasm v0.14.1, got {version}")
    with (
        tempfile.TemporaryDirectory(
            prefix="inlay-a-", dir=ROOT / "build"
        ) as raw_a,
        tempfile.TemporaryDirectory(
            prefix="inlay-b-", dir=ROOT / "build"
        ) as raw_b,
    ):
        tmp_a = Path(raw_a)
        tmp_b = Path(raw_b)
        check_cli(tmp_a)
        stats = check_fixture(tmp_a, tmp_b)
        check_structured_fixture(tmp_a, tmp_b)
        check_variant_fixture(tmp_a, tmp_b)
        check_negative_sources(tmp_a)
        check_downstream_diagnostics(tmp_a)
        rom_size, rom_hash = check_full_rom(tmp_a)
    print(
        "Inlay conformance: passed; "
        f"fixture operations={stats['operations']}, "
        f"workspace={stats['workspaceBytes']} bytes; "
        f"Celeste ROM={rom_size} bytes sha256={rom_hash}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
