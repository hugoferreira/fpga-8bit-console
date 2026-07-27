#!/usr/bin/env python3
"""Measure the immutable Phase-A Celeste baseline and later redesigns."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HANDWRITTEN = (
    "main.inlay.asm",
    "math.inlay.asm",
    "obj.inlay.asm",
    "collide.inlay.asm",
    "player.inlay.asm",
    "room.inlay.asm",
    "draw.inlay.asm",
    "fx.inlay.asm",
    "sound.inlay.asm",
    "platform.inlay.asm",
    "game.inlay.asm",
)
CUSTOM_OPS = (
    "mov", "add", "sub", "ldab", "stab", "addw", "subw", "cmpw",
    "cbeq", "cbne", "cblt", "cbge", "tbz", "tbnz", "bzero", "bnzero",
)
PHASE_A_VISUAL = {
    "title":
        "9f6d80ffa88c5b2833c95c6a9b36553133d5e0bd3ea9fc24f66cbcf91d43b53c",
    "first-room-play":
        "f6baa171ed5e6f3d4b9689316cc397b50d40436fedf16a9ce0096d71176ed993",
    "hud":
        "654a80be192ffa148acc3a9924c4f9b7660671b2a7b017cc239fd0ce8a7c303f",
    "room-transition":
        "7520f38e450645c502cfdecdf9668522ee4db7e6b2bac37af8137653a3f29091",
}
PHASE_A_AUDIO_TRACE = (
    "0f40c1e74d5de88e5fa973794285010fd20cfdd02e7317451e7ae3f3f0a74ca8"
)
TARGET_OPS = set(
    """
    adc and asl bcc bcs beq bit bmi bne bpl brk bvc bvs clc cld cli clv cmp
    cpx cpy dec dex dey eor inc inx iny jmp jsr lda ldx ldy lsr nop ora pha
    php pla plp rol ror rti rts sbc sec sed sei sta stx sty tax tay tsx txa
    txs tya
    """.split()
) | set(CUSTOM_OPS)
PAIR_KINDS = {
    ("lda", "sta"): "lda_sta",
    ("clc", "adc"): "clc_adc",
    ("sec", "sbc"): "sec_sbc",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_instructions(path: Path) -> list[tuple[int, str, str]]:
    result = []
    for number, raw in enumerate(path.read_text(encoding="ascii").splitlines(), 1):
        code = raw.split(";", 1)[0].strip()
        if not code:
            continue
        if ":" in code:
            prefix, rest = code.split(":", 1)
            if re.fullmatch(r"[.@A-Za-z_][.@A-Za-z0-9_]*", prefix.strip()):
                code = rest.strip()
        match = re.match(r"([A-Za-z][A-Za-z0-9_]*)\b(.*)$", code)
        if match:
            result.append((number, match.group(1).lower(), match.group(2).strip()))
    return result


def legacy_candidates(paths: list[Path]) -> list[dict[str, object]]:
    result = []
    for path in paths:
        instructions = source_instructions(path)
        for index, (line, mnemonic, operand) in enumerate(instructions):
            if index + 1 < len(instructions):
                next_line, next_mnemonic, next_operand = instructions[index + 1]
                kind = PAIR_KINDS.get((mnemonic, next_mnemonic))
                if kind is not None:
                    result.append({
                        "kind": kind,
                        "path": str(path.relative_to(ROOT)),
                        "line": line,
                        "nextLine": next_line,
                        "operands": [operand, next_operand],
                    })
            if index + 2 < len(instructions):
                second = instructions[index + 1]
                third = instructions[index + 2]
                kind = None
                if mnemonic == "lda" and second[1] == "cmp" and third[1].startswith("b"):
                    kind = "lda_cmp_branch"
                elif mnemonic == "lda" and second[1] == "and" and third[1].startswith("b"):
                    kind = "lda_and_branch"
                if kind is not None:
                    result.append({
                        "kind": kind,
                        "path": str(path.relative_to(ROOT)),
                        "line": line,
                        "nextLine": third[0],
                        "operands": [operand, second[2], third[2]],
                    })
    return result


def annotated_metrics(path: Path) -> dict[str, int]:
    instruction_sites = 0
    executable_bytes = 0
    addresses = []
    pattern = re.compile(
        r"\s*([0-9a-f]+):[0-9]+\s*\|[^|]*\|\s*"
        r"([0-9a-f ]*)\s*;\s*(.*)$",
        re.IGNORECASE,
    )
    for line in path.read_text(encoding="ascii").splitlines():
        match = pattern.match(line)
        if not match:
            continue
        address = int(match.group(1), 16)
        encoded = re.findall(r"\b[0-9a-f]{2}\b", match.group(2), re.IGNORECASE)
        if 0x0300 <= address < 0x5000 and encoded:
            addresses.extend(range(address, address + len(encoded)))
        source = match.group(3).strip()
        instruction = re.match(
            r"(?:[.@A-Za-z_][.@A-Za-z0-9_]*:\s*)?"
            r"([A-Za-z][A-Za-z0-9_]*)\b",
            source,
        )
        if (
            encoded
            and instruction is not None
            and instruction.group(1).lower() in TARGET_OPS
        ):
            instruction_sites += 1
            executable_bytes += len(encoded)
    return {
        "encodedInstructionSites": instruction_sites,
        "executableBytes": executable_bytes,
        "programSpanStart": min(addresses),
        "programSpanEndExclusive": max(addresses) + 1,
        "programSpanBytes": max(addresses) + 1 - min(addresses),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=ROOT / "src/celeste")
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--symbols", type=Path, required=True)
    parser.add_argument("--annotated", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--phase", default="celeste-inlay-phase-a",
        choices=("celeste-inlay-phase-a", "celeste-inlay-phase-b"),
    )
    args = parser.parse_args()
    args.source = args.source.resolve()
    args.binary = args.binary.resolve()
    args.symbols = args.symbols.resolve()
    args.annotated = args.annotated.resolve()
    if args.output is not None:
        args.output = args.output.resolve()

    paths = [args.source / name for name in HANDWRITTEN]
    texts = {path: path.read_text(encoding="ascii") for path in paths}
    combined = "\n".join(texts.values())
    candidates = legacy_candidates(paths)
    custom = {
        operation: len(re.findall(
            rf"^\s*{operation}\b", combined, re.MULTILINE
        ))
        for operation in CUSTOM_OPS
    }
    offset_sites = [
        {
            "path": str(path.relative_to(ROOT)),
            "line": number,
            "field": match.group(1),
        }
        for path, text in texts.items()
        for number, line in enumerate(text.splitlines(), 1)
        if (match := re.match(r"^\s*ldy\s+#(O_[A-Z0-9_]+)\b", line))
    ]
    raw_indirect_sites = [
        {
            "path": str(path.relative_to(ROOT)),
            "line": number,
            "base": match.group(1),
        }
        for path, text in texts.items()
        for number, line in enumerate(text.splitlines(), 1)
        if (match := re.search(r"\((pObj|pOth)\),\s*y\b", line))
    ]
    artifacts = {
        "sourcePortChange": "openspec/changes/port-celeste-sources-to-inlay",
        "bytePreservingChange":
            "openspec/changes/refactor-celeste-around-inlay-semantics",
        "directOracle": "tests/inlay/reference/celeste-customasm",
    }
    if args.phase == "celeste-inlay-phase-b":
        artifacts["redesignChange"] = (
            "openspec/changes/redesign-celeste-for-inlay"
        )
    result = {
        "format": 1,
        "phase": args.phase,
        "artifacts": artifacts,
        "rom": {
            "path": str(args.binary.relative_to(ROOT)),
            "bytes": args.binary.stat().st_size,
            "sha256": sha256(args.binary),
        },
        "symbols": {
            "path": str(args.symbols.relative_to(ROOT)),
            "sha256": sha256(args.symbols),
        },
        "assembly": annotated_metrics(args.annotated),
        "behavior": {
            "visualSha256": PHASE_A_VISUAL,
            "psgCommandTraceSha256": PHASE_A_AUDIO_TRACE,
        },
        "source": {
            "customOperations": custom,
            "objectOffsetSetups": len(offset_sites),
            "rawObjectIndirects": len(raw_indirect_sites),
            "legacyCandidateCounts": {
                kind: sum(item["kind"] == kind for item in candidates)
                for kind in sorted({item["kind"] for item in candidates})
            },
        },
        "objectOffsetSites": offset_sites,
        "rawObjectIndirectSites": raw_indirect_sites,
        "legacyCandidates": candidates,
    }
    encoded = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output is None:
        print(encoded, end="")
    else:
        args.output.write_text(encoded, encoding="ascii")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
