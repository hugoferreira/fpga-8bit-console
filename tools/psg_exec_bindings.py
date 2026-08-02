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
import copy
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Callable, Iterable


Json = dict[str, Any]

IMAGE = Path(__file__).resolve().parents[1] / "rtl/psg_exec.hex"
POOL_CONTAINERS = {"A": 18, "B": 18, "N": 17, "O": 17,
                   "Q": 16, "T": 6, "C": 7, "I": 6, "D": 3}
D1_PACKING_LAYOUT_SHA256 = \
    "242bfc8183feab4d80e81e10f04fec297bbdbffa6a358f2587aa5bd5c7f3efb0"
D1_LIVE_LAYOUT_SHA256 = \
    "55bb4b046212d20d8074bfcd074883c4a53e702d99e63fd91b43490b9f2c2075"
D1_SOURCE_PLAN_SHA256 = \
    "c5d274619488bb26e647ed5dd9a2b7291a37bb0856d1386304695fbaf5028dac"

# A typed state-q read is a legal D1 source only when it arrives from outside
# the unproved owner-zero write graph at the exact consuming edge.  Presently
# that is true only for the active parameter-bank damp field.
LIVE_STATE_Q_SOURCES = {
    ("built-in", "damp"): ((26, 30), 12, 2, 0x37),
    ("wavetable", "damp"): ((26, 30), 12, 2, 0x37),
}

# Root joins close a lifetime only when the observed transaction consumer is
# exactly the lifetime birth edge.  Anything later requires an independently
# bound physical relocation.
LIVE_ROOT_SOURCES = {
    ("built-in", "live_gain_limb"): ("mul_live_w4", 0),
    ("built-in", "current_arm"): ("mul_live_recip", 0),
    ("built-in", "old_gain_limb"): ("mul_old_w27", 0),
    ("wavetable", "live_gain_limb"): ("mul_live_w27", 0),
}

# These are literal relocations, but they close only when the predecessor is
# itself bound.  Keeping blocked relocations explicit prevents capacity-only
# rows from acquiring invented sources.
LIVE_PHYSICAL_SOURCES = {
    ("wavetable", "final_nz_phase"):
        ("wavetable", "pre_final_nz_phase", 0),
    ("wavetable", "refresh"): ("wavetable", "pre_refresh", 0),
    ("wavetable", "live_gain"): ("wavetable", "pre_live_gain", 0),
}

FIXED_GUARD_FIELDS = {
    "guard_wavetable", "guard_reverb", "guard_audible", "guard_blend",
    "guard_restart", "guard_clear", "guard_play", "guard_amplitude",
    "guard_noise", "guard_brown", "guard_hidden",
}


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


def source_plan() -> Json:
    return {
        "live_state_q": [
            {"path": path, "field": field, "words": list(words),
             "lsb": lsb, "width": width, "pc": pc}
            for (path, field), (words, lsb, width, pc)
            in sorted(LIVE_STATE_Q_SOURCES.items())
        ],
        "live_roots": [
            {"path": path, "field": field, "root": root, "lsb": lsb}
            for (path, field), (root, lsb)
            in sorted(LIVE_ROOT_SOURCES.items())
        ],
        "live_physical": [
            {"path": path, "field": field, "source_path": source_path,
             "source_field": source_field, "lsb": lsb}
            for (path, field), (source_path, source_field, lsb)
            in sorted(LIVE_PHYSICAL_SOURCES.items())
        ],
    }


def validate_source_plan(plan: Json) -> None:
    digest = hashlib.sha256(json.dumps(
        plan, sort_keys=True, separators=(",", ":")
    ).encode()).hexdigest()
    require(digest == D1_SOURCE_PLAN_SHA256,
            "D1 structured source plan changed")


def action_occurrence(manifest: Json, pc: int) -> tuple[Json, Json]:
    matches = [
        (action, occurrence)
        for action in manifest["actions"]
        for occurrence in action["occurrences"]
        if occurrence["pc"] == pc
    ]
    require(len(matches) == 1, f"PC {pc:02x} has no unique action occurrence")
    return matches[0]


def state_read_action(manifest: Json, word: int) -> str:
    matches = [
        action["name"] for action in manifest["actions"]
        if action["source_binding"].get("event") == "state_read"
        and word in action["source_binding"].get("words", [])
    ]
    require(len(matches) == 1, f"state word {word} has no unique read action")
    return matches[0]


