#!/usr/bin/env python3
"""Build and validate the R.84 address-state executor control contract.

This begins with the executor transaction model and adds only the bounded
sample-service formula/lifetime proofs needed before replacing psg_walk/psg_seq.
It answers the questions that must be closed before that replacement:

* do two owner-selected 256x16 banks hold the sample and tick/flow programs;
* can the owner-zero 256-word bank represent every persistent read/write,
  explicit service-latency clock and ordered fold without reintroducing pph;
* do synchronous state reads line up with the action that consumes them;
* do all branch/jump targets and per-slot state words stay in range;
* can every sequencer control state still reach S_IDLE after xs/vcnt become PC;
* what hard clock headroom remains for address-state operand micro-operations;
* whether the exact normalized advance image executes through the fixed
  decoder against a real synchronous-memory transaction model.

The action field is structured as family[2:0]:subop[3:0].  Sample and tick
owners interpret it independently, so neither owner gets a flat 256-way PC
decode.  The model proves the owner-zero schedule/dependency manifest, critical
context substitution and the lowered owner-one advance family.  It must not be
cited as whole-PSG behavioral, render, schedule or area equivalence.
"""

from __future__ import annotations

import argparse
import re
import runpy
from dataclasses import dataclass, replace
from enum import IntEnum
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]
SEQ = ROOT / "rtl" / "psg_seq.sv"
WALK = ROOT / "rtl" / "psg_walk.sv"
COMMON = ROOT / "rtl" / "psg_common.svh"
IMAGE = ROOT / "rtl" / "psg_exec.hex"
MOVE = ROOT / "rtl" / "psg_execmove.sv"
CTRL_GEN = ROOT / "tools" / "gen_psg_ctrl.py"

PAGE_SAMPLE = range(0x00, 0x100)
PAGE_TICK = range(0x40, 0xC0)
PAGE_FLOW = range(0xC0, 0x100)
PROGRAM_BANK_WORDS = 256
PROGRAM_BANKS = 2
OWNER_SAMPLE = 0
OWNER_TICK = 1
SAMPLE_START = 0x01
SAMPLE_CLOCK_LIMIT = 1003


class Op(IntEnum):
    READ = 0
    WRITE = 1
    BRANCH = 2
    SLOT = 3
    JUMP = 4
    OWNER = 5
    DONE = 6
    EXEC = 7


class Page(IntEnum):
    TICK = 0
    FLOW = 1


@dataclass(frozen=True)
class Instruction:
    op: Op
    action: int = 0
    word: int = 0
    cond: int = 0
    sense: int = 1
    target: int = 0
    slot_inc: bool = False
    slot_value: int = 0

    def encode(self) -> int:
        if self.op in (Op.READ, Op.WRITE, Op.EXEC):
            assert 0 <= self.action < 128
            assert 0 <= self.word < 64
            return (int(self.op) << 13) | (self.action << 6) | self.word
        if self.op == Op.BRANCH:
            assert 0 <= self.cond < 16 and self.sense in (0, 1)
            assert 0 <= self.target < 256
            return (int(self.op) << 13) | (self.cond << 9) \
                | (self.sense << 8) | self.target
        if self.op == Op.SLOT:
            return (int(self.op) << 13) | (int(self.slot_inc) << 3) \
                | (self.slot_value & 7)
        if self.op in (Op.JUMP, Op.OWNER):
            return (int(self.op) << 13) | (self.target & 0xFF)
        return int(self.op) << 13

    @staticmethod
    def decode(word: int) -> "Instruction":
        op = Op((word >> 13) & 7)
        if op in (Op.READ, Op.WRITE, Op.EXEC):
            return Instruction(op, action=(word >> 6) & 0x7F,
                               word=word & 0x3F)
        if op == Op.BRANCH:
            return Instruction(op, cond=(word >> 9) & 0xF,
                               sense=(word >> 8) & 1,
                               target=word & 0xFF)
        if op == Op.SLOT:
            return Instruction(op, slot_inc=bool((word >> 3) & 1),
                               slot_value=word & 7)
        if op in (Op.JUMP, Op.OWNER):
            return Instruction(op, target=word & 0xFF)
        return Instruction(op)


PackedFrame = dict[str, int]
FrameValues = dict[str, int]


@dataclass(frozen=True)
class B3B2AFrameCodec:
    """Literal A1 physical-frame encoder shared with service proofs."""

    pack: Callable[[str, FrameValues], tuple[PackedFrame, FrameValues]]
    unpack: Callable[[str, PackedFrame], FrameValues]
    source: Callable[[int, str, int], int]


@dataclass(frozen=True)
class AssemblyInstruction:
    op: Op
    action: int = 0
    word: int = 0
    cond: int = 0
    sense: int = 1
    target: str | None = None

    def encode(self, labels: dict[str, int]) -> int:
        if self.op == Op.BRANCH:
            assert self.target is not None
            return Instruction(self.op, cond=self.cond, sense=self.sense,
                               target=labels[self.target]).encode()
        if self.op == Op.JUMP:
            assert self.target is not None
            return Instruction(self.op, target=labels[self.target]).encode()
        return Instruction(self.op, action=self.action, word=self.word).encode()


@dataclass(frozen=True)
class Action:
    owner: str
    family: int
    subop: int
    name: str
    consumes: int | None = None

    @property
    def code(self) -> int:
        return (self.family << 4) | self.subop


class Actions:
    def __init__(self) -> None:
        self.by_owner: dict[str, dict[int, Action]] = {
            "sample": {}, "tick": {}
        }
        self.next_sub: dict[tuple[str, int], int] = {}

    def add(self, owner: str, family: int, name: str,
            *, subop: int | None = None,
            consumes: int | None = None) -> int:
        key = (owner, family)
        if subop is None:
            subop = self.next_sub.get(key, 0)
        assert 0 <= family < 8 and 0 <= subop < 16, \
            f"{owner} action family {family} exceeds sixteen subops"
        action = Action(owner, family, subop, name, consumes)
        assert action.code not in self.by_owner[owner]
        self.by_owner[owner][action.code] = action
        self.next_sub[key] = max(self.next_sub.get(key, 0), subop + 1)
        return action.code

    def pin(self, owner: str, code: int, name: str,
            *, consumes: int | None = None) -> int:
        assert 0 <= code < 128
        return self.add(owner, code >> 4, name, subop=code & 15,
                        consumes=consumes)

    def get(self, owner: str, code: int) -> Action | None:
        return self.by_owner[owner].get(code)

    def report(self) -> list[str]:
        out = []
        for owner in ("sample", "tick"):
            counts = [sum(action.family == family
                          for action in self.by_owner[owner].values())
                      for family in range(8)]
            out.append(f"{owner} actions {sum(counts)}; family occupancy "
                       + "/".join(str(n) for n in counts))
        return out


# R.84G-E reuses the action codes vacated by K_ADV/EA0..EA5 plus genuinely
# unused owner-local codes.  Family seven remains the common R.84D ALU.
ADV_ACTION = {
    "INIT": 0x40,
    "X_LO_FCNT": 0x47,
    "X_HI_TCNT": 0x48,
    "X_LO_SPEED": 0x49,
    "X_LENGTH": 0x4A,
    "SAVE44_R36": 0x4B,
    "MERGE_CTR_V_NR": 0x4C,
    "MERGE_CTR_V_ROLL": 0x4D,
    "PREV_V_PITCH": 0x4E,
    "PREV_V_VOL": 0x4F,
    "X_ROW_V": 0x0D,
    "X_LPS": 0x0E,
    "X_LPE": 0x0F,
    "X_END": 0x1C,
    "SAVE45_R39": 0x1D,
    "SAVE44": 0x1E,
    "MERGE_ROW_V": 0x1F,
    "MERGE_LEN_V": 0x29,
    "VOICE_STOP": 0x2A,
    "SKIP_CPZ": 0x2B,
    "MERGE_CTR_I_NR": 0x2C,
    "MERGE_CTR_I_ROLL": 0x2D,
    "PREV_I_PITCH": 0x2E,
    "PREV_I_VOL": 0x2F,
    "X_ROW_I": 0x3D,
    "MERGE_ROW_I": 0x3E,
    "INS_DONE": 0x3F,
}

COMMON_ACTION = {
    "HOLD": 0x70,
    "LOAD": 0x71,
    "ADD": 0x72,
    "SUB": 0x74,
    "CMP": 0x7F,
}

COND_Z = 0
COND_C = 2
COND_TRIG = 8
COND_ADVANCE = 9
COND_INS_USE = 10
COND_RELEASED = 11

# Condition bits 0..3 are the common Z/N/C/V flags.  Owner-zero conditions
# therefore live in the external bank at 8..15, just as owner-one's exact
# predicates do.  The old sample sketch incorrectly used Z/N as slot-wrap and
# fold-more.  The fold is now unrolled, so it needs no dynamic condition.
COND_SAMPLE_SLOT_WRAP = 8

# The exact ordered seven-node reduction.  Leaves and intermediate results are
# signed 18-bit pairs in per-slot scratch words 48 (low sixteen) and 49 (top
# two, sign extended by the fixed fold adapter).  Each node overwrites its
# left input, so no register-resident stack or variable address is required.
FOLD_NODES = (
    (0, 1, 0),
    (2, 3, 2),
    (0, 2, 0),
    (4, 5, 4),
    (6, 7, 6),
    (4, 6, 4),
    (0, 4, 0),
)

# Exact full-mode CAP cadence from gen_psg_ctrl.py, relative to W0.  The gaps
# are service dependencies, not disposable pph padding: W15/W26/W40/W51/W84
# consume or relaunch multiplier/wave results that cannot be made adjacent.
SAMPLE_CAP_SCHEDULE = (
    ("W0", 0),
    ("W1", 1),
    ("W2", 2),
    ("W3", 3),
    ("W4", 4),
    ("W5", 5),
    ("W6", 6),
    ("W15", 9),
    ("W26", 14),
    ("W27", 15),
    ("W40", 20),
    ("W51", 25),
    ("W75", 26),
    ("W84", 30),
)
SAMPLE_SERVICE_SCHEDULE = (
    ("NZ_OLD_LOAD_PAR_3", -10),
    ("NZ_LIVE", -5),
) + tuple((f"CAP_{name}", offset) for name, offset in SAMPLE_CAP_SCHEDULE)


def advance_manifest() -> tuple[list[AssemblyInstruction],
                                list[AssemblyInstruction]]:
    """Return the exact fallthrough-packed K_ADV/EA replacement manifest."""
    a = ADV_ACTION
    c = COMMON_ACTION

    def read(word: int, action: int = 0) -> AssemblyInstruction:
        return AssemblyInstruction(Op.READ, action=action, word=word)

    def execute(action: int, word: int = 0) -> AssemblyInstruction:
        return AssemblyInstruction(Op.EXEC, action=action, word=word)

    def write(word: int, action: int) -> AssemblyInstruction:
        return AssemblyInstruction(Op.WRITE, action=action, word=word)

    def branch(cond: int, sense: int, target: str) -> AssemblyInstruction:
        return AssemblyInstruction(Op.BRANCH, cond=cond, sense=sense,
                                   target=target)

    def jump(target: str) -> AssemblyInstruction:
        return AssemblyInstruction(Op.JUMP, target=target)

    def v(n: int) -> str:
        return f"ADV_V{n:02d}"

    def i(n: int) -> str:
        return f"ADV_I{n:02d}"

    voice = [
        execute(a["INIT"]),
        branch(COND_TRIG, 1, "T_FL"),
        branch(COND_ADVANCE, 0, v(66)),
        read(0),
        read(0, a["X_LO_FCNT"]),
        read(2, a["X_HI_TCNT"]),
        read(2, a["X_LO_SPEED"]),
        read(37, a["X_LENGTH"]),
        execute(c["LOAD"], 34),
        execute(c["ADD"]),
        write(44, a["SAVE44_R36"]),
        execute(c["LOAD"], 34),
        execute(c["ADD"], 38),
        execute(c["CMP"]),
        branch(COND_C, 1, v(19)),
        read(44),
        write(0, a["MERGE_CTR_V_NR"]),
        branch(COND_INS_USE, 1, "EA0"),
        jump("ES0"),
        read(44),
        write(0, a["MERGE_CTR_V_ROLL"]),
        write(48, a["PREV_V_PITCH"]),
        write(49, a["PREV_V_VOL"]),
        read(1, a["X_ROW_V"]),
        read(1, a["X_LPS"]),
        read(1, a["X_LPE"]),
        read(40, a["X_END"]),
        execute(c["LOAD"], 34),
        execute(c["ADD"]),
        write(45, a["SAVE45_R39"]),
        execute(c["LOAD"], 34),
        execute(c["SUB"]),
        write(44, a["SAVE44"]),
        branch(COND_C, 0, v(44)),
        branch(COND_Z, 1, v(64)),
        read(45),
        execute(c["LOAD"], 35),
        execute(c["CMP"]),
        branch(COND_Z, 1, v(64)),
        read(54),
        write(54, a["MERGE_ROW_V"]),
        execute(c["LOAD"], 2),
        write(2, a["MERGE_LEN_V"]),
        jump("K_NL"),
        read(41),
        execute(c["LOAD"], 42),
        execute(c["CMP"]),
        branch(COND_C, 1, v(53)),
        branch(COND_RELEASED, 1, v(53)),
        read(45),
        execute(c["LOAD"], 42),
        execute(c["CMP"]),
        branch(COND_C, 1, v(60)),
        read(45),
        execute(c["LOAD"], 43),
        execute(c["CMP"]),
        branch(COND_C, 1, v(64)),
        read(54),
        write(54, a["MERGE_ROW_V"]),
        jump("K_NL"),
        read(41),
        execute(c["LOAD"], 54),
        write(54, a["MERGE_ROW_V"]),
        jump("K_NL"),
        execute(a["VOICE_STOP"]),
        jump("K_ROT"),
        execute(a["SKIP_CPZ"]),
        jump("K_ROT"),
    ]

    instrument = [
        read(6),
        read(6, a["X_LO_FCNT"]),
        read(8, a["X_HI_TCNT"]),
        read(37, a["X_LO_SPEED"]),
        execute(c["LOAD"], 34),
        execute(c["ADD"]),
        write(44, a["SAVE44_R36"]),
        execute(c["LOAD"], 34),
        execute(c["ADD"], 38),
        execute(c["CMP"]),
        branch(COND_C, 1, i(14)),
        read(44),
        write(6, a["MERGE_CTR_I_NR"]),
        jump("I_NL"),
        read(44),
        write(6, a["MERGE_CTR_I_ROLL"]),
        execute(c["LOAD"], 52),
        write(52, a["PREV_I_PITCH"]),
        execute(c["LOAD"], 52),
        write(52, a["PREV_I_VOL"]),
        read(7, a["X_ROW_I"]),
        read(7, a["X_LPS"]),
        read(7, a["X_LPE"]),
        read(40, a["X_END"]),
        execute(c["LOAD"], 34),
        execute(c["ADD"]),
        write(45, a["SAVE45_R39"]),
        read(41),
        execute(c["LOAD"], 42),
        execute(c["CMP"]),
        branch(COND_C, 1, i(35)),
        read(45),
        execute(c["LOAD"], 42),
        execute(c["CMP"]),
        branch(COND_C, 1, i(42)),
        read(45),
        execute(c["LOAD"], 43),
        execute(c["CMP"]),
        branch(COND_C, 1, i(46)),
        read(50),
        write(50, a["MERGE_ROW_I"]),
        jump("I_NL"),
        read(41),
        execute(c["LOAD"], 50),
        write(50, a["MERGE_ROW_I"]),
        jump("I_NL"),
        read(49),
        write(49, a["INS_DONE"]),
        jump("I_NL"),
    ]
    assert len(voice) == 68 and len(instrument) == 49
    return voice, instrument


@dataclass(frozen=True)
class Branch:
    target: str
    cond: int
    sense: int = 1

    def __post_init__(self) -> None:
        assert 0 <= self.cond < 16 and self.cond not in range(4, 8)
        assert self.sense in (0, 1)


@dataclass(kw_only=True)
class Node:
    name: str
    base: str
    page: Page
    op: Op = Op.EXEC
    word: int = 0
    action: int = 0
    branches: tuple[Branch, ...] = ()
    default: str | None = None
    terminal: bool = False
    lowered: bool = False

    def __post_init__(self) -> None:
        assert self.terminal != (self.default is not None), \
            f"{self.name}: require exactly one explicit default or terminal"
        assert not self.branches or self.default is not None, \
            f"{self.name}: conditional node has no default edge"

    @property
    def successors(self) -> list[str]:
        return list(dict.fromkeys(
            [branch.target for branch in self.branches]
            + ([self.default] if self.default is not None else [])
        ))


def localparam(src: str, name: str) -> int:
    match = re.search(rf"localparam (?:int|logic \[[^]]+\])\s+{name}\s*=\s*"
                      r"(?:\d+'d)?(\d+)", src)
    assert match, f"cannot find {name}"
    return int(match.group(1))


def legacy_contract() -> tuple[str, str, str]:
    seq = SEQ.read_text()
    walk = WALK.read_text()
    common = COMMON.read_text()
    assert localparam(common, "PSG_VSTR") == 64
    assert localparam(common, "PSG_V_OSC") == 10
    assert localparam(common, "PSG_V_PAR0") == 24
    assert localparam(common, "PSG_V_PAR1") == 28
    assert localparam(common, "PSG_V_SEQ") == 32
    assert localparam(walk, "PNZ_OLD") == 19
    assert localparam(walk, "PNZ_LIVE") == 24
    return seq, walk, common


def sequencer_states(seq: str) -> list[str]:
    match = re.search(r"typedef enum logic \[5:0\] \{(.*?)\}\s*sst_t;",
                      seq, re.S)
    assert match, "cannot find psg_seq sst enum"
    body = re.sub(r"//.*", "", match.group(1))
    states = [word.strip() for word in body.replace("\n", " ").split(",")
              if word.strip()]
    assert len(states) == 63 and len(set(states)) == len(states)
    return states


def state_successors(seq: str, states: list[str]) -> dict[str, list[str]]:
    start = seq.index("if (!seq_hold)\n      case (sst)")
    match = re.search(r"^      endcase", seq[start:], re.M)
    assert match, "cannot find end of main sst case"
    block = seq[start:start + match.start()]
    marks = list(re.finditer(r"^        ([A-Z][A-Z0-9_]*):", block, re.M))
    arms: dict[str, str] = {}
    for i, mark in enumerate(marks):
        name = mark.group(1)
        if name not in states:
            continue
        end = marks[i + 1].start() if i + 1 < len(marks) else len(block)
        arms[name] = block[mark.end():end]
    assert set(arms) == set(states), \
        f"missing state arms: {sorted(set(states) - set(arms))}"
    out: dict[str, list[str]] = {}
    for state in states:
        seen: list[str] = []
        for target in re.findall(r"\bsst\s*<=\s*([A-Z][A-Z0-9_]*)", arms[state]):
            if target in states and target not in seen:
                seen.append(target)
        assert seen, f"{state}: no successor assignment found"
        out[state] = seen
    return out


def action_family(name: str) -> int:
    if name.startswith(("V_LD", "V_ST")):
        return 0
    if name.startswith("K_FX"):
        return 1
    if name.startswith("K_SL"):
        return 2
    if name.startswith("T_") or name.startswith("I_TR") or name == "I_TW":
        return 3
    if name.startswith("EA") or name in {
            "K_ADV", "K_NL", "K_NH", "K_LD", "K_ARP", "K_ARPC",
            "K_PF0"}:
        return 4
    if name.startswith(("ES", "P_W", "PC")) or name in {
            "K_ROT", "I_NL", "I_NH", "I_LD"}:
        return 5
    if name == "S_IDLE" or name == "W_MUS" \
            or name.startswith(("ML_", "MS_")):
        return 6
    return 7


FLOW_BASE = {"S_IDLE", "W_MUS", "ML_STOP", "ML_RD0", "ML_L0",
             "ML_L1", "ML_L2", "ML_L3", "MS_RD", "MS_CK",
             "T_FL", "T_SP", "T_LS", "T_LE", "T_NL", "T_NH",
             "T_LD"}


def legacy_page(base: str) -> Page:
    return Page.FLOW if base in FLOW_BASE else Page.TICK


def legacy_node(name: str, base: str, successors: list[str],
                *, op: Op = Op.EXEC, word: int = 0,
                action: int = 0) -> Node:
    """Keep an unlowered legacy edge manifest explicit and visibly provisional.

    Regex extraction proves only target topology.  Until a family is lowered,
    this helper pins the old ordinal condition spelling so emit() itself never
    invents predicates.  Lowered nodes must name their real Branch conditions.
    """
    targets = list(dict.fromkeys(successors))
    branches = tuple(Branch(target, cond)
                     for cond, target in enumerate(targets[:-1]))
    default = targets[-1] if targets else None
    return Node(name=name, base=base, op=op, word=word, action=action,
                branches=branches, default=default,
                page=legacy_page(base), lowered=False)


def expand_sequencer(states: list[str], succ: dict[str, list[str]],
                     actions: Actions) -> list[Node]:
    def entry(name: str) -> str:
        return {"V_LD": "V_LD0", "V_ST": "V_ST0",
                "K_FX": "K_FX0"}.get(name, name)

    nodes: list[Node] = []
    vld_words = [3, 4, 5, 8, 9, 26, 32, 26]
    vst_words = [3, 4, 5, 9, 32]
    for state in states:
        if state == "V_LD":
            for i, word in enumerate(vld_words):
                name = f"V_LD{i}"
                nxt = [f"V_LD{i + 1}"] if i + 1 < len(vld_words) \
                    else [entry(s) for s in succ[state]]
                code = actions.add("tick", 0, name)
                nodes.append(legacy_node(name, state, nxt, op=Op.READ,
                                         word=word, action=code))
            continue
        if state == "V_ST":
            for i, word in enumerate(vst_words):
                name = f"V_ST{i}"
                nxt = [f"V_ST{i + 1}"] if i + 1 < len(vst_words) \
                    else [entry(s) for s in succ[state]]
                code = actions.add("tick", 0, name)
                nodes.append(legacy_node(name, state, nxt, op=Op.WRITE,
                                         word=word, action=code))
            continue
        if state == "K_FX":
            edges = {
                0: ["K_FX1"], 1: ["K_FX2"],
                2: ["K_SL0", "K_FX3"], 3: ["K_FX4"],
                4: ["K_FX5"], 5: ["K_FX6"], 6: ["K_FX7"],
                7: ["P_W0", "K_FX8"], 8: ["K_FX9"],
                9: ["K_FX10"], 10: ["K_FX11"], 11: ["P_W2"],
            }
            for i in range(12):
                name = f"K_FX{i}"
                code = actions.add("tick", 1, name)
                nodes.append(legacy_node(name, state, edges[i], op=Op.EXEC,
                                         action=code))
            continue

        nexts = [entry(s) for s in succ[state]]
        if state == "P_W1":
            nexts = ["K_FX3", "K_FX8"]
        op, word = Op.EXEC, 0
        if state.startswith("P_W"):
            op, word = Op.WRITE, 24 + int(state[-1])
        elif state.startswith("PC"):
            op, word = Op.READ, 24 + int(state[-1])
        code = actions.add("tick", action_family(state), state)
        nodes.append(legacy_node(state, state, nexts, op=op, word=word,
                                 action=code))
    assert len({n.name for n in nodes}) == len(nodes)
    return nodes


def split_pages(nodes: list[Node]) -> tuple[list[Node], list[Node]]:
    tick = [node for node in nodes if node.page == Page.TICK]
    flow = [node for node in nodes if node.page == Page.FLOW]
    assert len(tick) + len(flow) == len(nodes)
    assert set(map(id, tick)).isdisjoint(map(id, flow))
    return tick, flow


def block_size(node: Node, next_name: str | None) -> int:
    if node.terminal:
        return 2
    assert node.default is not None
    return 1 + len(node.branches) + (node.default != next_name)


def layout(nodes: list[Node], page: range) -> dict[str, int]:
    labels: dict[str, int] = {}
    pc = page.start
    for i, node in enumerate(nodes):
        labels[node.name] = pc
        nxt = nodes[i + 1].name if i + 1 < len(nodes) else None
        pc += block_size(node, nxt)
    assert pc <= page.stop, \
        f"page {page.start:02x}..{page.stop - 1:02x} overflows at {pc:02x}"
    return labels


def emit(nodes: list[Node], page: range, labels: dict[str, int],
         program: list[int]) -> int:
    pc = page.start
    for i, node in enumerate(nodes):
        assert pc == labels[node.name]
        program[pc] = Instruction(node.op, action=node.action,
                                  word=node.word).encode()
        pc += 1
        nxt = nodes[i + 1].name if i + 1 < len(nodes) else None
        if node.terminal:
            program[pc] = Instruction(Op.DONE).encode()
            pc += 1
        else:
            assert node.default is not None
            for branch in node.branches:
                program[pc] = Instruction(
                    Op.BRANCH, cond=branch.cond, sense=branch.sense,
                    target=labels[branch.target]).encode()
                pc += 1
            if node.default != nxt:
                program[pc] = Instruction(
                    Op.JUMP, target=labels[node.default]).encode()
                pc += 1
    return pc - page.start


def emit_advance(program: list[int], tick_nodes: list[Node],
                 flow_nodes: list[Node]) -> tuple[dict[str, int], int, int, int]:
    """Pack the exact advance manifests and remaining legacy control in bank 1."""
    removed = {"K_ADV", "EA0", "EA1", "EA2", "EA3", "EA4", "EA5"}
    tick_rest = [node for node in tick_nodes if node.name not in removed]
    assert len(tick_nodes) - len(tick_rest) == len(removed)
    voice, instrument = advance_manifest()

    voice_base = 0
    tick_base = voice_base + len(voice)
    tick_labels = layout(tick_rest, range(tick_base, PROGRAM_BANK_WORDS))
    tick_used = sum(block_size(node,
                               tick_rest[n + 1].name
                               if n + 1 < len(tick_rest) else None)
                    for n, node in enumerate(tick_rest))
    instrument_base = tick_base + tick_used
    flow_base = instrument_base + len(instrument)
    flow_labels = layout(flow_nodes, range(flow_base, PROGRAM_BANK_WORDS))
    flow_used = sum(block_size(node,
                               flow_nodes[n + 1].name
                               if n + 1 < len(flow_nodes) else None)
                    for n, node in enumerate(flow_nodes))

    labels = {**tick_labels, **flow_labels}
    labels.update({f"ADV_V{n:02d}": voice_base + n
                   for n in range(len(voice))})
    labels.update({f"ADV_I{n:02d}": instrument_base + n
                   for n in range(len(instrument))})
    labels["K_ADV"] = voice_base
    labels["EA0"] = instrument_base
    assert len(labels) == len(set(labels.values())) + 2

    for base, section in ((voice_base, voice),
                          (instrument_base, instrument)):
        for offset, insn in enumerate(section):
            program[base + offset] = insn.encode(labels)
    emit(tick_rest, range(tick_base, instrument_base), labels, program)
    emit(flow_nodes, range(flow_base, flow_base + flow_used), labels, program)

    total = len(voice) + tick_used + len(instrument) + flow_used
    assert (tick_used, flow_used, total) == (83, 26, 226)
    assert flow_base + flow_used == total
    return labels, len(voice), len(instrument), total


def validate_advance_semantics() -> int:
    """Exhaust decomposed domains for the normalized EA branch algebra."""
    cases = 0

    # Counter rollover and reconstruction factor into an 8-bit counter pair
    # plus an independent modulo-256 tick-count update.
    for fcnt in range(256):
        for speed in range(256):
            fnext = fcnt + 1
            roll = fnext >= speed
            merged = (0 if roll else fnext) & 0xFF
            legacy = 0 if roll else ((fcnt + 1) & 0xFF)
            assert merged == legacy
            cases += 1
    for tcnt in range(256):
        wrapped = 0 if tcnt == 255 else tcnt + 1
        assert ((tcnt + 1) & 0xFF) == wrapped
        cases += 1

    def end_bound(lps: int, lpe: int) -> int:
        return min(lps, 32) if lpe == 0 and lps != 0 else 32

    for lps in range(256):
        for lpe in range(256):
            expected = lps if lpe == 0 and 1 <= lps <= 31 else 32
            assert end_bound(lps, lpe) == expected
            cases += 1

    # The nonzero-length path has priority over loop/end and depends only on
    # the six-bit foreground length and five-bit row.
    for length in range(64):
        for row in range(32):
            decremented = (length - 1) & 0xFFFF
            carry = length >= 1
            zero = decremented == 0
            if not carry:
                decision = "loop_end"
            elif zero or row + 1 == 32:
                decision = "stop"
            else:
                decision = "advance"
            expected = ("loop_end" if length == 0 else
                        "stop" if length == 1 or row == 31 else "advance")
            assert decision == expected
            cases += 1

    # With length zero, loop-before-end priority is exhaustive over every raw
    # loop byte, row and release state.  Instrument advance ignores release.
    for lps in range(256):
        for lpe in range(256):
            bound = end_bound(lps, lpe)
            for row in range(32):
                row_next = row + 1
                for released in (False, True):
                    valid_loop = lps < lpe and not released
                    if valid_loop and row_next >= lpe:
                        normalized = ("loop", lps & 31)
                    elif row_next >= bound:
                        normalized = ("stop", row)
                    else:
                        normalized = ("advance", row_next & 31)
                    if lps < lpe and not released and row_next >= lpe:
                        legacy = ("loop", lps & 31)
                    elif row_next >= bound:
                        legacy = ("stop", row)
                    else:
                        legacy = ("advance", row_next & 31)
                    assert normalized == legacy
                    cases += 1

                if lps < lpe and row_next >= lpe:
                    normalized_i = ("loop", lps & 31)
                elif row_next >= bound:
                    normalized_i = ("done", row)
                else:
                    normalized_i = ("advance", row_next & 31)
                if lps < lpe and row_next >= lpe:
                    legacy_i = ("loop", lps & 31)
                elif row_next >= bound:
                    legacy_i = ("done", row)
                else:
                    legacy_i = ("advance", row_next & 31)
                assert normalized_i == legacy_i
                cases += 1

    # Fixed projection/merge actions preserve every unrelated bit.
    for raw in range(1 << 16):
        assert ((raw & ~0x0FC0) | ((raw & 0x3F) << 6)) \
            == ((raw & 0xF03F) | ((raw & 0x3F) << 6))
        assert ((raw & ~0x01C0) | ((raw & 7) << 6)) \
            == ((raw & 0xFE3F) | ((raw & 7) << 6))
        assert ((raw | 0x8000) & 0xFFFF) == raw | 0x8000
        for pitch in range(64):
            merged_pitch = (raw & 0xFFC0) | pitch
            assert merged_pitch & 0x3F == pitch
            assert merged_pitch & 0xFFC0 == raw & 0xFFC0
            cases += 1
        for volume in range(8):
            merged_volume = (raw & 0xF1FF) | (volume << 9)
            assert (merged_volume >> 9) & 7 == volume
            assert merged_volume & 0xF1FF == raw & 0xF1FF
            cases += 1
        for row in range(32):
            assert ((raw & ~0x001F) | row) & 0xFFFF \
                == (raw & 0xFFE0) | row
            assert ((raw & ~0x03E0) | (row << 5)) & 0xFFFF \
                == (raw & 0xFC1F) | (row << 5)
            cases += 2
        for length in range(64):
            merged_length = (raw & 0xC0FF) | (length << 8)
            assert (merged_length >> 8) & 0x3F == length
            assert merged_length & 0xC0FF == raw & 0xC0FF
            cases += 1
        cases += 3

    return cases


def advance_fixed_decode(action: int, op: Op, word: int, state_q: int,
                         acc: int, *, spar_bank: int, join_stage: int,
                         playing: int, cpz: int) -> tuple[int | None,
                                                          tuple[int, int] | None,
                                                          bool, bool | None]:
    """Model the fixed-address R.84G-F movement/merge decoder.

    Return (read override, optional extra/direct fixed write, voice-stop pulse,
    optional cpz update).  An OP_WRITE action not returned here uses acc.
    """
    a = ADV_ACTION
    read_override: int | None = None
    write: tuple[int, int] | None = None
    voice_stop = False
    cpz_update: bool | None = None

    if op == Op.READ and action == 0 and word == 3:
        write = (34, 1)
    elif op == Op.READ and 1 <= action <= 7:
        write = (47 + action, state_q)
        if action in (5, 7):
            read_override = 30 if spar_bank else 26
    elif action == a["INIT"]:
        write = (35, 32)

    extracts = {
        a["X_LO_FCNT"]: (36, state_q & 0xFF),
        a["X_HI_TCNT"]: (37, state_q >> 8),
        a["X_LO_SPEED"]: (38, state_q & 0xFF),
        a["X_LENGTH"]: (39, (state_q >> 8) & 0x3F),
        a["X_ROW_V"]: (40, state_q & 0x1F),
        a["X_LPS"]: (41, state_q & 0xFF),
        a["X_LPE"]: (42, state_q >> 8),
        a["X_ROW_I"]: (40, (state_q >> 5) & 0x1F),
    }
    if action in extracts:
        write = extracts[action]
    elif action == a["X_END"]:
        lps, lpe = state_q & 0xFF, state_q >> 8
        write = (43, lps if lpe == 0 and 1 <= lps <= 31 else 32)

    fixed_writes: dict[int, tuple[int, int, int | None]] = {
        a["SAVE44_R36"]: (44, acc, 36),
        a["SAVE45_R39"]: (45, acc, 39),
        a["SAVE44"]: (44, acc, None),
        a["MERGE_CTR_V_NR"]: (word, ((state_q & 0xFF) << 8)
                                      | (acc & 0xFF), None),
        a["MERGE_CTR_V_ROLL"]: (word, (state_q & 0xFF) << 8, 48),
        a["PREV_V_PITCH"]: (word, (state_q & 0xF03F)
                                  | ((state_q & 0x3F) << 6), 49),
        a["PREV_V_VOL"]: (word, (state_q & 0xFE3F)
                                | ((state_q & 7) << 6), 54),
        a["MERGE_ROW_V"]: (word, (state_q & 0xFFE0) | (acc & 0x1F), 44),
        a["MERGE_LEN_V"]: (word, (state_q & 0xC0FF)
                                 | ((acc & 0x3F) << 8), None),
        a["MERGE_CTR_I_NR"]: (word, ((state_q & 0xFF) << 8)
                                      | (acc & 0xFF), None),
        a["MERGE_CTR_I_ROLL"]: (word, (state_q & 0xFF) << 8, 51),
        a["PREV_I_PITCH"]: (word, (state_q & 0xFFC0)
                                  | ((acc >> 8) & 0x3F), 50),
        a["PREV_I_VOL"]: (word, (state_q & 0xF1FF)
                                | (((acc >> 13) & 7) << 9), 50),
        a["MERGE_ROW_I"]: (word, (state_q & 0xFC1F)
                                 | ((acc & 0x1F) << 5), None),
        a["INS_DONE"]: (word, state_q | 0x8000, None),
    }
    if action in fixed_writes:
        wa, wd, ra = fixed_writes[action]
        write = (wa, wd & 0xFFFF)
        read_override = ra

    # Literal dynamic publication addresses.  P_W data is an owner macro and
    # is deliberately outside this fixed decoder; only its address is proved.
    inactive = (24, 25, 26, 27) if spar_bank else (28, 29, 30, 31)
    copy_bank = spar_bank ^ join_stage
    copy_words = (28, 29, 30, 31) if copy_bank else (24, 25, 26, 27)
    if action == 0x56:
        read_override = 48
    elif action == 0x5E:
        read_override = copy_words[0]
    elif 0x57 <= action <= 0x5A:
        n = action - 0x57
        data = state_q & (0xFF00 if n == 3 and cpz else 0xFFFF)
        write = (inactive[n], data)
        read_override = 48 if n == 3 else copy_words[n + 1]

    if action == a["VOICE_STOP"]:
        voice_stop = True
        cpz_update = True
    elif action == a["SKIP_CPZ"]:
        cpz_update = not playing
    return read_override, write, voice_stop, cpz_update


