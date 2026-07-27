#!/usr/bin/env python3
"""Host-only conformance oracle for the portable Inlay C core."""

from __future__ import annotations

import json
import os
import re
import shutil
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
OVERLAY_ADDRESS_FIXTURE = ROOT / "tests/inlay/overlay_address.inlay.asm"
OVERLAY_ADDRESS_REFERENCE = ROOT / "tests/inlay/overlay_address_reference.asm"
CELESTE_DIR = ROOT / "src/celeste"
CELESTE_INLAY = CELESTE_DIR / "main.inlay.asm"
CELESTE_REFERENCE_DIR = (
    ROOT / "tests/inlay/reference/celeste-customasm"
)
CELESTE_MEMMAP = CELESTE_REFERENCE_DIR / "memmap.asm"
EXPECTED_CELESTE_TYPED_OPERATIONS = 89
EXPECTED_CELESTE_OVERLAY_OPERATIONS = 50
EXPECTED_CELESTE_OFFSET_SETUPS = 0
EXPECTED_CELESTE_SEMANTIC_OFFSETS = 97
EXPECTED_CELESTE_RAW_OBJECT_INDIRECTS = 129
READABLE_CELESTE_MODULES = {
    "audio.inlay.asm",
    "collide.inlay.asm",
    "draw.inlay.asm",
    "fx.inlay.asm",
    "game.inlay.asm",
    "gfx.inlay.asm",
    "layout.inlay.asm",
    "main.inlay.asm",
    "math.inlay.asm",
    "memmap.inlay.asm",
    "obj.inlay.asm",
    "player.inlay.asm",
    "platform.inlay.asm",
    "room.inlay.asm",
    "rooms.inlay.asm",
    "sound.inlay.asm",
}
EXPECTED_CELESTE_MODULES = {
    "audio.inlay.asm",
    "collide.inlay.asm",
    "draw.inlay.asm",
    "fx.inlay.asm",
    "game.inlay.asm",
    "gfx.inlay.asm",
    "layout.inlay.asm",
    "main.inlay.asm",
    "math.inlay.asm",
    "memmap.inlay.asm",
    "obj.inlay.asm",
    "player.inlay.asm",
    "platform.inlay.asm",
    "room.inlay.asm",
    "rooms.inlay.asm",
    "sound.inlay.asm",
}
EXPECTED_CELESTE_SEMANTIC_INCLUDES = {
    "layout.inlay.asm",
    "gfx.inlay.asm",
    "math.inlay.asm",
    "memmap.inlay.asm",
    "obj.inlay.asm",
    "collide.inlay.asm",
    "player.inlay.asm",
    "room.inlay.asm",
    "draw.inlay.asm",
    "fx.inlay.asm",
    "platform.inlay.asm",
    "game.inlay.asm",
    "sound.inlay.asm",
}
EXPECTED_CELESTE_OPAQUE_INCLUDES = {
    "rooms.inlay.asm",
    "audio.inlay.asm",
}
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
        == "inlay 0.2 language-format=1 target-format=2 map-format=2"
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


def check_overlay_address_fixture(first: Path, second: Path) -> None:
    outputs = []
    maps = []
    for directory in (first, second):
        output = directory / "overlay_address.asm"
        map_path = directory / "overlay_address.map.json"
        translate(OVERLAY_ADDRESS_FIXTURE, output, map_path)
        outputs.append(output)
        maps.append(map_path)
    if outputs[0].read_bytes() != outputs[1].read_bytes():
        raise AssertionError("overlay-address output is not deterministic")
    if maps[0].read_bytes() != maps[1].read_bytes():
        raise AssertionError("overlay-address source map is not deterministic")
    generated = outputs[0].read_text()
    for required in (
        "mov $1a, #<(TILE_RAM + 0)",
        "mov $1a+1, #>(TILE_RAM + 0)",
        "mov $1a, #<(TILE_RAM + 512)",
        "mov $10, #<(OBJECT_RAM + 17)",
        "inc $0030 + 0",
        "dec $0030 + 0",
        "and #254",
        "ora #1",
    ):
        if required not in generated:
            raise AssertionError(
                f"fixed-overlay lowering missing line: {required!r}"
            )
    frontend = first / "overlay_address.bin"
    reference = first / "overlay_address-reference.bin"
    run("customasm", outputs[0], "-f", "binary", "-o", frontend)
    run("customasm", OVERLAY_ADDRESS_REFERENCE, "-f", "binary", "-o", reference)
    if frontend.read_bytes() != reference.read_bytes():
        raise AssertionError(
            "overlay address materialization differs from reference bytes"
        )


