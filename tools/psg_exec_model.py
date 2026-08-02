#!/usr/bin/env python3
"""Build and validate the R.84 address-state executor control contract.

This is deliberately a control/data-movement model, not an audio model.  It
answers the questions that must be closed before replacing psg_walk/psg_seq:

* do two owner-selected 256x16 banks hold the sample and tick/flow programs;
* can the 64-word sample page represent every persistent read/write and the
  ordered fold without reintroducing pph;
* do synchronous state reads line up with the action that consumes them;
* do all branch/jump targets and per-slot state words stay in range;
* can every sequencer control state still reach S_IDLE after xs/vcnt become PC;
* what hard clock headroom remains for address-state operand micro-operations.

The action field is structured as family[2:0]:subop[3:0].  Sample and tick
owners interpret it independently, so neither owner gets a flat 256-way PC
decode.  Arithmetic semantics remain in the established formula/service gates;
this model must not be cited as behavioral equivalence or as a whole-PSG area
result.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEQ = ROOT / "rtl" / "psg_seq.sv"
WALK = ROOT / "rtl" / "psg_walk.sv"
COMMON = ROOT / "rtl" / "psg_common.svh"
IMAGE = ROOT / "rtl" / "psg_exec.hex"

PAGE_SAMPLE = range(0x00, 0x40)
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
    wait: int = 0

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
            *, subop: int | None = None, consumes: int | None = None,
            wait: int = 0) -> int:
        key = (owner, family)
        if subop is None:
            subop = self.next_sub.get(key, 0)
        assert 0 <= family < 8 and 0 <= subop < 16, \
            f"{owner} action family {family} exceeds sixteen subops"
        action = Action(owner, family, subop, name, consumes, wait)
        assert action.code not in self.by_owner[owner]
        self.by_owner[owner][action.code] = action
        self.next_sub[key] = max(self.next_sub.get(key, 0), subop + 1)
        return action.code

    def pin(self, owner: str, code: int, name: str,
            *, consumes: int | None = None, wait: int = 0) -> int:
        assert 0 <= code < 128
        return self.add(owner, code >> 4, name, subop=code & 15,
                        consumes=consumes, wait=wait)

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
        cases += 3

    return cases


def build_sample(actions: Actions, program: list[int]) -> dict[int, str]:
    labels: dict[int, str] = {}

    def put(pc: int, insn: Instruction, label: str) -> None:
        assert pc in PAGE_SAMPLE and program[pc] == 0
        program[pc] = insn.encode()
        labels[pc] = label

    # Slot-wrap branch. start_pc is 1, so address zero is only reached after
    # OP_SLOT has advanced the completed slot. cond0 means the 3-bit slot
    # wrapped to zero after slot seven.
    put(0, Instruction(Op.BRANCH, cond=0, target=54), "slot_wrap")

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
    for i, (word, code) in enumerate(zip(reads, consume_codes), start=1):
        put(i, Instruction(Op.READ, action=code, word=word),
            f"read_{word}")

    # The first service action also consumes the final pipelined parameter
    # read. Four extra clocks on each noise action state the five-edge dq/noise
    # transaction without storing those idle clocks in the program EBR.
    nz_old = actions.add("sample", 2, "NZ_OLD_LOAD_PAR_3",
                         consumes=27, wait=4)
    nz_live = actions.add("sample", 2, "NZ_LIVE", wait=4)
    put(19, Instruction(Op.EXEC, action=nz_old), "nz_old")
    put(20, Instruction(Op.EXEC, action=nz_live), "nz_live")

    caps = ["W0", "W1", "W2", "W3", "W4", "W5", "W6", "W15",
            "W26", "W27", "W40", "W51", "W75", "W84"]
    for i, name in enumerate(caps, start=21):
        # Seven conservative wait credits restore the full accepted 68-phase
        # single-clock visit when combined with the two five-edge noise waits.
        wait = 7 if name == "W84" else 0
        code = actions.add("sample", 2, f"CAP_{name}", wait=wait)
        put(i, Instruction(Op.EXEC, action=code), f"cap_{name}")

    store_words = list(range(10, 24)) + [15, 14]
    for i, word in enumerate(store_words, start=35):
        code = actions.add("sample", 3 if i < 49 else 4,
                           f"STORE_{i - 35}_{word}")
        put(i, Instruction(Op.WRITE, action=code, word=word),
            f"store_{word}")
    leaf = actions.add("sample", 4, "STORE_LEAF")
    put(51, Instruction(Op.WRITE, action=leaf, word=48), "store_leaf")
    put(52, Instruction(Op.SLOT, slot_inc=True), "slot_inc")
    put(53, Instruction(Op.JUMP, target=0), "slot_loop")

    fold_setup = actions.add("sample", 5, "FOLD_SETUP")
    fold_ra = actions.add("sample", 5, "FOLD_READ_A")
    fold_rb = actions.add("sample", 5, "FOLD_READ_B")
    fold_start = actions.add("sample", 5, "FOLD_START")
    fold_run = actions.add("sample", 5, "FOLD_RUN", wait=8)
    fold_write = actions.add("sample", 5, "FOLD_WRITE")
    put(54, Instruction(Op.EXEC, action=fold_setup), "fold_setup")
    put(55, Instruction(Op.READ, action=fold_ra, word=48), "fold_read_a")
    put(56, Instruction(Op.READ, action=fold_rb, word=48), "fold_read_b")
    put(57, Instruction(Op.EXEC, action=fold_start), "fold_start")
    put(58, Instruction(Op.EXEC, action=fold_run), "fold_run")
    put(59, Instruction(Op.WRITE, action=fold_write, word=44), "fold_write")
    put(60, Instruction(Op.BRANCH, cond=1, target=55), "fold_more")
    put(61, Instruction(Op.DONE), "sample_done")
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
    fold_remaining = 0
    cycles = 0
    writes: list[tuple[int, int]] = []
    visits = 0
    for _ in range(4000):
        insn = Instruction.decode(program[pc])
        action = actions.get("sample", insn.action) \
            if insn.op in (Op.READ, Op.WRITE, Op.EXEC) else None
        if action and action.consumes is not None:
            assert pending == action.consumes, \
                f"pc {pc}: {action.name} consumes {pending}, expected " \
                f"{action.consumes}"
            pending = None
        if action:
            cycles += action.wait
            if action.name == "FOLD_SETUP":
                fold_remaining = 7
            elif action.name == "FOLD_WRITE":
                assert fold_remaining > 0
                fold_remaining -= 1

        cycles += 1
        if insn.op == Op.READ:
            pending = insn.word
            pc = (pc + 1) & 0xFF
        elif insn.op == Op.WRITE:
            writes.append((slot, insn.word))
            pc = (pc + 1) & 0xFF
        elif insn.op == Op.EXEC:
            pc = (pc + 1) & 0xFF
        elif insn.op == Op.SLOT:
            slot = (slot + 1) & 7 if insn.slot_inc else insn.slot_value
            visits += 1
            pc = (pc + 1) & 0xFF
        elif insn.op == Op.JUMP:
            pc = insn.target
        elif insn.op == Op.BRANCH:
            take = (insn.cond == 0 and slot == 0) \
                or (insn.cond == 1 and fold_remaining > 0)
            pc = insn.target if take == bool(insn.sense) else (pc + 1) & 0xFF
        elif insn.op == Op.DONE:
            break
        else:
            raise AssertionError(f"unexpected sample op {insn.op}")
    else:
        raise AssertionError("sample program did not terminate")

    assert visits == 8 and slot == 0 and fold_remaining == 0
    expected = list(range(10, 24)) + [15, 14, 48]
    for voice in range(8):
        actual = [word for owner, word in writes
                  if owner == voice and word != 44]
        assert actual == expected, (voice, actual, expected)
    assert [(owner, word) for owner, word in writes if word == 44] \
        == [(0, 44)] * 7
    assert cycles < SAMPLE_CLOCK_LIMIT
    return cycles, SAMPLE_CLOCK_LIMIT - cycles, len(labels)


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

    # K_ADV drains V_LD7's repeated word 26.  P_W3 and PC3 are the two
    # immediate V_ST0 predecessors and prime scratch word 48 after their
    # current state_q value has been consumed; K_ROT is not adjacent.
    assert by_name["K_ADV"].action == 0x40
    assert by_name["P_W3"].action == 0x56
    assert by_name["PC3"].action == 0x5A
    assert by_name["P_W3"].successors == ["V_ST0"]
    assert by_name["PC3"].successors == ["V_ST0"]
    assert by_name["K_ROT"].successors == ["PC0"]
    return ("loads 3,4,5,8,9,26,32 -> scratch 48..54; "
            "stores scratch 48,49,50,52,54 -> 3,4,5,9,32; "
            "0 extra hold clocks")


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
    replaced_actions = {"K_ADV", "EA0", "EA1", "EA2", "EA3", "EA4",
                        "EA5"}
    for code in ADV_ACTION.values():
        old = actions.get("tick", code)
        assert old is None or old.name in replaced_actions, \
            f"advance action {code:02x} collides with retained {old.name}"
    labels, voice_used, instrument_used, normalized_used = emit_advance(
        tick_program, tick_nodes, flow_nodes)
    program = sample_program + tick_program

    validate_instruction_codec(program)
    validate_explicit_emission()
    validate_node_contract(seq_nodes, tick_program)
    sample_cycles, sample_spare, sample_used = validate_sample(
        sample_program, actions, sample_labels)
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
    assert sample_used == 62
    assert voice_used + instrument_used == 117
    assert normalized_used == 226
    assert normalized_used <= PROGRAM_BANK_WORDS

    print("R.84G-E normalized advance control contract: PASS")
    print(f"sample bank: {sample_used}/256 words, {sample_cycles}/"
          f"{SAMPLE_CLOCK_LIMIT} conservative clocks, {sample_spare} spare")
    print(f"tick/flow bank: {normalized_used}/256 words "
          f"({voice_used} voice/K_ADV + {instrument_used} instrument + "
          "83 remaining tick + 26 flow); 30 spare")
    print(f"normalized advance semantics: {advance_cases:,} decomposed cases")
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
    print("warning: control/data-movement proof only; arithmetic and render "
          "equivalence remain integration gates")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