def run_advance_transaction(program: list[int], labels: dict[str, int],
                            initial: list[int], *, spar_bank: int = 0,
                            trig_req: int = 0, walk_tick: int = 1,
                            playing: int = 1, ins_use: int = 0,
                            released: int = 0) -> tuple[str, list[int], bool,
                                                        bool, int]:
    """Execute the production image against a synchronous 64-word store."""
    mem = list(initial)
    assert len(mem) == 64
    pc = labels["V_LD0"]
    state_q = 0
    acc = 0
    flag_z, flag_c = True, False
    cpz = False
    pend_stop = False
    exits = {labels[name]: name for name in ("T_FL", "ES0", "K_NL",
                                             "K_ROT", "I_NL")}
    for cycles in range(256):
        if pc in exits:
            return exits[pc], mem, pend_stop, cpz, cycles
        insn = Instruction.decode(program[pc])
        cond = {
            COND_Z: flag_z,
            COND_C: flag_c,
            COND_TRIG: bool(trig_req),
            COND_ADVANCE: bool(walk_tick and playing),
            COND_INS_USE: bool(ins_use),
            COND_RELEASED: bool(released),
        }
        next_pc = (pc + 1) & 0xFF
        if insn.op == Op.BRANCH and cond[insn.cond] == bool(insn.sense):
            next_pc = insn.target
        elif insn.op == Op.JUMP:
            next_pc = insn.target

        ra_override, fixed_write, stop, cpz_update = advance_fixed_decode(
            insn.action, insn.op, insn.word, state_q, acc,
            spar_bank=spar_bank, join_stage=0, playing=playing, cpz=cpz)
        ra = insn.word if ra_override is None else ra_override
        next_state_q = mem[ra]

        if insn.op == Op.WRITE:
            assert fixed_write is not None, f"pc {pc}: unfixed advance write"
            wa, wd = fixed_write
            mem[wa] = wd
        elif fixed_write is not None:
            wa, wd = fixed_write
            mem[wa] = wd

        if insn.op == Op.EXEC and insn.action in COMMON_ACTION.values():
            if insn.action == COMMON_ACTION["LOAD"]:
                acc = state_q
                flag_z = acc == 0
            elif insn.action == COMMON_ACTION["ADD"]:
                wide = acc + state_q
                acc = wide & 0xFFFF
                flag_c = wide > 0xFFFF
                flag_z = acc == 0
            elif insn.action in (COMMON_ACTION["SUB"], COMMON_ACTION["CMP"]):
                result = (acc - state_q) & 0xFFFF
                flag_c = acc >= state_q
                flag_z = result == 0
                if insn.action == COMMON_ACTION["SUB"]:
                    acc = result

        if stop:
            pend_stop = True
        if cpz_update is not None:
            cpz = cpz_update
        state_q = next_state_q
        pc = next_pc
    raise AssertionError("advance transaction did not reach an external exit")


def validate_advance_transactions(program: list[int], labels: dict[str, int]) -> int:
    """Bind the numbered image, fixed decoder and synchronous read latency."""
    cases = 0

    def base() -> list[int]:
        mem = [0] * 64
        mem[3], mem[4], mem[5], mem[9] = 0xA53C, 0x4A15, 0xA321, 0x1000
        mem[26], mem[30], mem[32] = 0x2611, 0x30EE, 0xC000
        return mem

    # Exhaust both complete counter domains through the real image.  Voice
    # rollover takes the length path; instrument rollover takes the row path.
    for fcnt in range(256):
        for speed in range(256):
            mem = base()
            mem[0] = (7 << 8) | fcnt
            mem[1] = 0
            mem[2] = (2 << 8) | speed
            exit_name, out, stop, _, _ = run_advance_transaction(
                program, labels, mem)
            roll = fcnt + 1 >= speed
            assert out[0] == (8 << 8) | (0 if roll else fcnt + 1)
            assert exit_name == ("K_NL" if roll else "ES0") and not stop
            cases += 1

            mem = base()
            mem[0] = (7 << 8) | 0
            mem[2] = (2 << 8) | 255  # voice no-roll enters instrument
            mem[6] = (9 << 8) | fcnt
            mem[7] = 0
            mem[8] = (37 << 8) | speed
            mem[5] = (5 << 13) | (1 << 5)
            exit_name, out, stop, _, _ = run_advance_transaction(
                program, labels, mem, ins_use=1)
            roll = fcnt + 1 >= speed
            assert out[6] == (10 << 8) | (0 if roll else fcnt + 1)
            assert exit_name == "I_NL" and not stop
            if roll:
                assert out[52] & 0x3F == 37
                assert (out[52] >> 9) & 7 == 5
            cases += 1

    # Path-complete boundary cases bind length, row, loop, release, trigger,
    # skip and both active parameter banks without multiplying the already
    # exhaustive decomposed algebra above by the full microprogram length.
    directed = [
        # length,row,lps,lpe,released,exit,row_out,stop
        (0, 1, 1, 4, 0, "K_NL", 2, False),
        (0, 3, 1, 4, 0, "K_NL", 1, False),
        (0, 3, 1, 4, 1, "K_NL", 4, False),
        (0, 31, 4, 4, 0, "K_ROT", 31, True),
        (1, 4, 1, 4, 0, "K_ROT", 4, True),
        (2, 4, 1, 4, 0, "K_NL", 5, False),
    ]
    for bank in (0, 1):
        for length, row, lps, lpe, rel, expected_exit, expected_row, stop in directed:
            mem = base()
            mem[0] = (7 << 8) | 1
            mem[1] = (lpe << 8) | lps
            mem[2] = (length << 8) | 2
            mem[32] = 0xC000 | row
            exit_name, out, got_stop, _, _ = run_advance_transaction(
                program, labels, mem, spar_bank=bank, released=rel)
            assert exit_name == expected_exit and got_stop == stop
            assert out[54] & 0x1F == expected_row
            assert out[53] == mem[30 if bank else 26]
            cases += 1

    mem = base()
    exit_name, _, _, cpz, _ = run_advance_transaction(
        program, labels, mem, trig_req=1)
    assert exit_name == "T_FL"
    cases += 1
    for playing in (0, 1):
        exit_name, _, _, cpz, _ = run_advance_transaction(
            program, labels, mem, walk_tick=0, playing=playing)
        assert exit_name == "K_ROT" and cpz == (not playing)
        cases += 1
    return cases


def build_sample(actions: Actions, program: list[int]) -> dict[int, str]:
    labels: dict[int, str] = {}
    pc = 0

    def put(insn: Instruction, label: str) -> int:
        nonlocal pc
        assert pc in PAGE_SAMPLE and program[pc] == 0
        program[pc] = insn.encode()
        labels[pc] = label
        old_pc = pc
        pc += 1
        return old_pc

    def hold(count: int, label: str,
             words: tuple[int, ...] | None = None) -> None:
        if words is None:
            words = (0,) * count
        assert len(words) == count
        for n, word in enumerate(words):
            put(Instruction(Op.EXEC, action=COMMON_ACTION["HOLD"],
                            word=word),
                f"{label}_hold_{n}")

    # Slot-wrap branch. start_pc is 1, so address zero is only reached after
    # OP_SLOT has advanced the completed slot.  Reserve its word until the
    # exact unrolled fold entry is known.  Condition 8 is owner-zero's external
    # slot-wrap fact; common condition 0 is Z and must never be overloaded.
    put(Instruction(Op.BRANCH, cond=COND_SAMPLE_SLOT_WRAP, target=0),
        "slot_wrap")

    reads = list(range(10, 24)) + [24, 25, 26, 27]
    consume_codes: list[int] = []
    consume_codes.append(actions.add("sample", 0, "READ_PRIME"))
    for word in range(10, 23):
        consume_codes.append(actions.add("sample", 0,
                                         f"LOAD_OSC_{word}", consumes=word))
    consume_codes.append(actions.add("sample", 0, "LOAD_OSC_23",
                                     consumes=23))
    for word in range(24, 27):
        consume_codes.append(actions.add("sample", 1,
                                         f"LOAD_PAR_{word - 24}",
                                         consumes=word))
    assert len(reads) == len(consume_codes) == 18
    for word, code in zip(reads, consume_codes):
        put(Instruction(Op.READ, action=code, word=word),
            f"read_{word}")

    # The first service action also consumes the final pipelined parameter
    # read.  Fixed service latency is represented by real common-HOLD
    # instructions.  It is no longer Python-only Action.wait metadata.
    nz_old = actions.add("sample", 2, "NZ_OLD_LOAD_PAR_3",
                         consumes=27)
    nz_live = actions.add("sample", 2, "NZ_LIVE")
    put(Instruction(Op.EXEC, action=nz_old), "nz_old")
    hold(4, "nz_old")
    put(Instruction(Op.EXEC, action=nz_live), "nz_live")
    # The last elapsed service edge primes current phase for W0.  Earlier H-C
    # RTL inferred this address from action 0x70; H-D stores it in the already
    # present word field so the blanket HOLD override can disappear.
    hold(4, "nz_live", (0, 0, 0, 10))

    previous_offset: int | None = None
    for name, offset in SAMPLE_CAP_SCHEDULE:
        if previous_offset is not None:
            gap = offset - previous_offset - 1
            # The four W40--W51 elapsed clocks are also the fixed ring-memory
            # read/capture microsteps.  REVERB=0 simply ignores these tags.
            words = tuple(range(1, 5)) if name == "W51" else None
            hold(gap, f"cap_{name}_wait", words)
        code = actions.add("sample", 2, f"CAP_{name}")
        # W0 primes phase2 for W1; W1 primes old phase for W2.  These literal
        # addresses preserve H-C's direct issue stream without action-derived
        # state-address overrides.
        word = {"W0": 12, "W1": 16}.get(name, 0)
        put(Instruction(Op.EXEC, action=code, word=word), f"cap_{name}")
        previous_offset = offset

    store_words = list(range(10, 24)) + [15, 14]
    for i, word in enumerate(store_words):
        code = actions.add("sample", 3 if i < 14 else 4,
                           f"STORE_{i}_{word}")
        put(Instruction(Op.WRITE, action=code, word=word),
            f"store_{word}")
    leaf_lo = actions.add("sample", 4, "STORE_LEAF_LO")
    leaf_hi = actions.add("sample", 4, "STORE_LEAF_HI")
    put(Instruction(Op.WRITE, action=leaf_lo, word=48), "store_leaf_lo")
    put(Instruction(Op.WRITE, action=leaf_hi, word=49), "store_leaf_hi")
    put(Instruction(Op.SLOT, slot_inc=True), "slot_inc")
    put(Instruction(Op.JUMP, target=0), "slot_loop")

    fold_entry = pc
    program[0] = Instruction(Op.BRANCH, cond=COND_SAMPLE_SLOT_WRAP,
                             target=fold_entry).encode()

    # Unroll the seven-node tree.  The controller's literal OP_SLOT and word
    # fields are the address schedule; no fold selector, loop counter or
    # register-resident stack is hidden in an action decoder.
    fold_prime = actions.add("sample", 5, "FOLD_PRIME")
    fold_a_lo = actions.add("sample", 5, "FOLD_A_LO", consumes=48)
    fold_a_hi = actions.add("sample", 5, "FOLD_A_HI", consumes=49)
    fold_b_lo = actions.add("sample", 5, "FOLD_B_LO", consumes=48)
    fold_start = actions.add("sample", 5, "FOLD_START", consumes=49)
    fold_run = actions.add("sample", 5, "FOLD_RUN")
    fold_write_lo = actions.add("sample", 5, "FOLD_WRITE_LO")
    fold_write_hi = actions.add("sample", 5, "FOLD_WRITE_HI")
    fold_finish = actions.add("sample", 5, "FOLD_FINISH")
    for n, (a_slot, b_slot, dst_slot) in enumerate(FOLD_NODES):
        put(Instruction(Op.SLOT, slot_value=a_slot), f"fold_{n}_slot_a")
        put(Instruction(Op.READ, action=fold_prime, word=48),
            f"fold_{n}_read_a_lo")
        put(Instruction(Op.READ, action=fold_a_lo, word=49),
            f"fold_{n}_read_a_hi")
        put(Instruction(Op.EXEC, action=fold_a_hi),
            f"fold_{n}_take_a_hi")
        put(Instruction(Op.SLOT, slot_value=b_slot), f"fold_{n}_slot_b")
        put(Instruction(Op.READ, action=fold_prime, word=48),
            f"fold_{n}_read_b_lo")
        put(Instruction(Op.READ, action=fold_b_lo, word=49),
            f"fold_{n}_read_b_hi")
        put(Instruction(Op.EXEC, action=fold_start), f"fold_{n}_start")
        put(Instruction(Op.EXEC, action=fold_run), f"fold_{n}_run")
        # The worst-case fold padding is executable microcode: its word fields
        # select the eight arithmetic steps, so no fold counter is required.
        hold(8, f"fold_{n}", tuple(range(1, 9)))
        put(Instruction(Op.SLOT, slot_value=dst_slot),
            f"fold_{n}_slot_dst")
        put(Instruction(Op.WRITE, action=fold_write_lo, word=48),
            f"fold_{n}_write_lo")
        put(Instruction(Op.WRITE, action=fold_write_hi, word=49),
            f"fold_{n}_write_hi")

    put(Instruction(Op.EXEC, action=fold_finish), "fold_finish")
    put(Instruction(Op.DONE), "sample_done")
    assert pc <= PROGRAM_BANK_WORDS
    return labels


def validate_instruction_codec(program: list[int]) -> None:
    for word in program:
        assert Instruction.decode(word).encode() == word
    for op in (Op.READ, Op.WRITE, Op.EXEC):
        for action in range(128):
            for word in range(64):
                insn = Instruction(op, action=action, word=word)
                assert Instruction.decode(insn.encode()) == insn
    for cond in range(16):
        for sense in (0, 1):
            for target in range(256):
                insn = Instruction(Op.BRANCH, cond=cond, sense=sense,
                                   target=target)
                assert Instruction.decode(insn.encode()) == insn
    for inc in (False, True):
        for value in range(8):
            insn = Instruction(Op.SLOT, slot_inc=inc, slot_value=value)
            assert Instruction.decode(insn.encode()) == insn
    for op in (Op.JUMP, Op.OWNER):
        for target in range(256):
            insn = Instruction(op, target=target)
            assert Instruction.decode(insn.encode()) == insn
    assert Instruction.decode(Instruction(Op.DONE).encode()) \
        == Instruction(Op.DONE)


def validate_explicit_emission() -> None:
    """Prove predicate identity, sense, priority and cross-page targets."""
    actions = Actions()
    assert actions.pin("tick", 0x71, "COMMON_LOAD") == 0x71
    pinned = actions.get("tick", 0x71)
    assert pinned is not None and (pinned.family, pinned.subop, pinned.name) \
        == (7, 1, "COMMON_LOAD")
    try:
        actions.add("tick", 7, "BAD_NEGATIVE", subop=-1)
    except AssertionError:
        pass
    else:
        raise AssertionError("negative action subop was accepted")
    try:
        Branch("bad", 4)
    except AssertionError:
        pass
    else:
        raise AssertionError("hard-zero branch condition was accepted")

    probe = Node(
        name="probe", base="probe", page=Page.TICK, op=Op.EXEC,
        word=5, action=0x71,
        branches=(Branch("shared", 12, 0), Branch("shared", 9, 1)),
        default="fallthrough", lowered=True)
    labels = {"probe": 0, "fallthrough": 0x40, "shared": 0xC4}
    program = [0] * 256
    assert block_size(probe, None) == 4
    assert emit([probe], range(0, 4), labels, program) == 4
    assert Instruction.decode(program[0]) == Instruction(
        Op.EXEC, action=0x71, word=5)
    assert Instruction.decode(program[1]) == Instruction(
        Op.BRANCH, cond=12, sense=0, target=0xC4)
    assert Instruction.decode(program[2]) == Instruction(
        Op.BRANCH, cond=9, sense=1, target=0xC4)
    assert Instruction.decode(program[3]) == Instruction(
        Op.JUMP, target=0x40)


def validate_node_contract(nodes: list[Node], program: list[int]) -> None:
    for node in nodes:
        assert node.default is not None, \
            f"{node.name}: sequencer nodes must name a default edge"
        assert not node.terminal
        for branch in node.branches:
            assert branch.cond not in range(4, 8)
    for word in program:
        insn = Instruction.decode(word)
        if insn.op == Op.BRANCH:
            assert insn.cond not in range(4, 8), \
                f"emitted branch consumes hard-zero condition {insn.cond}"


def validate_sample(program: list[int], actions: Actions,
                    labels: dict[int, str]) -> tuple[int, int, int]:
    pc, slot, pending = SAMPLE_START, 0, None
    cycles = 0
    writes: list[tuple[int, int, str]] = []
    fold_reads: list[tuple[str, int, int]] = []
    service_cycles: dict[int, list[tuple[str, int]]] = {}
    visits = 0
    hold_clocks = 0
    for _ in range(4000):
        insn = Instruction.decode(program[pc])
        action = actions.get("sample", insn.action) \
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC) else None
        if action and action.consumes is not None:
            assert pending is not None and pending[1] == action.consumes, \
                f"pc {pc}: {action.name} consumes {pending}, expected " \
                f"{action.consumes}"
            if action.name.startswith("FOLD_"):
                fold_reads.append((action.name, pending[0], pending[1]))
            pending = None
        if action and (action.name.startswith("NZ_")
                       or action.name.startswith("CAP_")):
            service_cycles.setdefault(visits, []).append((action.name,
                                                          cycles))
        if insn.op == Op.EXEC and insn.action == COMMON_ACTION["HOLD"]:
            hold_clocks += 1

        cycles += 1
        if insn.op == Op.READ:
            pending = (slot, insn.word)
            pc = (pc + 1) & 0xFF
        elif insn.op == Op.WRITE:
            writes.append((slot, insn.word,
                           action.name if action else "COMMON"))
            pc = (pc + 1) & 0xFF
        elif insn.op == Op.EXEC:
            pc = (pc + 1) & 0xFF
        elif insn.op == Op.SLOT:
            slot = (slot + 1) & 7 if insn.slot_inc else insn.slot_value
            if insn.slot_inc:
                visits += 1
            pc = (pc + 1) & 0xFF
        elif insn.op == Op.JUMP:
            pc = insn.target
        elif insn.op == Op.BRANCH:
            assert insn.cond == COND_SAMPLE_SLOT_WRAP
            take = slot == 0
            pc = insn.target if take == bool(insn.sense) else (pc + 1) & 0xFF
        elif insn.op == Op.DONE:
            break
        else:
            raise AssertionError(f"unexpected sample op {insn.op}")
    else:
        raise AssertionError("sample program did not terminate")

    assert visits == 8 and slot == 0 and pending is None
    expected = list(range(10, 24)) + [15, 14, 48, 49]
    for voice in range(8):
        actual = [word for owner, word, name in writes
                  if owner == voice and name.startswith("STORE_")]
        assert actual == expected, (voice, actual, expected)
        service = service_cycles[voice]
        w0_cycle = dict(service)["CAP_W0"]
        relative = [(name, cycle - w0_cycle) for name, cycle in service]
        assert relative == list(SAMPLE_SERVICE_SCHEDULE), \
            (voice, relative, SAMPLE_SERVICE_SCHEDULE)

    expected_fold_reads: list[tuple[str, int, int]] = []
    expected_fold_writes: list[tuple[int, int, str]] = []
    for a_slot, b_slot, dst_slot in FOLD_NODES:
        expected_fold_reads.extend((
            ("FOLD_A_LO", a_slot, 48),
            ("FOLD_A_HI", a_slot, 49),
            ("FOLD_B_LO", b_slot, 48),
            ("FOLD_START", b_slot, 49),
        ))
        expected_fold_writes.extend((
            (dst_slot, 48, "FOLD_WRITE_LO"),
            (dst_slot, 49, "FOLD_WRITE_HI"),
        ))
    assert fold_reads == expected_fold_reads
    assert [write for write in writes if write[2].startswith("FOLD_WRITE")] \
        == expected_fold_writes

    # Per visit: four old-noise and four live-noise clocks, plus the exact
    # seventeen holes in the accepted W0..W84 service cadence.
    # Per fold node: eight clocks after the explicit FOLD_RUN instruction.
    cap_holds = SAMPLE_CAP_SCHEDULE[-1][1] - (len(SAMPLE_CAP_SCHEDULE) - 1)
    assert cap_holds == 17
    assert hold_clocks == 8 * (4 + 4 + cap_holds) \
        + len(FOLD_NODES) * 8
    assert cycles < SAMPLE_CLOCK_LIMIT
    return cycles, SAMPLE_CLOCK_LIMIT - cycles, len(labels)


def validate_sample_wait_manifest(program: list[int],
                                  labels: dict[int, str]) -> str:
    """Prove every stored wait's physical-address/microstep word field."""
    by_label = {label: Instruction.decode(program[pc])
                for pc, label in labels.items()}

    expected_nonzero = {
        "nz_live_hold_3": 10,
        "cap_W0": 12,
        "cap_W1": 16,
    }
    expected_nonzero.update({f"cap_W51_wait_hold_{n}": n + 1
                             for n in range(4)})
    for node in range(len(FOLD_NODES)):
        expected_nonzero.update({f"fold_{node}_hold_{n}": n + 1
                                 for n in range(8)})

    stored_holds = 0
    nonzero_holds = 0
    for label, insn in by_label.items():
        expected_word = expected_nonzero.get(label, 0)
        if label in expected_nonzero:
            assert insn.word == expected_word, (label, insn.word,
                                                 expected_word)
        if insn.op == Op.EXEC and insn.action == COMMON_ACTION["HOLD"]:
            stored_holds += 1
            nonzero_holds += insn.word != 0
            assert insn.word == expected_word, (label, insn.word,
                                                 expected_word)

    assert stored_holds == 81
    assert nonzero_holds == 61  # final W0 prime + four ring + 7*8 fold
    assert by_label["cap_W0"].word == 12
    assert by_label["cap_W1"].word == 16
    assert len(expected_nonzero) == 63
    return ("81 stored HOLDs: 61 nonzero physical/step words; W0/W1 "
            "prime words 12/16; 63 owner-zero image words changed")


def validate_sample_fixed_tail_gap(program: list[int], actions: Actions,
                                   labels: dict[int, str]) -> str:
    """Prove why the current persistent STORE tail is not implementable.

    The composed semantic oracle below used to make the late writes look
    physical by selecting ``SampleTrace.final_words``.  In the real executor,
    however, state_q is the registered output of the *preceding* instruction's
    state read.  Record that exact stream here before any semantic RTL is
    allowed to depend on it.

    This is a rejection proof for the unchanged tail, not a claim that every
    mirror-free schedule is impossible.  A later image may relocate the same
    fixed writes onto the edges where their values become final.
    """
    by_pc = {pc: (labels[pc], Instruction.decode(program[pc]))
             for pc in labels}
    q_word: int | None = None
    stores: list[tuple[str, int, int | None]] = []
    for pc in range(SAMPLE_START, 0x4e):
        label, insn = by_pc[pc]
        action = actions.get("sample", insn.action) \
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC) else None
        if action is not None and action.name.startswith("STORE_"):
            stores.append((action.name, insn.word, q_word))
        # psg_execctl clocks the state EBR on every active READ/WRITE/EXEC,
        # not only on semantic READ instructions.
        if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
            q_word = insn.word

    expected = [
        (f"STORE_{index}_{10 + index}", 10 + index,
         0 if index == 0 else 9 + index)
        for index in range(14)
    ]
    expected.extend((
        ("STORE_14_15", 15, 23),
        ("STORE_15_14", 14, 15),
        ("STORE_LEAF_LO", 48, 14),
        ("STORE_LEAF_HI", 49, 48),
    ))
    assert stores == expected, (stores, expected)

    # Decoding these inputs wholesale is exactly the forbidden record mirror:
    # 202 meaningful oscillator bits plus 42 meaningful parameter bits, before
    # Python's padded 14+4 word lists or the much larger derived SampleTrace.
    record_bits = sum((16, 8, 17, 17, 1, 13, 13, 4, 2, 13, 17, 16,
                       7, 14, 2, 2, 3, 14, 1, 1, 2, 3, 16))
    parameter_bits = sum((14, 3, 1, 3, 2, 2, 2, 1, 1, 12, 1))
    assert record_bits == 202 and parameter_bits == 42
    assert record_bits + parameter_bits > 70

    source = Path(__file__).read_text()
    machine = source[source.index("\nclass SampleImageMachine:"):
                     source.index("\ndef make_sample_case(")]
    assert "self.loaded_words: list[int]" in machine
    assert "self.params_words: list[int]" in machine
    assert "self.trace: SampleTrace | None" in machine
    assert "self.trace.final_words" in machine

    first = stores[0]
    assert first == ("STORE_0_10", 10, 0)
    return ("fixed persistent STORE tail rejected: 16 writes consume the "
            "previous destination stream; PC 3c word10 sees q=word0; "
            "oracle mirror is 202 record + 42 parameter bits before Trace")


@dataclass(frozen=True)
class SampleCommitSite:
    pc: int
    action: str
    destination: int
    q_source: int | None
    final_after: str


def validate_sample_relocated_commit_manifest(
        program: list[int], actions: Actions,
        labels: dict[int, str]) -> tuple[str, list[int]]:
    """Build the H-D2 mirror-free fixed-edge commit candidate.

    This deliberately does not replace the accepted image yet.  It proves a
    complete alternative instruction/address manifest first: every relocated
    commit remains an OP_WRITE, its action owns one literal destination, and
    the instruction word primes the following fixed state_q source.  No
    action-side extra write is counted.
    """
    candidate = list(program)
    pc_of = {label: pc for pc, label in labels.items()}
    action_by_name = {action.name: code
                      for code, action in actions.by_owner["sample"].items()}

    def set_insn(pc: int, insn: Instruction) -> None:
        candidate[pc] = insn.encode()

    def set_word(label: str, word: int) -> None:
        pc = pc_of[label]
        insn = Instruction.decode(candidate[pc])
        assert insn.op in (Op.READ, Op.WRITE, Op.EXEC)
        set_insn(pc, Instruction(insn.op, action=insn.action, word=word))

    # The twelve old unique tail writes displaced onto finalization waits
    # become elapsed service clocks.  Word14/15 stay immediately after W84;
    # the two deliberate lowpass repeats at PCs 4a/4b remain writes.
    for pc in range(0x3c, 0x4a):
        set_insn(pc, Instruction(Op.EXEC, action=COMMON_ACTION["HOLD"]))

    sites = (
        SampleCommitSite(0x14, "STORE_10_20", 20, 20, "restart select"),
        SampleCommitSite(0x15, "STORE_11_21", 21, 21, "restart select"),
        SampleCommitSite(0x16, "STORE_12_22", 22, 22, "restart select"),
        SampleCommitSite(0x17, "STORE_8_18", 18, 18, "restart select"),
        SampleCommitSite(0x19, "STORE_9_19", 19, 19, "restart select"),
        SampleCommitSite(0x1d, "CAP_W0", 23, 10, "W0"),
        SampleCommitSite(0x1e, "CAP_W1", 10, 12, "W1"),
        SampleCommitSite(0x27, "STORE_1_11", 11, 11, "W5"),
        SampleCommitSite(0x28, "STORE_6_16", 16, 16, "W5"),
        SampleCommitSite(0x29, "STORE_7_17", 17, 17, "W5"),
        SampleCommitSite(0x2a, "STORE_3_13", 13, 13, "W6"),
        SampleCommitSite(0x2d, "STORE_2_12", 12, 12, "W6"),
        SampleCommitSite(0x3c, "STORE_4_14", 14, 14, "W84"),
        SampleCommitSite(0x3d, "STORE_5_15", 15, 15, "W84"),
        SampleCommitSite(0x4a, "STORE_14_15", 15, None, "W84 repeat"),
        SampleCommitSite(0x4b, "STORE_15_14", 14, None, "W84 repeat"),
    )
    next_prefetch = {
        0x13: 20, 0x14: 21, 0x15: 22, 0x16: 18,
        0x18: 19, 0x19: 23,
        0x26: 11, 0x27: 16, 0x28: 17, 0x29: 13,
        0x2c: 12, 0x2d: 17,
        0x3b: 14, 0x3c: 15,
    }
    for pc, word in next_prefetch.items():
        insn = Instruction.decode(candidate[pc])
        assert insn.op in (Op.READ, Op.WRITE, Op.EXEC)
        set_insn(pc, Instruction(insn.op, action=insn.action, word=word))
    for site in sites:
        old = Instruction.decode(candidate[site.pc])
        word = old.word
        set_insn(site.pc, Instruction(
            Op.WRITE, action=action_by_name[site.action], word=word))

    # Non-writing prefetch/capture edges.  H-C's retained old-q/tuple and the
    # 70-bit pool consume these words; none is a hidden semantic READ.
    set_word("nz_live_hold_1", 14)  # brown + lowpass sign
    set_word("nz_live_hold_2", 13)  # phase2 high + ack/nz phase/gain high
    set_word("nz_live_hold_3", 10)  # W0 current phase
    set_word("cap_W2", 18)          # selected old-inc low for W3/W4
    set_word("cap_W3", 19)          # selected old-inc high for W4/W5
    set_word("cap_W26_wait_hold_3", 19)  # old-gain low at W26
    set_word("cap_W40_wait_hold_1", 20)  # selected old reverb
    set_word("cap_W51", 26)         # damp/current reverb at W75
    set_word("cap_W75", 14)         # original filter high before W84
    set_word("cap_W84_wait_hold_0", 15)  # original filter low

    # Every fixed write action appears exactly once, and its destination stays
    # the one named by that action even when ir.word is a next-read prefetch.
    # W0/W1 retain their CAP action codes and gain literal destinations.  This
    # is a 16-entry fixed decoder, not an index mux.
    action_destination = {
        action_by_name[f"STORE_{index}_{10 + index}"]: 10 + index
        for index in range(1, 13)
    }
    action_destination.update({
        action_by_name["CAP_W0"]: 23,
        action_by_name["CAP_W1"]: 10,
        action_by_name["STORE_14_15"]: 15,
        action_by_name["STORE_15_14"]: 14,
    })
    seen: list[tuple[int, int, int | None]] = []
    q_word: int | None = None
    for pc in range(SAMPLE_START, 0x4e):
        insn = Instruction.decode(candidate[pc])
        if insn.op == Op.WRITE and insn.action in action_destination:
            seen.append((pc, action_destination[insn.action], q_word))
        if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
            q_word = insn.word
    assert [pc for pc, _, _ in seen] == [site.pc for site in sites]
    assert [dst for _, dst, _ in seen] == [site.destination for site in sites]
    for actual, site in zip(seen, sites):
        if site.q_source is not None:
            assert actual[2] == site.q_source, (actual, site)
    assert len({Instruction.decode(candidate[site.pc]).action
                for site in sites}) == 16

    # Control flow and operation counts are unchanged: twelve writes moved
    # onto twelve HOLDs.  Owner one is not part of this candidate at all.
    def execute_counts(image: list[int]) -> tuple[int, ...]:
        pc, slot = SAMPLE_START, 0
        counts = [0] * 8
        for _ in range(2_000):
            insn = Instruction.decode(image[pc])
            counts[int(insn.op)] += 1
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
                pc = (pc + 1) & 0xff
            elif insn.op == Op.SLOT:
                slot = (slot + 1) & 7 if insn.slot_inc else insn.slot_value
                pc = (pc + 1) & 0xff
            elif insn.op == Op.JUMP:
                pc = insn.target
            elif insn.op == Op.BRANCH:
                take = slot == 0
                pc = insn.target if take == bool(insn.sense) \
                    else (pc + 1) & 0xff
            elif insn.op == Op.DONE:
                break
            else:
                raise AssertionError(insn)
        else:
            raise AssertionError("relocated sample candidate did not finish")
        return tuple(counts)

    base_counts = execute_counts(program)
    candidate_counts = execute_counts(candidate)
    assert candidate_counts == base_counts
    assert sum(candidate_counts) == 782
    assert candidate_counts[int(Op.READ)] == 172
    assert candidate_counts[int(Op.WRITE)] == 158
    assert sum(word != 0 for word in candidate) == 222
    changed = sum(a != b for a, b in zip(program, candidate))
    assert changed == 39, changed
    result = ("H-D2A candidate: 16 fixed write actions at numbered "
              "finalization edges; 39 image words change; counts remain 222 "
              "words / 782 clocks / 172 reads / 158 writes; accepted image "
              "untouched")
    return result, candidate


def validate_sample_relocated_value_gap(candidate: list[int]) -> str:
    """Reject H-D2B at its first information and provenance failures.

    This is the corrected D2A instruction stream, before any accepted-image
    change.  Prove the strongest built-in allocation: even reusing every H-C
    field dead on that path cannot carry the independent values required at
    PC 1b.  Also convict two later values whose read arrives on an anonymous
    HOLD edge and therefore has no fixed consumer in a mirror-free adapter.
    """
    hold = COMMON_ACTION["HOLD"]

    def decoded(pc: int) -> Instruction:
        return Instruction.decode(candidate[pc])

    def q_word(pc: int) -> int | None:
        source: int | None = None
        for prior in range(SAMPLE_START, pc):
            insn = decoded(prior)
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
                source = insn.word
        return source

    # Worst built-in case: updated brown remains uncommitted, a wave0/7 mode-2
    # live coefficient needs fourteen DQ bits, and selected old wave6/non-alt
    # retains its old-noise step through W1.  At PC 1b the q stream presents
    # word14 and the IR primes word13.
    assert q_word(0x1b) == 14
    assert decoded(0x1b) == Instruction(Op.EXEC, action=hold, word=13)
    # Old-noise continuation and the old DQ update are mutually exclusive at
    # W5: CAP_W5 applies DQ only under !old_nz_r_on.  q13's old noise-phase
    # nibble is independently required until q10 supplies the current phase
    # nibble at W0.  Old q is unchanged on this path and is recovered from its
    # later typed q17 source rather than retained in the transient pool.
    old_noise_active = True
    old_dq_result_live = not old_noise_active
    assert old_noise_active and not old_dq_result_live
    payload = {
        "dq_live": 14,
        "old_noise_step": 17,
        "live_phase_delta": 13,
        "live_amplitude": 12,
        "noise_lowpass": 16,
        "updated_brown": 13,
        "phase2_msb": 1,
        "old_nz_phase": 4,
        "restart": 1,
        "clear": 1,
    }
    assert sum(payload.values()) == 92
    # A/B/N/O provide 70.  On a built-in path only H-C's ARAM phase index
    # (6) and snd_id (3) are dead; all live/old wave controls and old_q remain
    # required by W0--W5.  The strongest possible overlay is still short.
    available = 70 + 6 + 3
    assert sum(payload.values()) > available
    shortfall = sum(payload.values()) - available
    assert shortfall == 13

    # Updated word20 is presented at PC 2f, but PC 2f is one of many generic
    # HOLD/word-zero instructions.  Nothing fixed can capture selected
    # old_rev there before the stream moves on.
    assert decoded(0x2e).word == 20
    assert q_word(0x2f) == 20
    assert decoded(0x2f) == Instruction(Op.EXEC, action=hold, word=0)
    anonymous_zero_holds = sum(
        decoded(pc) == Instruction(Op.EXEC, action=hold, word=0)
        for pc in range(SAMPLE_START, 0x4e))
    assert anonymous_zero_holds > 1

    # Likewise PC 38 consumes q14 and primes word15; q15 arrives at another
    # anonymous HOLD at PC 39 and is overwritten before W84 can use it.
    assert q_word(0x38) == 14 and decoded(0x38).word == 15
    assert q_word(0x39) == 15
    assert decoded(0x39) == Instruction(Op.EXEC, action=hold, word=0)
    return ("H-D2B rejected: live old-noise PC 1b/1c needs 92 independent "
            "bits after excluding the mutually dead old-DQ delta, against the "
            f"strongest 79-bit pool/H-C overlay ({shortfall}-bit shortfall); "
            "q20 at PC 2f and q15 at PC 39 have no fixed consumer")