def check_celeste_source_boundary(
    directory: Path = CELESTE_DIR,
) -> list[Path]:
    files = sorted(path for path in directory.iterdir() if path.is_file())
    names = {path.name for path in files}
    if names != EXPECTED_CELESTE_MODULES:
        raise AssertionError(
            "Celeste production module set changed: "
            f"expected {sorted(EXPECTED_CELESTE_MODULES)}, "
            f"got {sorted(names)}"
        )
    non_inlay = [path.name for path in files if not path.name.endswith(".inlay.asm")]
    if non_inlay:
        raise AssertionError(f"non-Inlay Celeste production files: {non_inlay}")

    semantic = set()
    opaque = set()
    semantic_pattern = re.compile(r'^include "([^"]+)"$')
    opaque_pattern = re.compile(r'^\s*#include "([^"]+)"$')
    for path in files:
        for number, line in enumerate(path.read_text(encoding="ascii").splitlines(), 1):
            if "tests/inlay/reference/celeste-customasm" in line:
                raise AssertionError(
                    f"{path}:{number}: production source references test oracle"
                )
            match = semantic_pattern.fullmatch(line)
            if match:
                requested = match.group(1)
                if "/" in requested or requested not in EXPECTED_CELESTE_MODULES:
                    raise AssertionError(
                        f"{path}:{number}: invalid local Inlay include {requested}"
                    )
                semantic.add(requested)
                continue
            match = opaque_pattern.fullmatch(line)
            if not match:
                continue
            requested = match.group(1)
            marker = "../../src/celeste/"
            if requested.startswith(marker):
                name = requested.removeprefix(marker)
                if name not in EXPECTED_CELESTE_OPAQUE_INCLUDES:
                    raise AssertionError(
                        f"{path}:{number}: unapproved opaque include {requested}"
                    )
                opaque.add(name)
    if semantic != EXPECTED_CELESTE_SEMANTIC_INCLUDES:
        raise AssertionError(
            "Celeste semantic include set changed: "
            f"expected {sorted(EXPECTED_CELESTE_SEMANTIC_INCLUDES)}, "
            f"got {sorted(semantic)}"
        )
    if opaque != EXPECTED_CELESTE_OPAQUE_INCLUDES:
        raise AssertionError(
            "Celeste opaque include set changed: "
            f"expected {sorted(EXPECTED_CELESTE_OPAQUE_INCLUDES)}, "
            f"got {sorted(opaque)}"
        )
    return files


def check_generated_gfx_payload() -> None:
    def payload(path: Path) -> bytes:
        values: list[int] = []
        for line in path.read_text(encoding="ascii").splitlines():
            if not line.lstrip().startswith("#d8 "):
                continue
            values.extend(
                int(value, 16)
                for value in re.findall(r"\$([0-9A-Fa-f]{2})", line)
            )
        return bytes(values)

    current = CELESTE_DIR / "gfx.inlay.asm"
    reference = CELESTE_REFERENCE_DIR / "gfx.asm"
    if payload(current) != payload(reference):
        raise AssertionError(
            "generated Gfx payload changed from the Phase-A asset oracle"
        )
    text = current.read_text(encoding="ascii")
    required = {
        "draw_palette", "player_slots", "sheet", "tile_base", "tile_attr",
        "upload_bytes",
        "player_attr", "smoke_first", "smoke_attr", "hair_big",
        "hair_small", "solid", "dot",
    }
    exports = set(re.findall(r"^\s*export ([a-z0-9_]+)$", text, re.MULTILINE))
    missing = required - exports
    if missing:
        raise AssertionError(f"Gfx public manifest is missing {sorted(missing)}")
    if "export smoke_stride" in text:
        raise AssertionError("Gfx implementation stride must remain private")
    if "export sheet_bytes" in text:
        raise AssertionError("Gfx implementation byte count must remain private")


def expect_celeste_boundary_failure(directory: Path, fragment: str) -> None:
    try:
        check_celeste_source_boundary(directory)
    except AssertionError as error:
        if fragment not in str(error):
            raise AssertionError(
                f"boundary failure did not mention {fragment!r}: {error}"
            ) from error
    else:
        raise AssertionError(
            f"Celeste source boundary accepted invalid case {fragment!r}"
        )


