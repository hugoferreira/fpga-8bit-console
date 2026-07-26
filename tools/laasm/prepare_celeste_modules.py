#!/usr/bin/env python3
"""Generate compact, layout-owned Celeste module copies for laasm."""

from pathlib import Path
import re
import sys


EXPECTED_CONVERSIONS = 66
EXPECTED_PROCEDURES = 1
FRONTEND_MODULES = {"obj", "collide", "player", "draw"}
GAME_MODULES = {
    "gfx",
    "rooms",
    "audio",
    "math",
    "obj",
    "collide",
    "player",
    "room",
    "draw",
    "fx",
    "sound",
}
FIELDS = {
    "O_TYPE": "kind",
    "O_SPR": "sprite",
    "O_X": "x",
    "O_Y": "y",
    "O_SPDX": "speed_x.fraction",
    "O_SPDY": "speed_y.fraction",
    "O_REMX": "remainder_x.fraction",
    "O_REMY": "remainder_y.fraction",
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
    "O_DTX": "dash_target_x.fraction",
    "O_DTY": "dash_target_y.fraction",
    "O_DAX": "dash_accel_x.fraction",
    "O_DAY": "dash_accel_y.fraction",
    "O_TGTX": "target_x",
    "O_TGTY": "target_y",
}
ISA_INCLUDE = re.compile(
    r'^#include "\.\./isa/(nmos6502|ext_core|pseudo|memmap)\.asm"$'
)
LOCAL_MEMMAP_INCLUDE = re.compile(r'^\s*#include "memmap\.asm"$')
GAME_INCLUDE = re.compile(
    r'^(?P<indent>\s*)#include "'
    r'(?P<name>gfx|rooms|audio|math|obj|collide|player|room|draw|fx|sound)'
    r'\.asm"$'
)
DIRECT = re.compile(
    r"^(?P<indent>\s*)(?P<op>lda|sta) "
    r"\((?P<base>pObj|pOth)\), #(?P<field>O_[A-Z0-9_]+)"
    r"(?P<high>\+1)?(?P<comment>\s*(?:;.*)?)$"
)
ANY_DIRECT = re.compile(r"^\s*(?:lda|sta) \((?:pObj|pOth)\), #O_")
OBJECT_LAYOUT_START = re.compile(r"^\s*O_TYPE\s*=")
OBJECT_LAYOUT_END = re.compile(r"^\s*O_SIZE\s*=")
OBJECT_LAYOUT_DECLARATION = re.compile(
    r"^\s*O_[A-Z0-9_]+\s*=\s*[0-9]+(?:\s*;.*)?$"
)
OBJ_PTR = """obj_ptr:
    tax
    mov pObj, obj_lo + x
    lda obj_hi, x
    sta pObj+1
    rts"""
OBJ_PTR_STRUCTURED = """proc obj_ptr using console6502
    result : ptr CelesteObject return in pObj
    slot : u8
begin
    address result, objects[a]
    ret
end"""


def compact(line: str) -> str:
    """Remove comments without removing lines, preserving original line numbers."""
    return line.split(";", 1)[0].rstrip()


def write_lines(destination: Path, lines: list[str]) -> None:
    destination.write_text("\n".join(lines) + "\n", encoding="ascii")


def convert_module(source: Path, destination: Path) -> tuple[int, int]:
    converted = 0
    procedures = 0
    output = []
    text = source.read_text(encoding="ascii")
    if source.stem == "obj":
        if text.count(OBJ_PTR) != EXPECTED_PROCEDURES:
            raise SystemExit(
                f"{source}: expected one exact obj_ptr implementation"
            )
        text = text.replace(OBJ_PTR, OBJ_PTR_STRUCTURED)
        procedures = EXPECTED_PROCEDURES
    for number, line in enumerate(text.splitlines(), 1):
        match = DIRECT.match(line)
        if match:
            field = match.group("field")
            if field not in FIELDS:
                raise SystemExit(f"{source}:{number}: unmapped direct field {field}")
            path = FIELDS[field]
            if match.group("high"):
                if not path.endswith(".fraction"):
                    raise SystemExit(
                        f"{source}:{number}: +1 is invalid for scalar {field}"
                    )
                path = path.removesuffix(".fraction") + ".integer"
            comment = match.group("comment")
            output.append(
                f"{match.group('indent')}{match.group('op')} "
                f"[{match.group('base')} + CelesteObject.{path}]{comment}"
            )
            converted += 1
        else:
            if ANY_DIRECT.match(line):
                raise SystemExit(
                    f"{source}:{number}: unrecognised eligible direct operation: {line}"
                )
            output.append(compact(line))
    write_lines(destination, output)
    return converted, procedures