def validate_sample_relocated_stream_correction(
        program: list[int], d2a: list[int], actions: Actions) \
        -> tuple[str, list[int]]:
    """Build and prove the bounded D2C correction to the rejected D2A stream."""
    candidate = list(d2a)
    action_by_name = {action.name: code
                      for code, action in actions.by_owner["sample"].items()}

    def decoded(pc: int) -> Instruction:
        return Instruction.decode(candidate[pc])

    def set_insn(pc: int, insn: Instruction) -> None:
        candidate[pc] = insn.encode()

    def set_word(pc: int, word: int) -> None:
        insn = decoded(pc)
        assert insn.op in (Op.READ, Op.WRITE, Op.EXEC)
        set_insn(pc, Instruction(insn.op, action=insn.action, word=word))

    # Spend the two already-counted duplicate tail writes as typed q edges.
    # PC 1b commits updated brown/selected old mode while q14 is present; the
    # final post-W84 STORE_4_14 still replaces its filter-sign bit.  PC 39
    # performs a harmless same-word filter-low write while making q15 visible
    # to a unique action; STORE_5_15 still commits the final filtered value.
    set_insn(0x4b, Instruction(Op.EXEC, action=COMMON_ACTION["HOLD"]))
    set_insn(0x1b, Instruction(
        Op.WRITE, action=action_by_name["STORE_15_14"], word=13))
    set_insn(0x4a, Instruction(Op.EXEC, action=COMMON_ACTION["HOLD"]))
    set_insn(0x39, Instruction(
        Op.WRITE, action=action_by_name["STORE_14_15"], word=0))

    # Read the stored updated brown on the uniquely named W4 edge.  Move the
    # selected-old-reverb prime to the final pre-W40 wait so CAP_W40 consumes
    # q20 directly, with no previous-word tag or anonymous-HOLD capture.
    set_word(0x20, 14)  # CAP_W3 primes updated word14 for CAP_W4.
    set_word(0x2e, 0)
    set_word(0x30, 20)  # Final pre-W40 HOLD primes word20 for CAP_W40.

    def q_word(pc: int) -> int | None:
        source: int | None = None
        for prior in range(SAMPLE_START, pc):
            insn = decoded(prior)
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
                source = insn.word
        return source

    sites = (
        SampleCommitSite(0x14, "STORE_10_20", 20, 20, "restart select"),
        SampleCommitSite(0x15, "STORE_11_21", 21, 21, "restart select"),
        SampleCommitSite(0x16, "STORE_12_22", 22, 22, "restart select"),
        SampleCommitSite(0x17, "STORE_8_18", 18, 18, "restart select"),
        SampleCommitSite(0x19, "STORE_9_19", 19, 19, "restart select"),
        SampleCommitSite(0x1b, "STORE_15_14", 14, 14, "brown update"),
        SampleCommitSite(0x1d, "CAP_W0", 23, 10, "W0"),
        SampleCommitSite(0x1e, "CAP_W1", 10, 12, "W1"),
        SampleCommitSite(0x27, "STORE_1_11", 11, 11, "W5"),
        SampleCommitSite(0x28, "STORE_6_16", 16, 16, "W5"),
        SampleCommitSite(0x29, "STORE_7_17", 17, 17, "W5"),
        SampleCommitSite(0x2a, "STORE_3_13", 13, 13, "W6"),
        SampleCommitSite(0x2d, "STORE_2_12", 12, 12, "W6"),
        SampleCommitSite(0x39, "STORE_14_15", 15, 15, "filter-low capture"),
        SampleCommitSite(0x3c, "STORE_4_14", 14, 14, "W84"),
        SampleCommitSite(0x3d, "STORE_5_15", 15, 15, "W84"),
    )
    fixed_destination = {
        action_by_name[f"STORE_{index}_{10 + index}"]: 10 + index
        for index in range(1, 13)
    }
    fixed_destination.update({
        action_by_name["CAP_W0"]: 23,
        action_by_name["CAP_W1"]: 10,
        action_by_name["STORE_14_15"]: 15,
        action_by_name["STORE_15_14"]: 14,
    })
    seen: list[tuple[int, int, int | None]] = []
    for pc in range(SAMPLE_START, 0x4e):
        insn = decoded(pc)
        if insn.op == Op.WRITE and insn.action in fixed_destination:
            seen.append((pc, fixed_destination[insn.action], q_word(pc)))
    assert [pc for pc, _, _ in seen] == [site.pc for site in sites]
    assert [dst for _, dst, _ in seen] == [site.destination for site in sites]
    assert [source for _, _, source in seen] == \
        [site.q_source for site in sites]
    assert len({decoded(site.pc).action for site in sites}) == 16
    assert q_word(0x21) == 14  # Updated brown reaches CAP_W4.
    assert q_word(0x31) == 20  # Selected old reverb reaches CAP_W40.
    assert decoded(0x4a) == Instruction(
        Op.EXEC, action=COMMON_ACTION["HOLD"])
    assert decoded(0x4b) == Instruction(
        Op.EXEC, action=COMMON_ACTION["HOLD"])
    d2b_payload = {
        "dq_live": 14,
        "old_noise_step": 17,
        "live_phase_delta": 13,
        "live_amplitude": 12,
        "noise_lowpass": 16,
        "updated_brown": 13,
        "phase2_msb": 1,
        "old_nz_phase": 4,
        "restart": 1,
        "clear": 1,
    }
    assert sum(d2b_payload.values()) == 92
    # The typed q14 transaction stores the only 13-bit resident whose next
    # use is after W0.  It is fetched back as q14 at CAP_W4, reducing the
    # pre-W0 payload.  On this old-noise path CAP_W5 suppresses the old DQ
    # update, so its thirteen-bit delta is not simultaneously live.
    corrected_payload = sum(d2b_payload.values()) \
        - d2b_payload["updated_brown"]
    assert corrected_payload == 79

    def counts(image: list[int]) -> tuple[int, ...]:
        pc, slot = SAMPLE_START, 0
        result = [0] * 8
        for _ in range(2_000):
            insn = Instruction.decode(image[pc])
            result[int(insn.op)] += 1
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
                pc = (pc + 1) & 0xff
            elif insn.op == Op.SLOT:
                slot = (slot + 1) & 7 if insn.slot_inc else insn.slot_value
                pc = (pc + 1) & 0xff
            elif insn.op == Op.JUMP:
                pc = insn.target
            elif insn.op == Op.BRANCH:
                take = slot == 0
                pc = insn.target if take == bool(insn.sense) \
                    else (pc + 1) & 0xff
            elif insn.op == Op.DONE:
                break
            else:
                raise AssertionError(insn)
        else:
            raise AssertionError("D2C sample candidate did not finish")
        return tuple(result)

    base_counts = counts(program)
    assert counts(candidate) == base_counts
    assert sum(base_counts) == 782
    assert base_counts[int(Op.READ)] == 172
    assert base_counts[int(Op.WRITE)] == 158
    assert sum(word != 0 for word in candidate) == 222
    changed = sum(a != b for a, b in zip(program, candidate))
    return (f"H-D2C candidate: typed q14/q15 and CAP_W40 q20; live "
            f"old-noise payload 92 -> {corrected_payload} bits at the exact "
            f"fixed 79-bit H-C overlay; {changed} image words "
            "change; 16 fixed writes and 222/782/172/158 invariants; "
            "accepted image untouched", candidate)


def validate_sample_d2c_blend_gap(d2c: list[int]) -> str:
    """Reject D2C's anonymous final blend-count arrival at PC 2e."""
    hold_zero = Instruction(Op.EXEC, action=COMMON_ACTION["HOLD"], word=0)
    assert Instruction.decode(d2c[0x2d]).word == 17
    assert Instruction.decode(d2c[0x2e]) == hold_zero
    # PC 2d primes updated word17, so q17 arrives on PC 2e.  HOLD/word-zero
    # occurs repeatedly and cannot identify the fixed capture edge.
    anonymous = sum(Instruction.decode(d2c[pc]) == hold_zero
                    for pc in range(SAMPLE_START, 0x4e))
    assert anonymous > 1
    return ("H-D2C rejected: final q17/blend_count arrives at anonymous "
            "HOLD/word-zero PC 2e after the q20 prime moved")


def validate_sample_typed_blend_correction(
        program: list[int], d2c: list[int]) -> tuple[str, list[int]]:
    """Type the D2C q17 arrival using the existing stored HOLD word field."""
    candidate = list(d2c)
    hold = COMMON_ACTION["HOLD"]
    candidate[0x2e] = Instruction(Op.EXEC, action=hold, word=17).encode()

    def decoded(pc: int) -> Instruction:
        return Instruction.decode(candidate[pc])

    def q_word(pc: int) -> int | None:
        source: int | None = None
        for prior in range(SAMPLE_START, pc):
            insn = decoded(prior)
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
                source = insn.word
        return source

    assert q_word(0x2e) == 17
    assert decoded(0x2e) == Instruction(Op.EXEC, action=hold, word=17)
    typed = sum(decoded(pc) == decoded(0x2e)
                for pc in range(SAMPLE_START, 0x4e))
    assert typed == 1
    # The redundant word17 prime changes only q on the following anonymous
    # wait.  PC 30 still primes word20 and CAP_W40 still consumes it.
    assert q_word(0x2f) == 17
    assert decoded(0x30).word == 20 and q_word(0x31) == 20

    def counts(image: list[int]) -> tuple[int, ...]:
        pc, slot = SAMPLE_START, 0
        result = [0] * 8
        for _ in range(2_000):
            insn = Instruction.decode(image[pc])
            result[int(insn.op)] += 1
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
                pc = (pc + 1) & 0xff
            elif insn.op == Op.SLOT:
                slot = (slot + 1) & 7 if insn.slot_inc else insn.slot_value
                pc = (pc + 1) & 0xff
            elif insn.op == Op.JUMP:
                pc = insn.target
            elif insn.op == Op.BRANCH:
                take = slot == 0
                pc = insn.target if take == bool(insn.sense) \
                    else (pc + 1) & 0xff
            elif insn.op == Op.DONE:
                break
            else:
                raise AssertionError(insn)
        else:
            raise AssertionError("D2D sample candidate did not finish")
        return tuple(result)

    base_counts = counts(program)
    assert counts(candidate) == base_counts
    assert sum(base_counts) == 782
    assert base_counts[int(Op.READ)] == 172
    assert base_counts[int(Op.WRITE)] == 158
    assert sum(word != 0 for word in candidate) == 222
    changed = sum(a != b for a, b in zip(program, candidate))
    return (f"H-D2D candidate: unique HOLD/word17 consumes final q17; "
            f"{changed} image words change; 222/782/172/158 unchanged; "
            "accepted image untouched", candidate)


def validate_sample_context_path_bound(d2d: list[int]) -> str:
    """Exhaust every pre-W0 semantic class at the q13/q10 boundary.

    The old four-bit noise-phase value is presented in q13 at PC 1c, but the
    current phase nibble needed for its equality test does not arrive until
    q10 at W0.  This is the one-way equality problem: the earlier value needs
    four bits because every one of its sixteen values has a distinct response
    over the sixteen possible later values.
    """
    def decoded(pc: int) -> Instruction:
        return Instruction.decode(d2d[pc])

    def q_word(pc: int) -> int | None:
        source: int | None = None
        for prior in range(SAMPLE_START, pc):
            insn = decoded(prior)
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
                source = insn.word
        return source

    assert decoded(0x1b).word == 13 and q_word(0x1c) == 13
    assert decoded(0x1c).word == 10 and q_word(0x1d) == 10

    equality_signatures = {
        tuple(old_nz_phase == later_phase for later_phase in range(16))
        for old_nz_phase in range(16)
    }
    assert len(equality_signatures) == 16
    nz_phase_bits = (len(equality_signatures) - 1).bit_length()
    assert nz_phase_bits == 4

    def coefficient(wt: bool, wave: int, mode: int) -> int:
        if wt:
            return 256
        if wave == 0:
            return 193 if mode == 1 else 384 if mode == 2 else 256
        if wave == 7:
            return 250 if mode == 1 else 508 if mode == 2 else 254
        return 256 if mode == 0 else 255

    class_max: dict[tuple[bool, bool, bool, bool], int] = {}
    maxima = {False: 0, True: 0}
    cases = 0
    for wt in (False, True):
        for wave in range(8):
            for mode in range(4):
                dq_max = (8191 * coefficient(wt, wave, mode)) >> 8
                dq_bits = max(1, dq_max.bit_length())
                for noise in (False, True):
                    for buzz in (False, True):
                        for old_wave in range(8):
                            for old_mode in range(4):
                                for old_alt in (False, True):
                                    for control in range(4):
                                        restart = bool(control & 1)
                                        clear = bool(control & 2)
                                        cases += 1
                                        old_noise = old_wave == 6 \
                                            and not old_alt
                                        old_dq = not wt and not old_noise
                                        assert not (old_noise and old_dq)

                                        payload = {
                                            "dq_live": dq_bits,
                                            "live_phase_delta": 13,
                                            "live_amplitude": 12,
                                            "noise_lowpass": 16,
                                            "phase2_msb": 1,
                                            "restart": 1,
                                            "clear": 1,
                                        }
                                        if not noise:
                                            payload["old_nz_phase"] = \
                                                nz_phase_bits
                                        if old_noise:
                                            payload["old_noise_step"] = 17
                                        if old_dq:
                                            payload["old_phase_delta"] = 13
                                        if old_dq and not restart:
                                            payload["old_q_msb"] = 1
                                        required = sum(payload.values())

                                        # Built-in paths do not use ARAM index
                                        # or sound ID.  Wavetable uses both,
                                        # but its W2/W3 addresses ignore H-C
                                        # old-q and old tuple state after
                                        # classification.
                                        capacity = 70 + (22 if wt else 9)
                                        assert required <= capacity, (
                                            wt, wave, mode, noise, buzz,
                                            old_wave, old_mode, old_alt,
                                            restart, clear, payload, capacity)
                                        maxima[wt] = max(maxima[wt], required)
                                        key = (wt, wave == 6, noise,
                                               old_noise)
                                        class_max[key] = max(
                                            class_max.get(key, 0), required)

    assert cases == 65_536
    assert maxima == {False: 79, True: 78}
    assert class_max[(False, True, False, True)] == 78
    assert class_max[(False, True, False, False)] == 75
    assert class_max[(False, False, False, True)] == 79
    return ("H-D2E-A PC1c bound: 65,536 current/old "
            "wave-mode-noise-buzz-restart-clear "
            "classes; old-noise17 and old-DQ13 are W5-exclusive; built-in "
            "maximum 79/79, wavetable maximum 78/92, named brown+old-noise "
            "78/79; later W0-W6 physical packing remains unproved")


def validate_sample_physical_w2_gap(d2d: list[int], actions: Actions) -> str:
    """Reject D2F on the unchanged stream's no-restart old-DQ path.

    D2E-A proves an information bound at PC 1c.  This proof advances the
    literal D2D q stream through W2 and counts only values that are still
    independently observable on the named path.  One counterexample is
    sufficient to reject a physical allocation of the unchanged stream.
    """
    def decoded(pc: int) -> Instruction:
        return Instruction.decode(d2d[pc])

    def q_word(pc: int) -> int | None:
        source: int | None = None
        for prior in range(SAMPLE_START, pc):
            insn = decoded(prior)
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
                source = insn.word
        return source

    action_by_name = {action.name: code
                      for code, action in actions.by_owner["sample"].items()}
    assert decoded(0x1f).action == action_by_name["CAP_W2"]
    assert decoded(0x21).action == action_by_name["CAP_W4"]
    assert decoded(0x22).action == action_by_name["CAP_W5"]
    # D2D still primes word zero on CAP_W4, so W5 cannot recover word16's
    # original selected-old phase from the synchronous state output.
    assert decoded(0x21).word == 0 and q_word(0x22) == 0

    wt = False
    old_noise = False
    restart = False
    ordinary_old_dq = not wt and not old_noise
    assert ordinary_old_dq and not restart

    post_w2 = {
        "current_primary": 18,
        "selected_old_phase": 16,
        "live_dq": 14,
        "phase2": 17,
        "amplitude": 12,
        "old_phase_delta": 13,
        "old_q_msb": 1,
    }
    required = sum(post_w2.values())
    assert required == 91

    # H-C owns 38 bits.  The no-restart ordinary-old-DQ path must retain the
    # old-q low word and old wave/mode/alternate tuple until W5, leaving only
    # sixteen H-C bits for transient overlay beside A18+B18+N17+O17.
    pool = 18 + 18 + 17 + 17
    hc_total = 38
    hc_retained = 16 + (3 + 2 + 1)
    hc_overlay = hc_total - hc_retained
    available = pool + hc_overlay
    assert pool == 70 and hc_retained == 22 and hc_overlay == 16
    assert available == 86 and required > available
    deficit = required - available
    assert deficit == 5

    return ("H-D2F rejected: unchanged CAP_W4 primes word0, so no-restart "
            "ordinary old-DQ retains selected-old-phase16 through W5; "
            f"post-W2 payload {required} exceeds 70-bit pool + "
            f"{hc_overlay}-bit H-C overlay = {available} by {deficit} bits")


def build_sample_w5_q16_candidate(program: list[int], d2d: list[int],
                                  actions: Actions) \
        -> tuple[str, list[int]]:
    """Build the bounded D2F-A q16 prefetch candidate in memory only."""
    candidate = list(d2d)
    action_by_name = {action.name: code
                      for code, action in actions.by_owner["sample"].items()}

    def decoded(image: list[int], pc: int) -> Instruction:
        return Instruction.decode(image[pc])

    def q_word(image: list[int], pc: int) -> int | None:
        source: int | None = None
        for prior in range(SAMPLE_START, pc):
            insn = decoded(image, prior)
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
                source = insn.word
        return source

    cap_w4 = decoded(candidate, 0x21)
    assert cap_w4 == Instruction(
        Op.EXEC, action=action_by_name["CAP_W4"], word=0)
    assert q_word(candidate, 0x21) == 14
    candidate[0x21] = Instruction(
        cap_w4.op, action=cap_w4.action, word=16).encode()
    assert q_word(candidate, 0x21) == 14
    assert q_word(candidate, 0x22) == 16
    assert decoded(candidate, 0x22).action == action_by_name["CAP_W5"]
    assert [pc for pc, (before, after) in enumerate(zip(d2d, candidate))
            if before != after] == [0x21]

    # The new q word matters only for the ordinary old-DQ W5 update.  On a
    # no-restart path it is the original selected old phase.  Restart instead
    # selects the q10 phase snapshot and aliases selected old-q to phase2;
    # old-noise and wavetable paths suppress the W5 old-DQ update entirely.
    classes = 0
    consumers = {"q16": 0, "q10": 0, "none": 0}
    for wt in (False, True):
        for wave in range(8):
            for mode in range(4):
                for noise in (False, True):
                    for buzz in (False, True):
                        for old_wave in range(8):
                            for old_mode in range(4):
                                for old_alt in (False, True):
                                    for control in range(4):
                                        restart = bool(control & 1)
                                        classes += 1
                                        old_noise = old_wave == 6 \
                                            and not old_alt
                                        old_dq = not wt and not old_noise
                                        if old_dq and restart:
                                            consumers["q10"] += 1
                                        elif old_dq:
                                            consumers["q16"] += 1
                                        else:
                                            consumers["none"] += 1
    assert classes == 65_536
    assert sum(consumers.values()) == classes
    assert all(count for count in consumers.values())

    def counts(image: list[int]) -> tuple[int, ...]:
        pc, slot = SAMPLE_START, 0
        result = [0] * 8
        for _ in range(2_000):
            insn = decoded(image, pc)
            result[int(insn.op)] += 1
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
                pc = (pc + 1) & 0xff
            elif insn.op == Op.SLOT:
                slot = (slot + 1) & 7 if insn.slot_inc else insn.slot_value
                pc = (pc + 1) & 0xff
            elif insn.op == Op.JUMP:
                pc = insn.target
            elif insn.op == Op.BRANCH:
                take = slot == 0
                pc = insn.target if take == bool(insn.sense) \
                    else (pc + 1) & 0xff
            elif insn.op == Op.DONE:
                break
            else:
                raise AssertionError(insn)
        else:
            raise AssertionError("D2F-A sample candidate did not finish")
        return tuple(result)

    base_counts = counts(program)
    assert counts(candidate) == base_counts
    assert sum(base_counts) == 782
    assert base_counts[int(Op.READ)] == 172
    assert base_counts[int(Op.WRITE)] == 158
    assert sum(word != 0 for word in candidate) == 222
    changed = sum(a != b for a, b in zip(program, candidate))
    assert changed == 44
    return (f"H-D2F-A candidate: CAP_W4 word0 -> word16; q14 still consumed "
            f"at W4 and q16 reaches W5; {classes:,} paths select q16/q10/none "
            f"as {consumers['q16']}/{consumers['q10']}/{consumers['none']}; "
            f"{changed} image words change; 222/782/172/158 unchanged; "
            "accepted image untouched", candidate)


def validate_sample_b3b2a_slice_map(program: list[int], d2fa: list[int],
                                    actions: Actions) \
        -> tuple[str, list[int], B3B2AFrameCodec]:
    """Bind the active wavetable/old-noise repair to literal physical bits.

    This is deliberately narrower than a service executor.  It proves the
    corrected q stream and the complete W1/W2/W3/PRE_W15/W15 ownership map,
    including both interpolation base/sign lifetimes.  ARAM hold, stopped
    wavetable service state and composed multiplier freeze remain later gates.
    """
    candidate = list(d2fa)
    action_by_name = {action.name: code
                      for code, action in actions.by_owner["sample"].items()}

    def decoded(image: list[int], pc: int) -> Instruction:
        return Instruction.decode(image[pc])

    def q_word(image: list[int], pc: int) -> int | None:
        source: int | None = None
        for prior in range(SAMPLE_START, pc):
            insn = decoded(image, prior)
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
                source = insn.word
        return source

    cap_w2 = decoded(candidate, 0x1f)
    assert cap_w2 == Instruction(
        Op.EXEC, action=action_by_name["CAP_W2"], word=18)
    candidate[0x1f] = Instruction(
        cap_w2.op, action=cap_w2.action, word=19).encode()
    assert [q_word(candidate, pc) for pc in range(0x1d, 0x23)] \
        == [10, 12, 16, 19, 14, 16]
    assert [pc for pc, (before, after) in enumerate(zip(d2fa, candidate))
            if before != after] == [0x1f]
    changed = sum(before != after
                  for before, after in zip(program, candidate))
    assert changed == 44
    assert sum(word != 0 for word in candidate) == 222

    def counts(image: list[int]) -> tuple[int, ...]:
        pc, slot = SAMPLE_START, 0
        result = [0] * 8
        for _ in range(2_000):
            insn = decoded(image, pc)
            result[int(insn.op)] += 1
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
                pc = (pc + 1) & 0xff
            elif insn.op == Op.SLOT:
                slot = (slot + 1) & 7 if insn.slot_inc else insn.slot_value
                pc = (pc + 1) & 0xff
            elif insn.op == Op.JUMP:
                pc = insn.target
            elif insn.op == Op.BRANCH:
                take = slot == 0
                pc = insn.target if take == bool(insn.sense) \
                    else (pc + 1) & 0xff
            elif insn.op == Op.DONE:
                break
            else:
                raise AssertionError(insn)
        else:
            raise AssertionError("B3-B2-A candidate did not terminate")
        return tuple(result)

    base_counts = counts(program)
    assert counts(candidate) == base_counts
    assert (sum(base_counts), base_counts[int(Op.READ)],
            base_counts[int(Op.WRITE)]) == (782, 172, 158)

    # Source facts that force the two explicit interpolation sideband tokens.
    # W2's adjacent byte is the pre-edge seq_q; wt_p1 cannot be consumed until
    # the following edge.  The magnitude-only service retains neither sign nor
    # the signed base used by wt_z.
    walk = WALK.read_text()
    mulmp = (ROOT / "rtl" / "psg_mulmp.sv").read_text()
    for spelling in (
            "smp_a <= 18'($signed(seq_q));",
            "wt_p1 <= $signed(seq_q);",
            "smp_b <= 18'($signed(seq_q));",
            "wt_q1 <= $signed(seq_q);",
            "mxs_new <= wt_pd[8];",
            "mxs_new <= wt_qd[8];"):
        assert spelling in walk
    assert "callers retain the sign" in mulmp
    assert "wt_sum = $signed({wt_base[9:0], 10'b0}) + wt_prod" in walk
    assert "if (play_bits[pc_ch] && s_eff_a != 0) begin" in walk
    assert "wt_pf <= s_phase[9:0];" in walk
    assert "wt_qf <= q16[9:0];" in walk
    assert "(blend_restart || nz_tick_r) ? 16'(s_noise_lp) : s_old_phase" \
        in walk
    assert "(nz_old_pre > 18'sd6143)" in walk
    assert "wire [12:0] g_live = g_a + {1'b0, g_a[12:1]};" in walk

    capacities = {"A": 18, "B": 18, "N": 17, "O": 17,
                  "Q": 16, "T": 6, "C": 7, "I": 6, "D": 3}
    assert sum(capacities.values()) == 108

    @dataclass(frozen=True)
    class Field:
        name: str
        width: int
        pieces: tuple[tuple[str, int, int], ...]
        source: str

    def field(name: str, width: int,
              pieces: tuple[tuple[str, int, int], ...],
              source: str) -> Field:
        assert sum(part for _, _, part in pieces) == width
        assert source
        return Field(name, width, pieces, source)

    controls_w1 = (
        field("amplitude", 12, (("Q", 0, 12),), "typed amplitude"),
        field("restart", 1, (("Q", 12, 1),), "restart predicate"),
        field("clear", 1, (("Q", 13, 1),), "clear toggle"),
        field("nz_phase", 4, (("Q", 14, 2), ("T", 0, 2)),
              "noise phase"),
        field("refresh", 1, (("T", 2, 1),), "refresh predicate"),
    )
    fixed_w1 = (
        field("snd_wt", 1, (("C", 6, 1),), "live wavetable context"),
        field("live_is_wave6", 1, (("C", 3, 1),),
              "live wave-six predicate"),
        field("secondary_index", 6, (("I", 0, 6),),
              "H-C phase index"),
        field("snd_id", 3, (("D", 0, 3),), "H-C sounding id"),
    )
    w1 = (
        field("primary_fraction", 10, (("A", 0, 10),),
              "W0 phase fraction"),
        field("primary_base", 8, (("A", 10, 8),),
              "CAP_W1 ARAM base"),
        field("secondary_fraction", 10, (("B", 0, 10),),
              "old phase fraction"),
        field("seed_union", 16,
              (("B", 10, 8), ("T", 3, 3), ("C", 0, 1),
               ("C", 4, 2), ("C", 1, 2)),
              "exclusive wrapped seed or signed kick"),
        field("original_phase2", 17, (("N", 0, 17),), "typed q12"),
        field("old_noise_step", 17, (("O", 0, 17),),
              "old-noise multiplier result"),
        *controls_w1, *fixed_w1,
    )
    w2 = (
        field("primary_base", 8, (("A", 10, 8),),
              "retained CAP_W1 base"),
        field("primary_delta_sign", 1, (("A", 9, 1),),
              "sign(pre-edge seq_q - primary base)"),
        field("secondary_fraction", 10, (("B", 0, 10),),
              "old phase fraction"),
        field("original_phase2", 17, (("N", 0, 17),), "typed q12"),
        field("final_old_phase", 14, (("O", 0, 14),),
              "clamp14(wrapped seed plus old-noise step)"),
        *controls_w1, *fixed_w1,
    )
    w3 = (
        field("primary_base", 8, (("A", 10, 8),),
              "retained CAP_W1 base"),
        field("primary_delta_sign", 1, (("A", 9, 1),),
              "retained W2 delta sign"),
        field("secondary_fraction", 10, (("B", 0, 10),),
              "old phase fraction"),
        field("secondary_base", 8, (("B", 10, 8),),
              "CAP_W3 ARAM base"),
        field("original_phase2", 17, (("N", 0, 17),), "typed q12"),
        field("final_old_phase", 14, (("O", 0, 14),),
              "retained clamp14 result"),
        *controls_w1,
        field("snd_wt", 1, (("C", 6, 1),), "live wavetable context"),
        field("live_is_wave6", 1, (("C", 3, 1),),
              "live wave-six predicate"),
    )
    pre_w15 = (
        field("secondary_adjacent", 8, (("A", 0, 8),),
              "CAP_W4 ARAM adjacent"),
        field("live_gain", 13,
              (("A", 8, 7), ("A", 17, 1), ("C", 0, 5)),
              "amplitude-to-gain transform"),
        field("snd_wt", 1, (("A", 15, 1),), "relocated live context"),
        field("live_is_wave6", 1, (("A", 16, 1),),
              "relocated wave-six predicate"),
        field("secondary_fraction", 10, (("B", 0, 10),),
              "retained old fraction"),
        field("secondary_base", 8, (("B", 10, 8),),
              "retained CAP_W3 base"),
        field("final_phase2", 17, (("N", 0, 17),), "W6 DQ update"),
        field("final_old_q", 17, (("O", 0, 17),),
              "restart original phase2 or don't-care old q"),
        field("final_old_phase", 14, (("Q", 0, 14),),
              "relocated clamp14 result"),
        field("primary_base", 8,
              (("Q", 14, 2), ("T", 4, 2), ("I", 3, 3),
               ("D", 0, 1)), "W4 relocation of CAP_W1 base"),
        field("primary_delta_sign", 1, (("D", 1, 1),),
              "W4 relocation of W2 sign"),
        field("restart", 1, (("T", 0, 1),), "restart predicate"),
        field("clear", 1, (("T", 1, 1),), "clear toggle"),
        field("last_gain_we", 1, (("T", 2, 1),),
              "play/music predicate"),
        field("old_q_replace", 1, (("T", 3, 1),),
              "restart or old-DQ update"),
        field("nz_phase", 4, (("C", 5, 2), ("I", 0, 2)),
              "relocated noise phase"),
        field("refresh", 1, (("I", 2, 1),), "relocated refresh"),
    )
    post_w15 = (
        field("primary_interp", 15, (("A", 0, 15),),
              "base plus signed primary multiplier result"),
        field("snd_wt", 1, (("A", 15, 1),), "live context"),
        field("live_is_wave6", 1, (("A", 16, 1),),
              "wave-six predicate"),
        field("live_gain", 13, (("B", 0, 13),), "W15 relocation"),
        field("nz_phase", 4, (("B", 13, 4),), "W15 relocation"),
        field("refresh", 1, (("B", 17, 1),), "W15 relocation"),
        field("final_phase2", 17, (("N", 0, 17),), "retained W6 result"),
        field("final_old_q", 17, (("O", 0, 17),), "retained old q"),
        field("final_old_phase", 14, (("Q", 0, 14),),
              "retained clamp14 result"),
        field("secondary_base", 8,
              (("C", 0, 7), ("T", 4, 1)),
              "retained CAP_W3 base"),
        field("secondary_delta_sign", 1, (("T", 5, 1),),
              "sign(CAP_W4 adjacent - secondary base)"),
        field("restart", 1, (("T", 0, 1),), "restart predicate"),
        field("clear", 1, (("T", 1, 1),), "clear toggle"),
        field("last_gain_we", 1, (("T", 2, 1),),
              "play/music predicate"),
        field("old_q_replace", 1, (("T", 3, 1),),
              "restart or old-DQ update"),
    )
    post_pc27 = tuple(item for item in post_w15
                      if item.name != "refresh")
    post_pc28 = tuple(item for item in post_pc27
                      if item.name != "final_old_phase")
    post_pc29 = tuple(item for item in post_pc28
                      if item.name not in {"final_old_q", "old_q_replace"})
    post_pc2a = tuple(item for item in post_pc29
                      if item.name not in {"nz_phase", "restart",
                                           "last_gain_we"}) + (
        field("selected_old_gain_hi", 5, (("Q", 0, 5),),
              "typed q13 at PC2A"),
    )
    post_w26 = tuple(item for item in post_pc2a
                     if item.name not in {"secondary_base",
                                          "secondary_delta_sign",
                                          "selected_old_gain_hi"}) + (
        field("old_interp", 15, (("O", 0, 15),),
              "base plus signed secondary multiplier result"),
        field("old_gain_nonzero", 1, (("Q", 0, 1),),
              "typed q13 high plus q19 low"),
    )

    snapshots = (("W1", w1, 108), ("W2", w2, 80), ("W3", w3, 79),
                 ("PRE_W15", pre_w15, 107),
                 ("POST_W15", post_w15, 96),
                 ("POST_PC27", post_pc27, 95),
                 ("POST_PC28", post_pc28, 81),
                 ("POST_PC29", post_pc29, 63),
                 ("POST_PC2A", post_pc2a, 62),
                 ("POST_W26", post_w26, 64))
    snapshot_fields: dict[str, tuple[Field, ...]] = {}
    physical_used: dict[str, int] = {}
    for snapshot_name, fields, expected_used in snapshots:
        owned: set[tuple[str, int]] = set()
        names: set[str] = set()
        for item in fields:
            assert item.name not in names, (snapshot_name, item.name)
            names.add(item.name)
            for container, lsb, width in item.pieces:
                assert container in capacities
                assert 0 <= lsb and lsb + width <= capacities[container]
                for bit in range(lsb, lsb + width):
                    key = (container, bit)
                    assert key not in owned, (snapshot_name, key, item.name)
                    owned.add(key)
        assert len(owned) == expected_used, \
            (snapshot_name, len(owned), expected_used)
        snapshot_fields[snapshot_name] = fields
        physical_used[snapshot_name] = len(owned)
    overlay_used = (physical_used["W1"] - 11,
                    physical_used["W2"] - 11,
                    physical_used["W3"] - 2)
    assert overlay_used == (97, 69, 77)

    def unpack(snapshot_name: str, packed: PackedFrame) -> FrameValues:
        fields = snapshot_fields[snapshot_name]
        assert set(packed) == set(capacities)
        for container, width in capacities.items():
            assert 0 <= packed[container] < (1 << width)
        recovered: FrameValues = {}
        for item in fields:
            value = 0
            field_lsb = 0
            for container, lsb, width in item.pieces:
                mask = (1 << width) - 1
                value |= ((packed[container] >> lsb) & mask) << field_lsb
                field_lsb += width
            recovered[item.name] = value
        return recovered

    def pack(snapshot_name: str, values: FrameValues) \
            -> tuple[PackedFrame, FrameValues]:
        fields = snapshot_fields[snapshot_name]
        assert set(values) == {item.name for item in fields}, \
            (snapshot_name, set(values) ^ {item.name for item in fields})
        packed = {container: 0 for container in capacities}
        for item in fields:
            field_lsb = 0
            for container, lsb, width in item.pieces:
                mask = (1 << width) - 1
                assert 0 <= values[item.name] < (1 << item.width)
                packed[container] |= \
                    ((values[item.name] >> field_lsb) & mask) << lsb
                field_lsb += width
        recovered = unpack(snapshot_name, packed)
        assert recovered == values, (snapshot_name, recovered, values)
        return packed, recovered

    def source(case: int, name: str, width: int) -> int:
        return ((case * 0x5a17 + sum(ord(ch) for ch in name) * 0x9e37
                 + width * 0x45) & ((1 << width) - 1))

    def carry(prior: dict[str, int], *names: str) -> dict[str, int]:
        return {name: prior[name] for name in names}

    # Execute every replacement from the decoded previous physical frame.
    # New values enter only at the named q/input/service edge.  In particular,
    # no later frame is independently filled from a synthetic field table.
    for case in range(256):
        nz_tick = bool(case & 1)
        restart = bool(case & 2)
        restart_or_nz_tick = restart or nz_tick
        wrapped_seed = source(case, "wrapped_seed", 16)
        kick14 = source(case, "kick14", 14)
        kick16 = kick14 | (0xc000 if kick14 & 0x2000 else 0)
        seed_union = wrapped_seed if restart_or_nz_tick else kick16
        w1_values = {
            "primary_fraction": source(case, "primary_fraction", 10),
            "primary_base": source(case, "primary_base", 8),
            "secondary_fraction": source(case, "secondary_fraction", 10),
            "seed_union": seed_union,
            "original_phase2": source(case, "original_phase2", 17),
            "old_noise_step": source(case, "old_noise_step", 17),
            "amplitude": source(case, "amplitude", 12) or 1,
            "restart": int(restart),
            "clear": int(bool(case & 4)),
            "nz_phase": source(case, "nz_phase", 4),
            "refresh": int(bool(case & 8)),
            "snd_wt": 1,
            "live_is_wave6": int((case & 7) == 6),
            "secondary_index": source(case, "secondary_index", 6),
            "snd_id": source(case, "snd_id", 3),
        }
        _, w1_decoded = pack("W1", w1_values)

        # CAP_W2 consumes q16 and the arriving ARAM byte.  The adjacent byte
        # is explicitly pre-edge input, never the just-assigned wt_p1 value.
        primary_adjacent = source(case, "primary_adjacent", 8)
        primary_delta = signed(primary_adjacent, 8) \
            - signed(w1_decoded["primary_base"], 8)
        q16_old_phase = source(case, "q16_old_phase", 16)
        selected_seed = w1_decoded["seed_union"] \
            if restart_or_nz_tick else \
            (q16_old_phase + signed(w1_decoded["seed_union"], 16)) & 0xffff
        pre_sum = signed(selected_seed, 16) \
            + signed(w1_decoded["old_noise_step"], 17)
        final_old_phase = max(-6_143, min(6_143, pre_sum))
        w2_values = carry(
            w1_decoded, "primary_base", "secondary_fraction",
            "original_phase2", "amplitude", "restart", "clear",
            "nz_phase", "refresh", "snd_wt", "live_is_wave6",
            "secondary_index", "snd_id")
        w2_values.update({
            "primary_delta_sign": int(primary_delta < 0),
            "final_old_phase": final_old_phase & 0x3fff,
        })
        _, w2_decoded = pack("W2", w2_values)
        primary_token = {
            "kind": "primary_interp",
            "magnitude": abs(primary_delta)
                         * w1_decoded["primary_fraction"],
            "base": w2_decoded["primary_base"],
            "sign": w2_decoded["primary_delta_sign"],
        }

        # CAP_W3 consumes the next returned base, after which the phase index
        # and sounding id are dead.  All retained values come from W2 bits.
        w3_values = carry(
            w2_decoded, "primary_base", "primary_delta_sign",
            "secondary_fraction", "original_phase2", "final_old_phase",
            "amplitude", "restart", "clear", "nz_phase", "refresh",
            "snd_wt", "live_is_wave6")
        w3_values["secondary_base"] = source(case, "secondary_base", 8)
        _, w3_decoded = pack("W3", w3_values)

        # W4 supplies secondary adjacent and relocates primary base/sign.  W6
        # copies old N into O on restart before updating N; without restart O
        # is don't-care because old_q_replace stays clear.
        secondary_adjacent = source(case, "secondary_adjacent", 8)
        dq_visit = source(case, "dq_visit", 17)
        final_phase2 = (w3_decoded["original_phase2"] + dq_visit) & 0x1ffff
        old_q_replace = w3_decoded["restart"]
        final_old_q = w3_decoded["original_phase2"] \
            if old_q_replace else 0
        pre_values = carry(
            w3_decoded, "primary_base", "primary_delta_sign",
            "secondary_fraction", "secondary_base", "final_old_phase",
            "restart", "clear", "nz_phase", "refresh", "snd_wt",
            "live_is_wave6")
        pre_values.update({
            "secondary_adjacent": secondary_adjacent,
            "live_gain": (w3_decoded["amplitude"]
                          + (w3_decoded["amplitude"] >> 1)) & 0x1fff,
            "final_phase2": final_phase2,
            "final_old_q": final_old_q,
            "last_gain_we": int(bool(case & 16)),
            "old_q_replace": old_q_replace,
        })
        pre_packed, pre_decoded = pack("PRE_W15", pre_values)

        # CAP_W15 consumes the ready primary token and atomically launches the
        # secondary one.  Its base/sign are then read back unchanged at W26.
        assert primary_token["kind"] == "primary_interp"
        assert primary_token["base"] == pre_decoded["primary_base"]
        assert primary_token["sign"] == pre_decoded["primary_delta_sign"]
        primary_product = int(primary_token["magnitude"])
        if primary_token["sign"]:
            primary_product = -primary_product
        primary_interp = ((signed(pre_decoded["primary_base"], 8) << 10)
                          + primary_product) >> 3
        assert -(1 << 14) <= primary_interp < (1 << 14)
        secondary_delta = signed(pre_decoded["secondary_adjacent"], 8) \
            - signed(pre_decoded["secondary_base"], 8)
        secondary_token = {
            "kind": "secondary_interp",
            "magnitude": abs(secondary_delta)
                         * pre_decoded["secondary_fraction"],
            "base": pre_decoded["secondary_base"],
            "sign": int(secondary_delta < 0),
        }
        post_values = carry(
            pre_decoded, "snd_wt", "live_is_wave6", "live_gain",
            "final_phase2", "final_old_q", "final_old_phase",
            "secondary_base", "restart", "clear", "last_gain_we",
            "old_q_replace", "nz_phase", "refresh")
        post_values.update({
            "primary_interp": primary_interp & 0x7fff,
            "secondary_delta_sign": int(secondary_delta < 0),
        })
        _, post_decoded = pack("POST_W15", post_values)
        held_base = post_decoded["secondary_base"]
        held_sign = post_decoded["secondary_delta_sign"]

        # Execute each intervening fixed edge.  The two sideband fields are
        # decoded from and re-packed into every successor frame; they are not
        # reintroduced from locals at W26.
        pc27_values = {name: value for name, value in post_decoded.items()
                       if name != "refresh"}
        _, pc27_decoded = pack("POST_PC27", pc27_values)
        pc28_values = {name: value for name, value in pc27_decoded.items()
                       if name != "final_old_phase"}
        _, pc28_decoded = pack("POST_PC28", pc28_values)
        pc29_values = {name: value for name, value in pc28_decoded.items()
                       if name not in {"final_old_q", "old_q_replace"}}
        _, pc29_decoded = pack("POST_PC29", pc29_values)
        pc2a_values = {
            name: value for name, value in pc29_decoded.items()
            if name not in {"nz_phase", "restart", "last_gain_we"}
        }
        pc2a_values["selected_old_gain_hi"] = \
            source(case, "selected_old_gain_hi", 5)
        _, pc2a_decoded = pack("POST_PC2A", pc2a_values)
        for decoded_frame in (post_decoded, pc27_decoded, pc28_decoded,
                              pc29_decoded, pc2a_decoded):
            assert decoded_frame["secondary_base"] == held_base
            assert decoded_frame["secondary_delta_sign"] == held_sign

        assert held_base == pre_decoded["secondary_base"]
        assert held_sign == int(secondary_delta < 0)
        assert secondary_token["base"] == held_base
        assert secondary_token["sign"] == held_sign
        secondary_product = int(secondary_token["magnitude"])
        if secondary_token["sign"]:
            secondary_product = -secondary_product
        secondary_interp = ((signed(held_base, 8) << 10)
                            + secondary_product) >> 3
        assert -(1 << 14) <= secondary_interp < (1 << 14)
        old_gain_nonzero = int(
            (pc2a_decoded["selected_old_gain_hi"] << 8)
            | source(case, "selected_old_gain_low", 8) != 0)
        w26_values = {
            name: value for name, value in pc2a_decoded.items()
            if name not in {"secondary_base", "secondary_delta_sign",
                            "selected_old_gain_hi"}
        }
        w26_values.update({
            "old_interp": secondary_interp & 0x7fff,
            "old_gain_nonzero": old_gain_nonzero,
        })
        _, w26_decoded = pack("POST_W26", w26_values)
        assert w26_decoded["old_interp"] == (secondary_interp & 0x7fff)

    # W2 consumes the arriving byte combinationally.  The signed base and sign
    # are the only primary-interpolation payload retained through W15.  The
    # secondary request repeats the same contract from W15 through W26.
    for base in range(-128, 128):
        for adjacent in (-128, -1, 0, 1, 127):
            delta = adjacent - base
            sign_bit = int(delta < 0)
            assert sign_bit == int((-delta if sign_bit else delta) != delta)
            assert -255 <= delta <= 255
    assert dict(SAMPLE_CAP_SCHEDULE)["W15"] \
        - dict(SAMPLE_CAP_SCHEDULE)["W2"] == 7
    assert dict(SAMPLE_CAP_SCHEDULE)["W26"] \
        - dict(SAMPLE_CAP_SCHEDULE)["W15"] == 5

    summary = ("H-D2F-C-B3-B2-A1 active play&&amplitude!=0 wavetable/"
            "selected-old-noise path map: "
            "q W0..W5="
            "10/12/16/19/14/16; physical W1/W2/W3/PRE_W15/POST_W15/W26 "
            f"{physical_used['W1']}/{physical_used['W2']}/"
            f"{physical_used['W3']}/{physical_used['PRE_W15']}/"
            f"{physical_used['POST_W15']}/{physical_used['POST_W26']} "
            "of 108 (overlay "
            f"{overlay_used[0]}/{overlay_used[1]}/{overlay_used[2]}); "
            "primary base/sign "
            "W2->W15 and secondary base/sign W15->W26 literal and "
            f"overlap-free; {changed} image words and 222/782/172/158 "
            "unchanged; stopped/hold/service execution and accepted image/RTL "
            "untouched")
    return summary, candidate, B3B2AFrameCodec(pack, unpack, source)