def check_celeste_boundary_failures(tmp: Path) -> None:
    corpus = tmp / "celeste-boundary"
    shutil.copytree(CELESTE_DIR, corpus)
    legacy = corpus / "legacy.asm"
    legacy.write_text("; forbidden legacy production source\n", encoding="ascii")
    expect_celeste_boundary_failure(corpus, "module set changed")
    legacy.unlink()

    main = corpus / "main.inlay.asm"
    original = main.read_text(encoding="ascii")
    main.write_text(
        original + '#include "../../src/celeste/math.inlay.asm"\n',
        encoding="ascii",
    )
    expect_celeste_boundary_failure(corpus, "unapproved opaque include")
    main.write_text(
        original
        + '#include "../../tests/inlay/reference/'
        + 'celeste-customasm/main.asm"\n',
        encoding="ascii",
    )
    expect_celeste_boundary_failure(corpus, "test oracle")


def eligible_legacy_field_loads(path: Path, text: str) -> list[str]:
    lines = text.splitlines()
    failures = []
    offset = re.compile(
        r"^\s*mov\s+y,\s+offset\s+(CelesteObject\.[A-Za-z0-9_.]+)"
    )
    load = re.compile(r"^\s*lda\s+\(pObj\),\s*y\b")
    kills_y = re.compile(r"^\s*(?:ldy\b|tay\b|mov\s+y,)")
    control_boundary = re.compile(
        r"^\s*(?:[.@A-Za-z_][.@A-Za-z0-9_]*:|"
        r"b(?:cc|cs|eq|mi|ne|pl|vc|vs|ra)\b|j(?:mp|sr)\b|rts\b)"
    )
    reads_y = re.compile(r"(?:\by\b|\(pObj\),\s*y)")
    for index, line in enumerate(lines[:-1]):
        match = offset.match(line)
        if not match or not load.match(lines[index + 1]):
            continue
        if "inlay-exception:" in line:
            continue
        for following in lines[index + 2:]:
            code = following.split(";", 1)[0].strip()
            if not code:
                continue
            if kills_y.match(code):
                failures.append(
                    f"{path.name}:{index + 1}: {match.group(1)}"
                )
                break
            if control_boundary.match(code) or reads_y.search(code):
                break
    return failures


def check_legacy_exception_contract() -> None:
    path = Path("fixture.inlay.asm")
    candidate = (
        "mov y, offset CelesteObject.core.kind\n"
        "lda (pObj), y\n"
        "ldy #0\n"
    )
    documented = (
        "mov y, offset CelesteObject.core.kind "
        "; inlay-exception: flags are consumed\n"
        "lda (pObj), y\n"
        "ldy #0\n"
    )
    assert eligible_legacy_field_loads(path, candidate)
    assert not eligible_legacy_field_loads(path, documented)


def check_platform_game_design() -> None:
    def check_namespace(
        filename: str,
        namespace: str,
        expected_exports: set[str],
        expected_procedures: dict[str, str],
    ) -> str:
        path = CELESTE_DIR / filename
        text = path.read_text(encoding="ascii")
        if text.count(f"namespace {namespace}\n") != 1:
            raise AssertionError(
                f"{filename}: expected one {namespace} namespace"
            )
        exports = set(re.findall(
            r"^\s*export ([a-z_]+)$", text, re.MULTILINE
        ))
        if exports != expected_exports:
            raise AssertionError(
                f"{namespace} export manifest changed: "
                f"expected {sorted(expected_exports)}, got {sorted(exports)}"
            )
        declarations = {
            match.group(1): match.group(0)
            for match in re.finditer(
                r"^proc ([a-z_]+) using console6502(?: naked)?$",
                text,
                re.MULTILINE,
            )
        }
        if declarations != expected_procedures:
            raise AssertionError(
                f"{namespace} procedure manifest changed: "
                f"expected {sorted(expected_procedures)}, "
                f"got {sorted(declarations)}"
            )
        lines = text.splitlines()
        for number, line in enumerate(lines):
            if not line.startswith("proc "):
                continue
            comments = []
            cursor = number - 1
            while cursor >= 0 and lines[cursor].startswith(";"):
                comments.append(lines[cursor][1:].strip())
                cursor -= 1
            contract = " ".join(reversed(comments))
            missing = [
                heading for heading in
                ("Inputs:", "Returns:", "Frame locals:", "Clobbers:")
                if heading not in contract
            ]
            if missing:
                raise AssertionError(
                    f"{filename}:{number + 1}: incomplete physical contract; "
                    f"missing {missing}"
                )
        return text

    platform = check_namespace(
        "platform.inlay.asm",
        "Platform",
        {"reset", "wait_frame", "sample_input"},
        {
            "reset": "proc reset using console6502 naked",
            "wait_frame": "proc wait_frame using console6502",
            "sample_input": "proc sample_input using console6502",
            "upload_palette": "proc upload_palette using console6502",
            "upload_sheet": "proc upload_sheet using console6502",
        },
    )
    if platform.count("jmp Game.run") != 1:
        raise AssertionError(
            "Platform.reset must transfer exactly once to Game.run"
        )
    game = check_namespace(
        "game.inlay.asm",
        "Game",
        {"run", "frame"},
        {
            "run": "proc run using console6502",
            "frame": "proc frame using console6502",
            "show_title": "proc show_title using console6502",
            "begin_play": "proc begin_play using console6502",
            "update": "proc update using console6502",
            "title_tick": "proc title_tick using console6502",
        },
    )
    for service in (
        "jsr Platform.wait_frame",
        "jsr Platform.sample_input",
        "jsr Game.update",
        "jsr Draw.frame",
    ):
        if service not in game:
            raise AssertionError(f"Game.frame lost required service: {service}")

    main = (CELESTE_DIR / "main.inlay.asm").read_text(encoding="ascii")
    if main.count("reset = Platform.reset") != 1:
        raise AssertionError("main reset binding must name Platform.reset")
    if main.count("main_loop = Game.frame") != 1:
        raise AssertionError("main debug frame binding must name Game.frame")
    permitted = re.compile(
        r"^(?:#include |include |#bank |#addr |#d8 |data codeptr |"
        r"reset = |main_loop = )"
    )
    if main.count("data codeptr Platform.reset") != 3:
        raise AssertionError(
            "main vector table must contain three semantic code pointers"
        )
    for number, line in enumerate(main.splitlines(), 1):
        code = line.split(";", 1)[0].strip()
        if code and not permitted.match(code):
            raise AssertionError(
                f"main.inlay.asm:{number}: composition root owns runtime "
                f"source: {code!r}"
            )


