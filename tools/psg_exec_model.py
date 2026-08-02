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

import re
import runpy
import sys
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path

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


def main() -> int:
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
    sample_inventory = validate_sample_action_inventory(actions,
                                                        sample_program)
    fold_contract = validate_fold_word_contract()
    fold_arithmetic = validate_fold_arithmetic_contract()
    sample_pool = validate_sample_pool_contract()
    phase_substitution = validate_phase_substitution_contract()
    sample_arithmetic = validate_sample_arithmetic_contract()
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
    print("sample transient pool: " + sample_pool)
    print("sample phase substitution: " + phase_substitution)
    print("sample arithmetic: " + sample_arithmetic)
    print("fold word/tree contract: " + fold_contract)
    print("fold arithmetic contract: " + fold_arithmetic)
    print("remaining owner action inventory: " + owner_inventory)
    print("condition contract: " + condition_contract)
    print(public_priority)
    print("externally visible commits: " + ",".join(commits))
    image = "".join(f"{word:04x}\n" for word in program)
    if "--write" in sys.argv[1:]:
        IMAGE.write_text(image)
        print(f"wrote {IMAGE.relative_to(ROOT)}")
    else:
        assert IMAGE.exists(), f"{IMAGE}: missing; run with --write"
        assert IMAGE.read_text() == image, \
            f"{IMAGE}: stale; regenerate with --write"
        print(f"image: {IMAGE.relative_to(ROOT)} byte-identical")
    print("warning: owner-zero actions and remaining owner-one actions are "
          "manifests, not semantic RTL; whole-PSG schedule/render/area "
          "equivalence remain atomic integration gates")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