def validate_sample_b3b2a2a1_edge_services(
        candidate: list[int], actions: Actions,
        codec: B3B2AFrameCodec) -> str:
    """Sample a CE-selected W1--POST_W26 frame/service transducer."""
    action_by_name = {action.name: code
                      for code, action in actions.by_owner["sample"].items()}
    assert Instruction.decode(candidate[0x1f]) == Instruction(
        Op.EXEC, action=action_by_name["CAP_W2"], word=19)

    aram_rtl = (ROOT / "rtl" / "psg_aram.sv").read_text()
    mul_rtl = (ROOT / "rtl" / "psg_mulmp.sv").read_text()
    walk_rtl = WALK.read_text()
    for spelling in (
            "assign seq_frozen = syn_rd | replay;",
            "wire aram_rd = !syn_freeze && (syn_rd | replay | !seq_hold);",
            "wire [12:0] aram_addr = syn_rd ? syn_addr : seq_addr;",
            "seq_q <= aram[aram_addr];",
            "replay <= syn_rd;"):
        assert spelling in aram_rtl
    for spelling in (
            "assign m_busy     = req_tgl != ack_sync;",
            "ack_meta <= ack_tgl;",
            "ack_sync <= ack_meta;",
            "req_meta <= req_tgl;",
            "req_sync <= req_meta;",
            "m_p   <= {21'b0, req_b};",
            "m_cnt <= req_steps;",
            "else if (!freeze) begin"):
        assert spelling in mul_rtl
    assert "if (prun && !ctrl_stall && s_snd_wt && play_bits[pc_ch])" \
        in walk_rtl
    assert "if (play_bits[pc_ch] && s_eff_a != 0) begin" in walk_rtl
    assert "wire [12:0] g_live = g_a + {1'b0, g_a[12:1]};" in walk_rtl
    assert "s_snd_wt ? ((s_old_G == 13'd0) ? 17'sd0 : mx_new)" \
        in walk_rtl
    assert "mx_aud  <= play_bits[pc_ch]" in walk_rtl
    assert "wmul_mode = 2'd1;" in walk_rtl

    @dataclass(frozen=True)
    class Aram:
        memory: tuple[int, ...]
        wraddr: int = 0x3100
        seq_q: int = 0
        replay: bool = False
        # Proof witness only: the inferred RTL stores the byte, not its tag.
        q_origin: int | None = None

    def aram_edge(state: Aram, *, seq_addr: int, syn_rd: bool,
                  syn_addr: int = 0, syn_freeze: bool,
                  seq_hold: bool, reset: bool = False,
                  cpu: tuple[int, int] | None = None) -> Aram:
        assert len(state.memory) == 4608
        assert 0 <= seq_addr < 4608 and 0 <= syn_addr < 8192
        memory = state.memory
        aram_rd = (not syn_freeze) \
            and (syn_rd or state.replay or not seq_hold)
        aram_addr = syn_addr if syn_rd else seq_addr
        seq_q = state.seq_q
        q_origin = state.q_origin
        if aram_rd:
            assert aram_addr < 4608
            seq_q = memory[aram_addr]
            q_origin = aram_addr

        replay = False if reset else (
            state.replay if syn_freeze else syn_rd)
        wraddr = 0x3100 if reset else state.wraddr
        if not reset and cpu is not None:
            addr, data = cpu
            assert 0 <= addr < 256 and 0 <= data < 256
            if addr == 0:
                wraddr = (state.wraddr & 0xff00) | data
            elif addr == 1:
                wraddr = (state.wraddr & 0x00ff) | (data << 8)
            elif addr == 2:
                up_idx = state.wraddr - 0x3100
                if 0 <= up_idx < 4608:
                    image = list(memory)
                    image[up_idx] = data
                    memory = tuple(image)
                wraddr = (state.wraddr + 1) & 0xffff
        return Aram(memory, wraddr, seq_q, replay, q_origin)

    @dataclass(frozen=True)
    class Mul:
        req_a: int = 0
        req_b: int = 0
        req_steps: int = 0
        req_tgl: int = 0
        seq_pad: int = 0
        ack_tgl: int = 0
        ack_meta: int = 0
        ack_sync: int = 0
        req_meta: int = 0
        req_sync: int = 0
        m_p: int = 0
        m_cnt: int = 0

        @property
        def busy(self) -> bool:
            return bool(self.req_tgl != self.ack_sync)

    def mul_slow(state: Mul, *, start: bool = False, a: int = 0,
                 b: int = 0, enable: bool) -> Mul:
        if not enable:
            return state
        nxt = replace(
            state, ack_meta=state.ack_tgl, ack_sync=state.ack_meta,
            seq_pad=max(0, state.seq_pad - 1))
        if start:
            assert not state.busy
            assert -(1 << 17) <= a < (1 << 17)
            assert 0 <= b < (1 << 10)
            nxt = replace(
                nxt, req_a=abs(a), req_b=b, req_steps=10,
                req_tgl=state.req_tgl ^ 1, seq_pad=5)
        return nxt

    def mul_fast(state: Mul, *, enable: bool) -> Mul:
        if not enable:
            return state
        nxt = replace(state, req_meta=state.req_tgl,
                      req_sync=state.req_meta)
        if state.m_cnt != 0:
            acc = (state.m_p >> 12) & ((1 << 19) - 1)
            total = acc + (state.req_a if state.m_p & 1 else 0)
            product = ((total & ((1 << 20) - 1)) << 11) \
                | ((state.m_p >> 1) & 0x7ff)
            nxt = replace(nxt, m_p=product,
                          m_cnt=state.m_cnt - 1)
            if state.m_cnt == 1:
                nxt = replace(nxt, ack_tgl=state.req_sync)
        elif state.req_sync != state.ack_tgl:
            nxt = replace(nxt, m_p=state.req_b,
                          m_cnt=state.req_steps)
        return nxt

    def mul_edge(state: Mul, *, start: bool = False, a: int = 0,
                 b: int = 0, enable: bool) -> Mul:
        # clocks.sv and psg_mulmp_tb place the PSG rising edge on a fast-clock
        # falling edge, followed by exactly six fast rising edges.
        nxt = mul_slow(state, start=start, a=a, b=b, enable=enable)
        for _ in range(6):
            nxt = mul_fast(nxt, enable=enable)
        return nxt

    def mul_value(state: Mul) -> int:
        assert not state.busy and state.m_cnt == 0
        return state.m_p >> 2

    def sample_addr(snd_id: int, index: int, adjacent: bool) -> int:
        assert 0 <= snd_id < 8 and 0 <= index < 64
        point = (index + int(adjacent)) & 0x3f
        return 256 + (snd_id << 6) + (snd_id << 2) + point

    def frame_tuple(frame: PackedFrame) -> tuple[tuple[str, int], ...]:
        return tuple(sorted(frame.items()))

    def frame_dict(frame: tuple[tuple[str, int], ...]) -> PackedFrame:
        return dict(frame)

    def carry(prior: FrameValues, *names: str) -> FrameValues:
        return {name: prior[name] for name in names}

    @dataclass(frozen=True)
    class Scenario:
        case: int
        play: bool
        amplitude_nonzero: bool
        primary_phase: int
        secondary_phase: int
        primary_fraction: int
        secondary_fraction: int
        seq_addr: int

    @dataclass(frozen=True)
    class EdgeState:
        offset: int
        frame_name: str
        frame: tuple[tuple[str, int], ...]
        aram: Aram
        mul: Mul
        aram_issues: int = 0
        aram_takes: int = 0
        mul_issues: int = 0
        mul_takes: int = 0

    def initial_state(scenario: Scenario, aram: Aram, mul: Mul) -> EdgeState:
        case = scenario.case
        nz_tick = bool(case & 1)
        restart = bool(case & 2)
        restart_or_nz_tick = restart or nz_tick
        wrapped_seed = codec.source(case, "wrapped_seed", 16)
        kick14 = codec.source(case, "kick14", 14)
        kick16 = kick14 | (0xc000 if kick14 & 0x2000 else 0)
        seed_union = wrapped_seed if restart_or_nz_tick else kick16
        amplitude = (codec.source(case, "amplitude", 12) or 1) \
            if scenario.amplitude_nonzero else 0
        values = {
            "primary_fraction": scenario.primary_fraction,
            "primary_base": 0,
            "secondary_fraction": scenario.secondary_fraction,
            "seed_union": seed_union,
            "original_phase2": codec.source(case, "original_phase2", 17),
            "old_noise_step": codec.source(case, "old_noise_step", 17),
            "amplitude": amplitude,
            "restart": int(restart),
            "clear": int(bool(case & 4)),
            "nz_phase": codec.source(case, "nz_phase", 4),
            "refresh": int(bool(case & 8)),
            "snd_wt": 1,
            "live_is_wave6": int((case & 7) == 6),
            "secondary_index": scenario.secondary_phase >> 10,
            "snd_id": codec.source(case, "snd_id", 3),
        }
        packed = codec.pack("W1", values)[0]
        return EdgeState(0, "W1", frame_tuple(packed), aram, mul)

    def enabled_successor(state: EdgeState,
                          scenario: Scenario) -> EdgeState:
        assert 0 <= state.offset < 15
        frame = frame_dict(state.frame)
        pre_q = state.aram.seq_q
        pre_origin = state.aram.q_origin
        aram_req = False
        aram_addr = 0
        mul_start = False
        mul_a = 0
        mul_b = 0
        frame_name = state.frame_name
        aram_takes = state.aram_takes
        mul_takes = state.mul_takes

        snd_id = codec.unpack(frame_name, frame).get(
            "snd_id", codec.source(scenario.case, "snd_id", 3))
        pindex = scenario.primary_phase >> 10
        sindex = scenario.secondary_phase >> 10
        addresses = (
            sample_addr(snd_id, pindex, False),
            sample_addr(snd_id, pindex, True),
            sample_addr(snd_id, sindex, False),
            sample_addr(snd_id, sindex, True),
        )

        if state.offset == 0:
            if scenario.play:
                aram_req, aram_addr = True, addresses[0]
        elif state.offset == 1:
            values = codec.unpack("W1", frame)
            if scenario.play:
                assert pre_origin == addresses[0]
                aram_takes += 1
                aram_req, aram_addr = True, addresses[1]
            else:
                assert pre_origin == scenario.seq_addr
            values["primary_base"] = pre_q
            frame = codec.pack("W1", values)[0]
        elif state.offset == 2:
            w1 = codec.unpack("W1", frame)
            if scenario.play:
                assert pre_origin == addresses[1]
                aram_takes += 1
                aram_req, aram_addr = True, addresses[2]
            else:
                assert pre_q == w1["primary_base"]
            delta = signed(pre_q, 8) - signed(w1["primary_base"], 8)
            restart_or_nz_tick = bool(w1["restart"] or (scenario.case & 1))
            q16_old_phase = codec.source(
                scenario.case, "q16_old_phase", 16)
            selected_seed = w1["seed_union"] if restart_or_nz_tick else \
                (q16_old_phase + signed(w1["seed_union"], 16)) & 0xffff
            pre_sum = signed(selected_seed, 16) \
                + signed(w1["old_noise_step"], 17)
            final_old_phase = max(-6_143, min(6_143, pre_sum))
            w2 = carry(
                w1, "primary_base", "secondary_fraction",
                "original_phase2", "amplitude", "restart", "clear",
                "nz_phase", "refresh", "snd_wt", "live_is_wave6",
                "secondary_index", "snd_id")
            w2.update({"primary_delta_sign": int(delta < 0),
                       "final_old_phase": final_old_phase & 0x3fff})
            frame = codec.pack("W2", w2)[0]
            frame_name = "W2"
            assert not state.mul.busy
            mul_start, mul_a, mul_b = True, delta, w1["primary_fraction"]
        elif state.offset == 3:
            w2 = codec.unpack("W2", frame)
            if scenario.play:
                assert pre_origin == addresses[2]
                aram_takes += 1
                aram_req, aram_addr = True, addresses[3]
            w3 = carry(
                w2, "primary_base", "primary_delta_sign",
                "secondary_fraction", "original_phase2",
                "final_old_phase", "amplitude", "restart", "clear",
                "nz_phase", "refresh", "snd_wt", "live_is_wave6")
            w3["secondary_base"] = pre_q
            frame = codec.pack("W3", w3)[0]
            frame_name = "W3"
        elif state.offset == 4:
            w3 = codec.unpack("W3", frame)
            if scenario.play:
                assert pre_origin == addresses[3]
                aram_takes += 1
            else:
                assert pre_q == w3["secondary_base"]
            dq_visit = codec.source(scenario.case, "dq_visit", 17)
            final_phase2 = (w3["original_phase2"] + dq_visit) & 0x1ffff
            pre = carry(
                w3, "primary_base", "primary_delta_sign",
                "secondary_fraction", "secondary_base",
                "final_old_phase", "restart", "clear", "nz_phase",
                "refresh", "snd_wt", "live_is_wave6")
            pre.update({
                "secondary_adjacent": pre_q,
                "live_gain": (w3["amplitude"]
                              + (w3["amplitude"] >> 1)) & 0x1fff,
                "final_phase2": final_phase2,
                "final_old_q": (w3["original_phase2"]
                                if w3["restart"] else 0),
                "last_gain_we": int(bool(scenario.case & 16)),
                "old_q_replace": w3["restart"],
            })
            frame = codec.pack("PRE_W15", pre)[0]
            frame_name = "PRE_W15"
        elif state.offset == 9:
            pre = codec.unpack("PRE_W15", frame)
            magnitude = mul_value(state.mul)
            assert magnitude == state.mul.req_a * state.mul.req_b
            product = -magnitude if pre["primary_delta_sign"] else magnitude
            interp = ((signed(pre["primary_base"], 8) << 10)
                      + product) >> 3
            delta = signed(pre["secondary_adjacent"], 8) \
                - signed(pre["secondary_base"], 8)
            post = carry(
                pre, "snd_wt", "live_is_wave6", "live_gain",
                "final_phase2", "final_old_q", "final_old_phase",
                "secondary_base", "restart", "clear", "last_gain_we",
                "old_q_replace", "nz_phase", "refresh")
            post.update({"primary_interp": interp & 0x7fff,
                         "secondary_delta_sign": int(delta < 0)})
            frame = codec.pack("POST_W15", post)[0]
            frame_name = "POST_W15"
            mul_start, mul_a, mul_b = True, delta, pre["secondary_fraction"]
            mul_takes += 1
        elif state.offset == 10:
            post = codec.unpack("POST_W15", frame)
            frame = codec.pack("POST_PC27", {
                name: value for name, value in post.items()
                if name != "refresh"})[0]
            frame_name = "POST_PC27"
        elif state.offset == 11:
            post = codec.unpack("POST_PC27", frame)
            frame = codec.pack("POST_PC28", {
                name: value for name, value in post.items()
                if name != "final_old_phase"})[0]
            frame_name = "POST_PC28"
        elif state.offset == 12:
            post = codec.unpack("POST_PC28", frame)
            frame = codec.pack("POST_PC29", {
                name: value for name, value in post.items()
                if name not in {"final_old_q", "old_q_replace"}})[0]
            frame_name = "POST_PC29"
        elif state.offset == 13:
            post = codec.unpack("POST_PC29", frame)
            values = {name: value for name, value in post.items()
                      if name not in {"nz_phase", "restart",
                                      "last_gain_we"}}
            values["selected_old_gain_hi"] = codec.source(
                scenario.case, "selected_old_gain_hi", 5)
            frame = codec.pack("POST_PC2A", values)[0]
            frame_name = "POST_PC2A"
        elif state.offset == 14:
            post = codec.unpack("POST_PC2A", frame)
            magnitude = mul_value(state.mul)
            assert magnitude == state.mul.req_a * state.mul.req_b
            product = -magnitude \
                if post["secondary_delta_sign"] else magnitude
            interp = ((signed(post["secondary_base"], 8) << 10)
                      + product) >> 3
            old_gain = (post["selected_old_gain_hi"] << 8) \
                | codec.source(scenario.case, "selected_old_gain_low", 8)
            values = {name: value for name, value in post.items()
                      if name not in {"secondary_base",
                                      "secondary_delta_sign",
                                      "selected_old_gain_hi"}}
            values.update({"old_interp": interp & 0x7fff,
                           "old_gain_nonzero": int(old_gain != 0)})
            frame = codec.pack("POST_W26", values)[0]
            frame_name = "POST_W26"
            mul_takes += 1

        aram = aram_edge(
            state.aram, seq_addr=scenario.seq_addr, syn_rd=aram_req,
            syn_addr=aram_addr, syn_freeze=False, seq_hold=True)
        mul = mul_edge(state.mul, start=mul_start, a=mul_a, b=mul_b,
                       enable=True)
        return EdgeState(
            state.offset + 1, frame_name, frame_tuple(frame), aram, mul,
            state.aram_issues + int(aram_req), aram_takes,
            state.mul_issues + int(mul_start), mul_takes)

    def edge(state: EdgeState, scenario: Scenario, *, enable: bool) \
            -> EdgeState:
        # Deliberately compute the complete enabled successor first.  The
        # service CE then chooses that successor or the bit-identical prestate
        # as one atomic boundary, including schedule offset and packed frame.
        # The offset is not a production PC/IR/action/state_q controller proof.
        successor = enabled_successor(state, scenario)
        return successor if enable else state

    def run(scenario: Scenario, aram: Aram, mul: Mul) \
            -> tuple[EdgeState, int]:
        state = initial_state(scenario, aram, mul)
        holds = 0
        for offset in range(15):
            assert state.offset == offset
            successor = edge(state, scenario, enable=True)
            assert successor != state
            assert edge(state, scenario, enable=False) == state
            state = successor
            holds += 1
        assert state.offset == 15 and state.frame_name == "POST_W26"
        assert not state.mul.busy
        return state, holds

    def interp(base: int, adjacent: int, fraction: int) -> int:
        delta = signed(adjacent, 8) - signed(base, 8)
        product = abs(delta) * fraction
        if delta < 0:
            product = -product
        return ((signed(base, 8) << 10) + product) >> 3

    def fraction_gain_witness(values: FrameValues, play: bool) -> int:
        if not play:
            return 0
        # Exact candidate gain starts at amplitude + amplitude/2.  A zero
        # amplitude therefore convicts every later gain/blend arm to zero,
        # independent of both interpolation results.
        gain = values["live_gain"]
        combined = signed(values["primary_interp"], 15) \
            + (signed(values["old_interp"], 15) >> 1)
        return combined * gain

    quotient_cases = 0
    for raw in range(256):
        for fraction in range(1024):
            assert interp(raw, raw, fraction) == signed(raw, 8) << 7
            quotient_cases += 1
    for combined in range(-(1 << 17), 1 << 17):
        assert combined * 0 == 0

    # Freeze every recurrence count and the returned acknowledge using the
    # exact CE-selected pure functions, not an elapsed-age abstraction.
    mul_freezes = 0
    for target in range(10, 0, -1):
        mul = mul_slow(Mul(), start=True, a=-255, b=1023, enable=True)
        for _ in range(64):
            if mul.m_cnt == target:
                break
            mul = mul_fast(mul, enable=True)
        else:
            raise AssertionError(("unreached multiplier count", target))
        assert mul_slow(mul, enable=False) == mul
        assert mul_fast(mul, enable=False) == mul
        while mul.busy:
            mul = mul_edge(mul, enable=True)
        assert mul_value(mul) == 255 * 1023
        mul_freezes += 1
    mul = mul_slow(Mul(), start=True, a=127, b=777, enable=True)
    for _ in range(64):
        mul = mul_fast(mul, enable=True)
        if mul.m_cnt == 0 and mul.ack_tgl != mul.ack_sync:
            break
    else:
        raise AssertionError("unreached multiplier acknowledge crossing")
    assert mul_slow(mul, enable=False) == mul
    assert mul_fast(mul, enable=False) == mul
    while mul.busy:
        mul = mul_edge(mul, enable=True)
    assert mul_value(mul) == 127 * 777
    mul_freezes += 1

    # CPU upload is intentionally outside the executor CE.  It may update RAM
    # while synthesis output/replay are frozen, and resume must read the same
    # address rather than an injected request value.
    memory = tuple((i ^ (i >> 5) ^ 0xa5) & 0xff for i in range(4608))
    aram = Aram(memory)
    seq_addr, borrow_addr = 0x101, 0x020
    aram = aram_edge(aram, seq_addr=seq_addr, syn_rd=False,
                     syn_freeze=False, seq_hold=False)
    aram = aram_edge(aram, seq_addr=seq_addr, syn_rd=True,
                     syn_addr=borrow_addr, syn_freeze=False, seq_hold=True)
    held_q = aram.seq_q
    pico_addr = 0x3100 + seq_addr
    for cpu in ((0, pico_addr & 0xff), (1, pico_addr >> 8), (2, 0xd4)):
        aram = aram_edge(aram, seq_addr=seq_addr, syn_rd=False,
                         syn_freeze=True, seq_hold=True, cpu=cpu)
        assert aram.seq_q == held_q and aram.replay
    assert aram.memory[seq_addr] == 0xd4
    aram = aram_edge(aram, seq_addr=seq_addr, syn_rd=False,
                     syn_freeze=False, seq_hold=True)
    assert (aram.seq_q, aram.q_origin, aram.replay) \
        == (0xd4, seq_addr, False)

    class_counts = {"audible": 0, "silent": 0, "stopped": 0}
    hold_checks = 0
    convergence = 0
    for case in range(64):
        memory = tuple((((i * 0x59) ^ (i >> 4)
                         ^ (case * 0x6d) ^ 0xa5) & 0xff)
                       for i in range(4608))
        seq_addr = (0x700 + case) % 4608
        aram0 = aram_edge(Aram(memory), seq_addr=seq_addr, syn_rd=False,
                          syn_freeze=False, seq_hold=False)
        primary = codec.source(case, "a2a1_primary_phase", 16)
        secondary = codec.source(case, "a2a1_secondary_phase", 16)
        audible = Scenario(case, True, True, primary, secondary,
                           primary & 0x3ff, secondary & 0x3ff, seq_addr)
        live, held = run(audible, aram0, Mul())
        hold_checks += held
        class_counts["audible"] += 1
        live_values = codec.unpack("POST_W26", frame_dict(live.frame))
        snd_id = codec.source(case, "snd_id", 3)
        assert signed(live_values["primary_interp"], 15) == interp(
            memory[sample_addr(snd_id, primary >> 10, False)],
            memory[sample_addr(snd_id, primary >> 10, True)],
            primary & 0x3ff)
        assert signed(live_values["old_interp"], 15) == interp(
            memory[sample_addr(snd_id, secondary >> 10, False)],
            memory[sample_addr(snd_id, secondary >> 10, True)],
            secondary & 0x3ff)
        assert (live.aram_issues, live.aram_takes,
                live.mul_issues, live.mul_takes) == (4, 4, 2, 2)
        assert (live.aram.seq_q, live.aram.q_origin, live.aram.replay) \
            == (aram0.seq_q, seq_addr, False)

        # A playing zero-amplitude slot performs the four reads but retains
        # the preceding audible fractions in legacy RTL.  Execute both that
        # literal state and the canonical-zero candidate, then compare the
        # first public leaf and a following audible transaction.
        silent_legacy = Scenario(
            case, True, False, primary ^ 0x5a5a, secondary ^ 0xa5a5,
            primary & 0x3ff, secondary & 0x3ff, seq_addr)
        silent_zero = replace(silent_legacy,
                              primary_fraction=0,
                              secondary_fraction=0)
        legacy_silent, held = run(silent_legacy, live.aram, live.mul)
        zero_silent, held_zero = run(silent_zero, live.aram, live.mul)
        hold_checks += held + held_zero
        class_counts["silent"] += 1
        lv = codec.unpack("POST_W26", frame_dict(legacy_silent.frame))
        zv = codec.unpack("POST_W26", frame_dict(zero_silent.frame))
        assert fraction_gain_witness(lv, True) \
            == fraction_gain_witness(zv, True) == 0
        assert (legacy_silent.aram, legacy_silent.mul.req_tgl,
                legacy_silent.mul.ack_tgl) \
            == (zero_silent.aram, zero_silent.mul.req_tgl,
                zero_silent.mul.ack_tgl)
        assert replace(legacy_silent.mul,
                       req_b=zero_silent.mul.req_b,
                       m_p=zero_silent.mul.m_p) == zero_silent.mul
        assert legacy_silent.mul.m_p != zero_silent.mul.m_p \
            or (lv["primary_interp"], lv["old_interp"]) \
            == (zv["primary_interp"], zv["old_interp"])

        following = Scenario(
            case, True, True, primary ^ 0x33cc, secondary ^ 0xcc33,
            (primary ^ 0x33cc) & 0x3ff,
            (secondary ^ 0xcc33) & 0x3ff, seq_addr)
        after_legacy, held = run(
            following, legacy_silent.aram, legacy_silent.mul)
        after_zero, held_zero = run(
            following, zero_silent.aram, zero_silent.mul)
        hold_checks += held + held_zero
        assert after_legacy == after_zero
        convergence += 1

        stopped_legacy = Scenario(
            case, False, True, primary, secondary,
            primary & 0x3ff, secondary & 0x3ff, seq_addr)
        stopped_zero = replace(stopped_legacy,
                               primary_fraction=0,
                               secondary_fraction=0)
        legacy_stop, held = run(stopped_legacy, after_zero.aram,
                                after_zero.mul)
        zero_stop, held_zero = run(stopped_zero, after_zero.aram,
                                   after_zero.mul)
        hold_checks += held + held_zero
        class_counts["stopped"] += 1
        lsv = codec.unpack("POST_W26", frame_dict(legacy_stop.frame))
        zsv = codec.unpack("POST_W26", frame_dict(zero_stop.frame))
        assert fraction_gain_witness(lsv, False) \
            == fraction_gain_witness(zsv, False) == 0
        assert (legacy_stop.aram, legacy_stop.mul.m_p,
                legacy_stop.mul.req_tgl, legacy_stop.mul.ack_tgl) \
            == (zero_stop.aram, zero_stop.mul.m_p,
                zero_stop.mul.req_tgl, zero_stop.mul.ack_tgl)
        assert replace(legacy_stop.mul,
                       req_b=zero_stop.mul.req_b) == zero_stop.mul
        assert (legacy_stop.aram_issues, legacy_stop.aram_takes,
                legacy_stop.mul_issues, legacy_stop.mul_takes) \
            == (0, 0, 2, 2)
        after_legacy_stop, held = run(
            following, legacy_stop.aram, legacy_stop.mul)
        after_zero_stop, held_zero = run(
            following, zero_stop.aram, zero_stop.mul)
        hold_checks += held + held_zero
        assert after_legacy_stop == after_zero_stop
        convergence += 1

    assert class_counts == {"audible": 64, "silent": 64, "stopped": 64}
    assert hold_checks == 64 * 9 * 15
    return ("H-D2F-C-B3-B2-A2-A1 sampled W1-POST_W26 wave-service lemma: "
            "64 audible + 64 playing-zero-amplitude + 64 stopped slots; "
            f"{hold_checks} attempted offset/frame/service freezes; "
            f"{mul_freezes} exact multiplier count/ack freezes; "
            "four-read silent ARAM/replay retained-fraction quotient and "
            f"{convergence} following-audible convergences; stopped "
            f"equal-endpoint quotient {quotient_cases:,}; accepted "
            "image/RTL untouched; PC/IR/state_q and fold/public suffix "
            "unproved")