def check_objects_design() -> None:
    text = (CELESTE_DIR / "obj.inlay.asm").read_text(encoding="ascii")
    if text.count("namespace Objects\n") != 1:
        raise AssertionError("obj.inlay.asm must own one Objects namespace")
    expected_exports = {
        "pointer", "clear", "allocate", "dispatch", "spawn_smoke",
        "destroy", "update_all", "draw_all",
    }
    exports = set(re.findall(
        r"^\s*export ([a-z_]+)$", text, re.MULTILINE
    ))
    if exports != expected_exports:
        raise AssertionError(
            "Objects export manifest changed: "
            f"expected {sorted(expected_exports)}, got {sorted(exports)}"
        )
    expected_procedures = {
        "pointer": "proc pointer using console6502",
        "clear": "proc clear using console6502",
        "allocate": "proc allocate using console6502",
        "dispatch": "proc dispatch using console6502 naked",
        "spawn_smoke": "proc spawn_smoke using console6502",
        "destroy": "proc destroy using console6502",
        "update_all": "proc update_all using console6502",
        "draw_all": "proc draw_all using console6502",
        "move": "proc move using console6502",
        "prepare_step": "proc prepare_step using console6502 naked",
        "step_x": "proc step_x using console6502",
        "step_y": "proc step_y using console6502",
    }
    declarations = {
        match.group(1): match.group(0)
        for match in re.finditer(
            r"^proc ([a-z_]+) using console6502(?: naked)?$",
            text,
            re.MULTILINE,
        )
    }
    if declarations != expected_procedures:
        raise AssertionError(
            "Objects procedure manifest changed: "
            f"expected {sorted(expected_procedures)}, "
            f"got {sorted(declarations)}"
        )
    required = {
        "address result, objects[a]",
        "saved_self : ptr CelesteObject in frame",
        "mov [saved_self], self",
        "mov self, [saved_self]",
        "data u8 low(Player.init), low(Spawn.init), "
        "low(Smoke.init), low(Title.init)",
        "ldw value, [self + CelesteObject.core.remainder_x]",
        "ldw operand, [self + CelesteObject.core.speed_x]",
        "addw ab, operand",
        "stw [self + CelesteObject.core.remainder_y], value",
        "jsr Objects.prepare_step",
    }
    missing = sorted(item for item in required if item not in text)
    if missing:
        raise AssertionError(f"Objects semantic design changed: {missing}")
    manual_receiver_save = re.compile(
        r"lda pObj\s+pha\s+lda pObj\\+1\s+pha", re.MULTILINE
    )
    if manual_receiver_save.search(text):
        raise AssertionError(
            "Objects spawn path restored manual receiver stack plumbing"
        )
    legacy_names = {
        "obj_ptr", "obj_init", "init_object", "spawn_at", "destroy_object",
        "obj_update_all", "obj_move", "move_x", "move_y", "call_fn",
    }
    production = "\n".join(
        path.read_text(encoding="ascii")
        for path in sorted(CELESTE_DIR.glob("*.inlay.asm"))
    )
    found = sorted(
        name for name in legacy_names
        if re.search(rf"\b{name}\b", production)
    )
    if found:
        raise AssertionError(f"legacy object API names remain: {found}")