def q_source_at_pc(manifest: Json, pc: int) -> int:
    actions = [
        occurrence["q_source"]
        for action in manifest["actions"]
        for occurrence in action["occurrences"]
        if occurrence["pc"] == pc
    ]
    if actions:
        require(len(actions) == 1, f"PC {pc:02x} has multiple action origins")
        return actions[0]
    holds = [
        row["q_source"] for row in manifest["changed_pc_bindings"]
        if row["pc"] == pc
        and row["source_binding"].get("event") == "fixed_hold"
    ]
    require(len(holds) == 1, f"PC {pc:02x} has no explicit q origin")
    return holds[0]


def read_origin_at_pc(manifest: Json, pc: int,
                      words: tuple[int, ...]) -> Json:
    origins: list[Json] = []
    for action in manifest["actions"]:
        for occurrence in action["occurrences"]:
            if occurrence["pc"] != pc - 1:
                continue
            physical = occurrence.get("physical_read_words",
                                      [occurrence.get("word")])
            if set(words) <= set(physical):
                origins.append({"pc": occurrence["pc"],
                                "source": action["name"],
                                "physical_read_words": physical})
    for row in manifest["changed_pc_bindings"]:
        if row["pc"] == pc - 1 \
                and row["source_binding"].get("event") == "fixed_hold" \
                and row["word"] in words:
            origins.append({"pc": row["pc"], "source": "fixed_hold",
                            "physical_read_words": [row["word"]]})
    require(len(origins) == 1,
            f"PC {pc:02x} has no unique preceding q read for {words}")
    return origins[0]