def validate_sample_d2fb_packing(candidate: list[int], actions: Actions) \
        -> str:
    """Prove the tight D2F-B physical rows after the q16 prefetch.

    Each row assigns named value pieces to literal physical containers.  The
    checker rejects a container overflow, a missing/split field bit, or a
    round-trip alias.  H-C fields still needed by the wave cadence are not
    listed as capacity; only path-dead slices appear beside A/B/N/O.
    """
    action_by_name = {action.name: code
                      for code, action in actions.by_owner["sample"].items()}

    def decoded(pc: int) -> Instruction:
        return Instruction.decode(candidate[pc])

    def q_word(pc: int) -> int | None:
        source: int | None = None
        for prior in range(SAMPLE_START, pc):
            insn = decoded(prior)
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
                source = insn.word
        return source

    assert decoded(0x21) == Instruction(
        Op.EXEC, action=action_by_name["CAP_W4"], word=16)
    assert q_word(0x21) == 14 and q_word(0x22) == 16

    # The pre-W0 LFSR byte does not need an eight-bit transient.  CAP_W0's
    # exact full-mode shift makes old[7:0] equal new[8:1], and there is no
    # second visit advance before the typed q11 commit.
    walk = WALK.read_text()
    assert "lfsr  <= {lfsr[13:0], lfsr[14] ^ lfsr[13]};" in walk
    for old_lfsr in range(1 << 15):
        new_lfsr = ((old_lfsr << 1) & 0x7fff) \
            | (((old_lfsr >> 14) ^ (old_lfsr >> 13)) & 1)
        assert ((new_lfsr >> 1) & 0xff) == (old_lfsr & 0xff)

    @dataclass(frozen=True)
    class RowResult:
        name: str
        used: int
        capacity: int

    def row(name: str, capacities: dict[str, int],
            assignments: dict[str, tuple[tuple[str, int], ...]],
            expected_used: int) -> RowResult:
        field_widths: dict[str, int] = {}
        pieces: list[tuple[str, str, int, int, int]] = []
        container_offsets: dict[str, int] = {}
        for container, fields in assignments.items():
            assert container in capacities, (name, container)
            offset = 0
            for field, width in fields:
                assert width > 0
                field_lsb = field_widths.get(field, 0)
                pieces.append((container, field, offset, field_lsb, width))
                field_widths[field] = field_lsb + width
                offset += width
            assert offset <= capacities[container], \
                (name, container, offset, capacities[container])
            container_offsets[container] = offset
        used = sum(container_offsets.values())
        assert used == expected_used, (name, used, expected_used)

        # Give every logical field an independent deterministic value, pack
        # all pieces, then recover it.  This catches overlap and split-field
        # omissions rather than accepting a summed-width argument alone.
        values = {
            field: ((sum(ord(ch) for ch in field) * 0x9e37 + width * 0x45)
                    & ((1 << width) - 1))
            for field, width in field_widths.items()
        }
        packed = {container: 0 for container in capacities}
        reconstructed = {field: 0 for field in field_widths}
        for container, owner, container_lsb, field_lsb, width in pieces:
            mask = (1 << width) - 1
            fragment = (values[owner] >> field_lsb) & mask
            packed[container] |= fragment << container_lsb
            reconstructed[owner] |= \
                ((packed[container] >> container_lsb) & mask) << field_lsb
        assert reconstructed == values, (name, reconstructed, values)
        return RowResult(name, used, sum(capacities.values()))

    # Common physical fields.  C is the seven-bit live wt/wave/mode/alt
    # context; T is the six-bit old wave/mode/alt tuple.  WF/MF are the two
    # bits freed when wavetable wave3 is recoded as is-wave6 and live mode is
    # retired after W1.
    base = {"A": 18, "B": 18, "N": 17, "O": 17}
    bi_early = {**base, "I": 6, "D": 3}
    # After PC1b commits word14, old phase-view modes 0/1 are identical and
    # modes are irrelevant for old waves 0/7.  Recode the six-bit old tuple as
    # wave3/alternate/mode-is-two, freeing TF for the later wave-6 decision.
    bi_late = {**base, "C": 7, "I": 6, "D": 3, "TF": 1}
    bi_restart = {**bi_late, "Q": 16}
    all_fields = {**base, "Q": 16, "T": 6, "C": 7,
                  "I": 6, "D": 3}
    wt_early = {**base, "Q": 16, "T": 6, "X": 1}
    wt_w0 = {**wt_early, "WF": 2}
    wt_late = {**wt_w0, "MF": 2}

    rows = []
    rows.append(row("builtin ordinary PC1c", bi_early, {
        "A": (("noise_lp", 16), ("phase2_msb", 1), ("old_q_msb", 1)),
        "B": (("live_dq", 14), ("old_nz_phase", 4)),
        "N": (("live_delta", 13), ("amplitude", 4)),
        "O": (("old_delta", 13), ("amplitude", 4)),
        "I": (("amplitude", 4), ("restart", 1), ("clear", 1)),
    }, 76))
    rows.append(row("builtin old-noise PC1c", bi_early, {
        "A": (("noise_lp", 16), ("phase2_msb", 1), ("restart", 1)),
        "B": (("live_dq", 14), ("old_nz_phase", 4)),
        "N": (("live_delta", 13), ("amplitude", 4)),
        "O": (("old_noise_step", 17),),
        "I": (("amplitude", 6),),
        "D": (("amplitude", 2), ("clear", 1)),
    }, 79))
    rows.append(row("builtin ordinary W2 no-restart", bi_late, {
        "A": (("current_primary", 18),),
        "B": (("live_dq", 14), ("live_gain", 4)),
        "N": (("phase2_next", 17),),
        "O": (("old_delta", 13), ("old_q_msb", 1), ("clear", 1),
              ("refresh", 1), ("nz_phase", 1)),
        "C": (("live_gain", 7),),
        "I": (("live_gain", 2), ("post_w1_flags", 2),
              ("nz_phase", 2)),
        "D": (("nz_phase", 1), ("restart", 1), ("snd_wt", 1)),
        "TF": (("live_is_wave6", 1),),
    }, 87))
    rows.append(row("builtin ordinary W2 restart", bi_restart, {
        "A": (("current_primary", 18),),
        "B": (("live_dq", 14), ("live_gain", 4)),
        "N": (("phase2_next", 17),),
        "O": (("old_delta", 13), ("clear", 1), ("refresh", 1),
              ("nz_phase", 2)),
        "Q": (("q10_snapshot", 16),),
        "C": (("live_gain", 7),),
        "I": (("live_gain", 2), ("post_w1_flags", 2),
              ("nz_phase", 2)),
        "D": (("restart", 1), ("snd_wt", 1)),
        "TF": (("live_is_wave6", 1),),
    }, 102))
    rows.append(row("builtin old-noise W2", all_fields, {
        "A": (("current_primary", 18),),
        "B": (("old_noise_sample", 18),),
        "N": (("phase2_next", 17),),
        "O": (("final_old_phase", 16), ("clear", 1)),
        "Q": (("live_dq", 14), ("nz_phase", 2)),
        "T": (("live_gain", 6),),
        "C": (("live_gain", 7),),
        "I": (("post_w1_flags", 2), ("refresh", 1),
              ("nz_phase", 2)),
        "D": (("restart", 1), ("snd_wt", 1),
              ("live_is_wave6", 1)),
    }, 107))

    rows.append(row("wavetable old-noise PC1c", wt_early, {
        "A": (("live_delta", 13),),
        "B": (("amplitude", 12),),
        "N": (("noise_lp", 16),),
        "O": (("old_noise_step", 17),),
        "Q": (("live_dq", 13), ("phase2_msb", 1),
              ("restart", 1), ("clear", 1)),
        "T": (("refresh", 1),),
    }, 75))
    rows.append(row("wavetable old-noise W0", wt_w0, {
        "A": (("primary_fraction", 10),),
        "B": (("amplitude", 12),),
        "N": (("live_delta", 13),),
        "O": (("old_noise_step", 17),),
        "Q": (("live_dq", 13), ("phase2_msb", 1),
              ("restart", 1), ("clear", 1)),
        "T": (("nz_phase", 4), ("refresh", 1)),
    }, 73))

    def wt_overlay(extra: tuple[tuple[str, int], ...]) \
            -> dict[str, tuple[tuple[str, int], ...]]:
        return {
            "Q": (("amplitude", 12), ("restart", 1), ("clear", 1),
                  ("nz_phase", 2)),
            "T": (("nz_phase", 2), ("refresh", 1), *extra[:1]),
            "X": extra[1:2], "WF": extra[2:3], "MF": extra[3:4],
        }

    adjacent = (("primary_adjacent", 3), ("primary_adjacent", 1),
                ("primary_adjacent", 2), ("primary_adjacent", 2))
    for suffix, old_value, used_w1, used_w2, used_w3 in (
            ("no-restart", ("old_bias", 17), 81, 89, 97),
            ("restart", ("old_phase", 14), 78, 86, 94)):
        overlay_no_adj = wt_overlay(())
        # Remove empty physical containers from the W1 row.
        overlay_no_adj = {k: v for k, v in overlay_no_adj.items() if v}
        rows.append(row(f"wavetable old-noise W1 {suffix}", wt_late, {
            "A": (("primary_fraction_base", 18),),
            "B": (("old_fraction", 10),),
            "N": (("phase2_next", 17),),
            "O": (old_value,), **overlay_no_adj,
        }, used_w1))
        overlay_adj = wt_overlay(adjacent)
        rows.append(row(f"wavetable old-noise W2 {suffix}", wt_late, {
            "A": (("primary_fraction_base", 18),),
            "B": (("old_fraction", 10),),
            "N": (("phase2_next", 17),),
            "O": (old_value,), **overlay_adj,
        }, used_w2))
        rows.append(row(f"wavetable old-noise W3 {suffix}", wt_late, {
            "A": (("primary_fraction_base", 18),),
            "B": (("old_fraction_base", 18),),
            "N": (("phase2_next", 17),),
            "O": (old_value,), **overlay_adj,
        }, used_w3))

    old_other_overlay = wt_overlay(adjacent)
    rows.append(row("wavetable old-other W3 restart", wt_late, {
        "A": (("primary_fraction_base", 18),),
        "B": (("old_fraction_base", 18),),
        "N": (("phase2_next", 17),),
        "O": (("q10_snapshot", 16),), **old_other_overlay,
    }, 96))
    rows.append(row("wavetable old-other W3 no-restart", wt_late, {
        "A": (("primary_fraction_base", 18),),
        "B": (("old_fraction_base", 18),),
        "N": (("phase2_next", 17),),
        "O": (("primary_adjacent", 8),),
        "Q": (("amplitude", 12), ("restart", 1), ("clear", 1),
              ("nz_phase", 2)),
        "T": (("nz_phase", 2), ("refresh", 1)),
    }, 80))

    assert max(result.used / result.capacity for result in rows) == 1
    tight = sorted(result.name for result in rows
                   if result.used == result.capacity)
    assert tight == ["builtin old-noise PC1c",
                     "builtin ordinary W2 no-restart",
                     "wavetable old-noise W3 no-restart"]

    # The recoded old tuple is exact for every phase/wave/mode combination:
    # only mode two doubles non-0/7 phases, and alternate is orthogonal.
    for raw in range(1 << 16):
        for old_wave in range(8):
            for old_mode in range(4):
                recoded_mode = 2 if old_mode == 2 else 0
                assert phase_view(raw, old_wave, old_mode, False) \
                    == phase_view(raw, old_wave, recoded_mode, False)

    # The early phase2 formation and two compact noise identities used above
    # are exact over their full source domains.
    max_kick_draw = 0
    for lfsr2 in range(1 << 15):
        inv = 1 ^ ((lfsr2 >> 12) & 1)
        draw = signed((inv << 11) | (inv << 10)
                      | ((lfsr2 >> 2) & 0x3ff), 12)
        draw = draw - (draw >> 3) - (draw >> 6)
        max_kick_draw = max(max_kick_draw, abs(draw))
    assert max_kick_draw == 881
    assert 33_324 + 7 * max_kick_draw == 39_491 < (1 << 16)

    pair_min, pair_max = 0, 0
    for wave in range(8):
        for alt in (False, True):
            for phase in range(1 << 16):
                pair = wave_value(phase, wave, alt, False) \
                    + wave_value(phase, wave, alt, True)
                pair_min = min(pair_min, pair)
                pair_max = max(pair_max, pair)
    assert -(1 << 17) <= pair_min and pair_max < (1 << 17)

    return (f"H-D2F-B literal packing: {len(rows)} tight/edge rows; "
            f"exact fits at {', '.join(tight)}; old tuple 6 -> 5 bits exact; "
            "pre-W0 LFSR byte recovered "
            f"for all {1 << 15:,} states; old-noise bias <= 39,491; "
            f"built-in pair range {pair_min}..{pair_max} fits signed18; "
            "semantic commit executor and RTL remain unproved")


def validate_sample_d2fca_manifest(candidate: list[int],
                                   actions: Actions) -> str:
    """Prove the post-D2F-B physical-state and fixed-write manifest.

    This is deliberately a manifest rather than another semantic executor.
    It binds every late value to literal A/B/N/O or H-C bit slices, checks
    replacement at each producer/consumer edge, retains full write provenance,
    and proves the literal fold keeps its result until dry publication.
    """
    action_by_code = actions.by_owner["sample"]
    action_by_name = {action.name: code
                      for code, action in action_by_code.items()}

    def decoded(pc: int) -> Instruction:
        return Instruction.decode(candidate[pc])

    def action_name(pc: int) -> str:
        action = action_by_code.get(decoded(pc).action)
        return "HOLD" if action is None \
            and decoded(pc).action == COMMON_ACTION["HOLD"] else \
            ("" if action is None else action.name)

    def q_word(pc: int) -> int | None:
        source: int | None = None
        for prior in range(SAMPLE_START, pc):
            insn = decoded(prior)
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC):
                source = insn.word
        return source

    # Every persistent/scratch write keeps its PC, action, physical q source,
    # fixed destination and value provenance.  In particular, the early and
    # final word-14/15 writes may not disappear in a last-value dictionary.
    writes = (
        (0x14, "STORE_10_20", 20, 20, "selected old/current tuple"),
        (0x15, "STORE_11_21", 21, 21, "current increment low"),
        (0x16, "STORE_12_22", 22, 22, "last controls/gain low"),
        (0x17, "STORE_8_18", 18, 18, "selected old increment low"),
        (0x19, "STORE_9_19", 19, 19, "selected old gain/inc high"),
        (0x1b, "STORE_15_14", 14, 14, "early brown/mode/filter sign"),
        (0x1d, "CAP_W0", 10, 23, "final noise lowpass"),
        (0x1e, "CAP_W1", 12, 10, "final current phase"),
        (0x27, "STORE_1_11", 11, 11, "nz hold/old-q low"),
        (0x28, "STORE_6_16", 16, 16, "final old phase"),
        (0x29, "STORE_7_17", 17, 17, "blend/old-q high"),
        (0x2a, "STORE_3_13", 13, 13, "ack/gains/nz/phase2 high"),
        (0x2d, "STORE_2_12", 12, 12, "final phase2 low"),
        (0x39, "STORE_14_15", 15, 15, "clear-qualified filter low"),
        (0x3c, "STORE_4_14", 14, 14, "final filter high/mode/brown"),
        (0x3d, "STORE_5_15", 15, 15, "final filter low"),
        (0x4c, "STORE_LEAF_LO", 0, 48,
         "audible-gated retained filtered value low"),
        (0x4d, "STORE_LEAF_HI", 48, 49,
         "audible-gated retained filtered value high"),
    )
    for pc, name, q_source, destination, origin in writes:
        insn = decoded(pc)
        assert insn.op == Op.WRITE, (pc, insn)
        assert action_name(pc) == name, (pc, action_name(pc), name)
        assert q_word(pc) == q_source, (pc, q_word(pc), q_source)
        assert 10 <= destination <= 23 or destination in (48, 49)
        assert origin
    destinations = [destination for _, _, _, destination, _ in writes]
    assert {word: destinations.count(word) for word in range(10, 24)} \
        == {word: (2 if word in (14, 15) else 1)
            for word in range(10, 24)}
    assert destinations.count(48) == destinations.count(49) == 1

    typed_q = {0x1c: 13, 0x21: 14, 0x22: 16, 0x27: 11,
               0x28: 16, 0x29: 17, 0x2a: 13, 0x2b: 19,
               0x2d: 12, 0x2e: 17, 0x31: 20, 0x38: 14,
               0x39: 15}
    assert {pc: q_word(pc) for pc in typed_q} == typed_q

    # CAP_W51's literal word 26 is intended to prefetch active-bank dampen for
    # CAP_W75, but the committed movement layer remaps 24..27 only on OP_READ
    # while CAP is OP_EXEC.  D2F-C-B must add this exact action-qualified
    # 26/30 address selection before semantic RTL can be accepted.  Audible is
    # captured from play/hidden into one manifest bit until the leaf writes.
    assert decoded(0x36) == Instruction(
        Op.EXEC, action=action_by_name["CAP_W51"], word=26)
    assert q_word(0x37) == 26
    move = MOVE.read_text()
    assert "if (sample && op == OP_READ && state_word[5:2] == 4'b0110)" \
        in move
    assert tuple(30 if spar_bank else 26 for spar_bank in (0, 1)) == (26, 30)

    events = ("PRE_W15", "W15", "PC27", "PC28", "PC29", "PC2A",
              "W26", "W27", "PC2D", "PC2E", "W40", "W51", "W75",
              "PC38", "PC39", "W84", "PC3C", "PC3D", "PC4C", "PC4D",
              "DONE")
    event = {name: index for index, name in enumerate(events)}
    capacities = {"A": 18, "B": 18, "N": 17, "O": 17,
                  "Q": 16, "T": 6, "C": 7, "I": 6, "D": 3}
    assert sum(capacities.values()) == 108
    hc_aliases = {
        "Q": "old_q[15:0]",
        "T": "{old_wave[2:0],old_mode[1:0],old_alt}",
        "C": "{snd_wt,snd_wave[2:0],snd_mode[1:0],snd_alt}",
        "I": "phase_index_hold[5:0]",
        "D": "snd_id[2:0]",
    }
    assert set(hc_aliases) == set(capacities) - {"A", "B", "N", "O"}

    @dataclass(frozen=True)
    class LiveField:
        name: str
        width: int
        pieces: tuple[tuple[str, int, int], ...]
        born: str
        dead: str
        source: str
        consumer: str

    def field(name: str, width: int,
              pieces: tuple[tuple[str, int, int], ...],
              born: str, dead: str, source: str,
              consumer: str) -> LiveField:
        return LiveField(name, width, pieces, born, dead, source, consumer)

    built = (
        field("final_nz_phase", 4, (("A", 0, 4),), "PRE_W15", "PC2A",
              "unpacked D2F-B W0 state", "word13 merge"),
        field("refresh", 1, (("A", 4, 1),), "PRE_W15", "PC27",
              "unpacked D2F-B refresh", "word11 merge"),
        field("restart", 1, (("A", 5, 1),), "PRE_W15", "PC2A",
              "unpacked D2F-B restart", "blend/gain merges"),
        field("clear", 1, (("A", 6, 1),), "PRE_W15", "PC39",
              "unpacked D2F-B clear", "word13/15 merges"),
        field("last_gain_we", 1, (("A", 7, 1),), "PRE_W15", "PC2A",
              "play/music predicate", "word13 merge"),
        field("old_q_replace", 1, (("A", 8, 1),), "PRE_W15", "PC29",
              "restart or old-DQ update", "word11/17 merges"),
        field("live_gain_hi", 5, (("A", 9, 5),), "PRE_W15", "PC2A",
              "unpacked D2F-B live gain", "word13 last-gain merge"),
        field("current_sign", 1, (("A", 14, 1),), "PRE_W15", "W27",
              "sign of W4 current source", "signed current arm"),
        field("snd_wt", 1, (("A", 15, 1),), "PRE_W15", "W84",
              "unpacked D2F-B live context", "path decode"),
        field("live_is_wave6", 1, (("A", 16, 1),), "PRE_W15", "W27",
              "unpacked D2F-B live wave", "live reciprocal bypass"),
        field("audible", 1, (("A", 17, 1),), "PRE_W15", "DONE",
              "W4 play/hidden capture", "leaf48/49 gate"),
        field("old_source", 18, (("B", 0, 18),), "PRE_W15", "W27",
              "unpacked D2F-B W3 pair", "old-gain launch"),
        field("live_gain_limb", 17, (("N", 0, 17),), "W15", "W27",
              "CAP_W15 multiplier result", "current-arm reciprocal"),
        field("final_phase2", 17, (("O", 0, 17),), "PRE_W15", "PC2D",
              "W6 live-DQ merge", "word13/12 merges"),
        field("final_old_phase", 16, (("Q", 0, 16),),
              "PRE_W15", "PC28", "W5 old phase update", "word16 write"),
        field("final_old_q", 17,
              (("T", 0, 6), ("C", 0, 7), ("I", 0, 4)),
              "PRE_W15", "PC29", "W5 old-q update/copy",
              "word11/17 merges"),
        field("old_wave", 3, (("D", 0, 3),), "PRE_W15", "W27",
              "unpacked D2F-B selected tuple", "old-gain launch"),
        field("selected_old_gain_hi", 5, (("Q", 0, 5),),
              "PC2A", "W26", "typed q13", "typed q19 merge"),
        field("selected_old_gain", 13, (("Q", 0, 13),),
              "W26", "W27", "q13 high plus typed q19 low",
              "old-gain launch"),
        field("current_arm", 17, (("N", 0, 17),), "W27", "W84",
              "CAP_W27 reciprocal", "blend/dampen"),
        field("old_sign", 1, (("D", 0, 1),), "W27", "W51",
              "sign of retained old source", "signed old arm"),
        field("old_is_wave6", 1, (("D", 1, 1),), "W27", "W51",
              "compressed selected old wave", "old reciprocal bypass"),
        field("blend_count", 7, (("T", 0, 6), ("C", 0, 1)),
              "PC2E", "W75", "typed final q17", "blend launch/bypass"),
        field("old_gain_limb", 17, (("O", 0, 17),), "W40", "W51",
              "CAP_W40 multiplier", "old-arm reciprocal"),
        field("reverb_flags", 4, (("C", 1, 4),), "W40", "W84",
              "typed q20", "current/old ring combine and W84 base"),
        field("old_arm", 17, (("O", 0, 17),), "W51", "W84",
              "CAP_W51 reciprocal", "blend/dampen"),
        field("filter_hi", 16, (("B", 0, 16),), "PC38", "W84",
              "typed q14 at PC38", "filter/word14 merge"),
        field("damp", 2, (("A", 0, 2),), "W75", "W84",
              "active-bank q26/q30 at CAP_W75", "CAP_W84 dampen"),
        field("filter_lo", 16, (("Q", 0, 16),), "PC39", "W84",
              "clear-qualified typed q15", "filter/word15 merge"),
        field("sample_f", 17, (("A", 0, 17),), "W84", "DONE",
              "CAP_W84 blend/dampen result", "ring and word48/49 writes"),
        field("final_filter_hi", 16, (("B", 0, 16),), "W84", "PC3C",
              "lp_final sign merged with typed q14 payload",
              "final word14 write"),
        field("final_filter_lo", 16, (("Q", 0, 16),), "W84", "PC3D",
              "lp_final low word", "final word15 write"),
    )

    wavetable = (
        field("old_adjacent", 8, (("A", 0, 8),),
              "PRE_W15", "W15", "CAP_W4 ARAM result",
              "CAP_W15 old interpolation launch"),
        field("pre_live_gain", 13,
              (("A", 8, 7), ("A", 17, 1), ("C", 0, 5)),
              "PRE_W15", "W15", "unpacked D2F-B amplitude gain",
              "CAP_W15 B relocation"),
        field("primary_interp", 15, (("A", 0, 15),), "W15", "W27",
              "CAP_W15 multiplier", "wavetable current sum"),
        field("snd_wt", 1, (("A", 15, 1),), "PRE_W15", "W84",
              "unpacked D2F-B live context", "path decode"),
        field("live_is_wave6", 1, (("A", 16, 1),), "PRE_W15", "W51",
              "unpacked D2F-B live wave", "live reciprocal bypass"),
        field("old_fraction_base", 18, (("B", 0, 18),),
              "PRE_W15", "W15", "unpacked D2F-B W3 state",
              "CAP_W15 old interpolation launch"),
        field("old_base", 8, (("C", 0, 7), ("T", 4, 1)),
              "W15", "W26", "CAP_W15 retained signed base byte",
              "CAP_W26 interpolated sum"),
        field("old_delta_sign", 1, (("T", 5, 1),),
              "W15", "W26", "CAP_W15 old delta sign",
              "CAP_W26 signed multiplier result"),
        field("live_gain", 13, (("B", 0, 13),), "W15", "W27",
              "CAP_W15 relocation from pre_live_gain", "live-gain launch"),
        field("pre_final_nz_phase", 4,
              (("C", 5, 2), ("I", 0, 2)), "PRE_W15", "W15",
              "unpacked D2F-B W0 state", "CAP_W15 B relocation"),
        field("final_nz_phase", 4, (("B", 13, 4),),
              "W15", "PC2A", "CAP_W15 relocation",
              "word13 merge"),
        field("pre_refresh", 1, (("I", 2, 1),), "PRE_W15", "W15",
              "unpacked D2F-B refresh", "CAP_W15 B relocation"),
        field("refresh", 1, (("B", 17, 1),), "W15", "PC27",
              "CAP_W15 relocation", "word11 merge"),
        field("final_phase2", 17, (("N", 0, 17),),
              "PRE_W15", "PC2D", "W6 live-DQ merge", "word13/12 merges"),
        field("final_old_q", 17, (("O", 0, 17),),
              "PRE_W15", "PC29",
              "original phase2 on restart; typed q11/q17 otherwise",
              "word11/17 merges"),
        field("final_old_phase", 16, (("Q", 0, 16),),
              "PRE_W15", "PC28", "W5 old-noise/phase result",
              "word16 write"),
        field("restart", 1, (("T", 0, 1),), "PRE_W15", "PC2A",
              "unpacked D2F-B restart", "blend/gain merges"),
        field("clear", 1, (("T", 1, 1),), "PRE_W15", "PC39",
              "unpacked D2F-B clear", "word13/15 merges"),
        field("last_gain_we", 1, (("T", 2, 1),), "PRE_W15", "PC2A",
              "play/music predicate", "word13 merge"),
        field("old_q_replace", 1, (("T", 3, 1),), "PRE_W15", "PC29",
              "restart", "word11/17 merges"),
        field("selected_old_gain_hi", 5, (("Q", 0, 5),),
              "PC2A", "W26", "typed q13", "typed q19 merge"),
        field("old_interp", 15, (("O", 0, 15),), "W26", "W27",
              "CAP_W26 multiplier", "wavetable current sum"),
        field("old_gain_nonzero", 1, (("Q", 0, 1),), "W26", "W84",
              "q13 high plus typed q19 low", "old-arm enable through base"),
        field("current_sign", 1, (("T", 0, 1),), "W27", "W51",
              "sign of wavetable current sum", "signed current arm"),
        field("audible", 1, (("A", 17, 1),), "W27", "DONE",
              "W27 play/hidden capture", "leaf48/49 gate"),
        field("blend_count", 7, (("C", 0, 7),), "PC2E", "W75",
              "typed final q17", "blend launch/bypass"),
        field("reverb_flags", 4, (("I", 0, 4),), "W40", "W84",
              "typed q20", "current/old ring combine and W84 base"),
        field("live_gain_limb", 17, (("N", 0, 17),), "W40", "W51",
              "CAP_W40 multiplier", "current-arm reciprocal"),
        field("current_arm", 17, (("N", 0, 17),), "W51", "W84",
              "CAP_W51 reciprocal", "blend/dampen"),
        field("filter_hi", 16, (("B", 0, 16),), "PC38", "W84",
              "typed q14 at PC38", "filter/word14 merge"),
        field("damp", 2, (("A", 0, 2),), "W75", "W84",
              "active-bank q26/q30 at CAP_W75", "CAP_W84 dampen"),
        field("filter_lo", 16, (("O", 0, 16),), "PC39", "W84",
              "clear-qualified typed q15", "filter/word15 merge"),
        field("sample_f", 17, (("A", 0, 17),), "W84", "DONE",
              "CAP_W84 blend/dampen result", "ring and word48/49 writes"),
        field("final_filter_hi", 16, (("B", 0, 16),), "W84", "PC3C",
              "lp_final sign merged with typed q14 payload",
              "final word14 write"),
        field("final_filter_lo", 16, (("O", 0, 16),), "W84", "PC3D",
              "lp_final low word", "final word15 write"),
    )

    def validate_fields(path: str, fields: tuple[LiveField, ...],
                        expected_pre_w15: int,
                        expected_w15: int) -> tuple[int, int]:
        for item in fields:
            assert item.born in event and item.dead in event
            assert event[item.born] < event[item.dead], item
            assert sum(width for _, _, width in item.pieces) == item.width
            assert item.source and item.consumer
            for container, lsb, width in item.pieces:
                assert container in capacities
                assert 0 <= lsb and lsb + width <= capacities[container], item
        peak = 0
        w15 = 0
        for snapshot in range(len(events)):
            owned: set[tuple[str, int]] = set()
            used = 0
            for item in fields:
                if event[item.born] <= snapshot < event[item.dead]:
                    used += item.width
                    for container, lsb, width in item.pieces:
                        for bit in range(lsb, lsb + width):
                            key = (container, bit)
                            assert key not in owned, (path, events[snapshot],
                                                      key, item.name)
                            owned.add(key)
            assert used == len(owned), (path, events[snapshot], used,
                                        len(owned))
            assert used <= 108, (path, events[snapshot], used)
            peak = max(peak, used)
            if snapshot == event["PRE_W15"]:
                assert used == expected_pre_w15, \
                    (path, events[snapshot], used, expected_pre_w15)
            if snapshot == event["W15"]:
                w15 = used
            if snapshot == event["W84"]:
                assert used == 50, (path, events[snapshot], used)
            if snapshot == event["PC3C"]:
                assert used == 34, (path, events[snapshot], used)
            if snapshot in (event["PC3D"], event["PC4C"], event["PC4D"]):
                assert used == 18, (path, events[snapshot], used)
            if snapshot == event["DONE"]:
                assert used == 0, (path, events[snapshot], used)
        assert w15 == expected_w15, (path, w15, expected_w15)
        return w15, peak

    built_w15, built_peak = validate_fields("built-in", built, 89, 106)
    wave_w15, wave_peak = validate_fields("wavetable", wavetable, 100, 98)
    assert {item.name for item in built if item.born == "W15"} \
        == {"live_gain_limb"}
    assert {item.name for item in wavetable if item.born == "W15"} \
        == {"primary_interp", "old_base", "old_delta_sign", "live_gain",
            "final_nz_phase", "refresh"}
    assert next(item for item in wavetable
                if item.name == "primary_interp").source.startswith("CAP_W15")
    assert all("relocation" in item.source
               for item in wavetable
               if item.name in {"live_gain", "final_nz_phase", "refresh"})

    # The seven literal fold nodes preserve their q stream, fixed destinations
    # and eight physical microstep words.  The final signed-18 work value stays
    # in A through FOLD_FINISH, because that action receives q49 rather than a
    # typed q48 and must publish dry16 from retained state.
    fold_entry = decoded(0).target
    assert fold_entry == 0x50
    fold_prime = action_by_name["FOLD_PRIME"]
    fold_a_lo = action_by_name["FOLD_A_LO"]
    fold_a_hi = action_by_name["FOLD_A_HI"]
    fold_b_lo = action_by_name["FOLD_B_LO"]
    fold_start = action_by_name["FOLD_START"]
    fold_run = action_by_name["FOLD_RUN"]
    fold_write_lo = action_by_name["FOLD_WRITE_LO"]
    fold_write_hi = action_by_name["FOLD_WRITE_HI"]
    for node, (a_slot, b_slot, dst_slot) in enumerate(FOLD_NODES):
        base = fold_entry + node * 20
        assert decoded(base) == Instruction(Op.SLOT, slot_value=a_slot)
        assert decoded(base + 1) == Instruction(
            Op.READ, action=fold_prime, word=48)
        assert decoded(base + 2) == Instruction(
            Op.READ, action=fold_a_lo, word=49)
        assert decoded(base + 3) == Instruction(
            Op.EXEC, action=fold_a_hi)
        assert decoded(base + 4) == Instruction(Op.SLOT, slot_value=b_slot)
        assert decoded(base + 5) == Instruction(
            Op.READ, action=fold_prime, word=48)
        assert decoded(base + 6) == Instruction(
            Op.READ, action=fold_b_lo, word=49)
        assert decoded(base + 7) == Instruction(
            Op.EXEC, action=fold_start)
        assert decoded(base + 8) == Instruction(
            Op.EXEC, action=fold_run)
        for step in range(8):
            assert decoded(base + 9 + step) == Instruction(
                Op.EXEC, action=COMMON_ACTION["HOLD"], word=step + 1)
        assert decoded(base + 17) == Instruction(
            Op.SLOT, slot_value=dst_slot)
        assert decoded(base + 18) == Instruction(
            Op.WRITE, action=fold_write_lo, word=48)
        assert decoded(base + 19) == Instruction(
            Op.WRITE, action=fold_write_hi, word=49)
        assert q_word(base + 18) == 8 and q_word(base + 19) == 48
    finish_pc = fold_entry + len(FOLD_NODES) * 20
    assert decoded(finish_pc) == Instruction(
        Op.EXEC, action=action_by_name["FOLD_FINISH"])
    assert q_word(finish_pc) == 49
    assert decoded(finish_pc + 1).op == Op.DONE
    fold_events = ("INPUTS", "STEP1", "STEP2", "STEP3", "STEP4",
                   "STEP5", "STEP6", "STEP7", "STEP8", "WRITE_LO",
                   "WRITE_HI", "FINISH", "DONE")
    fold_event = {name: index for index, name in enumerate(fold_events)}
    fold_fields = (
        ("fold_a", 18, (("A", 0, 18),), "INPUTS", "STEP1"),
        ("fold_b", 18, (("B", 0, 18),), "INPUTS", "STEP1"),
        ("fold_sum", 18, (("A", 0, 18),), "STEP1", "STEP2"),
        ("threshold_class", 2, (("B", 0, 2),), "STEP2", "STEP7"),
        ("absolute_excess", 16, (("A", 0, 16),), "STEP2", "STEP4"),
        ("split_high_low", 16, (("A", 0, 16),), "STEP4", "STEP5"),
        ("partial_51high", 13, (("A", 0, 13),), "STEP5", "STEP6"),
        ("fdiv5_address", 9, (("B", 2, 9),), "STEP5", "STEP6"),
        ("fdiv5_q", 7, (("N", 0, 7),), "STEP5", "STEP6"),
        ("fold_quotient", 16, (("A", 0, 16),), "STEP6", "STEP7"),
        ("fold_result", 18, (("A", 0, 18),), "STEP7", "DONE"),
    )
    fold_peak = 0
    for snapshot, snapshot_name in enumerate(fold_events):
        owned: set[tuple[str, int]] = set()
        for name, width, pieces, born, dead in fold_fields:
            assert sum(part for _, _, part in pieces) == width
            if fold_event[born] <= snapshot < fold_event[dead]:
                for container, lsb, part in pieces:
                    assert lsb + part <= capacities[container]
                    for bit in range(lsb, lsb + part):
                        key = (container, bit)
                        assert key not in owned, (snapshot_name, key, name)
                        owned.add(key)
        fold_peak = max(fold_peak, len(owned))
        if snapshot_name in ("WRITE_LO", "WRITE_HI", "FINISH"):
            assert all(("A", bit) in owned for bit in range(18))
    assert fold_peak == 36

    return (f"H-D2F-C-A manifest: 18 per-slot writes with exact PC/action/q/"
            f"destination provenance; built W15 {built_w15}/108, peak "
            f"{built_peak}/108; wavetable pre/W15 {100}/{wave_w15}/108, "
            f"peak {wave_peak}/108; W84 split 50/108 -> 34/108 -> 18/108; "
            "active q26/q30 override exposed; seven 20-PC fold "
            f"nodes peak at {fold_peak}/70 and retain A18 through q49 "
            "FOLD_FINISH/dry publication")


