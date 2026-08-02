#!/usr/bin/env python3
"""Build and validate the R.84 address-state executor control contract.

This is deliberately a control/data-movement model, not an audio model.  It
answers the questions that must be closed before replacing psg_walk/psg_seq:

* does one 256x16 image hold the sample, tick/effect, and trigger/music pages;
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
from dataclasses import dataclass, field
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
            *, consumes: int | None = None, wait: int = 0) -> int:
        key = (owner, family)
        subop = self.next_sub.get(key, 0)
        assert 0 <= family < 8 and subop < 16, \
            f"{owner} action family {family} exceeds sixteen subops"
        action = Action(owner, family, subop, name, consumes, wait)
        assert action.code not in self.by_owner[owner]
        self.by_owner[owner][action.code] = action
        self.next_sub[key] = subop + 1
        return action.code

    def get(self, owner: str, code: int) -> Action | None:
        return self.by_owner[owner].get(code)

    def report(self) -> list[str]:
        out = []
        for owner in ("sample", "tick"):
            counts = [self.next_sub.get((owner, family), 0)
                      for family in range(8)]
            out.append(f"{owner} actions {sum(counts)}; family occupancy "
                       + "/".join(str(n) for n in counts))
        return out


@dataclass
class Node:
    name: str
    base: str
    successors: list[str] = field(default_factory=list)
    op: Op = Op.EXEC
    word: int = 0
    action: int = 0


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
                nodes.append(Node(name, state, nxt, Op.READ, word, code))
            continue
        if state == "V_ST":
            for i, word in enumerate(vst_words):
                name = f"V_ST{i}"
                nxt = [f"V_ST{i + 1}"] if i + 1 < len(vst_words) \
                    else [entry(s) for s in succ[state]]
                code = actions.add("tick", 0, name)
                nodes.append(Node(name, state, nxt, Op.WRITE, word, code))
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
                nodes.append(Node(name, state, edges[i], Op.EXEC, 0, code))
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
        nodes.append(Node(state, state, nexts, op, word, code))
    assert len({n.name for n in nodes}) == len(nodes)
    return nodes


def split_pages(nodes: list[Node]) -> tuple[list[Node], list[Node]]:
    flow_base = {"S_IDLE", "W_MUS", "ML_STOP", "ML_RD0", "ML_L0",
                 "ML_L1", "ML_L2", "ML_L3", "MS_RD", "MS_CK",
                 "T_FL", "T_SP", "T_LS", "T_LE", "T_NL", "T_NH",
                 "T_LD"}
    tick = [n for n in nodes if n.base not in flow_base]
    flow = [n for n in nodes if n.base in flow_base]
    return tick, flow


def block_size(node: Node, next_name: str | None) -> int:
    successors = list(dict.fromkeys(node.successors))
    if not successors:
        return 2
    if len(successors) == 1:
        return 1 if successors[0] == next_name else 2
    default = successors[-1]
    return 1 + len(successors) - 1 + (default != next_name)


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
        successors = list(dict.fromkeys(node.successors))
        nxt = nodes[i + 1].name if i + 1 < len(nodes) else None
        if not successors:
            program[pc] = Instruction(Op.DONE).encode()
            pc += 1
        elif len(successors) == 1:
            if successors[0] != nxt:
                program[pc] = Instruction(Op.JUMP,
                                          target=labels[successors[0]]).encode()
                pc += 1
        else:
            for cond, target in enumerate(successors[:-1]):
                program[pc] = Instruction(Op.BRANCH, cond=cond,
                                          target=labels[target]).encode()
                pc += 1
            if successors[-1] != nxt:
                program[pc] = Instruction(Op.JUMP,
                                          target=labels[successors[-1]]).encode()
                pc += 1
    return pc - page.start


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
    program = [0] * 256
    sample_labels = build_sample(actions, program)

    seq_nodes = expand_sequencer(states, successors, actions)
    tick_nodes, flow_nodes = split_pages(seq_nodes)
    tick_labels = layout(tick_nodes, PAGE_TICK)
    flow_labels = layout(flow_nodes, PAGE_FLOW)
    labels = {**tick_labels, **flow_labels}
    tick_used = emit(tick_nodes, PAGE_TICK, labels, program)
    flow_used = emit(flow_nodes, PAGE_FLOW, labels, program)

    validate_instruction_codec(program)
    sample_cycles, sample_spare, sample_used = validate_sample(
        program, actions, sample_labels)
    reachable_to_idle(seq_nodes)
    addresses = state_address_inventory(seq)
    commits = output_commit_inventory(seq, walk)

    # Every emitted branch/jump target must name a compiled instruction.
    live_pcs = set(sample_labels) | set(tick_labels.values()) \
        | set(flow_labels.values())
    for pc, word in enumerate(program):
        insn = Instruction.decode(word)
        if insn.op in (Op.BRANCH, Op.JUMP) and word != 0:
            assert insn.target in live_pcs, \
                f"pc {pc:02x}: target {insn.target:02x} is not a label"

    print("R.84C executor contract: PASS")
    print(f"sample page: {sample_used}/64 words, {sample_cycles}/"
          f"{SAMPLE_CLOCK_LIMIT} conservative clocks, {sample_spare} spare")
    print(f"tick/effect page: {tick_used}/128 words; "
          f"trigger/music page: {flow_used}/64 words")
    print(f"legacy sequencer: {len(states)} states -> {len(seq_nodes)} PC nodes; "
          "all nodes can reach S_IDLE")
    for line in actions.report():
        print(line)
    print("state words: " + ",".join(str(n) for n in addresses)
          + "; scratch 34..63")
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