def validate_pool_requirements(requirements: Json, manifest: Json) -> None:
    require(requirements.get("schema") == "psg_exec_pool_requirements_v2",
            "wrong D1 requirements schema")
    require(requirements.get("claim") == "requirements-and-source-catalog-only",
            "D1 requirements overclaim their boundary")
    require(requirements.get("containers") == POOL_CONTAINERS,
            "D1 container set changed")
    require(requirements.get("counts") == {
        "packing_rows": 15, "built_fields": 32, "wavetable_fields": 35,
        "fold_fields": 11, "roots": 30, "root_groups": 27,
        "bound_fields": 0,
    }, "D1 requirement counts changed")
    encoded = json.dumps(requirements, sort_keys=True)
    require("source_binding" not in encoded,
            "D1 requirements already carry a source binding")
    require(not forbidden_manifest_fields(requirements),
            "D1 requirements carry a semantic value field")

    rows = requirements["packing_rows"]
    require(len(rows) == 15 and len({row["name"] for row in rows}) == 15,
            "D1 packing row set changed")
    packing_layout = [
        {key: row[key] for key in
         ("name", "capacities", "pieces", "logical_widths")}
        for row in rows
    ]
    packing_digest = hashlib.sha256(json.dumps(
        packing_layout, sort_keys=True, separators=(",", ":")
    ).encode()).hexdigest()
    require(requirements.get("packing_layout_sha256") == packing_digest,
            "D1 packing layout digest does not match its rows")
    require(packing_digest == D1_PACKING_LAYOUT_SHA256,
            "D1 packing layout differs from the accepted literal slices")
    for row in rows:
        require(row.get("source_status") == "unbound",
                f"packing row {row['name']} is not explicitly unbound")
        require(sum(row["capacities"].values()) == row["capacity"],
                f"packing row {row['name']} capacity mismatch")
        occupied: set[tuple[str, int]] = set()
        logical: dict[str, set[int]] = defaultdict(set)
        for piece in row["pieces"]:
            container = piece["container"]
            width = piece["width"]
            require(container in row["capacities"] and width > 0,
                    f"packing row {row['name']} has an invalid piece")
            require(piece["container_lsb"] + width
                    <= row["capacities"][container],
                    f"packing row {row['name']} piece exceeds {container}")
            for bit in range(width):
                physical = (container, piece["container_lsb"] + bit)
                require(physical not in occupied,
                        f"packing row {row['name']} aliases {physical}")
                occupied.add(physical)
                logical[piece["field"]].add(piece["field_lsb"] + bit)
        require(len(occupied) == row["used"],
                f"packing row {row['name']} used-bit count changed")
        require(set(logical) == set(row["logical_widths"]),
                f"packing row {row['name']} logical field set changed")
        for field, width in row["logical_widths"].items():
            require(logical[field] == set(range(width)),
                    f"packing row {row['name']} field {field} has a gap")

    fields = requirements["live_fields"]
    require(len(fields) == 78
            and len({(row["path"], row["name"]) for row in fields}) == 78,
            "D1 live-field set changed")
    require(Counter(row["path"] for row in fields)
            == Counter({"built-in": 32, "wavetable": 35, "fold": 11}),
            "D1 live-field path counts changed")
    live_layout = [
        {key: row[key] for key in
         ("path", "name", "width", "pieces", "born", "dead")}
        for row in fields
    ]
    live_digest = hashlib.sha256(json.dumps(
        live_layout, sort_keys=True, separators=(",", ":")
    ).encode()).hexdigest()
    require(requirements.get("live_layout_sha256") == live_digest,
            "D1 live layout digest does not match its fields")
    require(live_digest == D1_LIVE_LAYOUT_SHA256,
            "D1 live layout differs from the accepted slices/lifetimes")
    for row in fields:
        require(row.get("source_status") == "unbound",
                f"live field {row['path']}:{row['name']} is not unbound")
        require(sum(piece["width"] for piece in row["pieces"]) == row["width"],
                f"live field {row['path']}:{row['name']} width mismatch")
        occupied: set[tuple[str, int]] = set()
        for piece in row["pieces"]:
            container = piece["container"]
            require(container in POOL_CONTAINERS
                    and piece["lsb"] + piece["width"]
                    <= POOL_CONTAINERS[container],
                    f"live field {row['path']}:{row['name']} bad slice")
            for bit in range(piece["lsb"], piece["lsb"] + piece["width"]):
                key = (container, bit)
                require(key not in occupied,
                        f"live field {row['path']}:{row['name']} aliases {key}")
                occupied.add(key)

    catalog = requirements["source_catalog"]
    roots = {row["name"]: row for row in manifest["roots"]}
    require(len(catalog) == len(roots) == 30
            and len({row["name"] for row in catalog}) == 30,
            "D1 source catalog set changed")
    for row in catalog:
        require(row["name"] in roots,
                f"D1 source {row['name']} has no C2-C-C root")
        root = roots[row["name"]]
        signature = {
            "name": root["name"], "group": root["group"],
            "width": root["width"], "owner": root["owner"],
            "producer_event": root["source_binding"]["producer_event"],
            "consumer_event": root["source_binding"]["consumer_event"],
        }
        require({key: row[key] for key in signature} == signature,
                f"D1 source {row['name']} matches a name but not its root")
        transaction_bound = root["source_binding"].get("transaction") is not None
        require(row["transaction_bound_candidate"] == transaction_bound,
                f"D1 source {row['name']} transaction class changed")


def state_q_source(manifest: Json, words: tuple[int, ...], lsb: int,
                   width: int, source_pc: int | None = None) -> Json:
    capacity = 32 if words == (48, 49) else 16
    require(words and 0 <= lsb and 0 < width <= capacity
            and lsb + width <= capacity,
            "invalid state-q source slice")
    if words == (26, 30):
        action, occurrence = action_occurrence(manifest, 0x36)
        require(action["name"] == "CAP_W51"
                and occurrence.get("physical_read_words") == [26, 30],
                "active parameter-bank state-q origin changed")
        issued_by = ["CAP_W51"]
        slices = [
            {"word": word, "lsb": lsb, "field_lsb": 0, "width": width}
            for word in words
        ]
        selection = "active_parameter_bank"
    elif words == (48, 49):
        q_words = {
            occurrence["q_source"]
            for action in manifest["actions"]
            if action["family"] == "fold"
            for occurrence in action["occurrences"]
        }
        require({48, 49} <= q_words, "fold state-q words are not in the stream")
        issued_by = ["FOLD_PRIME", "FOLD_A_LO", "FOLD_B_LO"]
        slices = [
            {"word": 48, "lsb": 0, "field_lsb": 0, "width": 16},
            {"word": 49, "lsb": 0, "field_lsb": 16, "width": 2},
        ]
        selection = "little_endian_composition"
    else:
        require(len(words) == 1, "unsupported multiword state-q source")
        issued_by = ([read_origin_at_pc(manifest, source_pc, words)["source"]]
                     if source_pc is not None
                     else [state_read_action(manifest, words[0])])
        slices = [{"word": words[0], "lsb": lsb, "field_lsb": 0,
                   "width": width}]
        selection = "single_word"
    if source_pc is not None:
        expected = words[0]
        require(q_source_at_pc(manifest, source_pc) == expected,
                f"PC {source_pc:02x} does not consume q{expected}")
        origin = read_origin_at_pc(manifest, source_pc, words)
    else:
        origin = None
    return {
        "kind": "state_q_slice",
        "selection": selection,
        "slices": slices,
        "total_width": width,
        "issued_by": issued_by,
        "source_pc": source_pc,
        "read_origin": origin,
    }