def validate_sample_b1_atomic_root_manifest(candidate: list[int],
                                            actions: Actions) -> str:
    """Inventory every internal SampleTrace replacement root before typing."""
    source_text = Path(__file__).read_text()
    machine = source_text[source_text.index("\nclass SampleImageMachine:"):
                          source_text.index("\ndef make_sample_case(")]
    issue_keys = re.findall(r'self\.issue\(\s*"([^"]+)"', machine)
    expected_issue_keys = (
        "dq_live", "noise_old", "noise_old_hold", "dq_live_hold",
        "dq_old", "noise_live", "wave_0", "aram_0", "wave_1",
        "aram_1", "wave_2", "aram_2", "wave_3", "aram_3",
        "mul_live", "mul_primary_interp", "mul_old_interp",
        "mul_live_recip", "mul_live", "mul_old", "mul_arm_recip",
        "mul_blend", "ring_current", "ring_old",
    )
    assert len(issue_keys) == len(expected_issue_keys) == 24
    assert sorted(issue_keys) == sorted(expected_issue_keys)
    for spelling in (
            "expected = (self.trace.current_arm",
            "record = decode_sample_record(self.trace.final_words)",
            "self.leaf = self.trace.leaf",
            "value = (self.trace.final_words[index]",
            "self.lfsr = self.trace.next_lfsr",
            "self.lfsr2 = self.trace.next_lfsr2"):
        assert spelling in machine

    events = (
        "LOAD", "NZ_OLD", "NZ_LIVE", "W0", "W1", "W2", "W3",
        "W4", "W5", "W6", "W15", "W26", "W27", "PC2E", "W40", "W51",
        "RING1", "RING2", "RING3", "W75", "W84", "STORES", "SLOT",
        "FOLD", "DONE",
    )
    event = {name: index for index, name in enumerate(events)}

    @dataclass(frozen=True)
    class Root:
        name: str
        trace_key: str
        group: str
        width: int
        producer: str
        born: str
        dead: str
        owner: str
        consumer: str

    def root(name: str, trace_key: str, group: str, width: int,
             producer: str, born: str, dead: str, owner: str,
             consumer: str) -> Root:
        return Root(name, trace_key, group, width, producer, born, dead,
                    owner, consumer)

    roots = (
        root("dq_live_issue", "dq_live", "dq_live", 17,
             "dqsvc(eff_inc,wavetable,wave,detune)", "LOAD", "NZ_LIVE",
             "service:dq", "NZ_LIVE fanout"),
        root("noise_old_issue", "noise_old", "noise_old_step", 17,
             "mul(nz_j(selected_old_inc),noise_draw(lfsr2))",
             "NZ_OLD", "NZ_LIVE", "service:mul", "NZ_LIVE capture"),
        root("noise_old_hold", "noise_old_hold", "noise_old_step", 17,
             "retained noise_old_step", "NZ_LIVE", "W1", "frame:O17",
             "old-noise pre-sum"),
        root("dq_live_hold", "dq_live_hold", "dq_live", 17,
             "retained dq_live", "NZ_LIVE", "W6", "frame:N17",
             "final_phase2"),
        root("dq_old_issue", "dq_old", "dq_old", 17,
             "dqsvc(selected_old_inc,wavetable,old_wave,old_mode)",
             "NZ_LIVE", "W5", "service:dq", "final_old_q"),
        root("noise_live_issue", "noise_live", "noise_live_step", 17,
             "mul(nz_j(eff_inc),noise_draw(lfsr))", "NZ_LIVE", "W0",
             "service:mul", "noise lowpass update"),
        root("wave_0_issue", "wave_0", "built_wave_0", 18,
             "wave(current_phase,live_context,primary)", "W0", "W2",
             "service:wave", "current pair"),
        root("aram_0_issue", "aram_0", "aram_base_0", 8,
             "aram[rec_base(snd_id)+current_index]", "W0", "W1",
             "service:aram_seq_q", "primary_base A17:10"),
        root("wave_1_issue", "wave_1", "built_wave_1", 18,
             "wave(phase2,live_context,secondary)", "W1", "W3",
             "service:wave", "current pair"),
        root("aram_1_issue", "aram_1", "aram_adjacent_1", 8,
             "aram[rec_base(snd_id)+current_index+1]", "W1", "W2",
             "service:aram_seq_q", "primary delta"),
        root("wave_2_issue", "wave_2", "built_wave_2", 18,
             "wave(old_phase,old_context,primary)", "W2", "W4",
             "service:wave", "old pair"),
        root("aram_2_issue", "aram_2", "aram_base_2", 8,
             "aram[rec_base(snd_id)+old_index]", "W2", "W3",
             "service:aram_seq_q", "secondary_base B17:10"),
        root("wave_3_issue", "wave_3", "built_wave_3", 18,
             "wave(old_q,old_context,secondary)", "W3", "W5",
             "service:wave", "old pair"),
        root("aram_3_issue", "aram_3", "aram_adjacent_3", 8,
             "aram[rec_base(snd_id)+old_index+1]", "W3", "W4",
             "service:aram_seq_q", "secondary_adjacent A7:0"),
        root("mul_live_w4", "mul_live", "built_live_gain_limb", 17,
             "mul(abs(current_source),live_gain)", "W4", "W15",
             "service:mul", "frame:N17 or current reciprocal"),
        root("mul_primary_interp", "mul_primary_interp",
             "primary_interp", 19,
             "mul(abs(primary_delta),primary_fraction); base/sign in frame",
             "W4", "W15", "service:mul+frame:A15", "wavetable sum"),
        root("mul_old_interp", "mul_old_interp", "old_interp", 19,
             "mul(abs(old_delta),old_fraction); base/sign in frame", "W15",
             "W26", "service:mul+frame:O15", "wavetable sum"),
        root("mul_live_recip", "mul_live_recip", "current_arm", 17,
             "reciprocal_or_wave6(live_gain_limb,current_sign)",
             "W15", "W27", "service:mul+frame:N17", "blend current"),
        root("mul_live_w27", "mul_live", "wave_live_gain_limb", 17,
             "mul(abs(primary_interp+old_interp/2),live_gain)",
             "W27", "W40", "service:mul+frame:N17", "current reciprocal"),
        root("mul_old_w27", "mul_old", "old_gain_limb", 17,
             "mul(abs(old_source),selected_old_gain)", "W27", "W40",
             "service:mul+frame:O17", "old reciprocal"),
        root("mul_arm_recip", "mul_arm_recip", "arm_result", 17,
             "reciprocal_or_wave6(selected_limb,selected_sign)",
             "W40", "W51", "service:mul+frame:N17/O17", "blend arms"),
        root("mul_blend", "mul_blend", "blend_product", 23,
             "mul(abs(current_arm-old_arm),blend_count)",
             "W75", "W84", "service:mul", "signed blend reconstruction"),
        root("ring_current", "ring_current", "ring_current", 16,
             "ring[current_slot,current_tap]", "RING1", "RING2",
             "service:ring", "current comb"),
        root("ring_old", "ring_old", "ring_old", 16,
             "ring[current_slot,old_tap]", "RING2", "RING3",
             "service:ring", "old comb"),
        root("expected_arm", "direct:expected_arm", "arm_result", 17,
             "retained current_arm or old_arm", "W51", "W51",
             "frame:N17/O17", "remove circular assertion"),
        root("blend_control", "direct:blend_control", "blend_count", 7,
             "typed q17 blend_count", "PC2E", "W75", "frame:C7",
             "blend launch or bypass"),
        root("leaf_commit", "direct:leaf", "filtered_leaf", 17,
             "audible ? dampen(blend(arms,rings,count),q14,q15,q26/30) : 0",
             "W84", "STORES",
             "frame:A17", "state words 48/49"),
        root("record_commit", "direct:final_words", "record_commits", 16,
             "typed fixed-edge phase/noise/gain/filter merge", "W0", "STORES",
             "state:words10..23", "18 fixed writes"),
        root("lfsr_next", "direct:next_lfsr", "lfsr_next", 15,
             "{lfsr[13:0],lfsr[14]^lfsr[13]}", "W0", "SLOT",
             "persistent:lfsr", "next slot"),
        root("lfsr2_next", "direct:next_lfsr2", "lfsr2_next", 15,
             "{lfsr2[13:0],lfsr2[14]^lfsr2[10]}", "W0", "SLOT",
             "persistent:lfsr2", "next slot"),
    )
    assert len(roots) == 30
    assert len({item.name for item in roots}) == 30
    assert [item.trace_key for item in roots[:24]] == list(expected_issue_keys)
    assert {item.trace_key for item in roots[24:]} == {
        "direct:expected_arm", "direct:blend_control", "direct:leaf",
        "direct:final_words", "direct:next_lfsr", "direct:next_lfsr2",
    }
    owner_prefixes = ("service:", "frame:", "state:", "persistent:")
    for item in roots:
        assert 0 < item.width <= (34 if item.owner.startswith("service:")
                                  else 19)
        assert item.born in event and item.dead in event
        assert event[item.born] <= event[item.dead], item
        assert item.owner.startswith(owner_prefixes), item
        assert item.producer and item.consumer
        assert "trace" not in item.producer.lower()
        assert "oracle" not in item.producer.lower()

    groups: dict[str, list[Root]] = {}
    for item in roots:
        groups.setdefault(item.group, []).append(item)
    assert len(groups) == 27
    assert {item.name for item in groups["dq_live"]} \
        == {"dq_live_issue", "dq_live_hold"}
    assert {item.name for item in groups["noise_old_step"]} \
        == {"noise_old_issue", "noise_old_hold"}
    assert {item.name for item in groups["arm_result"]} \
        == {"mul_arm_recip", "expected_arm"}
    assert all(len(items) == 1 for name, items in groups.items()
               if name not in {"dq_live", "noise_old_step", "arm_result"})

    # Bind the direct record root to the already-proved fixed-write image and
    # require the fold/public skeleton to remain literal production topology.
    action_names = {action.name
                    for action in actions.by_owner["sample"].values()}
    assert {f"STORE_{index}_{10 + index}" for index in range(14)} \
        <= action_names
    assert {"STORE_14_15", "STORE_15_14", "STORE_LEAF_LO",
            "STORE_LEAF_HI", "FOLD_FINISH"} <= action_names
    assert sum(word != 0 for word in candidate) == 222
    return ("H-D2F-C-B3-B2-A2-A1-B1-A atomic-root inventory: 30 trace/direct "
            f"replacement roots grouped into {len(groups)} exact values; "
            "24 issue sites and six direct uses bound to production edges, "
            "coarse service/frame/state owners and final consumers; no "
            "Trace/oracle producer; literal slices, collision/capacity and "
            "executor/value equivalence remain unproved")


def reachable_to_idle(nodes: list[Node]) -> None:
    graph = {node.name: set(node.successors) for node in nodes}
    assert "S_IDLE" in graph
    reverse: dict[str, set[str]] = {name: set() for name in graph}
    for source, targets in graph.items():
        for target in targets:
            assert target in graph, f"{source}: missing target {target}"
            reverse[target].add(source)
    seen, work = {"S_IDLE"}, ["S_IDLE"]
    while work:
        target = work.pop()
        for source in reverse[target]:
            if source not in seen:
                seen.add(source)
                work.append(source)
    missing = set(graph) - seen
    assert not missing, f"sequencer nodes cannot reach S_IDLE: {sorted(missing)}"


def tick_movement_inventory(nodes: list[Node]) -> str:
    """Pin the generated action/address contract consumed by psg_execmove."""
    by_name = {node.name: node for node in nodes}
    load_words = [3, 4, 5, 8, 9, 26, 32, 26]
    store_words = [3, 4, 5, 9, 32]
    for i, word in enumerate(load_words):
        node = by_name[f"V_LD{i}"]
        assert (node.op, node.word, node.action) == (Op.READ, word, i)
    for i, word in enumerate(store_words):
        node = by_name[f"V_ST{i}"]
        assert (node.op, node.word, node.action) == (Op.WRITE, word, 8 + i)

    # V_LD6 has already consumed active par+2.  K_ADV repurposes the redundant
    # V_LD7 repeated read edge to initialize scratch 35.  P_W3 and PC3 are the
    # two immediate V_ST0 predecessors and prime scratch word 48 after their
    # current state_q value has been consumed; K_ROT is not adjacent.
    assert by_name["K_ADV"].action == 0x40
    assert by_name["P_W3"].action == 0x56
    assert by_name["PC3"].action == 0x5A
    assert by_name["P_W3"].successors == ["V_ST0"]
    assert by_name["PC3"].successors == ["V_ST0"]
    assert by_name["K_ROT"].successors == ["PC0"]
    return ("loads 3,4,5,8,9,(26|30),32 -> scratch 48..54; "
            "V_LD0/K_ADV initialize scratch 34/35 to 1/32; "
            "stores scratch 48,49,50,52,54 -> 3,4,5,9,32; "
            "0 extra hold clocks")


def validate_move_rtl_contract() -> str:
    """Bind generated action numbers to the fixed RTL decoder spelling."""
    text = MOVE.read_text()
    aliases = {"INIT": "K_ADV"}
    for name, code in ADV_ACTION.items():
        rtl_name = aliases.get(name, name)
        match = re.search(rf"\b{rtl_name}\s*=\s*7'h([0-9a-fA-F]+)", text)
        assert match and int(match.group(1), 16) == code, \
            f"{name}: RTL action code is missing or stale"
    for name, code in {"P_W0": 0x53, "P_W1": 0x54, "P_W2": 0x55,
                       "P_W3": 0x56, "PC0": 0x57, "PC1": 0x58,
                       "PC2": 0x59, "PC3": 0x5A,
                       "K_ROT": 0x5E}.items():
        match = re.search(rf"\b{name}\s*=\s*7'h([0-9a-fA-F]+)", text)
        assert match and int(match.group(1), 16) == code

    # Addresses are literal action metadata.  These spellings would recreate
    # the variable address arithmetic G-F explicitly forbids.
    for forbidden in ("action - P_W0", "action - PC0", "par_active +",
                      "par_inactive +", "par_copy +"):
        assert forbidden not in text, f"variable address arithmetic: {forbidden}"

    for bank in (0, 1):
        active = (28, 29, 30, 31) if bank else (24, 25, 26, 27)
        inactive = (24, 25, 26, 27) if bank else (28, 29, 30, 31)
        assert (30 if bank else 26) == active[2]
        for join in (0, 1):
            copy = inactive if join else active
            assert len(set(copy)) == 4 and len(set(inactive)) == 4
    return ("27 action codes pinned; literal V_LD/P/PC addresses cover both "
            "parameter banks and both join-stage sources")


def state_address_inventory(seq: str) -> list[int]:
    # This spans the literal tick load/store helpers and eng read/write cases.
    start = seq.index("function automatic logic [5:0] tick_load_word")
    end = seq.index("// Multiply request bundle", start)
    values = {int(n) for n in re.findall(r"6'd(\d+)", seq[start:end])}
    values.update(range(24, 32))
    values.add(32)
    assert values and min(values) >= 0 and max(values) < 64
    return sorted(values)


def output_commit_inventory(seq: str, walk: str) -> list[str]:
    commits = ["dry_valid", "spar_bank", "bank_ready", "playing",
               "trig_req", "sfx_id", "aud_row", "mus_playing",
               "mus_pat", "mus_mask", "fade_len", "clr_tog"]
    joined = seq + walk
    for name in commits:
        assert re.search(rf"\b{re.escape(name)}\b[^\n]*<=", joined), \
            f"legacy output commit {name} not found"
    return commits


def validate_sample_action_inventory(actions: Actions,
                                     program: list[int]) -> str:
    """Prove every owner-zero action belongs to one fixed lowering family."""
    names = {action.name for action in actions.by_owner["sample"].values()}
    loads = {name for name in names
             if name == "READ_PRIME" or name.startswith("LOAD_")}
    services = {name for name in names
                if name.startswith("NZ_") or name.startswith("CAP_")}
    stores = {name for name in names if name.startswith("STORE_")}
    folds = {name for name in names if name.startswith("FOLD_")}
    assert not names - loads - services - stores - folds
    assert (len(loads), len(services), len(stores), len(folds), len(names)) \
        == (18, 16, 18, 9, 61)

    # Name every service edge rather than treating CAP as a generic macro.
    dependencies = {
        "NZ_OLD_LOAD_PAR_3": ("state", "mul", "dq"),
        "NZ_LIVE": ("mul", "dq"),
        "CAP_W0": ("aram", "phase", "noise"),
        "CAP_W1": ("aram", "wave", "dq"),
        "CAP_W2": ("aram", "wave"),
        "CAP_W3": ("aram", "wave"),
        "CAP_W4": ("aram", "wave", "mul"),
        "CAP_W5": ("wave", "dq"),
        "CAP_W6": ("dq",),
        "CAP_W15": ("wave", "mul"),
        "CAP_W26": ("mul",),
        "CAP_W27": ("mul",),
        "CAP_W40": ("mul",),
        "CAP_W51": ("mul",),
        "CAP_W75": ("mul", "ring"),
        "CAP_W84": ("mul", "ring", "dampen"),
    }
    assert set(dependencies) == services
    assert all(deps for deps in dependencies.values())

    # Bind the model to the accepted full-mode schedule rather than copying a
    # prose list.  The CAP indices and the two noise launches are executable
    # source facts in the current walker/control generator.
    ctrl = runpy.run_path(str(CTRL_GEN))
    expected_caps = {offset: n
                     for n, (_, offset) in enumerate(SAMPLE_CAP_SCHEDULE)}
    assert ctrl["PWORK"] == 29 and ctrl["CAPS"] == expected_caps
    walk = WALK.read_text()
    assert re.search(r"localparam int PNZ_OLD\s*=\s*19;", walk)
    assert re.search(r"localparam int PNZ_LIVE\s*=\s*24;", walk)

    static_holds = sum(
        Instruction.decode(word).op == Op.EXEC
        and Instruction.decode(word).action == COMMON_ACTION["HOLD"]
        for word in program)
    cap_holds = SAMPLE_CAP_SCHEDULE[-1][1] - (len(SAMPLE_CAP_SCHEDULE) - 1)
    assert static_holds == 4 + 4 + cap_holds + len(FOLD_NODES) * 8
    return ("61 owner-zero actions: 18 addressed loads, 16 named service/CAP "
            "edges, 18 addressed stores and 9 unrolled-fold actions; "
            f"{static_holds} fixed-latency HOLD words; exact accepted "
            "NZ/W0..W84 cadence")


def validate_fold_word_contract() -> str:
    """Prove the two-word signed-18 representation and literal tree shape."""
    for value in range(-(1 << 17), 1 << 17):
        lo = value & 0xffff
        hi = (value >> 16) & 0xffff
        raw = ((hi & 3) << 16) | lo
        decoded = raw - (1 << 18) if raw & (1 << 17) else raw
        assert decoded == value

    # Treat the fold as an arbitrary non-associative binary operation.  If
    # the symbolic expression is exact, the address schedule preserves the
    # required soft_add ordering independently of its arithmetic internals.
    values: list[object] = list(range(8))
    for a_slot, b_slot, dst_slot in FOLD_NODES:
        values[dst_slot] = (values[a_slot], values[b_slot])
    expected = (((0, 1), (2, 3)), ((4, 5), (6, 7)))
    assert values[0] == expected
    return ("all 262,144 signed-18 values round-trip through words 48/49; "
            "literal nodes preserve ((0,1),(2,3)),((4,5),(6,7)) ordering")


def validate_fold_arithmetic_contract() -> str:
    """Prove the base-256 /5 lowering over every reachable fold sum."""
    threshold = 24_576
    pair_lo = -(1 << 16)
    pair_hi = (1 << 16) - 2
    excess_max = max(pair_hi - threshold, -threshold - pair_lo)
    assert excess_max == 40_960

    def split5(excess: int) -> tuple[int, int, int]:
        high, low = divmod(excess, 256)
        address = high + low
        return 51 * high + address // 5, address, address // 5

    for excess in range(excess_max + 1):
        quotient, address, table_q = split5(excess)
        assert quotient == excess // 5
        assert 0 <= address <= 414
        assert 0 <= table_q < (1 << 7)

    def shipped(sum_value: int) -> int:
        if sum_value >= threshold:
            excess = sum_value - threshold
            return threshold + ((excess * 52_429) >> 18)
        if sum_value <= -threshold:
            excess = -threshold - sum_value
            return -threshold - ((excess * 52_429) >> 18)
        return sum_value

    def lowered(sum_value: int) -> int:
        if sum_value >= threshold:
            return threshold + split5(sum_value - threshold)[0]
        if sum_value <= -threshold:
            return -threshold - split5(-threshold - sum_value)[0]
        return sum_value

    outputs = []
    for sum_value in range(pair_lo, pair_hi + 1):
        got = lowered(sum_value)
        assert got == shipped(sum_value), sum_value
        assert -(1 << 15) <= got < (1 << 15)
        outputs.append(got)
    assert len(outputs) == 131_071
    assert min(outputs) == -(1 << 15) and max(outputs) == (1 << 15) - 1
    return ("131,071 signed-int16 pair sums and 40,961 reachable /5 "
            "excesses; exact reciprocal equivalence and signed16 result")


def validate_sample_pool_contract() -> str:
    """Execute the four-field 70-bit transient lifetime hypothesis.

    This is an information/lifetime proof, not sample arithmetic.  Persistent
    oscillator/restart state and state owned inside wave, DQ, multiplier and
    ring services are deliberately outside this pool.
    """
    capacities = {"A": 18, "B": 18, "N": 17, "O": 17}

    class Pool:
        def __init__(self) -> None:
            self.live: dict[str, tuple[str, int] | None] = {
                field: None for field in capacities
            }
            self.peak_payload = 0

        def put(self, field: str, name: str, bits: int) -> None:
            assert self.live[field] is None, (field, self.live[field], name)
            assert 0 < bits <= capacities[field], (field, name, bits)
            self.live[field] = (name, bits)
            self.peak_payload = max(
                self.peak_payload,
                sum(value[1] for value in self.live.values()
                    if value is not None))

        def take(self, field: str, name: str) -> None:
            assert self.live[field] is not None
            assert self.live[field][0] == name, (field, self.live[field], name)
            self.live[field] = None

        def empty(self) -> None:
            assert all(value is None for value in self.live.values()), self.live

    def begin_visit(pool: Pool) -> None:
        pool.put("N", "dq_live", 14)        # W-5 -> W6
        pool.put("O", "old_noise_step", 17) # W-5 -> W1

    # Built-in oscillator path.
    built = Pool()
    begin_visit(built)
    built.take("O", "old_noise_step")        # W1
    built.put("A", "new_wave", 18)           # W2 -> W4
    built.put("B", "old_wave", 18)           # W3 -> W27
    built.take("A", "new_wave")              # W4 gain launch
    built.put("A", "sign_aud_flags", 3)      # W4 -> W84
    built.take("N", "dq_live")               # W6
    built.put("N", "live_gain_limb", 17)     # W15 -> W27
    built.take("N", "live_gain_limb")        # W27
    built.put("N", "current_arm", 17)        # W27 -> W84
    built.take("B", "old_wave")               # W27 old-gain launch
    built.put("O", "old_gain_limb", 17)      # W40 -> W51
    built.take("O", "old_gain_limb")         # W51
    built.put("O", "old_arm", 17)            # W51 -> W84
    built.take("N", "current_arm")           # W84
    built.take("O", "old_arm")
    built.take("A", "sign_aud_flags")
    built.put("A", "filtered_leaf", 17)      # W84 -> word48/49
    built.take("A", "filtered_leaf")
    built.empty()

    # Wavetable path.  The 18-bit packed point is exactly fraction10 plus a
    # signed byte.  Linear interpolation is a convex combination, so its
    # scaled result is bounded by signed-byte*128: -16384..16256 (signed15).
    interp_min = (-128 * 1024) >> 3
    interp_max = (127 * 1024) >> 3
    assert (interp_min, interp_max) == (-16_384, 16_256)
    assert -(1 << 14) <= interp_min and interp_max < (1 << 14)

    wave = Pool()
    begin_visit(wave)
    wave.take("O", "old_noise_step")          # W1
    wave.put("A", "primary_fraction_base", 18)
    wave.put("O", "primary_adjacent", 8)     # W2 -> W4
    wave.put("B", "old_fraction_base", 18)   # W3 -> W15
    wave.take("O", "primary_adjacent")       # W4 primary launch
    wave.take("A", "primary_fraction_base")
    wave.put("O", "old_adjacent", 8)         # W4 -> W15
    wave.take("N", "dq_live")                # W6
    wave.take("B", "old_fraction_base")      # W15 old launch
    wave.take("O", "old_adjacent")
    wave.put("A", "primary_interpolated", 15)
    wave.put("B", "old_interpolated", 15)   # W26
    wave.take("A", "primary_interpolated")   # W27 gain launch
    wave.take("B", "old_interpolated")
    wave.put("A", "sign_aud_flags", 3)
    wave.put("N", "live_gain_limb", 17)     # W40 -> W51
    wave.take("N", "live_gain_limb")
    wave.put("N", "current_arm", 17)        # W51 -> W84
    wave.take("N", "current_arm")
    wave.take("A", "sign_aud_flags")
    wave.put("A", "filtered_leaf", 17)
    wave.take("A", "filtered_leaf")
    wave.empty()

    # The fold begins only after the eighth leaf write, so it reuses the same
    # fields.  HOLD words 1..8 are its step identity; no state counter exists.
    fold = Pool()
    fold.put("A", "fold_a", 18)
    fold.put("B", "fold_b", 18)
    fold.take("A", "fold_a")
    fold.take("B", "fold_b")
    fold.put("A", "fold_sum_or_result", 18)
    fold.put("N", "fdiv5_q", 7)
    assert tuple(range(1, 9)) == (1, 2, 3, 4, 5, 6, 7, 8)
    fold.take("N", "fdiv5_q")
    fold.take("A", "fold_sum_or_result")
    fold.empty()

    assert sum(capacities.values()) == 70
    assert max(built.peak_payload, wave.peak_payload,
               fold.peak_payload) <= 70
    return ("A18+B18+N17+O17 = 70 shared bits; built-in, wavetable and "
            "counter-free fold lifetimes execute without overlap or spill")


@dataclass(frozen=True)
class PhaseContextCase:
    phase: int
    phase2: int
    old_phase: int
    old_q: int
    eff_inc: int
    old_inc: int
    dq_live: int
    dq_old: int
    noise_seed: int
    old_noise_next: int
    play: bool
    amp_nonzero: bool
    wt: bool
    restart: bool
    old_noise_on: bool
    old_gain_nonzero: bool
    wave: int
    mode: int
    old_wave: int
    old_mode: int


@dataclass(frozen=True)
class PhaseContextResult:
    w0_primary: int
    w1_secondary: int
    w2_old_primary: int
    w3_old_secondary: int
    phase: int
    phase2: int
    old_phase: int
    old_q: int


def phase_view(raw: int, wave: int, mode: int, wt: bool) -> int:
    """Exact low-16 context transform used by psg_execwave."""
    raw &= 0xffff
    if not wt and wave in (0, 7):
        return raw
    if mode == 2:
        return (raw << 1) & 0xffff
    return raw


def legacy_phase_contexts(case: PhaseContextCase) -> PhaseContextResult:
    """Execute W0/W1/W5/W6 in legacy nonblocking-assignment source order."""
    phase = case.phase & 0xffff
    phase2 = case.phase2 & 0x1ffff
    old_phase = case.old_phase & 0xffff
    old_q = case.old_q & 0x1ffff
    run = case.play and case.amp_nonzero

    # W0 issues the old value before any edge assignments commit.
    w0_primary = phase
    if run and not case.wt:
        phase = (phase + (case.eff_inc >> 1)) & 0xffff

    if case.restart:
        old_phase = case.phase & 0xffff
        old_q = case.phase2 & 0x1ffff
        if not case.amp_nonzero:
            phase = 0
            phase2 = 0

    old_nz_active = run and case.old_noise_on
    # noise_filt_step is textually after restart and therefore wins this NBA.
    if old_nz_active:
        old_phase = case.noise_seed & 0xffff

    w1_secondary = phase_view(phase2, case.wave, case.mode, case.wt)

    # W1 consumes the old-noise temporary and advances wavetable primary phase.
    if old_nz_active:
        old_phase = case.old_noise_next & 0xffff
    if run and case.wt:
        phase = (phase + (case.eff_inc >> 1)) & 0xffff

    w2_old_primary = old_phase
    w3_old_secondary = phase_view(old_q, case.old_wave,
                                  case.old_mode, False)

    # W5/W6 updates are later writeback values, after their issue contexts.
    if (not case.wt and case.old_gain_nonzero and not old_nz_active):
        old_phase = (old_phase + (case.old_inc >> 1)) & 0xffff
        old_q = (old_q + case.dq_old) & 0x1ffff
    if run:
        phase2 = (phase2 + case.dq_live) & 0x1ffff

    return PhaseContextResult(w0_primary, w1_secondary, w2_old_primary,
                              w3_old_secondary, phase, phase2,
                              old_phase, old_q)


def compiled_phase_contexts(case: PhaseContextCase) -> PhaseContextResult:
    """Closed addressed-state substitution intended for the H-D adapter."""
    run = case.play and case.amp_nonzero
    w0_primary = case.phase & 0xffff

    # Restart selects the just-audible tuple.  The later noise seed has source
    # priority only while the old-noise arm is actually running.
    old_nz_active = run and case.old_noise_on
    selected_old_phase = ((case.phase if case.restart else case.old_phase)
                          & 0xffff)
    if old_nz_active:
        selected_old_phase = case.noise_seed & 0xffff
    w2_old_primary = ((case.old_noise_next if old_nz_active
                       else selected_old_phase) & 0xffff)
    selected_old_q = ((case.phase2 if case.restart else case.old_q)
                      & 0x1ffff)

    cleared = case.restart and not case.amp_nonzero
    selected_phase2 = 0 if cleared else case.phase2 & 0x1ffff
    w1_secondary = phase_view(selected_phase2, case.wave,
                              case.mode, case.wt)
    w3_old_secondary = phase_view(selected_old_q, case.old_wave,
                                  case.old_mode, False)

    phase = case.phase & 0xffff
    if run:
        phase = (phase + (case.eff_inc >> 1)) & 0xffff
    elif cleared:
        phase = 0
    phase2 = selected_phase2
    if run:
        phase2 = (phase2 + case.dq_live) & 0x1ffff

    old_phase = w2_old_primary
    old_q = selected_old_q
    if (not case.wt and case.old_gain_nonzero and not old_nz_active):
        old_phase = (old_phase + (case.old_inc >> 1)) & 0xffff
        old_q = (old_q + case.dq_old) & 0x1ffff

    return PhaseContextResult(w0_primary, w1_secondary, w2_old_primary,
                              w3_old_secondary, phase, phase2,
                              old_phase, old_q)