def check_object_kind_design() -> set[str]:
    text = (CELESTE_DIR / "player.inlay.asm").read_text(encoding="ascii")
    namespaces = ("Player", "Spawn", "Smoke", "Title")
    starts = []
    for namespace in namespaces:
        marker = f"namespace {namespace}\n"
        if text.count(marker) != 1:
            raise AssertionError(
                f"player.inlay.asm: expected one {namespace} namespace"
            )
        starts.append(text.index(marker))
    if starts != sorted(starts):
        raise AssertionError("Celeste object-kind namespace order changed")

    expected_procedures = {
        "Player": {
            "init", "update", "sample_input", "environment", "active_dash",
            "horizontal", "vertical", "jump_dash", "animation",
            "set_speed_x_signed", "set_speed_y_signed", "signed_word",
            "create_hair", "set_hair_color", "draw_hair", "kill", "draw",
        },
        "Spawn": {"init", "update", "draw"},
        "Smoke": {"init", "update", "draw"},
        "Title": {"init", "update", "draw"},
    }
    lifecycle = set()
    for index, namespace in enumerate(namespaces):
        finish = starts[index + 1] if index + 1 < len(starts) else len(text)
        body = text[starts[index]:finish]
        exports = set(re.findall(
            r"^\s*export ([a-z_]+)$", body, re.MULTILINE
        ))
        if exports != {"init", "update", "draw"}:
            raise AssertionError(
                f"{namespace} export manifest changed: "
                f"expected ['draw', 'init', 'update'], got {sorted(exports)}"
            )
        procedures = set(re.findall(
            r"^proc ([a-z_]+) using console6502(?: naked)?$",
            body,
            re.MULTILINE,
        ))
        if procedures != expected_procedures[namespace]:
            raise AssertionError(
                f"{namespace} procedure manifest changed: "
                f"expected {sorted(expected_procedures[namespace])}, "
                f"got {sorted(procedures)}"
            )
        lifecycle.update(
            f"{namespace}.{operation}"
            for operation in ("init", "update", "draw")
        )

    required = {
        "jmp Player.sample_input",
        "jmp Player.environment",
        "jmp Player.active_dash",
        "jmp Player.horizontal",
        "jmp Player.vertical",
        "jmp Player.jump_dash",
        "jmp Player.animation",
        "input = $50",
        "wall = $5F",
        "jmp Draw.hair_create",
        "jmp Draw.hair_color",
        "jmp Draw.hair_draw",
    }
    missing = sorted(item for item in required if item not in text)
    if missing:
        raise AssertionError(
            f"Celeste object-kind semantic design changed: {missing}"
        )
    production = "\n".join(
        path.read_text(encoding="ascii")
        for path in sorted(CELESTE_DIR.glob("*.inlay.asm"))
    )
    legacy_scratch = sorted(set(re.findall(r"\bp_[a-z_]+\b", production)))
    if legacy_scratch:
        raise AssertionError(
            f"legacy file-scope player scratch remains: {legacy_scratch}"
        )
    return lifecycle