def root_source(manifest: Json, name: str, lsb: int, width: int,
                expected_consumer_event: str) -> Json:
    matches = [row for row in manifest["roots"] if row["name"] == name]
    require(len(matches) == 1, f"root {name} is not unique")
    root = matches[0]
    binding = root["source_binding"]
    observation = binding["producer_observation"]
    require(binding.get("transaction") is not None,
            f"root {name} is not transaction-bound")
    require(binding["consumer_event"] == expected_consumer_event,
            f"root {name} is consumed at {binding['consumer_event']}, not "
            f"lifetime birth {expected_consumer_event}")
    require(lsb >= 0 and width > 0 and lsb + width <= root["width"]
            and lsb + width <= observation["physical_width"],
            f"root {name} cannot supply slice {lsb}+:{width}")
    return {
        "kind": "root_slice",
        "root": name,
        "group": root["group"],
        "lsb": lsb,
        "width": width,
        "producer_event": binding["producer_event"],
        "consumer_event": binding["consumer_event"],
        "producer_observation": observation,
        "transaction": binding["transaction"],
    }


def packing_field_rows(requirements: Json, manifest: Json) -> list[Json]:
    result: list[Json] = []
    for row in requirements["packing_rows"]:
        pieces_by_field: dict[str, list[Json]] = defaultdict(list)
        for piece in row["pieces"]:
            pieces_by_field[piece["field"]].append({
                "container": piece["container"],
                "container_lsb": piece["container_lsb"],
                "field_lsb": piece["field_lsb"],
                "width": piece["width"],
            })
        for field, width in row["logical_widths"].items():
            output: Json = {
                "id": f"packing:{row['name']}:{field}",
                "row": row["name"], "field": field, "width": width,
                "pieces": pieces_by_field[field],
            }
            # A source value observed before this snapshot does not prove the
            # unimplemented enabled-edge transport into these literal pieces.
            output["source_status"] = "unmatched"
            output["unmatched_reason"] = "physical_transition_unproved"
            result.append(output)
    return result


def live_field_rows(requirements: Json, manifest: Json) -> list[Json]:
    fields = {(row["path"], row["name"]): row
              for row in requirements["live_fields"]}
    result: list[Json] = []
    by_key: dict[tuple[str, str], Json] = {}
    for requirement in requirements["live_fields"]:
        key = (requirement["path"], requirement["name"])
        output: Json = {
            "id": f"lifetime:{key[0]}:{key[1]}",
            "path": key[0], "field": key[1],
            "width": requirement["width"],
            "pieces": requirement["pieces"],
            "born": requirement["born"], "dead": requirement["dead"],
        }
        if key in LIVE_STATE_Q_SOURCES:
            words, lsb, width, pc = LIVE_STATE_Q_SOURCES[key]
            require(width == requirement["width"],
                    f"state-q width changed for {key}")
            output["source_status"] = "bound"
            output["source_binding"] = state_q_source(
                manifest, words, lsb, width, pc)
        elif key in LIVE_ROOT_SOURCES:
            root, lsb = LIVE_ROOT_SOURCES[key]
            output["source_status"] = "bound"
            output["source_binding"] = root_source(
                manifest, root, lsb, requirement["width"],
                requirement["born"])
        else:
            output["source_status"] = "unmatched"
            output["unmatched_reason"] = "no_structured_source_binding"
        result.append(output)
        by_key[key] = output

    for target, (source_path, source_name, source_lsb) \
            in LIVE_PHYSICAL_SOURCES.items():
        source = (source_path, source_name)
        require(target in fields and source in fields,
                f"physical relocation endpoint is missing: {target} <- {source}")
        target_row = by_key[target]
        source_row = by_key[source]
        require(fields[source]["dead"] == fields[target]["born"],
                f"physical relocation edge is not adjacent: {target} <- {source}")
        require(source_lsb + fields[target]["width"] <= fields[source]["width"],
                f"physical relocation slice is too narrow: {target} <- {source}")
        if source_row["source_status"] == "bound":
            target_row["source_status"] = "bound"
            target_row.pop("unmatched_reason", None)
            target_row["source_binding"] = {
                "kind": "physical_slice",
                "source": source_row["id"],
                "lsb": source_lsb,
                "width": fields[target]["width"],
            }
        else:
            target_row["unmatched_reason"] = "preceding_physical_slice_unmatched"
            target_row["blocked_by"] = source_row["id"]
    return result


