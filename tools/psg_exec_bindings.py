#!/usr/bin/env python3
"""Check the R.84 candidate-to-live-RTL structural binding contract.

This checker deliberately does not execute sample arithmetic.  It joins the
metadata-only candidate manifest to source events observed at the live HX8K
walker, radix-2 multiplier/DQ primitives and production-image wave/ARAM
executor boundaries.  Semantic sample values and final expected outputs are
outside this proof.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Callable, Iterable


Json = dict[str, Any]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def load_json(path: Path) -> Json:
    value = json.loads(path.read_text())
    require(isinstance(value, dict), f"{path}: expected one JSON object")
    return value


def load_jsonl(path: Path) -> list[Json]:
    rows: list[Json] = []
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        if not line:
            continue
        value = json.loads(line)
        require(isinstance(value, dict),
                f"{path}:{line_number}: expected a JSON object")
        rows.append(value)
    require(bool(rows), f"{path}: empty trace")
    return rows


def forbidden_manifest_fields(value: Any, path: str = "$") -> list[str]:
    forbidden: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            if key in {"value", "expected", "result", "sample_trace"}:
                forbidden.append(f"{path}.{key}")
            forbidden.extend(forbidden_manifest_fields(child, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            forbidden.extend(forbidden_manifest_fields(child,
                                                        f"{path}[{index}]"))
    return forbidden


def pair_trace(rows: list[Json], key_fields: tuple[str, ...]) \
        -> list[tuple[Json, Json]]:
    grouped: dict[tuple[Any, ...], dict[str, Json]] = defaultdict(dict)
    for row in rows:
        key = tuple(row[field] for field in key_fields)
        phase = row["phase"]
        require(phase in {"pre", "post"}, f"bad phase {phase!r} at {key}")
        require(phase not in grouped[key], f"duplicate {phase} row at {key}")
        grouped[key][phase] = row
    pairs = []
    for key, phases in grouped.items():
        require(set(phases) == {"pre", "post"},
                f"incomplete pre/post pair at {key}: {set(phases)}")
        pairs.append((phases["pre"], phases["post"]))
    return pairs


def check_manifest(manifest: Json) -> None:
    require(manifest.get("schema") == "psg_exec_binding_v1",
            "wrong binding manifest schema")
    encoded = json.dumps(manifest, sort_keys=True)
    require("SampleTrace" not in encoded and "evaluate_sample_slot" not in encoded,
            "manifest names a forbidden semantic oracle")
    forbidden = forbidden_manifest_fields(manifest)
    require(not forbidden, f"manifest carries semantic fields: {forbidden}")

    counts = manifest["counts"]
    require(counts == {"actions": 61, "changed_pcs": 44,
                       "fixed_writes": 18, "groups": 27, "roots": 30},
            f"unexpected manifest counts: {counts}")
    source = manifest["source_contract"]
    require(source["target"] == "ice40-hx8k"
            and source["target_multipump"] == 1,
            "manifest is not bound to the multi-pumped HX8K target")
    require(len(source["cap_indices"]) == 14,
            "manifest must bind all fourteen CAP events")
    require(len(source["fold_nodes"]) == 7,
            "manifest must bind all seven ordered fold nodes")

    actions = manifest["actions"]
    require(len(actions) == 61, "action row count")
    require(len({row["name"] for row in actions}) == 61,
            "action names are not unique")
    require(len({row["code"] for row in actions}) == 61,
            "action codes are not unique")
    require(Counter(row["family"] for row in actions)
            == Counter({"load": 18, "service": 16,
                        "store": 18, "fold": 9}),
            "action family counts changed")
    for row in actions:
        require(row.get("source_binding"),
                f"action {row['name']} lacks a source binding")
        if row.get("retired_replacement"):
            require(not row["occurrences"],
                    f"retired action {row['name']} still has a PC")
            require(row["source_binding"]["event"] == "retired_alias",
                    f"retired action {row['name']} is not explicit")
        else:
            require(bool(row["occurrences"]),
                    f"live action {row['name']} has no reachable occurrence")
        for occurrence in row["occurrences"]:
            require(0 < occurrence["pc"] <= 0xdd,
                    f"action {row['name']} names unexecuted PC")

    changed = manifest["candidate_changed_pcs"]
    bindings = manifest["changed_pc_bindings"]
    require(len(changed) == len(set(changed)) == 44, "changed-PC set")
    require({row["pc"] for row in bindings} == set(changed),
            "changed-PC bindings are incomplete")
    action_names = {row["name"] for row in actions}
    for row in bindings:
        binding = row.get("source_binding", {})
        require(binding.get("event") in {"action", "fixed_hold"},
                f"PC {row['pc']:02x} has an untyped binding")
        if binding["event"] == "action":
            require(binding.get("action") in action_names,
                    f"PC {row['pc']:02x} names an unknown action")

    roots = manifest["roots"]
    require(len(roots) == 30 and len({row["name"] for row in roots}) == 30,
            "root set")
    require(len({row["group"] for row in roots}) == 27,
            "root group count")
    for row in roots:
        require(row["width"] > 0 and row["owner"] and row["guard"],
                f"root {row['name']} is not typed")
        require(row["producer_pcs"] and row["consumer_pcs"],
                f"root {row['name']} lacks candidate endpoints")
        require(row.get("source_binding"),
                f"root {row['name']} lacks a source binding")

    writes = manifest["fixed_writes"]
    require(len(writes) == 18 and len({row["pc"] for row in writes}) == 18,
            "fixed-write manifest")
    for row in writes:
        require(row.get("source_binding"),
                f"fixed write {row['action']} lacks a source binding")


def cap_mask(manifest: Json, name: str) -> int:
    return 1 << int(manifest["source_contract"]["cap_indices"][name])


def rows_for_event(manifest: Json, legacy: list[Json], event: str) -> list[Json]:
    if event == "LOAD":
        return [row for row in legacy if row["state_read"]]
    if event == "NZ_OLD":
        phase = manifest["source_contract"]["noise_phases"]["NZ_OLD"]
        return [row for row in legacy if row["pph"] == phase]
    if event == "NZ_LIVE":
        phase = manifest["source_contract"]["noise_phases"]["NZ_LIVE"]
        return [row for row in legacy if row["pph"] == phase]
    if event.startswith("W") and event[1:].isdigit():
        mask = cap_mask(manifest, event)
        return [row for row in legacy if int(row["cap"], 16) & mask]
    if event == "RING1":
        return [row for row in legacy if row["ring_read"]]
    if event == "RING2":
        return [row for row in legacy if row["ring_take_current"]]
    if event == "RING3":
        return [row for row in legacy if row["ring_take_old"]]
    if event.startswith("PC"):
        return legacy
    if event == "STORES":
        return [row for row in legacy
                if row["state_write"] or row["leaf_commit"]]
    if event == "SLOT":
        return [row for row in legacy if row["lfsr_commit"]]
    if event == "FOLD":
        return [row for row in legacy if row["fold_step"]]
    if event == "DONE":
        return [row for row in legacy if row["dry_valid"]]
    raise AssertionError(f"unknown source event {event}")


def check_guard(root: Json, rows: list[Json]) -> None:
    guard = root["guard"]
    if guard == "always":
        return
    field = {
        "wavetable": "guard_wavetable",
        "!wavetable": "guard_wavetable",
        "blend_count!=64": "guard_blend",
        "reverb": "guard_reverb",
        "audible": "guard_audible",
    }[guard]
    values = {int(row[field]) for row in rows}
    require(values == {0, 1},
            f"root {root['name']} does not exercise both {guard} classes")


def check_legacy(manifest: Json, legacy: list[Json]) -> dict[str, int]:
    require({row["schema"] for row in legacy} == {"psg_legacy_binding_v1"},
            "legacy trace schema")
    require({row["multipump"] for row in legacy} == {1},
            "legacy trace is not the HX8K multi-pumped schedule")
    cycles = [row["cycle"] for row in legacy]
    require(cycles == sorted(cycles) and len(cycles) == len(set(cycles)),
            "legacy cycles are not strictly ordered")
    require({row["slot"] for row in legacy} == set(range(8)),
            "legacy trace does not cover all eight slots")

    dry = [row for row in legacy if row["dry_valid"]]
    require(len(dry) >= 200, "legacy trace has fewer than 200 full samples")
    sample_ids = {row["sample"] for row in dry}
    require(len(sample_ids) == len(dry), "multiple dry commits per sample")
    sample_count = len(dry)

    reads = [row for row in legacy if row["state_read"]]
    writes = [row for row in legacy if row["state_write"]]
    require(len(reads) == sample_count * 8 * 18,
            "legacy state-read count is not 18 per slot")
    require(len(writes) == sample_count * 8 * 16,
            "legacy state-write count is not 16 per slot")
    read_words = {row["state_ra"] & 0x3f for row in reads}
    write_words = {row["state_wa"] & 0x3f for row in writes}
    require(set(range(10, 24)) <= read_words,
            "legacy oscillator read words are incomplete")
    require(set(range(24, 32)) <= read_words,
            "legacy trace did not exercise both parameter banks")
    require({26, 30} <= read_words,
            "active parameter word 26/30 distinction is absent")
    require(set(range(10, 24)) == write_words,
            "legacy persistent write words changed")

    for action in manifest["actions"]:
        binding = action["source_binding"]
        event = binding["event"]
        if event == "retired_alias":
            continue
        if event == "state_read":
            for word in binding["words"]:
                word_rows = [row for row in reads
                             if (row["state_ra"] & 0x3f) == word]
                require(word in read_words
                        and {row["slot"] for row in word_rows} == set(range(8)),
                        f"action {action['name']} read word {word} unseen")
        elif event == "state_write":
            for word in binding["words"]:
                word_rows = [row for row in writes
                             if (row["state_wa"] & 0x3f) == word]
                require(word in write_words
                        and {row["slot"] for row in word_rows} == set(range(8)),
                        f"action {action['name']} write word {word} unseen")
        elif event == "leaf_commit":
            require(any(row["leaf_commit"] for row in legacy),
                    f"action {action['name']} leaf commit unseen")
        elif event == "cap":
            cap_rows = rows_for_event(manifest, legacy, binding["cap"])
            require(cap_rows
                    and {row["slot"] for row in cap_rows} == set(range(8)),
                    f"action {action['name']} CAP unseen")
        elif event == "service_phase":
            phase_rows = [row for row in legacy
                          if row["pph"] == binding["source_phase"]]
            require(phase_rows
                    and {row["slot"] for row in phase_rows} == set(range(8)),
                    f"action {action['name']} phase unseen")
        elif event == "fold_step":
            require(any(row["fold_step"] for row in legacy),
                    f"action {action['name']} fold unseen")
        else:
            raise AssertionError(f"unknown action binding event {event}")

    for root in manifest["roots"]:
        producer = rows_for_event(manifest, legacy, root["producer_event"])
        consumer = rows_for_event(manifest, legacy, root["consumer_event"])
        require(producer and consumer, f"root {root['name']} has no live edge")
        if root["producer_event"] not in {"FOLD", "DONE"}:
            require({row["slot"] for row in producer} == set(range(8)),
                    f"root {root['name']} producer misses a slot")
        if root["consumer_event"] not in {"FOLD", "DONE"}:
            require({row["slot"] for row in consumer} == set(range(8)),
                    f"root {root['name']} consumer misses a slot")
        check_guard(root, producer)

    for write in manifest["fixed_writes"]:
        binding = write["source_binding"]
        if binding["event"] == "state_write":
            require(binding["word"] in write_words,
                    f"fixed write {write['action']} source unseen")
        elif binding["event"] == "cap":
            require(rows_for_event(manifest, legacy, binding["cap"]),
                    f"fixed write {write['action']} CAP unseen")
        elif binding["event"] == "leaf_commit":
            require(any(row["leaf_commit"] for row in legacy),
                    f"fixed write {write['action']} leaf source unseen")
        else:
            raise AssertionError(
                f"unknown fixed-write binding {binding['event']}")

    for field in ("wave_primary", "wave_secondary",
                  "wave_old_primary", "wave_old_secondary"):
        rows = [row for row in legacy if row[field]]
        require(len(rows) == sample_count * 8,
                f"{field} is not one context per slot")
        require({row["slot"] for row in rows} == set(range(8)),
                f"{field} misses a slot")
    for cap in ("W0", "W1", "W2", "W3"):
        rows = [row for row in rows_for_event(manifest, legacy, cap)
                if row["aram_issue"]]
        require(rows, f"ARAM context {cap} absent")

    require(sum(row["dq_start"] for row in legacy)
            == sum(row["dq_done"] for row in legacy) > 0,
            "live DQ issue/done balance")
    require(sum(row["dq_start_old"] for row in legacy)
            == sum(row["dq_old_take"] for row in legacy) > 0,
            "old DQ issue/take balance")

    mul_roots = [row for row in manifest["roots"]
                 if "service:mul" in row["owner"]]
    require(len(mul_roots) == 10, "multiplier root-role count")
    for root in mul_roots:
        event_rows = rows_for_event(manifest, legacy, root["producer_event"])
        require(any(row["mul_start"] for row in event_rows),
                f"multiplier role {root['name']} never starts")

    require({row["guard_wavetable"] for row in legacy} == {0, 1}
            and {row["guard_reverb"] for row in legacy} == {0, 1}
            and {row["guard_audible"] for row in legacy} == {0, 1}
            and {row["guard_blend"] for row in legacy} == {0, 1},
            "legacy guard matrix is incomplete")

    leaf = [row for row in legacy if row["leaf_commit"]]
    lfsr = [row for row in legacy if row["lfsr_commit"]]
    require(len(leaf) == sample_count * 8, "leaf commit count")
    require(len(lfsr) == sample_count * 8, "LFSR commit count")
    require({row["slot"] for row in leaf} == set(range(8)),
            "leaf commits miss a slot")

    starts = 0
    prior_step = 0
    prior_sample: int | None = None
    starts_by_sample: Counter[int] = Counter()
    for row in legacy:
        if row["sample"] != prior_sample:
            prior_step = 0
            prior_sample = row["sample"]
        if row["fold_step"] == 1 and prior_step != 1:
            starts += 1
            starts_by_sample[row["sample"]] += 1
        prior_step = row["fold_step"]
    require(starts == sample_count * 7, "fold-node start count")
    require(all(starts_by_sample[sample] == 7 for sample in sample_ids),
            "a sample does not contain seven ordered fold starts")

    return {"samples": sample_count, "legacy_rows": len(legacy),
            "state_reads": len(reads), "state_writes": len(writes),
            "fold_nodes": starts}


def check_multiplier(rows: list[Json]) -> dict[str, int]:
    require({row["schema"] for row in rows} == {"psg_edge_v1"}
            and {row["svc"] for row in rows} == {"mul"},
            "multiplier trace schema")
    pairs = pair_trace(rows, ("domain", "edge"))
    slow = [(pre, post) for pre, post in pairs if pre["domain"] == "slow"]
    fast = [(pre, post) for pre, post in pairs if pre["domain"] == "fast"]
    require(len(slow) == 105 and len(fast) == 630,
            "multiplier 105x6 edge topology changed")
    fast_by_slow: Counter[int] = Counter(pre["slow_edge"] for pre, _ in fast)
    require(set(fast_by_slow) == {pre["edge"] for pre, _ in slow}
            and set(fast_by_slow.values()) == {6},
            "multiplier fast edges do not join six-per-slow")
    held_slow = held_fast = 0
    for pre, post in pairs:
        if not pre["freeze"]:
            continue
        fields = ("req_tgl", "ack_tgl", "m_p", "m_cnt", "busy",
                  "seq_busy")
        require(all(pre[field] == post[field] for field in fields),
                "multiplier state moved while frozen")
        if pre["domain"] == "slow":
            held_slow += 1
        else:
            held_fast += 1
    require((held_slow, held_fast) == (27, 162),
            "multiplier freeze coverage changed")
    return {"mul_slow_pairs": len(slow), "mul_fast_pairs": len(fast),
            "mul_held_pairs": held_slow + held_fast}


def check_dq(rows: list[Json]) -> dict[str, int]:
    require({row["schema"] for row in rows} == {"psg_edge_v1"}
            and {row["svc"] for row in rows} == {"dq"},
            "DQ trace schema")
    pairs = pair_trace(rows, ("domain", "edge"))
    require(len(pairs) == 61, "DQ edge-pair count changed")
    held = held_starts = 0
    for pre, post in pairs:
        if pre["ce"]:
            continue
        fields = ("p", "count", "result", "done", "busy")
        require(all(pre[field] == post[field] for field in fields),
                "DQ state moved while CE was low")
        held += 1
        held_starts += int(bool(pre["start"]))
    require(held == 15 and held_starts >= 12,
            "DQ held/rejected-start coverage changed")
    require(any(pre["done"] and pre["start"] and pre["ce"]
                for pre, _ in pairs),
            "DQ terminal relaunch edge absent")
    return {"dq_pairs": len(pairs), "dq_held_pairs": held}


def check_execwave(rows: list[Json]) -> dict[str, int]:
    require({row["schema"] for row in rows} == {"psg_edge_v1"}
            and {row["svc"] for row in rows} == {"execwave"},
            "execwave trace schema")
    pairs = pair_trace(rows, ("domain", "bench_case", "edge"))
    require(len(pairs) == 4404, "execwave pair count changed")
    pre_rows = [pre for pre, _ in pairs]
    require({row["slot"] for row in pre_rows} == set(range(8)),
            "execwave misses a slot")
    required_pcs = set(range(0x13, 0x3d))
    for slot in range(8):
        seen = {int(row["pc"], 16) for row in pre_rows if row["slot"] == slot}
        require(required_pcs <= seen, f"execwave slot {slot} misses PCs")
    held = [row for row in pre_rows if row["hold"]]
    require(len(held) == 36, "execwave hold count changed")
    for row in held:
        require(not any(row[field] for field in
                        ("state_re", "state_we", "wave_issue", "wave_take",
                         "aram_req", "aram_take")),
                "execwave held edge leaked a transaction")
    wave_issue = sum(row["wave_issue"] for row in pre_rows)
    wave_take = sum(row["wave_take"] for row in pre_rows)
    aram_req = sum(row["aram_req"] for row in pre_rows)
    aram_take = sum(row["aram_take"] for row in pre_rows)
    require((wave_issue, wave_take, aram_req, aram_take) == (224, 224, 96, 96),
            "execwave issue/take queues changed")
    require(sum(row["state_re"] for row in pre_rows) == 4368
            and sum(row["proof_q_valid"] for row in pre_rows) == len(pre_rows),
            "execwave state-q origin coverage changed")
    return {"execwave_pairs": len(pairs), "execwave_holds": len(held),
            "wave_joins": wave_issue, "aram_joins": aram_req}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="join metadata-only PSG candidate bindings to RTL traces")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--legacy", type=Path, required=True)
    parser.add_argument("--mul", type=Path, required=True)
    parser.add_argument("--dq", type=Path, required=True)
    parser.add_argument("--execwave", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest = load_json(args.manifest)
    legacy = load_jsonl(args.legacy)
    mul = load_jsonl(args.mul)
    dq = load_jsonl(args.dq)
    execwave = load_jsonl(args.execwave)
    check_manifest(manifest)
    result: dict[str, int] = {}
    result.update(check_legacy(manifest, legacy))
    result.update(check_multiplier(mul))
    result.update(check_dq(dq))
    result.update(check_execwave(execwave))
    print("psg_exec_bindings: PASS "
          + " ".join(f"{key}={value}" for key, value in result.items()))
    print("boundary: structural source contract only; no semantic values, "
          "adapter equivalence, generic integration, synthesis or area claim")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