def validate_phase_substitution_contract() -> str:
    """Prove control priority and context/writeback association at W0--W6."""
    numeric = [0, 1, 2, 0x7fff, 0x8000, 0xffff, 0x1ffff]
    value = 0x4d35
    while len(numeric) < 64:
        value = (value * 25_173 + 13_849) & 0x1ffff
        numeric.append(value)

    cases = 0
    for flags in range(64):
        play = bool(flags & 1)
        amp_nonzero = bool(flags & 2)
        wt = bool(flags & 4)
        restart = bool(flags & 8)
        old_noise_on = bool(flags & 16)
        old_gain_nonzero = bool(flags & 32)
        if restart and not play:  # blend_restart itself includes play_bits
            continue
        for wave in range(8):
            for mode in range(3):
                for n, raw in enumerate(numeric):
                    case = PhaseContextCase(
                        phase=raw, phase2=(raw * 3 + n) & 0x1ffff,
                        old_phase=(raw * 5 + 7) & 0xffff,
                        old_q=(raw * 9 + 11) & 0x1ffff,
                        eff_inc=(raw * 13 + 17) & 0x3fff,
                        old_inc=(raw * 19 + 23) & 0x3fff,
                        dq_live=(raw * 29 + 31) & 0x3fff,
                        dq_old=(raw * 37 + 41) & 0x3fff,
                        noise_seed=(raw * 43 + 47) & 0xffff,
                        old_noise_next=(raw * 53 + 59) & 0xffff,
                        play=play, amp_nonzero=amp_nonzero, wt=wt,
                        restart=restart, old_noise_on=old_noise_on,
                        old_gain_nonzero=old_gain_nonzero,
                        wave=wave, mode=mode,
                        old_wave=(wave + 3) & 7,
                        old_mode=(mode + 1) % 3)
                    legacy = legacy_phase_contexts(case)
                    compiled = compiled_phase_contexts(case)
                    assert compiled == legacy, (case, legacy, compiled)
                    cases += 1

    # Direct convictions for the three non-commutative substitution edges.
    zero_restart = PhaseContextCase(
        phase=0x1234, phase2=0x15678, old_phase=0xaaaa,
        old_q=0x1bbbb, eff_inc=0x321, old_inc=0x222,
        dq_live=0x111, dq_old=0x333, noise_seed=0x4444,
        old_noise_next=0x5555, play=True, amp_nonzero=False, wt=False,
        restart=True, old_noise_on=True, old_gain_nonzero=True,
        wave=2, mode=2, old_wave=7, old_mode=1)
    result = compiled_phase_contexts(zero_restart)
    assert result.w0_primary == 0x1234
    assert result.w1_secondary == 0
    assert result.w2_old_primary == 0x1234
    assert result.w3_old_secondary == 0x5678

    noise_restart = PhaseContextCase(
        **{**zero_restart.__dict__, "amp_nonzero": True,
           "noise_seed": 0x6789, "old_noise_next": 0x789a})
    result = compiled_phase_contexts(noise_restart)
    assert result.w2_old_primary == 0x789a
    return (f"{cases:,} W0--W6 context/writeback cases; restart zero, "
            "noise-seed priority and old/live DQ association exact")


def trunc_zero(value: int, divisor: int) -> int:
    quotient = abs(value) // divisor
    return -quotient if value < 0 else quotient