def build_pool_source_inventory(requirements: Json, manifest: Json) -> Json:
    validate_pool_requirements(requirements, manifest)
    validate_source_plan(source_plan())
    packing = packing_field_rows(requirements, manifest)
    lifetimes = live_field_rows(requirements, manifest)
    catalog = [
        {
            "name": row["name"], "group": row["group"],
            "width": row["width"], "owner": row["owner"],
            "producer_event": row["producer_event"],
            "consumer_event": row["consumer_event"],
            "source_status": "joined",
        }
        for row in requirements["source_catalog"]
    ]
    bound_packing = sum(row["source_status"] == "bound" for row in packing)
    bound_lifetimes = sum(row["source_status"] == "bound" for row in lifetimes)
    return {
        "schema": "psg_exec_pool_source_inventory_v1",
        "claim": "structured-source-completeness-inventory-only",
        "containers": requirements["containers"],
        "packing_fields": packing,
        "live_fields": lifetimes,
        "source_catalog": catalog,
        "counts": {
            "packing_rows": len(requirements["packing_rows"]),
            "packing_fields": len(packing),
            "bound_packing_fields": bound_packing,
            "unmatched_packing_fields": len(packing) - bound_packing,
            "live_fields": len(lifetimes),
            "bound_live_fields": bound_lifetimes,
            "unmatched_live_fields": len(lifetimes) - bound_lifetimes,
            "joined_roots": len(catalog),
        },
    }


def validate_pool_source_inventory(inventory: Json, requirements: Json,
                                   manifest: Json) -> None:
    require(inventory["schema"] == "psg_exec_pool_source_inventory_v1",
            "wrong D1 source-inventory schema")
    require(not forbidden_manifest_fields(inventory),
            "D1 source inventory carries a semantic value")
    for row in inventory["packing_fields"] + inventory["live_fields"]:
        require(row["source_status"] in {"bound", "unmatched"},
                f"D1 requirement {row['id']} has no source classification")
        if row["source_status"] == "bound":
            binding = row["source_binding"]
            require(binding["kind"] in {
                "state_q_slice", "root_slice", "physical_slice"},
                f"D1 requirement {row['id']} has a forbidden source kind")
            text = json.dumps(binding, sort_keys=True)
            require(not any(name in text for name in
                            ("record_commit", "state_wd", "final_words")),
                    f"D1 requirement {row['id']} uses a final legacy value")
        else:
            require("source_binding" not in row and row["unmatched_reason"],
                    f"D1 requirement {row['id']} hides an unmatched source")
    expected = build_pool_source_inventory(requirements, manifest)
    require(inventory == expected, "D1 source inventory differs from its inputs")