def check_remaining_subsystem_design() -> None:
    manifests = {
        "collide.inlay.asm": (
            "Collision",
            {"solid", "ice", "box", "spikes"},
            {
                "solid", "ice", "box", "flags", "tiles", "floor", "spikes",
                "ids", "lo", "hi",
            },
            {"down", "up", "right", "left"},
        ),
        "room.inlay.asm": (
            "Room",
            {"init", "title", "load", "next", "restart", "camera"},
            {
                "init", "title", "load", "next", "cue_level", "cue_music",
                "restart", "camera",
            },
            set(),
        ),
        "draw.inlay.asm": (
            "Draw",
            {
                "frame", "sprite", "object", "hair_create", "hair_color",
                "hair_draw", "overlay_init", "overlay_dirty", "room_title",
            },
            {
                "frame", "palette", "palette_slots", "sprite", "object",
                "position", "hair_create", "hair_color", "hair_palette",
                "hair_draw", "hair_chase", "asr_w1", "asr_w2",
                "overlay_init", "overlay_dirty", "overlay_clear",
                "overlay_begin", "overlay_end", "char", "text", "string",
                "byte", "hud", "title_credits", "room_title", "str_time",
                "str_dead", "str_oldsite", "str_summit", "str_xc",
                "str_thorson", "str_berry", "font",
            },
            set(),
        ),
        "sound.inlay.asm": (
            "Audio",
            {"init", "sfx", "guarded_sfx", "music", "fade", "stop"},
            {
                "init", "sfx", "channel_bits", "guarded_sfx", "music",
                "fade", "stop",
            },
            set(),
        ),
    }
    for filename, manifest in manifests.items():
        namespace, expected_exports, expected_labels, expected_procs = manifest
        text = (CELESTE_DIR / filename).read_text(encoding="ascii")
        if text.count(f"namespace {namespace}\n") != 1:
            raise AssertionError(
                f"{filename}: expected one {namespace} namespace"
            )
        exports = set(re.findall(
            r"^\s*export ([a-z_]+)$", text, re.MULTILINE
        ))
        labels = set(re.findall(
            r"^([a-z_][a-z0-9_]*):$", text, re.MULTILINE
        ))
        procedures = set(re.findall(
            r"^proc ([a-z_]+) using console6502(?: naked)?$",
            text,
            re.MULTILINE,
        ))
        if exports != expected_exports:
            raise AssertionError(
                f"{namespace} export manifest changed: "
                f"expected {sorted(expected_exports)}, got {sorted(exports)}"
            )
        if labels != expected_labels:
            raise AssertionError(
                f"{namespace} label manifest changed: "
                f"expected {sorted(expected_labels)}, got {sorted(labels)}"
            )
        if procedures != expected_procs:
            raise AssertionError(
                f"{namespace} procedure manifest changed: "
                f"expected {sorted(expected_procs)}, "
                f"got {sorted(procedures)}"
            )

    collision = (CELESTE_DIR / "collide.inlay.asm").read_text(
        encoding="ascii"
    )
    for declaration in (
        "data u8 low(down), low(up), low(right), low(left)",
        "data u8 high(down), high(up), high(right), high(left)",
    ):
        if collision.count(declaration) != 1:
            raise AssertionError(
                "Collision dispatch data lost semantic procedure addresses"
            )

    production = "\n".join(
        path.read_text(encoding="ascii")
        for path in sorted(CELESTE_DIR.glob("*.inlay.asm"))
    )
    required_qualified_calls = {
        "Collision.solid", "Collision.ice", "Collision.box",
        "Collision.spikes", "Room.init", "Room.title", "Room.load",
        "Room.next", "Room.restart", "Room.camera", "Draw.frame",
        "Draw.sprite", "Draw.object", "Draw.hair_create", "Draw.hair_color",
        "Draw.hair_draw", "Draw.overlay_init", "Draw.overlay_dirty",
        "Draw.room_title", "Audio.init", "Audio.sfx", "Audio.guarded_sfx",
        "Audio.music", "Audio.fade", "Audio.stop",
    }
    missing = sorted(
        name for name in required_qualified_calls if name not in production
    )
    if missing:
        raise AssertionError(
            f"remaining subsystem qualified-call manifest changed: {missing}"
        )

    expected_exceptions = {
        "branch observes pre-decrement value": 3,
        "complemented target constant": 6,
        "following flags feed control flow": 2,
        "mask constant remains target-owned": 3,
        "variable update operand t0": 4,
        "variable update operand t1": 2,
        "wrapping add-and-mask update": 1,
    }
    exception_reasons = re.findall(
        r"inlay-exception: ([^\n]+)", production
    )
    actual_exceptions = {
        reason: exception_reasons.count(reason)
        for reason in set(exception_reasons)
    }
    if actual_exceptions != expected_exceptions:
        raise AssertionError(
            "Celeste raw-sequence exception audit changed: "
            f"expected {expected_exceptions}, got {actual_exceptions}"
        )

    raw_slices = {
        path.name: len(re.findall(r"\([^)]*\)\[(?:7:0|15:8)\]", text))
        for path in sorted(CELESTE_DIR.glob("*.inlay.asm"))
        for text in [path.read_text(encoding="ascii")]
        if re.search(r"\([^)]*\)\[(?:7:0|15:8)\]", text)
    }
    if raw_slices != {"obj.inlay.asm": 4, "rooms.inlay.asm": 8}:
        raise AssertionError(
            "raw target address-slice audit changed: "
            f"expected obj=4 and rooms=8, got {raw_slices}"
        )