def signed(value: int, bits: int) -> int:
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def wave_value(phase: int, wave: int, alt: bool, secondary: bool) -> int:
    """Scalar form of the separately exhaustive psg_wave_ctx oracle."""
    phase &= 0xffff
    if wave in (0, 7):
        raw = 3 * phase - 49_152 if phase < 32_768 \
            else 147_456 - 3 * phase
        if wave == 0 and alt:
            ramp = 65_535 - phase if phase >= 57_344 else phase
            numerator = 3 * ramp - ((ramp + 2_047) >> 11)
            tilt = (numerator if phase >= 57_344 else numerator // 7) - 12_286
            raw = tilt + 3 * trunc_zero(raw, 4)
        return trunc_zero(raw, 8 if secondary else 4)
    if wave == 1:
        boundary = 61_440 if alt else 57_344
        divisor = 15 if alt else 7
        ceil_shift = 10 if alt else 11
        scale = 6 if alt else 3
        ramp = 65_535 - phase if phase >= boundary else phase
        numerator = scale * ramp - ((ramp + (1 << ceil_shift) - 1)
                                    >> ceil_shift)
        raw = (numerator if phase >= boundary else numerator // divisor) \
            - 12_286
        return trunc_zero(raw, 2) if secondary else raw
    if wave == 2:
        raw = trunc_zero(phase - 32_768, 4)
        if alt:
            raw = trunc_zero(raw + trunc_zero((phase // 2) - 32_768, 4), 2)
        return trunc_zero(raw, 2) if secondary else raw
    if wave in (3, 4):
        threshold = ((0x9800 if alt else 0x8000) if wave == 3
                     else (0xC800 if alt else 0xB000))
        raw = -6_143 if phase < threshold else 6_143
        return trunc_zero(raw, 2) if secondary else raw
    if wave == 5:
        if alt and secondary:
            raw = -3_071 if phase < 32_768 else 3_071
        elif phase < 16_384:
            raw = phase - 8_192
        elif phase < 32_768:
            raw = 24_576 - phase
        else:
            magnitude = 2 * (phase - 32_768) if phase < 49_152 \
                else 2 * (65_536 - phase)
            raw = magnitude // 3 - 8_192
        return trunc_zero(raw, 2) if secondary else raw
    return 0


def soft_add_value(a: int, b: int) -> int:
    total = a + b
    threshold = 24_576
    if total >= threshold:
        return threshold + (total - threshold) // 5
    if total <= -threshold:
        return -threshold - (-threshold - total) // 5
    return total


@dataclass
class SampleRecord:
    phase: int
    nz_hold: int
    old_q: int
    phase2: int
    clr_ack: int
    old_gain: int
    last_gain: int
    nz_phase: int
    old_mode: int
    brown: int
    lowpass: int
    old_phase: int
    blend_count: int
    old_inc: int
    old_rev: int
    last_rev: int
    last_wave: int
    last_inc: int
    old_alt: int
    last_alt: int
    last_mode: int
    old_wave: int
    noise_lowpass: int


@dataclass(frozen=True)
class SampleParams:
    eff_inc: int
    snd_id: int
    wavetable: bool
    wave: int
    damp: int
    reverb: int
    detune: int
    buzz: bool
    noise: bool
    amplitude: int
    clr_tog: int


@dataclass(frozen=True)
class SampleInputs:
    play: bool
    hidden: bool
    music_slot: bool
    music_playing: bool
    nz_tog: bool
    nz_tick: bool
    lfsr: int
    lfsr2: int
    ring_current: int
    ring_old: int
    aram_salt: int


@dataclass(frozen=True)
class SampleTrace:
    initial_words: tuple[int, ...]
    final_words: tuple[int, ...]
    dq_live: int
    dq_old: int
    noise_old_step: int
    noise_live_step: int
    wave_contexts: tuple[tuple[int, int, bool, bool], ...]
    wave_results: tuple[int, ...]
    aram_requests: tuple[tuple[int, int, bool], ...]
    aram_results: tuple[int, ...]
    primary_interp: int
    old_interp: int
    live_gain_limb: int
    old_gain_limb: int
    current_arm: int
    old_arm: int
    ring_current: int
    ring_old: int
    blend_value: int
    filtered_value: int
    leaf: int
    ring_write: int | None
    next_lfsr: int
    next_lfsr2: int


def decode_sample_record(words: list[int] | tuple[int, ...]) -> SampleRecord:
    assert len(words) == 14
    return SampleRecord(
        phase=words[0],
        nz_hold=signed(words[1] >> 8, 8),
        old_q=((words[7] & 0x1ff) << 8) | (words[1] & 0xff),
        phase2=((words[3] & 1) << 16) | words[2],
        clr_ack=(words[3] >> 15) & 1,
        old_gain=((words[3] >> 10) & 0x1f) << 8 | (words[9] >> 8),
        last_gain=((words[3] >> 5) & 0x1f) << 8 | (words[12] & 0xff),
        nz_phase=(words[3] >> 1) & 0xf,
        old_mode=(words[4] >> 13) & 3,
        brown=signed(words[4], 13),
        lowpass=signed(((words[4] >> 15) << 16) | words[5], 17),
        old_phase=words[6],
        blend_count=(words[7] >> 9) & 0x7f,
        old_inc=((words[9] & 0x1f) << 9) | (words[8] >> 7),
        old_rev=(words[10] >> 13) & 3,
        last_rev=(words[10] >> 11) & 3,
        last_wave=(words[10] >> 8) & 7,
        last_inc=((words[10] & 0x1f) << 9) | (words[11] >> 7),
        old_alt=bool((words[12] >> 14) & 1),
        last_alt=bool((words[12] >> 13) & 1),
        last_mode=(words[12] >> 11) & 3,
        old_wave=(words[12] >> 8) & 7,
        noise_lowpass=signed(words[13], 16),
    )


def encode_sample_record(record: SampleRecord) -> tuple[int, ...]:
    words = [0] * 14
    words[0] = record.phase & 0xffff
    words[1] = ((record.nz_hold & 0xff) << 8) | (record.old_q & 0xff)
    words[2] = record.phase2 & 0xffff
    words[3] = ((record.clr_ack & 1) << 15) \
        | (((record.old_gain >> 8) & 0x1f) << 10) \
        | (((record.last_gain >> 8) & 0x1f) << 5) \
        | ((record.nz_phase & 0xf) << 1) | ((record.phase2 >> 16) & 1)
    words[4] = ((record.lowpass < 0) << 15) \
        | ((record.old_mode & 3) << 13) | (record.brown & 0x1fff)
    words[5] = record.lowpass & 0xffff
    words[6] = record.old_phase & 0xffff
    words[7] = ((record.blend_count & 0x7f) << 9) \
        | ((record.old_q >> 8) & 0x1ff)
    words[8] = (record.old_inc & 0x1ff) << 7
    words[9] = ((record.old_gain & 0xff) << 8) \
        | ((record.old_inc >> 9) & 0x1f)
    words[10] = ((record.old_rev & 3) << 13) \
        | ((record.last_rev & 3) << 11) \
        | ((record.last_wave & 7) << 8) \
        | ((record.last_inc >> 9) & 0x1f)
    words[11] = (record.last_inc & 0x1ff) << 7
    words[12] = (int(record.old_alt) << 14) \
        | (int(record.last_alt) << 13) \
        | ((record.last_mode & 3) << 11) \
        | ((record.old_wave & 7) << 8) | (record.last_gain & 0xff)
    words[13] = record.noise_lowpass & 0xffff
    return tuple(words)


def decode_sample_params(words: list[int] | tuple[int, ...]) -> SampleParams:
    assert len(words) == 4
    return SampleParams(
        eff_inc=((words[1] & 0x1f) << 9) | (words[0] >> 7),
        snd_id=(words[1] >> 12) & 7,
        wavetable=bool((words[1] >> 11) & 1),
        wave=(words[1] >> 8) & 7,
        damp=(words[2] >> 12) & 3,
        reverb=(words[2] >> 10) & 3,
        detune=(words[2] >> 8) & 3,
        buzz=bool((words[2] >> 7) & 1),
        noise=bool((words[2] >> 6) & 1),
        amplitude=words[3] & 0xfff,
        clr_tog=(words[3] >> 13) & 1,
    )


def encode_sample_params(params: SampleParams) -> tuple[int, ...]:
    return (
        (params.eff_inc & 0x1ff) << 7,
        ((params.snd_id & 7) << 12) | (int(params.wavetable) << 11)
        | ((params.wave & 7) << 8) | ((params.eff_inc >> 9) & 0x1f),
        ((params.damp & 3) << 12) | ((params.reverb & 3) << 10)
        | ((params.detune & 3) << 8) | (int(params.buzz) << 7)
        | (int(params.noise) << 6),
        (params.clr_tog << 13) | (params.amplitude & 0xfff),
    )


def phase_view(raw: int, wave: int, mode: int, wavetable: bool) -> int:
    raw &= 0xffff
    if not wavetable and wave in (0, 7):
        return raw
    return ((raw << 1) & 0xffff) if mode == 2 else raw


def dq_value(increment: int, wavetable: bool, wave: int, mode: int) -> int:
    if wavetable:
        coefficient = 256
    elif wave == 0:
        coefficient = (256, 193, 384)[mode]
    elif wave == 7:
        coefficient = (254, 250, 508)[mode]
    else:
        coefficient = 256 if mode == 0 else 255
    return ((increment >> 1) * coefficient) >> 8


def noise_draw(lfsr: int) -> int:
    value = 0
    for term in range(8):
        source = 7 + term
        value |= (((lfsr >> source) ^ (lfsr >> (source - 1))) & 1) \
            << (7 - term)
    return signed(value, 8)


def advance_lfsr(value: int, tap: int) -> int:
    return ((value << 1) & 0x7fff) | (((value >> 14) ^ (value >> tap)) & 1)


def noise_kick(lfsr: int, lfsr2: int, dp: int, amplitude: int) -> int:
    gain = ((lfsr >> 7) & 0xff) << 5 | (lfsr & 0x1f)
    if 3 * gain > dp + 497:
        return 0
    inv = 1 ^ ((lfsr2 >> 12) & 1)
    draw = signed((inv << 11) | (inv << 10) | ((lfsr2 >> 2) & 0x3ff), 12)
    draw = draw - (draw >> 3) - (draw >> 6)
    return draw * ((amplitude >> 8) & 7)


def aram_value(snd_id: int, index: int, salt: int) -> int:
    index &= 0x3f
    raw = ((snd_id * 73 + index * 29 + salt * 17) ^ 0xa5) & 0xff
    return signed(raw, 8)


def wavetable_value(snd_id: int, phase: int, salt: int) \
        -> tuple[int, tuple[tuple[int, int, bool], ...], tuple[int, ...]]:
    index = (phase >> 10) & 0x3f
    fraction = phase & 0x3ff
    base = aram_value(snd_id, index, salt)
    adjacent = aram_value(snd_id, index + 1, salt)
    value = (base * 1024 + (adjacent - base) * fraction) // 8
    requests = ((snd_id, index, False), (snd_id, index, True))
    return value, requests, (base, adjacent)


def gain_arm(value: int, gain: int, wave: int) -> tuple[int, int]:
    limb = (abs(value) * gain) >> 10
    if wave == 6:
        magnitude = limb >> 1
    else:
        p341 = limb * 341
        reciprocal = (((p341 & ((1 << 25) - 1)) << 9)
                      + ((p341 + limb) >> 1)) & ((1 << 34) - 1)
        magnitude = (reciprocal >> 19) & 0x1ffff
    return (-magnitude if value < 0 else magnitude), limb


def evaluate_sample_slot(record: SampleRecord, params: SampleParams,
                         inputs: SampleInputs) -> SampleTrace:
    """Direct legacy source/NBA oracle for one complete full-mode slot."""
    initial_words = encode_sample_record(record)
    state = SampleRecord(**record.__dict__)
    run = inputs.play and params.amplitude != 0
    boost = params.detune != 0 and not params.wavetable \
        and not ((params.wave & 4) and (params.wave & 2))
    gain_a = params.amplitude + (params.amplitude >> 2) \
        if boost else params.amplitude
    live_gain = gain_a + (gain_a >> 1)
    restart = inputs.play and (
        params.eff_inc != state.last_inc or live_gain != state.last_gain
        or params.wave != state.last_wave or params.detune != state.last_mode
        or params.reverb != state.last_rev or params.buzz != state.last_alt
        or (params.amplitude != 0 and params.wave == 6
            and not params.wavetable and not params.buzz and inputs.nz_tick))

    old_inc_now = state.last_inc if restart else state.old_inc
    old_wave_now = state.last_wave if restart else state.old_wave
    old_mode_now = state.last_mode if restart else state.old_mode
    old_alt_now = state.last_alt if restart else state.old_alt
    old_gain_now = state.last_gain if restart else state.old_gain
    old_rev_now = state.last_rev if restart else state.old_rev
    dq_live = dq_value(params.eff_inc, params.wavetable, params.wave,
                       params.detune)
    dq_old = dq_value(old_inc_now, params.wavetable, old_wave_now,
                      old_mode_now)
    live_random = noise_draw(inputs.lfsr)
    old_random = noise_draw(inputs.lfsr2)
    noise_live_step = (((params.eff_inc >> 1) << 3) + 1_120) \
        * live_random // 256
    noise_old_step = (((old_inc_now >> 1) << 3) + 1_120) \
        * old_random // 256
    kick = noise_kick(inputs.lfsr, inputs.lfsr2, params.eff_inc >> 1,
                      params.amplitude)
    old_noise_on = old_wave_now == 6 and not old_alt_now
    old_noise_active = run and old_noise_on

    w0_phase = state.phase
    if run and not params.wavetable:
        state.phase = (state.phase + (params.eff_inc >> 1)) & 0xffff
    if restart:
        state.blend_count = 0
        state.old_phase = record.phase
        state.old_q = record.phase2
        state.old_inc = record.last_inc
        state.old_gain = record.last_gain
        state.old_wave = record.last_wave
        state.old_mode = record.last_mode
        state.old_alt = record.last_alt
        state.old_rev = record.last_rev
        if params.amplitude == 0:
            state.phase = 0
            state.phase2 = 0
    elif state.blend_count != 64:
        state.blend_count += 1

    clear = params.clr_tog != state.clr_ack
    if run and (params.noise or (record.phase >> 12) != state.nz_phase):
        state.nz_phase = record.phase >> 12
        state.nz_hold = signed(inputs.lfsr, 8)
    if clear:
        state.clr_ack = params.clr_tog
        state.lowpass = 0
    if run or clear:
        state.brown = 0 if clear else signed(
            state.brown - (state.brown >> 5) + signed(inputs.lfsr, 8), 13)
    noise_pre = state.noise_lowpass \
        + (noise_live_step if inputs.nz_tog else 0) + kick
    if (run and params.wave == 6) or clear:
        state.noise_lowpass = 0 if clear else max(-6_143, min(6_143, noise_pre))
        live_noise_out = 0 if clear else noise_pre
    else:
        live_noise_out = 0
    if old_noise_active:
        seed_base = record.noise_lowpass if (restart or inputs.nz_tick) \
            else record.old_phase
        state.old_phase = (signed(seed_base, 16) + kick) & 0xffff

    w1_phase = phase_view(state.phase2, params.wave, params.detune,
                          params.wavetable)
    old_noise_pre = signed(state.old_phase, 16) \
        + (noise_old_step if inputs.nz_tog else 0)
    if old_noise_active:
        state.old_phase = max(-6_143, min(6_143, old_noise_pre)) & 0xffff
        old_noise_out = old_noise_pre
    else:
        old_noise_out = 0
    if run and params.wavetable:
        state.phase = (state.phase + (params.eff_inc >> 1)) & 0xffff

    w2_phase = state.old_phase
    w3_phase = phase_view(state.old_q, state.old_wave, state.old_mode, False)
    contexts = (
        (w0_phase, params.wave, params.buzz, False),
        (w1_phase, params.wave, params.buzz, True),
        (w2_phase, state.old_wave, state.old_alt, False),
        (w3_phase, state.old_wave, state.old_alt, True),
    )
    wave_results = tuple(wave_value(*context) for context in contexts)
    aram_requests: tuple[tuple[int, int, bool], ...] = ()
    aram_results: tuple[int, ...] = ()
    primary_interp = old_interp = 0
    if params.wavetable and inputs.play:
        primary_interp, primary_req, primary_bytes = wavetable_value(
            params.snd_id, w0_phase, inputs.aram_salt)
        old_interp, old_req, old_bytes = wavetable_value(
            params.snd_id, w1_phase, inputs.aram_salt)
        aram_requests = primary_req + old_req
        aram_results = primary_bytes + old_bytes
        z_new = primary_interp + trunc_zero(old_interp, 2)
        z_old = 0
    elif params.wavetable:
        z_new = z_old = 0
    else:
        z_new = wave_results[0] + wave_results[1]
        z_old = wave_results[2] + wave_results[3]

    if params.wave == 6 and not params.wavetable:
        if params.buzz and not params.noise:
            z_new = state.brown << 3
        else:
            coarse = live_noise_out >> 6
            z_new = coarse * (68 if params.eff_inc & 0x2000 else 80)
    if old_noise_active:
        coarse = old_noise_out >> 6
        z_old = coarse * (68 if state.old_inc & 0x2000 else 80)

    state.last_inc = params.eff_inc
    if inputs.play or not (inputs.music_slot and inputs.music_playing):
        state.last_gain = live_gain
    state.last_wave = params.wave
    state.last_mode = params.detune
    state.last_alt = params.buzz
    state.last_rev = params.reverb
    if not params.wavetable and state.old_gain != 0 and not old_noise_active:
        state.old_phase = (state.old_phase + (state.old_inc >> 1)) & 0xffff
        state.old_q = (state.old_q + dq_old) & 0x1ffff
    if run:
        state.phase2 = (state.phase2 + dq_live) & 0x1ffff

    current_arm, live_limb = gain_arm(z_new, live_gain, params.wave)
    if params.wavetable:
        old_arm = current_arm if state.old_gain != 0 else 0
        old_limb = 0
    else:
        old_arm, old_limb = gain_arm(z_old, state.old_gain, state.old_wave)
    combined_new = trunc_zero(2 * current_arm + inputs.ring_current, 2) \
        if params.reverb != 0 else current_arm
    combined_old = trunc_zero(2 * old_arm + inputs.ring_old, 2) \
        if state.old_rev != 0 else old_arm
    blend_value = combined_new if state.blend_count == 64 else trunc_zero(
        combined_old * 64 + (combined_new - combined_old)
        * state.blend_count, 64)
    if params.damp == 0:
        filtered = blend_value
    else:
        factor = 1 if params.damp == 1 else 3
        divisor = 2 if params.damp == 1 else 4
        filtered = trunc_zero(blend_value + factor * state.lowpass, divisor)
        state.lowpass = signed(filtered, 17)
    audible = inputs.play and not inputs.hidden
    # The shipped fold boundary deliberately takes mx_filt[15:0] and restores
    # its bit-15 sign; persistent dampen state separately retains bit 16.
    leaf = signed(filtered, 16) if audible else 0
    ring_write = (signed(filtered, 17) & 0xffff) if inputs.play else None
    next_lfsr = advance_lfsr(inputs.lfsr, 13)
    next_lfsr2 = advance_lfsr(inputs.lfsr2, 10)
    return SampleTrace(
        initial_words=initial_words, final_words=encode_sample_record(state),
        dq_live=dq_live, dq_old=dq_old,
        noise_old_step=noise_old_step, noise_live_step=noise_live_step,
        wave_contexts=contexts, wave_results=wave_results,
        aram_requests=aram_requests, aram_results=aram_results,
        primary_interp=primary_interp, old_interp=old_interp,
        live_gain_limb=live_limb, old_gain_limb=old_limb,
        current_arm=current_arm, old_arm=old_arm,
        ring_current=inputs.ring_current, ring_old=inputs.ring_old,
        blend_value=blend_value, filtered_value=signed(filtered, 17),
        leaf=leaf, ring_write=ring_write,
        next_lfsr=next_lfsr, next_lfsr2=next_lfsr2)


@dataclass
class ServiceToken:
    producer: str
    consumer: str
    ready_cycle: int
    value: object


SAMPLE_HOLD_TARGETS = (
    "NZ_OLD_LOAD_PAR_3", "NZ_LIVE",
    *(f"CAP_{name}" for name, _ in SAMPLE_CAP_SCHEDULE),
    *(f"HOLD_{word}" for word in range(9)),
    "FOLD_PRIME", "FOLD_A_LO", "FOLD_A_HI", "FOLD_B_LO",
    "FOLD_START", "FOLD_RUN", "FOLD_WRITE_LO", "FOLD_WRITE_HI",
    "FOLD_FINISH",
)


class SampleImageMachine:
    """Execute the real owner-zero image and compose the proved services."""
    def __init__(self, program: list[int], actions: Actions, memory: list[int],
                 *, spar_bank: int, play_bits: int, music_playing: bool,
                 reverb: bool, lfsr: int, lfsr2: int, nz_tog: bool,
                 nz_tick: bool, aram_salt: int, hold_selector: int) -> None:
        self.program = program
        self.actions = actions
        self.memory = memory
        self.spar_bank = spar_bank
        self.play_bits = play_bits
        self.music_playing = music_playing
        self.reverb = reverb
        self.lfsr = lfsr
        self.lfsr2 = lfsr2
        self.nz_tog = nz_tog
        self.nz_tick = nz_tick
        self.aram_salt = aram_salt
        self.hold_selector = hold_selector
        self.pc = SAMPLE_START
        self.slot = 0
        self.state_q = 0
        self.active_cycles = 0
        self.wall_cycles = 0
        self.semantic_reads = 0
        self.semantic_writes = 0
        self.physical_reads = 0
        self.pending: tuple[int, int] | None = None
        self.loaded_words: list[int] = []
        self.params_words: list[int] = []
        self.trace: SampleTrace | None = None
        self.tokens: dict[str, ServiceToken] = {}
        self.leaf = 0
        self.hold_checks = 0
        self.hold_labels: set[str] = set()
        self.service_transactions = 0
        self.ring_tags: list[int] = []
        self.fold_a = 0
        self.fold_b = 0
        self.fold_value = 0
        self.fold_tags: list[int] = []
        self.dry16 = 0
        self.dry_valid = 0

    def address(self, slot: int, word: int) -> int:
        return (slot << 6) | word

    def freeze_fingerprint(self) -> tuple[object, ...]:
        return (self.pc, self.slot, self.state_q, self.active_cycles,
                self.semantic_reads, self.semantic_writes, self.physical_reads,
                self.pending, tuple(self.loaded_words), tuple(self.params_words),
                repr(self.trace), repr(self.tokens), self.leaf,
                tuple(self.ring_tags), self.fold_a, self.fold_b,
                self.fold_value, tuple(self.fold_tags), self.dry16,
                self.dry_valid, self.lfsr, self.lfsr2)

    def inject_hold(self, label: str) -> None:
        target = SAMPLE_HOLD_TARGETS[self.hold_selector
                                     % len(SAMPLE_HOLD_TARGETS)]
        if self.hold_checks or label != target:
            return
        before = self.freeze_fingerprint()
        self.wall_cycles += 3
        assert self.freeze_fingerprint() == before, label
        self.hold_checks += 1
        self.hold_labels.add(label)

    def issue(self, key: str, producer: str, consumer: str,
              delay: int, value: object) -> None:
        assert key not in self.tokens, (key, self.tokens)
        self.tokens[key] = ServiceToken(producer, consumer,
                                        self.active_cycles + delay, value)
        self.service_transactions += 1

    def take(self, key: str, consumer: str) -> object:
        token = self.tokens.pop(key)
        assert token.consumer == consumer, (key, token, consumer)
        assert self.active_cycles >= token.ready_cycle, (key, token,
                                                         self.active_cycles)
        return token.value

    def begin_trace(self) -> None:
        assert len(self.loaded_words) == 14 and len(self.params_words) == 4
        record = decode_sample_record(self.loaded_words)
        params = decode_sample_params(self.params_words)
        hidden = self.slot >= 4 and bool(self.play_bits & (1 << (self.slot - 4)))
        ring_current = signed((self.slot * 0x1931 + self.aram_salt * 0x111)
                              & 0xffff, 16) if self.reverb else 0
        ring_old = signed((self.slot * 0x2b17 + self.aram_salt * 0x73)
                          & 0xffff, 16) if self.reverb else 0
        inputs = SampleInputs(
            play=bool(self.play_bits & (1 << self.slot)), hidden=hidden,
            music_slot=self.slot >= 4, music_playing=self.music_playing,
            nz_tog=self.nz_tog, nz_tick=self.nz_tick,
            lfsr=self.lfsr, lfsr2=self.lfsr2,
            ring_current=ring_current, ring_old=ring_old,
            aram_salt=self.aram_salt)
        self.trace = evaluate_sample_slot(record, params, inputs)

    def fold_step(self, tag: int) -> None:
        assert tag == len(self.fold_tags) + 1, (self.fold_tags, tag)
        self.fold_tags.append(tag)
        if tag == 1:
            self.fold_value = self.fold_a + self.fold_b
        elif tag == 2:
            total = self.fold_value
            self.fold_value = (total - 24_576 if total >= 24_576
                               else -24_576 - total if total <= -24_576
                               else 0)
        elif tag == 3:
            self.fold_value = abs(self.fold_value)
        elif tag == 4:
            high, low = divmod(self.fold_value, 256)
            self.fold_value = (high << 16) | low
        elif tag == 5:
            high, low = self.fold_value >> 16, self.fold_value & 0xffff
            self.fold_value = (51 * high << 16) | (high + low)
        elif tag == 6:
            partial, address = self.fold_value >> 16, self.fold_value & 0xffff
            self.fold_value = partial + address // 5
        elif tag == 7:
            total = self.fold_a + self.fold_b
            self.fold_value = (24_576 + self.fold_value
                               if total >= 24_576 else
                               -24_576 - self.fold_value
                               if total <= -24_576 else total)
        else:
            assert self.fold_value == soft_add_value(self.fold_a, self.fold_b)

    def execute_action(self, name: str, insn: Instruction) -> None:
        if name.startswith("LOAD_OSC_"):
            assert self.pending is not None
            self.loaded_words.append(self.state_q)
            self.pending = None
        elif name.startswith("LOAD_PAR_"):
            assert self.pending is not None
            self.params_words.append(self.state_q)
            self.pending = None
        elif name == "NZ_OLD_LOAD_PAR_3":
            assert self.pending is not None
            self.params_words.append(self.state_q)
            self.pending = None
            self.begin_trace()
            assert self.trace is not None
            self.issue("dq_live", name, "NZ_LIVE", 5, self.trace.dq_live)
            self.issue("noise_old", name, "NZ_LIVE", 5,
                       self.trace.noise_old_step)
        elif name == "NZ_LIVE":
            assert self.trace is not None
            assert self.take("dq_live", name) == self.trace.dq_live
            assert self.take("noise_old", name) == self.trace.noise_old_step
            self.issue("noise_old_hold", name, "CAP_W1", 0,
                       self.trace.noise_old_step)
            self.issue("dq_live_hold", name, "CAP_W6", 0,
                       self.trace.dq_live)
            self.issue("dq_old", name, "CAP_W5", 5, self.trace.dq_old)
            self.issue("noise_live", name, "CAP_W0", 5,
                       self.trace.noise_live_step)
        elif name == "CAP_W0":
            assert self.trace is not None
            assert self.state_q == self.trace.initial_words[0]
            assert self.take("noise_live", name) == self.trace.noise_live_step
            if not decode_sample_params(self.params_words).wavetable:
                self.issue("wave_0", name, "CAP_W2", 2,
                           self.trace.wave_results[0])
            elif self.trace.aram_requests:
                self.issue("aram_0", name, "CAP_W1", 1,
                           self.trace.aram_results[0])
        elif name == "CAP_W1":
            assert self.trace is not None
            assert self.state_q == self.trace.initial_words[2]
            assert self.take("noise_old_hold", name) \
                == self.trace.noise_old_step
            if not decode_sample_params(self.params_words).wavetable:
                self.issue("wave_1", name, "CAP_W3", 2,
                           self.trace.wave_results[1])
            elif self.trace.aram_requests:
                assert self.take("aram_0", name) == self.trace.aram_results[0]
                self.issue("aram_1", name, "CAP_W2", 1,
                           self.trace.aram_results[1])
        elif name == "CAP_W2":
            assert self.trace is not None
            assert self.state_q == self.trace.initial_words[6]
            params = decode_sample_params(self.params_words)
            if not params.wavetable:
                assert self.take("wave_0", name) == self.trace.wave_results[0]
                self.issue("wave_2", name, "CAP_W4", 2,
                           self.trace.wave_results[2])
            elif self.trace.aram_requests:
                assert self.take("aram_1", name) == self.trace.aram_results[1]
                self.issue("aram_2", name, "CAP_W3", 1,
                           self.trace.aram_results[2])
        elif name == "CAP_W3":
            assert self.trace is not None
            params = decode_sample_params(self.params_words)
            if not params.wavetable:
                assert self.take("wave_1", name) == self.trace.wave_results[1]
                self.issue("wave_3", name, "CAP_W5", 2,
                           self.trace.wave_results[3])
            elif self.trace.aram_requests:
                assert self.take("aram_2", name) == self.trace.aram_results[2]
                self.issue("aram_3", name, "CAP_W4", 1,
                           self.trace.aram_results[3])
        elif name == "CAP_W4":
            assert self.trace is not None
            params = decode_sample_params(self.params_words)
            if not params.wavetable:
                assert self.take("wave_2", name) == self.trace.wave_results[2]
                self.issue("mul_live", name, "CAP_W15", 5,
                           self.trace.live_gain_limb)
            elif self.trace.aram_requests:
                assert self.take("aram_3", name) == self.trace.aram_results[3]
                self.issue("mul_primary_interp", name, "CAP_W15", 5,
                           self.trace.primary_interp)
        elif name == "CAP_W5":
            assert self.trace is not None
            params = decode_sample_params(self.params_words)
            assert self.take("dq_old", name) == self.trace.dq_old
            if not params.wavetable:
                assert self.take("wave_3", name) == self.trace.wave_results[3]
        elif name == "CAP_W6":
            assert self.trace is not None
            assert self.take("dq_live_hold", name) == self.trace.dq_live
        elif name == "CAP_W15":
            assert self.trace is not None
            params = decode_sample_params(self.params_words)
            if params.wavetable and self.trace.aram_requests:
                assert self.take("mul_primary_interp", name) \
                    == self.trace.primary_interp
                self.issue("mul_old_interp", name, "CAP_W26", 5,
                           self.trace.old_interp)
            elif not params.wavetable:
                assert self.take("mul_live", name) == self.trace.live_gain_limb
                self.issue("mul_live_recip", name, "CAP_W27", 6,
                           self.trace.current_arm)
        elif name == "CAP_W26":
            assert self.trace is not None
            if self.trace.aram_requests:
                assert self.take("mul_old_interp", name) == self.trace.old_interp
        elif name == "CAP_W27":
            assert self.trace is not None
            params = decode_sample_params(self.params_words)
            if params.wavetable:
                self.issue("mul_live", name, "CAP_W40", 5,
                           self.trace.live_gain_limb)
            else:
                assert self.take("mul_live_recip", name) \
                    == self.trace.current_arm
                self.issue("mul_old", name, "CAP_W40", 5,
                           self.trace.old_gain_limb)
        elif name == "CAP_W40":
            assert self.trace is not None
            params = decode_sample_params(self.params_words)
            if params.wavetable:
                assert self.take("mul_live", name) == self.trace.live_gain_limb
            else:
                assert self.take("mul_old", name) == self.trace.old_gain_limb
            self.issue("mul_arm_recip", name, "CAP_W51", 5,
                       (self.trace.current_arm if params.wavetable
                        else self.trace.old_arm))
        elif name == "CAP_W51":
            assert self.trace is not None
            expected = (self.trace.current_arm
                        if decode_sample_params(self.params_words).wavetable
                        else self.trace.old_arm)
            assert self.take("mul_arm_recip", name) == expected
            assert self.ring_tags == ([1, 2, 3, 4] if self.reverb else [])
        elif name == "CAP_W75":
            assert self.trace is not None
            record = decode_sample_record(self.trace.final_words)
            if record.blend_count != 64:
                self.issue("mul_blend", name, "CAP_W84", 4,
                           self.trace.blend_value)
        elif name == "CAP_W84":
            assert self.trace is not None
            if "mul_blend" in self.tokens:
                assert self.take("mul_blend", name) == self.trace.blend_value
            self.leaf = self.trace.leaf
        elif name.startswith("STORE_"):
            assert self.trace is not None
            if name == "STORE_LEAF_LO":
                value = self.leaf & 0xffff
            elif name == "STORE_LEAF_HI":
                value = (self.leaf >> 16) & 0xffff
            else:
                index = int(name.split("_")[1])
                value = (self.trace.final_words[index]
                         if index < 14 else
                         self.trace.final_words[5 if index == 14 else 4])
            self.memory[self.address(self.slot, insn.word)] = value
            self.semantic_writes += 1
        elif name == "FOLD_A_LO":
            self.fold_a = self.state_q
            self.pending = None
        elif name == "FOLD_A_HI":
            self.fold_a = signed(((self.state_q & 3) << 16) | self.fold_a, 18)
            self.pending = None
        elif name == "FOLD_B_LO":
            self.fold_b = self.state_q
            self.pending = None
        elif name == "FOLD_START":
            self.fold_b = signed(((self.state_q & 3) << 16) | self.fold_b, 18)
            self.pending = None
            self.fold_tags = []
        elif name == "FOLD_WRITE_LO":
            self.memory[self.address(self.slot, insn.word)] = \
                self.fold_value & 0xffff
            self.semantic_writes += 1
        elif name == "FOLD_WRITE_HI":
            self.memory[self.address(self.slot, insn.word)] = \
                (self.fold_value >> 16) & 0xffff
            self.semantic_writes += 1
        elif name == "FOLD_FINISH":
            self.dry16 = signed(self.memory[self.address(0, 48)], 16)
            self.dry_valid += 1

    def run(self) -> tuple[int, int, int, int, int]:
        for _ in range(2_000):
            insn = Instruction.decode(self.program[self.pc])
            label = ""
            action = self.actions.get("sample", insn.action) \
                if insn.op in (Op.READ, Op.WRITE, Op.EXEC) else None
            if action is not None:
                label = action.name
            elif insn.op == Op.EXEC and insn.action == COMMON_ACTION["HOLD"]:
                label = f"HOLD_{insn.word}"
            self.inject_hold(label)
            self.active_cycles += 1
            self.wall_cycles += 1
            self.physical_reads += 1
            if action is not None and action.consumes is not None:
                assert self.pending == (self.slot, action.consumes), \
                    (self.pc, action.name, self.pending)
            if action is not None:
                self.execute_action(action.name, insn)
            if insn.op == Op.READ:
                self.semantic_reads += 1
                self.pending = (self.slot, insn.word)
                next_pc = (self.pc + 1) & 0xff
            elif insn.op in (Op.WRITE, Op.EXEC):
                if insn.op == Op.EXEC and insn.action == COMMON_ACTION["HOLD"]:
                    if 1 <= insn.word <= 4 and self.trace is not None:
                        if self.reverb:
                            self.ring_tags.append(insn.word)
                            if insn.word == 1:
                                self.issue("ring_current", "HOLD_1", "HOLD_2",
                                           1, self.trace.ring_current)
                            elif insn.word == 2:
                                assert self.take("ring_current", "HOLD_2") \
                                    == self.trace.ring_current
                                self.issue("ring_old", "HOLD_2", "HOLD_3", 1,
                                           self.trace.ring_old)
                            elif insn.word == 3:
                                assert self.take("ring_old", "HOLD_3") \
                                    == self.trace.ring_old
                            else:
                                assert "ring_current" not in self.tokens \
                                    and "ring_old" not in self.tokens
                    elif 1 <= insn.word <= 8 and self.trace is None:
                        self.fold_step(insn.word)
                next_pc = (self.pc + 1) & 0xff
            elif insn.op == Op.SLOT:
                self.slot = (self.slot + 1) & 7 if insn.slot_inc \
                    else insn.slot_value
                if insn.slot_inc:
                    assert self.trace is not None and not self.tokens
                    self.lfsr = self.trace.next_lfsr
                    self.lfsr2 = self.trace.next_lfsr2
                    self.loaded_words = []
                    self.params_words = []
                    self.trace = None
                    self.ring_tags = []
                next_pc = (self.pc + 1) & 0xff
            elif insn.op == Op.JUMP:
                next_pc = insn.target
            elif insn.op == Op.BRANCH:
                take = self.slot == 0
                next_pc = insn.target if take == bool(insn.sense) \
                    else (self.pc + 1) & 0xff
            elif insn.op == Op.DONE:
                assert not self.tokens and self.pending is None
                assert self.dry_valid == 1
                break
            else:
                raise AssertionError(insn)
            physical_word = insn.word
            if (insn.op == Op.READ and 24 <= insn.word <= 27
                    and self.spar_bank):
                physical_word += 4
            self.state_q = self.memory[self.address(self.slot, physical_word)] \
                if insn.op in (Op.READ, Op.WRITE, Op.EXEC) else \
                self.memory[self.address(self.slot, 0)]
            self.pc = next_pc
        else:
            raise AssertionError("sample image did not terminate")
        return (self.active_cycles, self.semantic_reads, self.semantic_writes,
                self.service_transactions, self.hold_checks)


def make_sample_case(case: int, spar_bank: int) \
        -> tuple[list[int], int, bool, int, int, bool, bool, int]:
    memory = [((case * 0x91 + n * 0x25) ^ 0x5a5a) & 0xffff
              for n in range(512)]
    play_bits = 0
    music_playing = bool(case & 1)
    for slot in range(8):
        play = ((case + slot * 3) % 5) != 0
        if play:
            play_bits |= 1 << slot
        wavetable = play and ((case + slot) % 4 == 0)
        wave = (case + slot) & 7
        amplitude = 0 if play and ((case + slot) % 7 == 0) \
            else (0 if not play else ((case * 173 + slot * 419) & 0xfff) or 1)
        detune = (case + 2 * slot) % 3
        buzz = bool((case ^ slot) & 1)
        noise = bool((case + slot) & 2)
        damp = 0 if not play else (case + slot) % 3
        reverb = (case + slot) % 3
        eff_inc = (0x101 + case * 0x93 + slot * 0x257) & 0x3fff
        gain_a = amplitude + (amplitude >> 2) \
            if detune != 0 and not wavetable and not ((wave & 4) and (wave & 2)) \
            else amplitude
        gain = gain_a + (gain_a >> 1)
        restart = play and bool((case + slot) & 1)
        last_wave = ((wave + 3) & 7) if restart else wave
        last_gain = (gain ^ 0x155) & 0x1fff if restart else gain
        last_inc = (eff_inc ^ 0x321) & 0x3fff if restart else eff_inc
        last_mode = ((detune + 1) % 3) if restart else detune
        last_alt = not buzz if restart else buzz
        last_rev = ((reverb + 1) % 3) if restart else reverb
        old_noise = (case + slot * 2) % 9 == 0
        record = SampleRecord(
            phase=(0xf031 + case * 0x511 + slot * 0x1d3) & 0xffff,
            nz_hold=signed(case * 17 + slot * 31, 8),
            old_q=(0x1e123 + case * 0x229 + slot * 0x431) & 0x1ffff,
            phase2=(0x10123 + case * 0x337 + slot * 0x119) & 0x1ffff,
            clr_ack=(case + slot + 1) & 1,
            old_gain=(0x311 + case * 0x51 + slot * 0x87) & 0x1fff,
            last_gain=last_gain, nz_phase=(case + slot) & 0xf,
            old_mode=(case + slot + 1) % 3,
            brown=signed(0x177 + case * 0x29 + slot * 0x77, 13),
            lowpass=signed(0x1a031 + case * 0x991 + slot * 0x533, 17),
            old_phase=(0x8123 + case * 0x739 + slot * 0x2b1) & 0xffff,
            blend_count=(0, 1, 63, 64)[(case + slot) & 3],
            old_inc=(0x222 + case * 0x71 + slot * 0x183) & 0x3fff,
            old_rev=(case + slot + 2) % 3, last_rev=last_rev,
            last_wave=last_wave, last_inc=last_inc,
            old_alt=False if old_noise else bool((case + slot + 1) & 1),
            last_alt=last_alt, last_mode=last_mode,
            old_wave=6 if old_noise else ((wave + 5) & 7),
            noise_lowpass=signed(0x9234 + case * 0x155 + slot * 0x2d1, 16))
        params = SampleParams(
            eff_inc=eff_inc, snd_id=(7 - slot) & 7,
            wavetable=wavetable, wave=wave, damp=damp, reverb=reverb,
            detune=detune, buzz=buzz, noise=noise, amplitude=amplitude,
            clr_tog=(case + slot) & 1)
        base = slot << 6
        memory[base + 10:base + 24] = encode_sample_record(record)
        selected = 28 if spar_bank else 24
        other = 24 if spar_bank else 28
        memory[base + selected:base + selected + 4] = encode_sample_params(params)
        poison = SampleParams(**{**params.__dict__,
                                 "wave": params.wave ^ 7,
                                 "amplitude": params.amplitude ^ 0xfff})
        memory[base + other:base + other + 4] = encode_sample_params(poison)
    lfsr = (0x2a5f ^ (case * 0x133)) & 0x7fff
    lfsr2 = (0x5117 ^ (case * 0x287)) & 0x7fff
    return (memory, play_bits, music_playing, lfsr, lfsr2,
            bool(case & 2), bool(case & 4), case ^ 0x35)


def direct_sample_image(memory: list[int], *, spar_bank: int, play_bits: int,
                        music_playing: bool, reverb: bool, lfsr: int, lfsr2: int,
                        nz_tog: bool, nz_tick: bool, aram_salt: int) \
        -> tuple[list[int], int]:
    out = list(memory)
    leaves = []
    for slot in range(8):
        base = slot << 6
        record = decode_sample_record(out[base + 10:base + 24])
        pbase = base + (28 if spar_bank else 24)
        params = decode_sample_params(out[pbase:pbase + 4])
        inputs = SampleInputs(
            play=bool(play_bits & (1 << slot)),
            hidden=slot >= 4 and bool(play_bits & (1 << (slot - 4))),
            music_slot=slot >= 4, music_playing=music_playing,
            nz_tog=nz_tog, nz_tick=nz_tick, lfsr=lfsr, lfsr2=lfsr2,
            ring_current=signed((slot * 0x1931 + aram_salt * 0x111)
                                & 0xffff, 16) if reverb else 0,
            ring_old=signed((slot * 0x2b17 + aram_salt * 0x73)
                            & 0xffff, 16) if reverb else 0,
            aram_salt=aram_salt)
        trace = evaluate_sample_slot(record, params, inputs)
        out[base + 10:base + 24] = trace.final_words
        out[base + 15] = trace.final_words[5]
        out[base + 14] = trace.final_words[4]
        out[base + 48] = trace.leaf & 0xffff
        out[base + 49] = (trace.leaf >> 16) & 0xffff
        leaves.append(trace.leaf)
        lfsr, lfsr2 = trace.next_lfsr, trace.next_lfsr2
    for a_slot, b_slot, dst_slot in FOLD_NODES:
        leaves[dst_slot] = soft_add_value(leaves[a_slot], leaves[b_slot])
        base = dst_slot << 6
        out[base + 48] = leaves[dst_slot] & 0xffff
        out[base + 49] = (leaves[dst_slot] >> 16) & 0xffff
    return out, signed(leaves[0], 16)


def validate_sample_image_semantics(program: list[int], actions: Actions) -> str:
    runs = slots = active = transactions = hold_checks = 0
    held_labels: set[str] = set()
    coverage: dict[str, set[object]] = {
        "bank": set(), "reverb_build": set(), "wave": set(),
        "wavetable": set(), "play": set(), "hidden": set(),
        "amplitude_zero": set(), "restart": set(), "old_noise": set(),
        "buzz": set(), "noise": set(), "detune": set(), "dampen": set(),
        "blend_count": set(),
    }
    for spar_bank in (0, 1):
        for reverb in (False, True):
            for case in range(16):
                (memory, play_bits, music_playing, lfsr, lfsr2,
                 nz_tog, nz_tick, aram_salt) = make_sample_case(case, spar_bank)
                coverage["bank"].add(spar_bank)
                coverage["reverb_build"].add(reverb)
                for slot in range(8):
                    base = slot << 6
                    record = decode_sample_record(memory[base + 10:base + 24])
                    pbase = base + (28 if spar_bank else 24)
                    params = decode_sample_params(memory[pbase:pbase + 4])
                    play = bool(play_bits & (1 << slot))
                    hidden = slot >= 4 and bool(play_bits & (1 << (slot - 4)))
                    boost = params.detune != 0 and not params.wavetable \
                        and not ((params.wave & 4) and (params.wave & 2))
                    gain_a = params.amplitude + (params.amplitude >> 2) \
                        if boost else params.amplitude
                    gain = gain_a + (gain_a >> 1)
                    restart = play and (
                        params.eff_inc != record.last_inc
                        or gain != record.last_gain
                        or params.wave != record.last_wave
                        or params.detune != record.last_mode
                        or params.reverb != record.last_rev
                        or params.buzz != record.last_alt
                        or (params.amplitude != 0 and params.wave == 6
                            and not params.wavetable and not params.buzz
                            and nz_tick))
                    old_wave = record.last_wave if restart else record.old_wave
                    old_alt = record.last_alt if restart else record.old_alt
                    coverage["wave"].add(params.wave)
                    coverage["wavetable"].add(params.wavetable)
                    coverage["play"].add(play)
                    coverage["hidden"].add(hidden)
                    coverage["amplitude_zero"].add(params.amplitude == 0)
                    coverage["restart"].add(restart)
                    coverage["old_noise"].add(old_wave == 6 and not old_alt)
                    coverage["buzz"].add(params.buzz)
                    coverage["noise"].add(params.noise)
                    coverage["detune"].add(params.detune)
                    coverage["dampen"].add(params.damp)
                    coverage["blend_count"].add(record.blend_count)
                expected, expected_dry = direct_sample_image(
                    memory, spar_bank=spar_bank, play_bits=play_bits,
                    music_playing=music_playing, reverb=reverb,
                    lfsr=lfsr, lfsr2=lfsr2, nz_tog=nz_tog, nz_tick=nz_tick,
                    aram_salt=aram_salt)
                machine = SampleImageMachine(
                    program, actions, list(memory), spar_bank=spar_bank,
                    play_bits=play_bits, music_playing=music_playing,
                    reverb=reverb, lfsr=lfsr, lfsr2=lfsr2,
                    nz_tog=nz_tog, nz_tick=nz_tick, aram_salt=aram_salt,
                    hold_selector=runs)
                counts = machine.run()
                assert counts[0:3] == (782, 172, 158), counts
                if machine.memory != expected:
                    mismatch = next(index for index, pair in
                                    enumerate(zip(machine.memory, expected))
                                    if pair[0] != pair[1])
                    raise AssertionError(
                        (case, spar_bank, reverb, mismatch,
                         machine.memory[mismatch], expected[mismatch]))
                assert machine.dry16 == expected_dry and machine.dry_valid == 1
                runs += 1
                slots += 8
                active += counts[0]
                transactions += counts[3]
                hold_checks += counts[4]
                held_labels.update(machine.hold_labels)
    assert runs == 64 and slots == 512 and active == 50_048
    assert transactions == 8_052
    assert hold_checks == runs
    assert held_labels == set(SAMPLE_HOLD_TARGETS)
    assert coverage["bank"] == {0, 1}
    assert coverage["reverb_build"] == {False, True}
    assert coverage["wave"] == set(range(8))
    for name in ("wavetable", "play", "hidden", "amplitude_zero", "restart",
                 "old_noise", "buzz", "noise"):
        assert coverage[name] == {False, True}, (name, coverage[name])
    assert coverage["detune"] == {0, 1, 2}
    assert coverage["dampen"] == {0, 1, 2}
    assert coverage["blend_count"] == {0, 1, 63, 64}
    return (f"{runs} production-image runs / {slots} slots / {active:,} active "
            f"instructions; {transactions:,} service transactions; "
            f"{hold_checks} external-hold freezes; persistent/scratch/fold/"
            "dry commits exact")


def validate_sample_arithmetic_contract() -> str:
    """Prove the bounded arithmetic identities used around retained services."""
    dq_cases = 0
    coefficients = {193, 250, 254, 255, 256, 384, 508}
    for wt in (False, True):
        for wave in range(8):
            for mode in range(3):
                if wt:
                    coefficient = 256
                elif wave == 0:
                    coefficient = (256, 193, 384)[mode]
                elif wave == 7:
                    coefficient = (254, 250, 508)[mode]
                else:
                    coefficient = 256 if mode == 0 else 255
                assert coefficient in coefficients
                for dp in range(1 << 13):
                    # Five radix-4 coefficient digits are the exact service
                    # recurrence expressed as a positional sum.
                    product = 0
                    for shift in range(0, 10, 2):
                        product += dp * ((coefficient >> shift) & 3) << shift
                    assert product == dp * coefficient
                    assert product >> 8 == (dp * coefficient) // 256
                    dq_cases += 1

    # Noise multiply: the service uses magnitude and then restores the sign
    # with floor semantics for a negative arithmetic right shift.
    noise_mul_cases = 0
    max_noise_step = 0
    for dp in range(1 << 13):
        jitter = (dp << 3) + 1120
        for random_step in range(-128, 128):
            product = jitter * abs(random_step)
            magnitude = product >> 8
            restored = (-magnitude - bool(product & 0xff)
                        if random_step < 0 else magnitude)
            reference = (jitter * random_step) // 256
            assert restored == reference
            max_noise_step = max(max_noise_step, abs(restored))
            noise_mul_cases += 1
    assert max_noise_step == 33_324

    # The old/live noise output shifts are exact small-constant multiplies.
    noise_scale_cases = 0
    for raw in range(1 << 18):
        signed = raw - (1 << 18) if raw & (1 << 17) else raw
        coarse = signed >> 6
        assert (coarse << 6) + (coarse << 2) == coarse * 68
        assert (coarse << 6) + (coarse << 4) == coarse * 80
        noise_scale_cases += 2

    # Positive amplitude boost and G formation are nested floor operations.
    gain_cases = 0
    for amplitude in range(1 << 12):
        for wt in (False, True):
            for wave in range(8):
                for mode in range(3):
                    boost = mode != 0 and not wt and not (
                        (wave & 4) and (wave & 2))
                    gain_a = amplitude + (amplitude >> 2) \
                        if boost else amplitude
                    gain = gain_a + (gain_a >> 1)
                    reference_a = (5 * amplitude) // 4 \
                        if boost else amplitude
                    assert gain_a == reference_a
                    assert gain == (3 * reference_a) // 2
                    gain_cases += 1

    def comb(value: int, history: int, enabled: bool) -> int:
        if not enabled:
            return value
        acc = 2 * value + history
        return (acc + (1 if acc < 0 else 0)) >> 1

    def blend(new: int, old: int, count: int) -> int:
        if count == 64:
            return new
        diff = new - old
        product = abs(diff) * count
        signed_product = -product if diff < 0 else product
        acc = old * 64 + signed_product
        return (acc + (63 if acc < 0 else 0)) >> 6

    def damp(value: int, previous: int, level: int) -> int:
        if level == 0:
            return value
        factor = 1 if level == 1 else 3
        divisor = 2 if level == 1 else 4
        acc = value + factor * previous
        correction = divisor - 1 if acc < 0 else 0
        return (acc + correction) >> (1 if level == 1 else 2)

    # Boundary vectors plus a deterministic full-width stream convict signed
    # truncation, bypass, count-64 and both dampen levels.
    arithmetic_cases = 0
    boundaries = (-(1 << 16), -32_768, -1, 0, 1,
                  32_767, (1 << 16) - 1)
    vectors = []
    for new in boundaries:
        for old in boundaries:
            for history in (-32_768, -1, 0, 1, 32_767):
                for count in range(65):
                    vectors.append((new, old, history, count))
    state = 0x5a17_3c29
    while len(vectors) < 262_144:
        state = (state * 1_664_525 + 1_013_904_223) & 0xffff_ffff
        new = (state & 0x1ffff) - 0x10000
        state = (state * 1_664_525 + 1_013_904_223) & 0xffff_ffff
        old = (state & 0x1ffff) - 0x10000
        history = ((state >> 16) & 0xffff) - 0x8000
        count = state % 65
        vectors.append((new, old, history, count))

    for new, old, history, count in vectors:
        for enabled in (False, True):
            got = comb(new, history, enabled)
            want = (trunc_zero(2 * new + history, 2)
                    if enabled else new)
            assert got == want
            arithmetic_cases += 1
        got_blend = blend(new, old, count)
        want_blend = (new if count == 64 else
                      trunc_zero(old * 64 + (new - old) * count, 64))
        assert got_blend == want_blend
        arithmetic_cases += 1
        for level in range(3):
            got_damp = damp(got_blend, old, level)
            want_damp = (got_blend if level == 0 else
                         trunc_zero(got_blend + (1 if level == 1 else 3)
                                    * old, 2 if level == 1 else 4))
            assert got_damp == want_damp
            arithmetic_cases += 1

    total = (dq_cases + noise_mul_cases + noise_scale_cases
             + gain_cases + arithmetic_cases)
    return (f"{total:,} DQ/noise/gain/comb/blend/dampen formulas; "
            f"noise step <= {max_noise_step:,}; signed truncation exact")


def remaining_owner_action_inventory(nodes: list[Node]) -> str:
    """Separate proved transactions from every owner-one placeholder site."""
    names = {node.name for node in nodes}
    advance = {"K_ADV", "EA0", "EA1", "EA2", "EA3", "EA4", "EA5"}
    movement = ({f"V_LD{i}" for i in range(8)}
                | {f"V_ST{i}" for i in range(5)}
                | {"K_ROT", "PC0", "PC1", "PC2", "PC3"})
    publication = {"P_W0", "P_W1", "P_W2", "P_W3"}
    remaining = names - advance - movement - publication
    assert len(names) == 85
    assert len(advance) == 7 and advance <= names
    assert len(movement) == 18 and movement <= names
    assert len(publication) == 4 and publication <= names
    assert len(remaining) == 56

    trigger_note = ({f"T_{name}" for name in ("FL", "SP", "LS", "LE",
                                               "NL", "NH", "LD")}
                    | {"K_NL", "K_NH", "K_LD"}
                    | {f"I_TR{i}" for i in range(5)}
                    | {"I_TW", "I_NL", "I_NH", "I_LD"})
    effect = ({"ES0", "ES1", "ES2", "K_ARP", "K_ARPC", "K_PF0"}
              | {f"K_FX{i}" for i in range(12)}
              | {f"K_SL{i}" for i in range(9)})
    flow = ({"S_IDLE", "W_MUS", "ML_STOP", "ML_RD0", "MS_RD", "MS_CK"}
            | {f"ML_L{i}" for i in range(4)})
    assert (len(trigger_note), len(effect), len(flow)) == (19, 27, 10)
    assert remaining == trigger_note | effect | flow
    return ("owner-one: 18 proved memory transactions, 4 address-only "
            "publication sites, 56 placeholders (19 trigger/note, 27 effect/"
            "service, 10 music flow); completion/arbitration still external")


def validate_condition_contract(sample_program: list[int],
                                tick_program: list[int]) -> str:
    sample_conds = {
        Instruction.decode(word).cond
        for word in sample_program
        if Instruction.decode(word).op == Op.BRANCH
    }
    tick_conds = {
        Instruction.decode(word).cond
        for word in tick_program
        if Instruction.decode(word).op == Op.BRANCH
    }
    assert sample_conds == {COND_SAMPLE_SLOT_WRAP}
    assert not (sample_conds | tick_conds) & set(range(4, 8))
    assert {COND_TRIG, COND_ADVANCE, COND_INS_USE, COND_RELEASED} \
        <= tick_conds
    return ("owner-zero slot-wrap is external condition 8; owner-one exact "
            "advance predicates occupy external conditions 8..11; common "
            "Z/N/C/V remain 0..3 and hard-zero 4..7 are unused")


def validate_public_priority(seq: str) -> str:
    """Pin the source-order/NBA priority that one future adapter must retain."""
    start = seq.index("// Main controller.")
    end = seq.index("// Register-resident record words", start)
    owner = seq[start:end]
    tokens = (
        "if (ptick_pend && !m_busy)",
        "if (tick_en_d)",
        "case (sst)",
        "if (pre_tick)",
        "if (cs && rw && addr[7:4] == 4'h1)",
        "if (cs && rw && addr == 8'h21)",
    )
    positions = [owner.index(token) for token in tokens]
    assert positions == sorted(positions)

    layers = ("service", "boundary", "action", "pre_tick", "cpu", "tail")
    rank = {name: n for n, name in enumerate(layers)}
    winner_sets = (
        (("service", "action"), "action"),
        (("boundary", "action"), "action"),
        (("action", "pre_tick"), "pre_tick"),
        (("action", "cpu"), "cpu"),
        (("pre_tick", "cpu"), "cpu"),
        (("cpu", "tail"), "tail"),
    )
    for contenders, expected in winner_sets:
        assert max(contenders, key=rank.__getitem__) == expected
    return "public priority: " + " < ".join(layers)


def serialize_program(words: list[int]) -> str:
    """Return the controller's complete plain-hex memory image."""
    assert len(words) == PROGRAM_BANKS * PROGRAM_BANK_WORDS
    assert all(0 <= word <= 0xffff for word in words)
    return "".join(f"{word:04x}\n" for word in words)


def write_candidate_image(path: Path, accepted: list[int],
                          sample_candidate: list[int],
                          tick_program: list[int]) -> str:
    """Materialize the bounded D2F candidate without touching production."""
    output = path.resolve()
    assert output != IMAGE.resolve(), \
        "candidate output must not replace rtl/psg_exec.hex"
    if output.exists():
        assert not output.samefile(IMAGE), \
            "candidate output must not hard-link rtl/psg_exec.hex"
    assert len(accepted) == PROGRAM_BANKS * PROGRAM_BANK_WORDS
    assert len(sample_candidate) == PROGRAM_BANK_WORDS
    assert len(tick_program) == PROGRAM_BANK_WORDS

    candidate = list(sample_candidate) + list(tick_program)
    lower_changes = [index for index in range(PROGRAM_BANK_WORDS)
                     if candidate[index] != accepted[index]]
    upper_changes = [index for index in range(PROGRAM_BANK_WORDS,
                                               len(candidate))
                     if candidate[index] != accepted[index]]
    assert len(lower_changes) == 44
    assert not upper_changes
    assert sum(word != 0 for word in candidate[:PROGRAM_BANK_WORDS]) == 222

    production_before = IMAGE.read_bytes()
    image = serialize_program(candidate)
    # A second serializer invocation pins stable same-input formatting.  The
    # gate runs the complete generator twice to prove whole-run determinism.
    image_again = serialize_program(
        list(sample_candidate) + list(tick_program))
    assert image_again == image

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(image)
    readback = output.read_text()
    assert readback == image
    lines = readback.splitlines()
    assert len(lines) == PROGRAM_BANKS * PROGRAM_BANK_WORDS
    assert all(re.fullmatch(r"[0-9a-f]{4}", line) for line in lines)
    assert [int(line, 16) for line in lines] == candidate
    assert IMAGE.read_bytes() == production_before
    return (f"{output}: 512 words, 44 owner-zero differences, "
            "0 owner-one differences, 222 owner-zero nonzero words")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="build and validate the R.84 executor control contract")
    parser.add_argument(
        "--write", action="store_true",
        help="regenerate the accepted production image")
    parser.add_argument(
        "--candidate-out", type=Path,
        help="write the complete bounded D2F candidate to this separate path")
    args = parser.parse_args()
    if args.write and args.candidate_out:
        parser.error("--write and --candidate-out are mutually exclusive")
    return args


def main() -> int:
    args = parse_args()
    seq, walk, _ = legacy_contract()
    states = sequencer_states(seq)
    successors = state_successors(seq, states)
    actions = Actions()
    sample_program = [0] * PROGRAM_BANK_WORDS
    tick_program = [0] * PROGRAM_BANK_WORDS
    sample_labels = build_sample(actions, sample_program)

    seq_nodes = expand_sequencer(states, successors, actions)
    tick_nodes, flow_nodes = split_pages(seq_nodes)
    movement = tick_movement_inventory(seq_nodes)
    move_rtl = validate_move_rtl_contract()
    replaced_actions = {"K_ADV", "EA0", "EA1", "EA2", "EA3", "EA4",
                        "EA5"}
    for code in ADV_ACTION.values():
        old = actions.get("tick", code)
        assert old is None or old.name in replaced_actions, \
            f"advance action {code:02x} collides with retained {old.name}"
    labels, voice_used, instrument_used, normalized_used = emit_advance(
        tick_program, tick_nodes, flow_nodes)
    advance_transactions = validate_advance_transactions(tick_program, labels)
    program = sample_program + tick_program

    validate_instruction_codec(program)
    validate_explicit_emission()
    validate_node_contract(seq_nodes, tick_program)
    sample_cycles, sample_spare, sample_used = validate_sample(
        sample_program, actions, sample_labels)
    sample_waits = validate_sample_wait_manifest(sample_program,
                                                 sample_labels)
    sample_tail_gap = validate_sample_fixed_tail_gap(sample_program, actions,
                                                     sample_labels)
    sample_relocated, sample_candidate = validate_sample_relocated_commit_manifest(
        sample_program, actions, sample_labels)
    sample_value_gap = validate_sample_relocated_value_gap(sample_candidate)
    sample_stream, sample_stream_candidate = \
        validate_sample_relocated_stream_correction(
            sample_program, sample_candidate, actions)
    sample_blend_gap = validate_sample_d2c_blend_gap(sample_stream_candidate)
    sample_blend, sample_blend_candidate = \
        validate_sample_typed_blend_correction(
            sample_program, sample_stream_candidate)
    sample_overlay = validate_sample_context_path_bound(
        sample_blend_candidate)
    sample_physical_gap = validate_sample_physical_w2_gap(
        sample_blend_candidate, actions)
    sample_w5_q16, sample_w5_q16_candidate = \
        build_sample_w5_q16_candidate(
            sample_program, sample_blend_candidate, actions)
    sample_b3b2a, sample_b3b2a_candidate, sample_b3b2a_codec = \
        validate_sample_b3b2a_slice_map(
            sample_program, sample_w5_q16_candidate, actions)
    sample_b3b2a2a1 = validate_sample_b3b2a2a1_edge_services(
        sample_b3b2a_candidate, actions, sample_b3b2a_codec)
    sample_d2fb_packing = validate_sample_d2fb_packing(
        sample_b3b2a_candidate, actions)
    sample_d2fca_manifest = validate_sample_d2fca_manifest(
        sample_b3b2a_candidate, actions)
    sample_b1_roots = validate_sample_b1_atomic_root_manifest(
        sample_b3b2a_candidate, actions)
    sample_inventory = validate_sample_action_inventory(actions,
                                                        sample_program)
    fold_contract = validate_fold_word_contract()
    fold_arithmetic = validate_fold_arithmetic_contract()
    sample_pool = validate_sample_pool_contract()
    phase_substitution = validate_phase_substitution_contract()
    sample_arithmetic = validate_sample_arithmetic_contract()
    sample_semantics = validate_sample_image_semantics(sample_program, actions)
    owner_inventory = remaining_owner_action_inventory(seq_nodes)
    condition_contract = validate_condition_contract(sample_program,
                                                     tick_program)
    public_priority = validate_public_priority(seq)
    reachable_to_idle(seq_nodes)
    addresses = state_address_inventory(seq)
    commits = output_commit_inventory(seq, walk)
    advance_cases = validate_advance_semantics()

    # Branches and jumps never cross an owner-selected bank.  OP_OWNER is the
    # only instruction allowed to select the other bank for the next fetch.
    bank_contracts = (
        (OWNER_SAMPLE, sample_program, set(sample_labels)),
        (OWNER_TICK, tick_program, set(labels.values())),
    )
    for owner, bank, live_pcs in bank_contracts:
        assert len(bank) == PROGRAM_BANK_WORDS
        for pc, word in enumerate(bank):
            insn = Instruction.decode(word)
            if insn.op in (Op.BRANCH, Op.JUMP) and word != 0:
                assert insn.target in live_pcs, \
                    f"owner {owner} pc {pc:02x}: target " \
                    f"{insn.target:02x} is not a same-bank label"

    assert len(program) == PROGRAM_BANKS * PROGRAM_BANK_WORDS
    assert sample_used == 222
    assert voice_used + instrument_used == 117
    assert normalized_used == 226
    assert normalized_used <= PROGRAM_BANK_WORDS

    print("R.84H-A addressed-state/service manifest contract: PASS")
    print(f"sample bank: {sample_used}/256 words, {sample_cycles}/"
          f"{SAMPLE_CLOCK_LIMIT} conservative clocks, {sample_spare} spare")
    print(f"tick/flow bank: {normalized_used}/256 words "
          f"({voice_used} voice/K_ADV + {instrument_used} instrument + "
          "83 remaining tick + 26 flow); 30 spare")
    print(f"normalized advance semantics: {advance_cases:,} decomposed cases")
    print(f"normalized synchronous transactions: {advance_transactions:,} "
          "counter-domain and path-complete cases")
    print(f"normalized advance actions: {len(ADV_ACTION)} fixed + 4 common")
    print(f"legacy sequencer: {len(states)} states -> {len(seq_nodes)} PC nodes; "
          "all nodes can reach S_IDLE")
    lowered = sum(node.lowered for node in seq_nodes)
    print(f"explicit branch IR: 117 exact advance words; {lowered} other "
          f"lowered / {len(seq_nodes) - 7 - lowered} visibly unlowered nodes")
    for line in actions.report():
        print(line)
    print("state words: " + ",".join(str(n) for n in addresses)
          + "; scratch 34..63")
    print("tick record movement: " + movement)
    print("fixed decoder RTL: " + move_rtl)
    print("sample action inventory: " + sample_inventory)
    print("sample stored-wait manifest: " + sample_waits)
    print("sample fixed-tail manifest: " + sample_tail_gap)
    print("sample relocated-commit manifest: " + sample_relocated)
    print("sample relocated-value gate: " + sample_value_gap)
    print("sample corrected-stream manifest: " + sample_stream)
    print("sample corrected-stream blend gate: " + sample_blend_gap)
    print("sample typed-blend manifest: " + sample_blend)
    print("sample context-overlay gate: " + sample_overlay)
    print("sample physical-allocation gate: " + sample_physical_gap)
    print("sample W5-q16 candidate: " + sample_w5_q16)
    print("sample B3-B2-A1 slice map: " + sample_b3b2a)
    print("sample B3-B2-A2-A1 services: " + sample_b3b2a2a1)
    print("sample D2F-B packing: " + sample_d2fb_packing)
    print("sample D2F-C-A manifest: " + sample_d2fca_manifest)
    print("sample B1-A atomic inventory: " + sample_b1_roots)
    print("sample transient pool: " + sample_pool)
    print("sample phase substitution: " + phase_substitution)
    print("sample arithmetic: " + sample_arithmetic)
    print("sample image semantics: " + sample_semantics)
    print("fold word/tree contract: " + fold_contract)
    print("fold arithmetic contract: " + fold_arithmetic)
    print("remaining owner action inventory: " + owner_inventory)
    print("condition contract: " + condition_contract)
    print(public_priority)
    print("externally visible commits: " + ",".join(commits))
    image = serialize_program(program)
    if args.write:
        IMAGE.write_text(image)
        print(f"wrote {IMAGE.relative_to(ROOT)}")
    else:
        assert IMAGE.exists(), f"{IMAGE}: missing; run with --write"
        assert IMAGE.read_text() == image, \
            f"{IMAGE}: stale; regenerate with --write"
        print(f"image: {IMAGE.relative_to(ROOT)} byte-identical")
    if args.candidate_out:
        print("candidate image: " + write_candidate_image(
            args.candidate_out, program, sample_b3b2a_candidate,
            tick_program))
    print("warning: owner-zero actions and remaining owner-one actions are "
          "manifests, not semantic RTL; whole-PSG schedule/render/area "
          "equivalence remain atomic integration gates")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
