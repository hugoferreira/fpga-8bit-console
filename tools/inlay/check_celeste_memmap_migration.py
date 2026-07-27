#!/usr/bin/env python3
"""Freeze the Celeste compatibility aliases while they are being removed."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CHANGE = ROOT / "openspec/changes/replace-celeste-raw-memmap"
INVENTORY = CHANGE / "legacy-aliases.txt"
MEMMAP = ROOT / "src/celeste/memmap.inlay.asm"
DEFINITION = re.compile(
    r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
    r"(\$[0-9A-Fa-f]+|[0-9]+)\b"
)


def inventory() -> dict[str, str]:
    result: dict[str, str] = {}
    for line_number, line in enumerate(
        INVENTORY.read_text(encoding="ascii").splitlines(), 1
    ):
        if not line or line.startswith("#"):
            continue
        try:
            _, name, value = line.split("|")
        except ValueError as error:
            raise AssertionError(
                f"{INVENTORY}:{line_number}: malformed inventory row"
            ) from error
        if name in result:
            raise AssertionError(f"duplicate inventoried alias: {name}")
        result[name] = value.lower()
    return result


def definitions() -> dict[str, str]:
    result: dict[str, str] = {}
    for line_number, line in enumerate(
        MEMMAP.read_text(encoding="ascii").splitlines(), 1
    ):
        match = DEFINITION.match(line.split(";", 1)[0])
        if not match:
            continue
        name, value = match.groups()
        if name in result:
            raise AssertionError(
                f"{MEMMAP}:{line_number}: duplicate alias {name}"
            )
        result[name] = value.lower()
    return result


# The one legacy address deliberately retained (reviewed): the object pool base
# is consumed by the pool strategy's raw obj_lo/obj_hi target tables.
RETAINED = {"OBJPOOL"}
HANDWRITTEN = sorted((ROOT / "src/celeste").glob("*.inlay.asm"))


def deny_list(expected: dict[str, str]) -> int:
    """Permanent gate: no handwritten module may reintroduce a legacy alias as a
    bare `NAME = VALUE` compatibility definition once the memory map is gone."""
    if MEMMAP.exists():
        print(f"{MEMMAP} must be deleted; the deny-list is now permanent",
              file=sys.stderr)
        return 1
    violations: list[str] = []
    for path in HANDWRITTEN:
        for number, line in enumerate(
            path.read_text(encoding="ascii").splitlines(), 1
        ):
            match = DEFINITION.match(line.split(";", 1)[0])
            if not match:
                continue
            name = match.group(1)
            if name in expected and name not in RETAINED:
                violations.append(f"{path.name}:{number}: {name}")
    if violations:
        print("reintroduced legacy alias definitions:\n  "
              + "\n  ".join(violations), file=sys.stderr)
        return 1
    print(
        "Celeste memmap deny-list: memory map deleted, "
        f"{len(expected)} aliases retired, {len(RETAINED)} reviewed retention"
    )
    return 0


def main() -> int:
    expected = inventory()
    if not MEMMAP.exists():
        return deny_list(expected)
    actual = definitions()
    added = sorted(actual.keys() - expected.keys())
    changed = sorted(
        name for name in actual.keys() & expected.keys()
        if actual[name] != expected[name]
    )
    if added or changed:
        if added:
            print("unrecorded legacy aliases: " + ", ".join(added),
                  file=sys.stderr)
        if changed:
            print("changed legacy aliases: " + ", ".join(changed),
                  file=sys.stderr)
        return 1
    print(
        f"Celeste migration alias gate: {len(actual)} aliases, "
        f"{len(expected) - len(actual)} removed"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