def prepare_main(main: Path, destination: Path) -> None:
    isa_includes = 0
    local_memmap = 0
    module_includes = set()
    output = []
    for line in main.read_text(encoding="ascii").splitlines():
        if ISA_INCLUDE.match(line):
            isa_includes += 1
            output.append("")
            continue
        if LOCAL_MEMMAP_INCLUDE.match(line):
            local_memmap += 1
            output.append('    #include "celeste_memmap.asm"')
            continue
        match = GAME_INCLUDE.match(line)
        if match:
            name = match.group("name")
            module_includes.add(name)
            if name in FRONTEND_MODULES:
                output.append(f'include "{name}.la.asm"')
            else:
                output.append(
                    f'{match.group("indent")}#include "../../src/celeste/{name}.asm"'
                )
            continue
        output.append(compact(line))
    if isa_includes != 4 or local_memmap != 1 or module_includes != GAME_MODULES:
        raise SystemExit("prepare_celeste_modules: unexpected main include structure")
    write_lines(destination, output)


def prepare_memmap(source: Path, destination: Path) -> None:
    output = []
    in_object = False
    starts = 0
    ends = 0
    for line in source.read_text(encoding="ascii").splitlines():
        if OBJECT_LAYOUT_START.match(line):
            in_object = True
            starts += 1
        if in_object:
            if (
                line.strip()
                and not line.lstrip().startswith(";")
                and not OBJECT_LAYOUT_DECLARATION.match(line)
            ):
                raise SystemExit(f"unrecognised object-layout declaration: {line}")
            if OBJECT_LAYOUT_END.match(line):
                in_object = False
                ends += 1
            output.append("")
        else:
            output.append(line)
    if starts != 1 or ends != 1 or in_object:
        raise SystemExit("object-layout block was not contiguous")
    write_lines(destination, output)


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(
            "usage: prepare_celeste_modules.py "
            "CELESTE_SOURCE_DIR MEMMAP LAYOUT_ENTRY OUTPUT_DIR"
        )
    source_dir = Path(sys.argv[1])
    memmap = Path(sys.argv[2])
    layout_entry = Path(sys.argv[3])
    output_dir = Path(sys.argv[4])
    modules = output_dir / "modules"
    modules.mkdir(parents=True, exist_ok=True)
    (output_dir / "celeste.la.asm").write_bytes(layout_entry.read_bytes())
    prepare_main(source_dir / "main.asm", modules / "celeste_body.la.asm")
    prepare_memmap(memmap, output_dir / "celeste_memmap.asm")
    results = [
        convert_module(source_dir / f"{name}.asm", modules / f"{name}.la.asm")
        for name in sorted(FRONTEND_MODULES)
    ]
    converted = sum(result[0] for result in results)
    procedures = sum(result[1] for result in results)
    if converted != EXPECTED_CONVERSIONS:
        raise SystemExit(
            f"expected {EXPECTED_CONVERSIONS} conversions, generated {converted}"
        )
    if procedures != EXPECTED_PROCEDURES:
        raise SystemExit(
            f"expected {EXPECTED_PROCEDURES} procedure migration, "
            f"generated {procedures}"
        )
    print(
        f"prepared {len(FRONTEND_MODULES)} modules; converted {converted} "
        f"operations and {procedures} procedure"
    )


if __name__ == "__main__":
    main()