def check_pool_mutations(requirements: Json, manifest: Json,
                         inventory: Json) -> int:
    convictions = 0

    def reject(action: Callable[[], None], label: str) -> None:
        nonlocal convictions
        rejected = False
        try:
            action()
        except AssertionError:
            rejected = True
        require(rejected, f"D1 mutation survived: {label}")
        convictions += 1

    missing = copy.deepcopy(requirements)
    missing["packing_rows"].pop()
    reject(lambda: validate_pool_requirements(missing, manifest), "missing row")

    wrong_slice = copy.deepcopy(requirements)
    piece = next(
        piece for row in wrong_slice["packing_rows"]
        if row["name"] == "builtin ordinary PC1c"
        for piece in row["pieces"] if piece["field"] == "phase2_msb"
    )
    piece["container"] = "D"
    piece["container_lsb"] = 0
    reject(lambda: validate_pool_requirements(wrong_slice, manifest),
           "wrong literal slice")

    wrong_live = copy.deepcopy(requirements)
    live = next(row for row in wrong_live["live_fields"]
                if row["path"] == "built-in"
                and row["name"] == "live_gain_limb")
    live["pieces"][0]["container"] = "O"
    reject(lambda: validate_pool_requirements(wrong_live, manifest),
           "wrong live slice")

    final_value = copy.deepcopy(inventory)
    bound = next(row for row in final_value["live_fields"]
                 if row["source_status"] == "bound")
    bound["source_binding"] = {"kind": "final_value", "signal": "state_wd"}
    reject(lambda: validate_pool_source_inventory(final_value, requirements,
                                                  manifest), "final value")

    false_root = copy.deepcopy(requirements)
    false_root["source_catalog"][0]["group"] += "-wrong"
    reject(lambda: build_pool_source_inventory(false_root, manifest),
           "false root-name match")

    wrong_plan = source_plan()
    wrong_plan["live_roots"][0]["root"] = "noise_old_issue"
    reject(lambda: validate_source_plan(wrong_plan), "wrong root target")
    require(convictions == 6, "D1 mutation conviction count changed")
    return convictions


def write_pool_source_inventory(path: Path, inventory: Json,
                                inputs: tuple[Path, ...]) -> None:
    output = path.resolve()
    require(output != IMAGE.resolve(),
            "D1 source inventory must not replace rtl/psg_exec.hex")
    for input_path in inputs:
        source = input_path.resolve()
        require(output != source, "D1 source inventory aliases an input")
        if output.exists() and source.exists():
            require(not output.samefile(source),
                    "D1 source inventory hard-links an input")
    encoded = json.dumps(inventory, sort_keys=True, indent=2) + "\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(encoded)
    require(output.read_text() == encoded,
            "D1 source inventory readback changed")


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
    require(len(writes) == 18 and len({row["pc"] for row in writes}) == 18
            and len({row["action"] for row in writes}) == 18,
            "fixed-write manifest")
    leaf_destinations = {
        row["action"]: int(row["destination"])
        for row in writes if row["action"].startswith("STORE_LEAF_")
    }
    require(leaf_destinations == {"STORE_LEAF_LO": 48,
                                  "STORE_LEAF_HI": 49},
            "leaf fixed writes must target distinct words 48/49")
    for row in writes:
        binding = row.get("source_binding")
        require(binding,
                f"fixed write {row['action']} lacks a source binding")
        obligations = binding.get("guard_obligations")
        require(isinstance(obligations, list) and obligations,
                f"fixed write {row['action']} lacks guard obligations")
        fields = [obligation.get("field") for obligation in obligations]
        require(len(fields) == len(set(fields))
                and set(fields) <= FIXED_GUARD_FIELDS,
                f"fixed write {row['action']} has invalid guard predicates")
        require(all(isinstance(obligation.get("reason"), str)
                    and obligation["reason"] for obligation in obligations),
                f"fixed write {row['action']} lacks guard reasons")


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
    if guard == "wavetable&&play":
        values = {
            int(bool(row["guard_wavetable"]) and bool(row["guard_play"]))
            for row in rows
        }
        require(values == {0, 1},
                f"root {root['name']} does not exercise both {guard} classes")
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
    parser.add_argument("--pool-requirements", type=Path)
    parser.add_argument("--pool-out", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    require((args.pool_requirements is None) == (args.pool_out is None),
            "--pool-requirements and --pool-out must be used together")
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
    if args.pool_requirements is not None:
        requirements = load_json(args.pool_requirements)
        inventory = build_pool_source_inventory(requirements, manifest)
        validate_pool_source_inventory(inventory, requirements, manifest)
        result["pool_mutations"] = check_pool_mutations(
            requirements, manifest, inventory)
        write_pool_source_inventory(
            args.pool_out, inventory,
            (args.manifest, args.pool_requirements, args.legacy,
             args.mul, args.dq, args.execwave))
        result.update(inventory["counts"])
    print("psg_exec_bindings: PASS "
          + " ".join(f"{key}={value}" for key, value in result.items()))
    print("boundary: structural source/source-completeness inventory only; "
          "no semantic values, pool transitions, adapter equivalence, "
          "generic integration, synthesis or area claim")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