def check_full_rom(tmp: Path) -> tuple[int, str, int, int, int]:
    production_files = check_celeste_source_boundary()
    check_platform_game_design()
    check_objects_design()
    lifecycle_names = check_object_kind_design()
    check_remaining_subsystem_design()
    module_texts = [
        path.read_text(encoding="ascii")
        for path in production_files
    ]
    missed_field_loads = [
        failure
        for path, text in zip(production_files, module_texts)
        for failure in eligible_legacy_field_loads(path, text)
    ]
    if missed_field_loads:
        raise AssertionError(
            "mechanically eligible legacy field load remains; use a typed "
            "operand or add an inlay-exception reason:\n"
            + "\n".join(missed_field_loads)
        )
    typed_operations = sum(
        len(re.findall(r"\[(?:pObj|pOth) \+ CelesteObject\.", text))
        for text in module_texts
    )
    if typed_operations != EXPECTED_CELESTE_TYPED_OPERATIONS:
        raise AssertionError(
            "checked-in Celeste typed-operation count changed: "
            f"expected {EXPECTED_CELESTE_TYPED_OPERATIONS}, "
            f"got {typed_operations}"
        )
    overlay_operations = sum(
        len(re.findall(
            r"\[(?:video|psg|framebuffer|tile_map|zero_page|game|"
            r"room_tiles|overlay_rows|overlay_shadow) \+ "
            r"(?:VideoRegisters|PsgRegisters|OverlayFramebuffer|TileMap|"
            r"ZeroPageWorking|GameState|RoomTileBuffer|"
            r"OverlayRowPointers)\.",
            text,
        ))
        for text in module_texts
    )
    if overlay_operations != EXPECTED_CELESTE_OVERLAY_OPERATIONS:
        raise AssertionError(
            "checked-in Celeste overlay-operation count changed: "
            f"expected {EXPECTED_CELESTE_OVERLAY_OPERATIONS}, "
            f"got {overlay_operations}"
        )
    offset_setups = sum(
        len(re.findall(r"^\s*ldy\s+#O_[A-Z0-9_]+\b", text, re.MULTILINE))
        for text in module_texts
    )
    if offset_setups != EXPECTED_CELESTE_OFFSET_SETUPS:
        raise AssertionError(
            "checked-in Celeste legacy offset-setup count changed: "
            f"expected {EXPECTED_CELESTE_OFFSET_SETUPS}, got {offset_setups}"
        )
    semantic_offsets = sum(
        len(re.findall(
            r"^\s*mov\s+[axy],\s+offset\s+CelesteObject\.",
            text,
            re.MULTILINE,
        ))
        for text in module_texts
    )
    if semantic_offsets != EXPECTED_CELESTE_SEMANTIC_OFFSETS:
        raise AssertionError(
            "checked-in Celeste semantic offset count changed: "
            f"expected {EXPECTED_CELESTE_SEMANTIC_OFFSETS}, "
            f"got {semantic_offsets}"
        )
    raw_indirects = sum(
        len(re.findall(r"\((?:pObj|pOth)\),\s*y\b", text))
        for text in module_texts
    )
    if raw_indirects != EXPECTED_CELESTE_RAW_OBJECT_INDIRECTS:
        raise AssertionError(
            "checked-in Celeste raw object-indirect count changed: "
            f"expected {EXPECTED_CELESTE_RAW_OBJECT_INDIRECTS}, "
            f"got {raw_indirects}"
        )
    for path, text in zip(production_files, module_texts):
        if path.name not in READABLE_CELESTE_MODULES:
            continue
        comment_lines = sum(
            line.lstrip().startswith(";") for line in text.splitlines()
        )
        if comment_lines == 0:
            raise AssertionError(f"{path.name}: restored commentary is missing")
        if re.search(r"\n[ \t]*\n[ \t]*\n[ \t]*\n", text):
            raise AssertionError(f"{path.name}: excessive blank-line run")
    layout_module = (CELESTE_DIR / "layout.inlay.asm").read_text(
        encoding="ascii"
    )
    required_layout_declarations = {
        "enum ObjectKind : u8",
        "enum SpawnPhase : u8",
        "union ObjectPayload",
        "struct VideoRegisters",
        "struct PsgRegisters",
        "struct TileMap packed",
        "struct OverlayFramebuffer packed",
        "struct RoomTileBuffer packed",
        "struct OverlayRowPointers",
        "struct ZeroPageWorking",
        "struct GameState",
        "overlay video : VideoRegisters at $4000 volatile",
        "overlay psg : PsgRegisters at $4100 volatile",
        "overlay framebuffer : OverlayFramebuffer at $e000 volatile",
        "overlay tile_map : TileMap at $f000",
        "overlay zero_page : ZeroPageWorking at $0000",
        "overlay game : GameState at $0030",
        "overlay room_tiles : RoomTileBuffer at $5400",
        "overlay overlay_rows : OverlayRowPointers at $5500",
        "overlay overlay_shadow : OverlayFramebuffer at $6000",
    }
    missing_layout = sorted(
        item for item in required_layout_declarations
        if layout_module.count(item) != 1
    )
    if missing_layout:
        raise AssertionError(
            f"Celeste semantic layout manifest changed: {missing_layout}"
        )
    generated = tmp / "celeste.asm"
    translate(
        CELESTE_INLAY, generated, tmp / "celeste.map.json"
    )
    generated_text = generated.read_text(encoding="ascii")
    for name in lifecycle_names:
        target_name = "__inlay_q" + "".join(
            f"{len(component)}_{component}"
            for component in name.split(".")
        ) + ":"
        if generated_text.count(target_name) != 1:
            raise AssertionError(
                f"qualified procedure {name} did not lower to {target_name}"
            )
    frontend = tmp / "frontend.bin"
    run(
        "customasm", generated, "-t", "10", "--color=off",
        "--legacy=off", "-f", "binary", "-o", frontend
    )
    import hashlib
    frontend_bytes = frontend.read_bytes()
    digest = hashlib.sha256(frontend_bytes).hexdigest()
    if len(frontend_bytes) != 65536:
        raise AssertionError(
            f"Celeste ROM size changed: expected 65536, got {len(frontend_bytes)}"
        )
    metrics_path = (
        ROOT / "tests/inlay/reference/celeste-phase-b-final.json"
    )
    metrics = json.loads(metrics_path.read_text(encoding="ascii"))
    expected_assembly = {
        "encodedInstructionSites": 2329,
        "executableBytes": 5161,
        "programSpanBytes": 12813,
        "programSpanEndExclusive": 13581,
        "programSpanStart": 768,
    }
    if metrics.get("phase") != "celeste-inlay-phase-b":
        raise AssertionError("Celeste final metrics phase changed")
    if metrics.get("assembly") != expected_assembly:
        raise AssertionError("Celeste final assembly measurements changed")
    if metrics.get("rom", {}).get("bytes") != len(frontend_bytes):
        raise AssertionError("Celeste final metric ROM size is stale")
    if metrics.get("rom", {}).get("sha256") != digest:
        raise AssertionError("Celeste final metric ROM digest is stale")
    measured_source = metrics.get("source", {})
    if measured_source.get("objectOffsetSetups") != offset_setups:
        raise AssertionError("Celeste final offset measurement is stale")
    if measured_source.get("rawObjectIndirects") != raw_indirects:
        raise AssertionError("Celeste final indirect measurement is stale")
    custom_operations = {
        operation: sum(
            len(re.findall(
                rf"^\s*{operation}\b", text, re.MULTILINE
            ))
            for text in module_texts
        )
        for operation in (
            "mov", "add", "sub", "ldab", "stab", "addw", "subw", "cmpw",
            "cbeq", "cbne", "cblt", "cbge", "tbz", "tbnz", "bzero",
            "bnzero",
        )
    }
    if measured_source.get("customOperations") != custom_operations:
        raise AssertionError("Celeste final custom-operation metrics are stale")
    return (
        len(frontend_bytes), digest, overlay_operations,
        offset_setups, raw_indirects,
    )


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
        check_overlay_address_fixture(tmp_a, tmp_b)
        check_negative_sources(tmp_a)
        check_downstream_diagnostics(tmp_a)
        check_celeste_boundary_failures(tmp_a)
        check_generated_gfx_payload()
        check_legacy_exception_contract()
        (
            rom_size, rom_hash, overlay_operations,
            offset_setups, raw_indirects,
        ) = check_full_rom(tmp_a)
    print(
        "Inlay conformance: passed; "
        f"fixture operations={stats['operations']}, "
        f"workspace={stats['workspaceBytes']} bytes; "
        f"Celeste overlay operations={overlay_operations}, "
        f"legacy offset setups={offset_setups}, "
        f"raw object indirects={raw_indirects}; "
        f"ROM={rom_size} bytes sha256={rom_hash}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
