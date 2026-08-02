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
import re
import subprocess
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Callable, Iterable


Json = dict[str, Any]

ROOT = Path(__file__).resolve().parents[1]
IMAGE = ROOT / "rtl/psg_exec.hex"
POOL_CONTAINERS = {"A": 18, "B": 18, "N": 17, "O": 17,
                   "Q": 16, "T": 6, "C": 7, "I": 6, "D": 3}
D1_PACKING_LAYOUT_SHA256 = \
    "242bfc8183feab4d80e81e10f04fec297bbdbffa6a358f2587aa5bd5c7f3efb0"
D1_LIVE_LAYOUT_SHA256 = \
    "55bb4b046212d20d8074bfcd074883c4a53e702d99e63fd91b43490b9f2c2075"
D1_SOURCE_PLAN_SHA256 = \
    "c5d274619488bb26e647ed5dd9a2b7291a37bb0856d1386304695fbaf5028dac"
D1_CANDIDATE_SHA256 = \
    "6f5713e22197d8c03bffeac070b3d9b9b2b2f7b20df98dbff4566d778b5e9177"
D1_BINDING_MANIFEST_SHA256 = \
    "438d85a0d7ea9f212cb5ad6efeafefd7a9eb2c8950d182e44abe8895c11249c3"
D1_PRODUCTION_IMAGE_SHA256 = \
    "59b6f86e1917c069762c2c67c3cfc33d3d1a7652c518e99f9f8437e019d4ebcf"
D1_OWNER_ZERO_WORDS_SHA256 = \
    "521f0bbdbc4085ea55cb64db5e4132a210d48cf6f50efed4751f6c320ed71986"
D1_CONTROLLER_SHA256 = \
    "f86698f67769c1d53bc976ad4868df004755ddb46cd218cab7b9d27d8b5439b4"
D1_REQUIREMENTS_SHA256 = \
    "5a7b9809b74b0e9094c864597de89c42e7f269ca1169aefd88f803999792c92e"
H095_RTL_REVISION = \
    "3d7a2e2ea1ed6a59cf868570755210e8b9ef81e8"
H095_SOURCE_SHA256 = {
    "rtl/psg_aram.sv":
        "a1f8c668aacd5c946d8497c42d3f718906efcab1e00c964be0d26be5a126549e",
    "rtl/psg_common.svh":
        "da29f84e538c07c4e74ae82be45c0d297fcc23223cae6bbf81d30058623886b6",
    "rtl/psg_dqsvc.sv":
        "06d26dd2760b6a450bdcad8a7e01c72a14a3436de6b41e5e3b695cb1f6ffe95b",
    "rtl/psg_mulmp.sv":
        "8df7c9f737d6b414d0342fa25a622e176514fb4d26f238bc6e31b2bde9cf0876",
    "rtl/psg_seq.sv":
        "6b2e688ff523559b221e440911b591c25a8399ba0fa7dcab57d969c2aeda2564",
    "rtl/psg_timing.sv":
        "838f5ce103dc3056fbe96444f183acb812749e78fa9b3444a5a1e8c8a0f11bfc",
    "rtl/psg_walk.sv":
        "33554a88b3ff68d12a8b592a82e0d69927a7266e87ff90304f09c492d40443a8",
    "rtl/psg_wave.sv":
        "687dbeb6949d46a1ccc2d59a7430e3c5af71eb28bb43938f4cee5d1b5ae75406",
    "rtl/target_psg.sv":
        "16bd4aaac4f8b2a4a20a0735d69c213a623de9b777291101898f0b5a18f9cc7f",
    "tools/psg_hw_forms.py":
        "3eb0f3f15fad04b42ec2bec1037513ebc24cb94cc14b9392d3fa1d4e321284d1",
}
I001_RTL_REVISION = \
    "6c9eebe1bf78591a748208fb9763bf9d9abf4ac6"
I001_COMBINED_SOURCE_SHA256 = {
    **H095_SOURCE_SHA256,
    "rtl/psg_aram.sv":
        "497cee26589b6a264b2fb86a227a0ba9d2bb2ddff6b8727481c22188c89478a7",
    "rtl/psg_dqsvc.sv":
        "93f9c973343ee49bdb0eeae1f5dfdc33898531e634c015720e09edcdee8c1a17",
    "rtl/psg_mulmp.sv":
        "501212cc205d43bbcc0e2026dec3b210dfa04cf4afa79da8c6f2c2d54a4650b3",
    "rtl/psg_wave.sv":
        "d92f77de6207940167550424b2223a88a8ef2bb71f68e49ff0229078c69d8220",
    "rtl/psg_exec.hex": D1_PRODUCTION_IMAGE_SHA256,
    "rtl/psg_execmove.sv":
        "3bf543a849a77a652ef043b7be2ca2dd798ad4c0bb3fd630c2d3547b6beae133",
}
MAIN_COMBINED_REVISION = \
    "9aacce15482ff6e73504400db8b80d1c9d0c0512"
COMBINED_SOURCE_SHA256 = {
    **I001_COMBINED_SOURCE_SHA256,
    "rtl/psg_aram.sv":
        "92fae0f8d71cd481733d171d01fd8b41d28f0739c0c21bff9669e140f95640ef",
}
MODEL_LIVE_SOURCES = (
    "rtl/psg_common.svh", "rtl/psg_seq.sv", "rtl/psg_walk.sv",
)
R84_COMBINED_OVERRIDES = (
    "rtl/psg_aram.sv", "rtl/psg_dqsvc.sv", "rtl/psg_mulmp.sv",
    "rtl/psg_wave.sv", "rtl/psg_exec.hex", "rtl/psg_execmove.sv",
)

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


def git_blob(revision: str, relative: str) -> bytes:
    return subprocess.run(
        ("git", "show", f"{revision}:{relative}"), cwd=ROOT,
        check=True, stdout=subprocess.PIPE).stdout


def validate_h095_r84_source_contract(contract: Json,
                                       recompute: bool = True) -> None:
    expected_fields = {
        "schema", "h095_revision", "i001_revision", "main_revision",
        "h095_generic_source_sha256", "combined_source_sha256",
        "model_live_sources", "r84_combined_overrides", "counts", "boundary",
    }
    require(set(contract) == expected_fields,
            "H095/R.84 source-contract fields changed")
    require(contract["schema"]
            == "psg_exec_h095_r84_main_source_contract_v3",
            "H095/R.84 source-contract schema")
    require(contract["h095_revision"] == H095_RTL_REVISION,
            "H095 source-contract revision")
    require(contract["i001_revision"] == I001_RTL_REVISION,
            "I001 source-contract revision")
    require(contract["main_revision"] == MAIN_COMBINED_REVISION,
            "main source-contract revision")
    require(contract["h095_generic_source_sha256"] == H095_SOURCE_SHA256,
            "H095 generic source hashes")
    require(contract["combined_source_sha256"] == COMBINED_SOURCE_SHA256,
            "I001 combined source hashes")
    require(contract["model_live_sources"] == list(MODEL_LIVE_SOURCES),
            "H095/I001 model-live source boundary")
    require(contract["r84_combined_overrides"]
            == list(R84_COMBINED_OVERRIDES),
            "R.84 combined override boundary")
    expected_counts = {
        "expanded_pc_nodes": 85,
        "legacy_states": 63,
        "normalized_formula_cases": 19_728_640,
        "normalized_transactions": 131_087,
    }
    require(contract["counts"] == expected_counts
            and all(type(value) is int
                    for value in contract["counts"].values()),
            "H095/R.84 source-contract counts")
    require(contract["boundary"] == [
        "model live sources are byte-identical in H095, I001 and main",
        "R.84 overrides and diagnostic ARAM are bound to main",
        "source certificate relies on I001 gates plus main ARAM tests",
    ], "H095/R.84 source-contract boundary")
    if not recompute:
        return
    h095_observed = {
        relative: hashlib.sha256(
            git_blob(H095_RTL_REVISION, relative)).hexdigest()
        for relative in H095_SOURCE_SHA256
    }
    require(h095_observed == H095_SOURCE_SHA256,
            "H095 git-object source drift")
    i001_observed = {
        relative: hashlib.sha256(
            git_blob(I001_RTL_REVISION, relative)).hexdigest()
        for relative in I001_COMBINED_SOURCE_SHA256
    }
    require(i001_observed == I001_COMBINED_SOURCE_SHA256,
            "I001 git-object source drift")
    main_observed = {
        relative: hashlib.sha256(
            git_blob(MAIN_COMBINED_REVISION, relative)).hexdigest()
        for relative in COMBINED_SOURCE_SHA256
    }
    require(main_observed == COMBINED_SOURCE_SHA256,
            "main composition git-object source drift")
    worktree_observed = {
        relative: hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
        for relative in COMBINED_SOURCE_SHA256
    }
    require(worktree_observed == COMBINED_SOURCE_SHA256,
            "I001 combined worktree drift")
    require(all(h095_observed[relative] == main_observed[relative]
                for relative in MODEL_LIVE_SOURCES),
            "model live sources differ between H095 and main")


def check_h095_r84_source_contract(path: Path) -> int:
    contract = load_json(path)
    validate_h095_r84_source_contract(contract)
    mutations: list[Json] = []
    mutation = copy.deepcopy(contract)
    mutation["i001_revision"] = "0" * 40
    mutations.append(mutation)
    mutation = copy.deepcopy(contract)
    mutation["main_revision"] = "0" * 40
    mutations.append(mutation)
    mutation = copy.deepcopy(contract)
    mutation["h095_generic_source_sha256"]["rtl/psg_walk.sv"] = "0" * 64
    mutations.append(mutation)
    mutation = copy.deepcopy(contract)
    mutation["combined_source_sha256"]["rtl/psg_aram.sv"] = "0" * 64
    mutations.append(mutation)
    mutation = copy.deepcopy(contract)
    mutation["combined_source_sha256"]["rtl/psg_mulmp.sv"] = "0" * 64
    mutations.append(mutation)
    mutation = copy.deepcopy(contract)
    mutation["unknown"] = 1
    mutations.append(mutation)
    mutation = copy.deepcopy(contract)
    mutation["counts"]["legacy_states"] = True
    mutations.append(mutation)
    for index, changed in enumerate(mutations):
        try:
            validate_h095_r84_source_contract(changed, recompute=False)
        except AssertionError:
            continue
        raise AssertionError(f"H095 source mutation {index} survived")
    return len(mutations)


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


def canonical_json(value: Json) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()


def canonical_image(words: list[int]) -> bytes:
    return "".join(f"{word:04x}\n" for word in words).encode()


def validate_d1_controller_anchors(manifest: Json,
                                   candidate: list[int]) -> None:
    require(hashlib.sha256(canonical_json(manifest)).hexdigest()
            == D1_BINDING_MANIFEST_SHA256,
            "D1 controller binding manifest is not the accepted C2-C-C anchor")
    require(len(candidate) == 512 and all(0 <= word <= 0xffff
                                          for word in candidate),
            "D1 controller candidate is not one complete two-bank image")
    require(hashlib.sha256(canonical_image(candidate)).hexdigest()
            == D1_CANDIDATE_SHA256,
            "D1 controller candidate image is not the accepted anchor")
    require(hashlib.sha256(IMAGE.read_bytes()).hexdigest()
            == D1_PRODUCTION_IMAGE_SHA256,
            "production executor image changed during D1 controller proof")
    owner_zero = b"".join(
        word.to_bytes(2, "big") for word in candidate[:256])
    require(hashlib.sha256(owner_zero).hexdigest()
            == D1_OWNER_ZERO_WORDS_SHA256,
            "D1 owner-zero candidate words changed")


def load_d1_candidate(path: Path) -> list[int]:
    lines = path.read_text().splitlines()
    require(len(lines) == 512, "D1 candidate must contain exactly 512 words")
    require(all(len(line) == 4 and line == line.lower()
                and all(char in "0123456789abcdef" for char in line)
                for line in lines),
            "D1 candidate is not canonical lowercase four-hex-word text")
    words = [int(line, 16) for line in lines]
    require(canonical_image(words) == path.read_bytes(),
            "D1 candidate has non-canonical formatting")
    return words


def d1_instruction_row(raw: int) -> Json:
    op = (raw >> 13) & 7
    names = ("READ", "WRITE", "BRANCH", "SLOT",
             "JUMP", "OWNER", "DONE", "EXEC")
    row: Json = {"op": names[op], "raw": raw}
    if op in (0, 1, 7):
        row.update({"action": (raw >> 6) & 0x7f, "word": raw & 0x3f})
    elif op == 2:
        row.update({"condition": (raw >> 9) & 0xf,
                    "sense": (raw >> 8) & 1, "target": raw & 0xff})
    elif op == 3:
        row.update({"increment": bool((raw >> 3) & 1),
                    "slot_value": raw & 7})
    elif op in (4, 5):
        row["target"] = raw & 0xff
    return row


def build_d1_controller_edges(manifest: Json,
                              candidate: list[int]) -> Json:
    """Independently reconstruct the direct-core dynamic control relation."""
    validate_d1_controller_anchors(manifest, candidate)
    owner_zero = candidate[:256]
    action_by_code = {int(row["code"]): row["name"]
                      for row in manifest["actions"]}
    require(len(action_by_code) == 61, "D1 action code map changed")
    fixed_destinations = {
        row["action"]: int(row["destination"])
        for row in manifest["fixed_writes"]
    }
    require(len(fixed_destinations) == 18,
            "D1 fixed-destination map changed")
    cap_w51 = next(row for row in manifest["actions"]
                   if row["name"] == "CAP_W51")
    require(cap_w51["code"] == 0x2d
            and cap_w51["occurrences"] == [{
                "changed": True, "op": "EXEC", "pc": 0x36,
                "physical_read_words": [26, 30], "q_source": 4,
                "word": 26,
            }], "CAP_W51 q26/q30 binding changed")

    def action_name(row: Json) -> str | None:
        if row["op"] not in {"READ", "WRITE", "EXEC"}:
            return None
        return action_by_code.get(int(row["action"]))

    def effective_read(row: Json, name: str | None,
                       bank: int) -> tuple[int, str]:
        literal = int(row["raw"]) & 0x3f
        if row["op"] == "READ" and int(row["word"]) >> 2 == 6:
            return 24 + (bank << 2) + (int(row["word"]) & 3), \
                "sample-parameter-bank"
        if name == "CAP_W51":
            require(row["op"] == "EXEC" and row["word"] == 26,
                    "CAP_W51 instruction changed")
            return (30 if bank else 26), "cap-w51-active-bank"
        return literal, "instruction-low6"

    edges: list[Json] = []
    run_counts: list[Json] = []
    for bank in (0, 1):
        pc, slot = 1, 0
        predecessor: Json | None = None
        op_counts: Counter[str] = Counter()
        read_counts: Counter[str] = Counter()
        taken = not_taken = 0
        run_start = len(edges)
        for occurrence in range(900):
            raw = owner_zero[pc]
            require(raw != 0,
                    f"D1 run bank {bank} reached zero word at PC {pc:02x}")
            instruction = d1_instruction_row(raw)
            op = instruction["op"]
            name = action_name(instruction)
            word, read_kind = effective_read(instruction, name, bank)
            state_read: Json = {
                "enabled": True,
                "kind": read_kind,
                "literal_word": raw & 0x3f,
                "effective_word": word,
                "address": (slot << 6) | word,
                "available_on": (None if op == "DONE" else {
                    "run_bank": bank, "occurrence": occurrence + 1,
                }),
            }

            state_write: Json | None = None
            if op == "WRITE":
                if name in fixed_destinations:
                    write_word = fixed_destinations[name]
                    write_kind = "fixed-action-destination"
                else:
                    write_word = int(instruction["word"])
                    write_kind = "instruction-word"
                state_write = {
                    "enabled": True, "kind": write_kind,
                    "effective_word": write_word,
                    "address": (slot << 6) | write_word,
                    "requires_address_override":
                        write_word != int(instruction["word"]),
                }

            next_pc, next_slot = (pc + 1) & 0xff, slot
            successor_kind = "fallthrough"
            guard: Json = {"kind": "unconditional"}
            terminal = False
            if op == "BRANCH":
                require(instruction["condition"] == 8,
                        "owner-zero branch is not sample-slot-wrap")
                branch_taken = ((slot == 0)
                                == bool(instruction["sense"]))
                if branch_taken:
                    next_pc = int(instruction["target"])
                    successor_kind = "branch-taken"
                    taken += 1
                else:
                    successor_kind = "branch-fallthrough"
                    not_taken += 1
                guard = {
                    "kind": "sample-slot-wrap", "condition": 8,
                    "sense": int(instruction["sense"]),
                    "slot_is_zero": slot == 0, "taken": branch_taken,
                }
            elif op == "JUMP":
                next_pc = int(instruction["target"])
                successor_kind = "jump"
            elif op == "SLOT":
                next_slot = ((slot + 1) & 7 if instruction["increment"]
                             else int(instruction["slot_value"]))
                successor_kind = "slot-update"
            elif op == "DONE":
                terminal = True
                successor_kind = "done"
            else:
                require(op in {"READ", "WRITE", "EXEC"},
                        f"unsupported owner-zero opcode {op}")

            edges.append({
                "run_bank": bank,
                "occurrence": occurrence,
                "pc": pc,
                "slot": slot,
                "instruction": instruction,
                "action_name": name,
                "guard": guard,
                "pre_edge_q": predecessor,
                "state_read": state_read,
                "state_write": state_write,
                "successor": {
                    "kind": successor_kind,
                    "terminal": terminal,
                    "pc": None if terminal else next_pc,
                    "slot": None if terminal else next_slot,
                },
            })
            op_counts[op] += 1
            read_counts[read_kind] += 1
            if terminal:
                require(occurrence == 781,
                        "D1 owner-zero run terminated at the wrong edge")
                break
            predecessor = {
                "run_bank": bank,
                "occurrence": occurrence,
                "pc": pc,
                "slot": slot,
                "effective_word": word,
                "address": (slot << 6) | word,
                "phase": "successor-pre-edge",
            }
            pc, slot = next_pc, next_slot
        else:
            raise AssertionError("D1 owner-zero run did not terminate")

        run = edges[run_start:]
        require(len(run) == 782 and len({row["pc"] for row in run}) == 222,
                "D1 dynamic/static controller coverage changed")
        require({row["slot"] for row in run} == set(range(8)),
                "D1 controller run misses a slot class")
        require(dict(op_counts) == {
            "READ": 172, "EXEC": 406, "WRITE": 158,
            "SLOT": 29, "JUMP": 8, "BRANCH": 8, "DONE": 1,
        }, "D1 controller opcode counts changed")
        require((taken, not_taken) == (1, 7),
                "D1 sample-slot branch guards changed")
        require(dict(read_counts) == {
            "instruction-low6": 742,
            "sample-parameter-bank": 32,
            "cap-w51-active-bank": 8,
        }, "D1 controller read classes changed")
        require(run[0]["pre_edge_q"] is None
                and all(row["pre_edge_q"] is not None for row in run[1:]),
                "D1 state-q predecessor coverage changed")
        require(sum(row["state_write"] is not None
                    and row["state_write"]["requires_address_override"]
                    for row in run) == 128,
                "D1 future address-override count changed")
        run_counts.append({
            "run_bank": bank,
            "edges": len(run),
            "static_pcs": len({row["pc"] for row in run}),
            "op_counts": dict(op_counts),
            "read_kinds": dict(read_counts),
            "writes": sum(row["state_write"] is not None for row in run),
            "address_overrides": sum(
                row["state_write"] is not None
                and row["state_write"]["requires_address_override"]
                for row in run),
            "branch_taken": taken,
            "branch_not_taken": not_taken,
        })

    owner_zero_bytes = b"".join(
        word.to_bytes(2, "big") for word in owner_zero)
    return {
        "schema": "psg_exec_d1_controller_edges_v1",
        "claim": "future-direct-core-controller-address-obligations-only",
        "candidate_owner_zero_sha256": hashlib.sha256(
            owner_zero_bytes).hexdigest(),
        "source_contract": {
            "current_controller":
                "psg_execctl-state-read-every-enabled-edge",
            "current_movement":
                "psg_execmove-sample-parameter-read-bank-only",
            "future_address_sidebands":
                "c2cc-cap-w51-q26-q30-and-16-remapped-fixed-write-destinations",
            "excluded_current_rtl_claim":
                "cap-w51-and-16-remapped-owner-zero-writes-not-implemented",
            "wave_adapter": "direct-core-literal-words",
            "excluded_compatibility_override": "hc-hold-to-word10",
        },
        "external_hold": {
            "successor": "self",
            "controller_advance": "disabled",
            "ucode_read": "disabled",
            "state_read": "disabled",
            "state_write": "disabled",
            "service_transaction": "disabled",
            "state_q": "retain",
        },
        "counts": {
            "runs": 2, "edges": len(edges), "edges_per_run": 782,
            "static_pcs_per_run": 222,
            "future_address_overrides": sum(
                row["state_write"] is not None
                and row["state_write"]["requires_address_override"]
                for row in edges),
        },
        "run_counts": run_counts,
        "edges": edges,
    }


def validate_d1_controller_edges(controller: Json, manifest: Json,
                                 candidate: list[int]) -> None:
    expected = build_d1_controller_edges(manifest, candidate)
    forbidden = forbidden_manifest_fields(controller)
    require(not forbidden,
            f"D1 controller relation carries semantic fields: {forbidden}")
    encoded = json.dumps(controller, sort_keys=True)
    require("SampleTrace" not in encoded
            and "evaluate_sample_slot" not in encoded,
            "D1 controller relation names a semantic oracle")
    require(canonical_json(controller) == canonical_json(expected),
            "D1 controller relation differs from independent reconstruction")


def check_d1_controller_mutations(controller: Json, manifest: Json,
                                  candidate: list[int]) -> int:
    convictions = 0

    def reject(mutated: Json, label: str,
               *, changed_manifest: Json | None = None,
               changed_candidate: list[int] | None = None) -> None:
        nonlocal convictions
        rejected = False
        try:
            validate_d1_controller_edges(
                mutated,
                manifest if changed_manifest is None else changed_manifest,
                candidate if changed_candidate is None else changed_candidate)
        except (AssertionError, StopIteration):
            rejected = True
        require(rejected, f"D1 controller mutation survived: {label}")
        convictions += 1

    branch = copy.deepcopy(controller)
    for row in branch["edges"]:
        if row["pc"] == 0 and row["instruction"]["op"] == "BRANCH":
            row["instruction"]["target"] = 0x51
            row["instruction"]["raw"] = \
                (int(row["instruction"]["raw"]) & 0xff00) | 0x51
            if row["successor"]["kind"] == "branch-taken":
                row["successor"]["pc"] = 0x51
    reject(branch, "branch target 50 to 51")

    fold_slot = copy.deepcopy(controller)
    for row in fold_slot["edges"]:
        if row["pc"] == 0x61:
            row["instruction"]["slot_value"] = 7
            row["instruction"]["raw"] = \
                (int(row["instruction"]["raw"]) & ~7) | 7
            row["successor"]["slot"] = 7
    reject(fold_slot, "fold slot destination")

    hold_word = copy.deepcopy(controller)
    for row in hold_word["edges"]:
        if row["pc"] == 0x1c:
            row["instruction"]["word"] = 11
            row["instruction"]["raw"] += 1
            row["state_read"]["literal_word"] = 11
            row["state_read"]["effective_word"] = 11
            row["state_read"]["address"] += 1
    reject(hold_word, "PC1c word10 to word11")

    loop = copy.deepcopy(controller)
    for row in loop["edges"]:
        if row["pc"] == 0x4f:
            row["instruction"]["target"] = 1
            row["instruction"]["raw"] += 1
            row["successor"]["pc"] = 1
    reject(loop, "loop jump zero to one")

    read_address = copy.deepcopy(controller)
    read_address["edges"][1]["state_read"]["address"] ^= 1
    reject(read_address, "state-read address")

    q_edge = copy.deepcopy(controller)
    q_edge["edges"][0]["state_read"]["available_on"]["occurrence"] += 1
    reject(q_edge, "state-q availability edge")

    hold = copy.deepcopy(controller)
    hold["external_hold"]["successor"] = "fallthrough"
    reject(hold, "external hold drift")

    colluding_manifest = copy.deepcopy(manifest)
    colluding_graph = copy.deepcopy(controller)
    fixed = next(row for row in colluding_manifest["fixed_writes"]
                 if row["action"] == "STORE_10_20")
    fixed["destination"] = 19
    for row in colluding_graph["edges"]:
        if row["action_name"] == "STORE_10_20":
            row["state_write"]["effective_word"] = 19
            row["state_write"]["address"] = (row["slot"] << 6) | 19
    reject(colluding_graph, "manifest and graph collusion",
           changed_manifest=colluding_manifest)

    unknown = copy.deepcopy(controller)
    unknown["oracle_output"] = 0
    reject(unknown, "unknown schema field")

    wrong_type = copy.deepcopy(controller)
    wrong_type["edges"][0]["state_read"]["available_on"]["occurrence"] = True
    reject(wrong_type, "numeric field coerced to Boolean")
    require(convictions == 10, "D1 controller mutation count changed")
    return convictions


def build_d1_event_dictionary(requirements: Json, manifest: Json,
                              candidate: list[int], controller: Json) -> Json:
    """Independently reconstruct D1's dynamic event identity dictionary."""
    validate_pool_requirements(requirements, manifest)
    validate_d1_controller_edges(controller, manifest, candidate)
    require(hashlib.sha256(canonical_json(controller)).hexdigest()
            == D1_CONTROLLER_SHA256,
            "D1 event dictionary controller is not the accepted C-A anchor")
    require(hashlib.sha256(canonical_json(requirements)).hexdigest()
            == D1_REQUIREMENTS_SHA256,
            "D1 event dictionary requirements are not the accepted anchor")

    edges = controller["edges"]
    action_rows = {row["name"]: row for row in manifest["actions"]}
    fixed = manifest["fixed_writes"]
    source_rows = {row["name"]: row
                   for row in requirements["source_catalog"]}
    roots = {row["name"]: row for row in manifest["roots"]}
    require(len(source_rows) == len(roots) == 30,
            "D1 event root catalog changed")

    def only_action_pc(name: str) -> int:
        pcs = {int(row["pc"]) for row in action_rows[name]["occurrences"]}
        require(len(pcs) == 1, f"D1 event {name} is not one static PC")
        pc = next(iter(pcs))
        selected = [edge for edge in edges if int(edge["pc"]) == pc]
        require(bool(selected)
                and all(edge["action_name"] == name for edge in selected),
                f"D1 event {name} is not the controller action at {pc:02x}")
        return pc

    def event_refs(pcs: set[int], phase: str) -> list[Json]:
        require(phase in {"pre", "post"} and bool(pcs),
                "D1 event phase/PC set invalid")
        matched = [edge for edge in edges if int(edge["pc"]) in pcs]
        require(bool(matched)
                and {int(edge["pc"]) for edge in matched} == pcs,
                f"D1 event PCs absent from controller: {sorted(pcs)}")
        refs = [{
            "bank": int(edge["run_bank"]),
            "slot": int(edge["slot"]),
            "occurrence": int(edge["occurrence"]),
            "pc": int(edge["pc"]),
            "phase": phase,
        } for edge in matched]
        require(len({(ref["bank"], ref["occurrence"], ref["phase"])
                     for ref in refs}) == len(refs),
                "D1 event dynamic key is not unique")
        return refs

    def event_coverage(refs: list[Json], guard: str) -> Json:
        keys = {(int(ref["bank"]), int(ref["occurrence"])) for ref in refs}
        source = [edge for edge in edges
                  if (int(edge["run_bank"]), int(edge["occurrence"]))
                  in keys]
        encoded_guards = sorted({json.dumps(
            edge["guard"], sort_keys=True, separators=(",", ":")
        ) for edge in source})
        return {
            "banks": sorted({int(ref["bank"]) for ref in refs}),
            "slots": sorted({int(ref["slot"]) for ref in refs}),
            "controller_guards": [json.loads(value)
                                  for value in encoded_guards],
            "semantic_guard": guard,
            "occurrences": len(refs),
        }

    leaf_pcs = {int(row["pc"]) for row in fixed
                if str(row["action"]).startswith("STORE_LEAF_")}
    record_pcs = {int(row["pc"]) for row in fixed
                  if not str(row["action"]).startswith("STORE_LEAF_")}
    increment_pcs = {
        int(edge["pc"]) for edge in edges
        if edge["run_bank"] == 0
        and edge["instruction"]["op"] == "SLOT"
        and edge["instruction"]["increment"] is True
    }
    require((len(leaf_pcs), len(record_pcs), len(increment_pcs)) == (2, 16, 1),
            "D1 composite root event partitions changed")

    root_events: list[Json] = []
    for name in sorted(roots):
        root, source = roots[name], source_rows[name]
        for key in ("name", "group", "width", "owner",
                    "producer_event", "consumer_event"):
            require(root[key] == source[key],
                    f"D1 root {name} structured identity changed at {key}")
        transaction = root["source_binding"]["transaction"]
        root_identity = {key: root[key] for key in
                         ("name", "group", "width", "owner", "guard")}
        root_identity["transaction"] = transaction
        for endpoint in ("producer", "consumer"):
            symbolic = root[f"{endpoint}_event"]
            observed = root["source_binding"][f"{endpoint}_observation"]
            if endpoint == "consumer" and name == "leaf_commit":
                pcs, basis = set(leaf_pcs), "leaf-fixed-writes"
            elif endpoint == "consumer" and name == "record_commit":
                pcs, basis = set(record_pcs), "record-fixed-writes"
            elif endpoint == "consumer" and name in {
                    "lfsr_next", "lfsr2_next"}:
                pcs, basis = set(increment_pcs), "per-slot-increment"
            else:
                pcs = {int(pc) for pc in root[f"{endpoint}_pcs"]}
                basis = "manifest-pcs"
            if endpoint == "producer":
                phase = "post" if transaction is not None \
                    else observed["phase"]
                roles = ["issue"] if transaction is not None else ["define"]
            else:
                phase = observed["phase"]
                roles = (["take", "consume"] if transaction is not None
                         else ["consume"])
                if symbolic == "STORES":
                    roles.append("commit")
            refs = event_refs(pcs, phase)
            event: Json = {
                "id": f"root:{name}:{endpoint}",
                "root": root_identity,
                "endpoint": endpoint,
                "symbolic_event": symbolic,
                "selection_basis": basis,
                "roles": roles,
                "observation": {"event": observed["event"],
                                "phase": observed["phase"]},
                "coverage": event_coverage(refs, root["guard"]),
                "occurrences": refs,
            }
            if endpoint == "producer" and transaction is not None:
                completion_refs = event_refs(pcs, observed["phase"])
                event["transaction_completion"] = {
                    "role": "complete",
                    "service": transaction["service"],
                    "kind": transaction["kind"],
                    "observation_event": observed["event"],
                    "observation_phase": observed["phase"],
                    "occurrences": completion_refs,
                }
            root_events.append(event)
    require(len(root_events) == 60, "D1 root endpoint count changed")

    def cap_pc(symbolic: str) -> int:
        require(bool(re.fullmatch(r"W[0-9]+", symbolic)),
                f"D1 CAP event malformed: {symbolic}")
        return only_action_pc("CAP_" + symbolic)

    def sample_site(symbolic: str) -> tuple[set[int], str]:
        if symbolic == "PRE_W15":
            return {cap_pc("W6")}, "post-w6"
        if symbolic == "DONE":
            return {only_action_pc("STORE_LEAF_HI")}, "post-leaf-high"
        if symbolic.startswith("W"):
            return {cap_pc(symbolic)}, "cap-action"
        require(bool(re.fullmatch(r"PC[0-9A-F]{2}", symbolic)),
                f"unknown D1 sample lifecycle event {symbolic}")
        return {int(symbolic[2:], 16)}, "literal-pc"

    fold_nodes = manifest["source_contract"]["fold_nodes"]
    require(len(fold_nodes) == 7, "D1 fold topology changed")

    def fold_site(node: int, symbolic: str) -> tuple[set[int], str]:
        require(0 <= node < 7, "D1 fold node out of range")
        base = 0x50 + 20 * node
        input_slot = fold_nodes[node][1]
        destination_slot = fold_nodes[node][2]

        def require_site(pc: int, *, action: str | None = None,
                         step: int | None = None, slot: int) -> None:
            selected = [edge for edge in edges if int(edge["pc"]) == pc]
            require(bool(selected)
                    and all(int(edge["slot"]) == slot for edge in selected),
                    f"D1 fold {node} {symbolic} slot/site changed")
            if action is not None:
                require(all(edge["action_name"] == action
                            for edge in selected),
                        f"D1 fold {node} {symbolic} action changed")
            if step is not None:
                require(all(edge["instruction"]["op"] == "EXEC"
                            and int(edge["instruction"]["action"]) == 0x70
                            and int(edge["instruction"]["word"]) == step
                            for edge in selected),
                        f"D1 fold {node} {symbolic} step tag changed")

        if symbolic == "INPUTS":
            require_site(base + 7, action="FOLD_START", slot=input_slot)
            return {base + 7}, "fold-start"
        if symbolic.startswith("STEP"):
            step = int(symbolic[4:])
            require(1 <= step <= 8, "D1 fold step out of range")
            require_site(base + 8 + step, step=step, slot=input_slot)
            return {base + 8 + step}, "hold-step-tag"
        if symbolic == "WRITE_LO":
            require_site(base + 18, action="FOLD_WRITE_LO",
                         slot=destination_slot)
            return {base + 18}, "fold-write-low"
        if symbolic == "WRITE_HI":
            require_site(base + 19, action="FOLD_WRITE_HI",
                         slot=destination_slot)
            return {base + 19}, "fold-write-high"
        if symbolic == "DONE":
            if node < 6:
                require_site(base + 19, action="FOLD_WRITE_HI",
                             slot=destination_slot)
                return {base + 19}, "node-write-high"
            require_site(0xdc, action="FOLD_FINISH",
                         slot=destination_slot)
            return {0xdc}, "root-fold-finish"
        raise AssertionError(f"unknown D1 fold lifecycle event {symbolic}")

    lifetime_events: list[Json] = []
    fields = requirements["live_fields"]
    require(len(fields) == 78
            and len({(field["path"], field["name"])
                     for field in fields}) == 78,
            "D1 live-field identities changed")
    for field in fields:
        for endpoint in ("born", "dead"):
            symbolic = field[endpoint]
            phase = "post" if endpoint == "born" else "pre"
            if field["path"] == "fold":
                if symbolic == "DONE":
                    phase = "post"
                pcs: set[int] = set()
                bases: set[str] = set()
                for node in range(7):
                    node_pcs, basis = fold_site(node, symbolic)
                    pcs.update(node_pcs)
                    bases.add(basis)
                selection_basis = "+".join(sorted(bases))
                guard = "fold"
            else:
                pcs, selection_basis = sample_site(symbolic)
                if symbolic == "DONE":
                    phase = "post"
                guard = field["path"]
            refs = event_refs(pcs, phase)
            lifetime_events.append({
                "id": (f"lifetime:{field['path']}:{field['name']}:"
                       f"{endpoint}"),
                "lifetime": {key: field[key] for key in
                             ("path", "name", "width", "pieces")},
                "endpoint": endpoint,
                "symbolic_event": symbolic,
                "selection_basis": selection_basis,
                "roles": ["define" if endpoint == "born" else "consume"],
                "coverage": event_coverage(refs, guard),
                "occurrences": refs,
            })
    require(len(lifetime_events) == 156,
            "D1 lifetime endpoint count changed")

    fold_events: list[Json] = []
    for node, slots in enumerate(fold_nodes):
        for symbolic in ("INPUTS", *(f"STEP{step}" for step in range(1, 9)),
                         "WRITE_LO", "WRITE_HI", "DONE"):
            pcs, selection_basis = fold_site(node, symbolic)
            refs = event_refs(pcs, "post")
            if symbolic == "INPUTS":
                roles = ["define"]
            elif symbolic.startswith("STEP"):
                roles = ["consume", "define"]
            elif symbolic.startswith("WRITE"):
                roles = ["consume", "commit"]
            else:
                roles = ["complete"]
            fold_events.append({
                "id": f"fold:{node}:{symbolic}",
                "node": node,
                "topology": {"a_slot": slots[0], "b_slot": slots[1],
                             "destination_slot": slots[2]},
                "symbolic_event": symbolic,
                "selection_basis": selection_basis,
                "roles": roles,
                "coverage": event_coverage(refs, "fold"),
                "occurrences": refs,
            })
    finish_refs = event_refs({only_action_pc("FOLD_FINISH")}, "post")
    fold_events.append({
        "id": "fold:root:FOLD_FINISH",
        "node": "root",
        "symbolic_event": "FOLD_FINISH",
        "selection_basis": "fold-finish-action",
        "roles": ["consume", "complete", "commit"],
        "coverage": event_coverage(finish_refs, "fold"),
        "occurrences": finish_refs,
    })
    require(len(fold_events) == 85, "D1 fold event count changed")

    return {
        "schema": "psg_exec_d1_event_dictionary_v1",
        "claim": "dynamic-event-identity-only-no-values-or-pool-updates",
        "anchors": {
            "controller_sha256": D1_CONTROLLER_SHA256,
            "candidate_sha256": D1_CANDIDATE_SHA256,
            "binding_manifest_sha256": D1_BINDING_MANIFEST_SHA256,
            "requirements_sha256": D1_REQUIREMENTS_SHA256,
            "packing_layout_sha256": D1_PACKING_LAYOUT_SHA256,
            "live_layout_sha256": D1_LIVE_LAYOUT_SHA256,
            "production_image_sha256": D1_PRODUCTION_IMAGE_SHA256,
        },
        "external_hold": controller["external_hold"],
        "counts": {
            "root_events": len(root_events),
            "lifetime_events": len(lifetime_events),
            "fold_events": len(fold_events),
            "root_occurrences": sum(len(row["occurrences"])
                                    for row in root_events),
            "transaction_completions": sum(
                "transaction_completion" in row for row in root_events),
            "transaction_completion_occurrences": sum(
                len(row["transaction_completion"]["occurrences"])
                for row in root_events
                if "transaction_completion" in row),
            "lifetime_occurrences": sum(len(row["occurrences"])
                                        for row in lifetime_events),
            "fold_occurrences": sum(len(row["occurrences"])
                                    for row in fold_events),
        },
        "root_events": root_events,
        "lifetime_events": lifetime_events,
        "fold_events": fold_events,
    }


def validate_d1_event_dictionary(dictionary: Json, requirements: Json,
                                 manifest: Json, candidate: list[int],
                                 controller: Json) -> None:
    forbidden = forbidden_manifest_fields(dictionary)
    require(not forbidden,
            f"D1 event dictionary carries semantic fields: {forbidden}")
    encoded = json.dumps(dictionary, sort_keys=True)
    for spelling in ("state_wd", "final_words",
                     "pool_update", "SampleTrace", "evaluate_sample_slot"):
        require(spelling not in encoded,
                f"D1 event dictionary names forbidden {spelling}")
    expected = build_d1_event_dictionary(
        requirements, manifest, candidate, controller)
    require(canonical_json(dictionary) == canonical_json(expected),
            "D1 event dictionary differs from independent reconstruction")


def check_d1_event_mutations(dictionary: Json, requirements: Json,
                             manifest: Json, candidate: list[int],
                             controller: Json) -> int:
    convictions = 0

    def reject(mutated: Json, label: str, *,
               changed_manifest: Json | None = None,
               changed_controller: Json | None = None) -> None:
        nonlocal convictions
        rejected = False
        try:
            validate_d1_event_dictionary(
                mutated, requirements,
                manifest if changed_manifest is None else changed_manifest,
                candidate,
                controller if changed_controller is None else changed_controller)
        except (AssertionError, KeyError, StopIteration, ValueError):
            rejected = True
        require(rejected, f"D1 event mutation survived: {label}")
        convictions += 1

    missing = copy.deepcopy(dictionary)
    missing["root_events"][0]["occurrences"].pop()
    reject(missing, "missing dynamic event")

    ambiguous = copy.deepcopy(dictionary)
    ambiguous["root_events"][0]["occurrences"].append(
        copy.deepcopy(ambiguous["root_events"][0]["occurrences"][0]))
    reject(ambiguous, "ambiguous duplicate event")

    phase = copy.deepcopy(dictionary)
    completion = next(
        row["transaction_completion"] for row in phase["root_events"]
        if row.get("transaction_completion", {}).get("observation_phase")
        == "pre")
    completion["occurrences"][0]["phase"] = "post"
    reject(phase, "wrong pre/post phase")

    coverage = copy.deepcopy(dictionary)
    coverage["root_events"][0]["occurrences"] = [
        row for row in coverage["root_events"][0]["occurrences"]
        if row["bank"] == 0 and row["slot"] != 7]
    reject(coverage, "bank and slot loss")

    name_only = copy.deepcopy(dictionary)
    name_only["root_events"][0]["root"]["group"] = "same-name-wrong-group"
    reject(name_only, "name-only root match")

    copied_q = copy.deepcopy(dictionary)
    copied_q["lifetime_events"][0]["occurrences"][0]["pc"] -= 1
    reject(copied_q, "copied predecessor q word")

    hold = copy.deepcopy(dictionary)
    hold["external_hold"]["state_read"] = "enabled"
    reject(hold, "external hold drift")

    colluding_controller = copy.deepcopy(controller)
    colluding = copy.deepcopy(dictionary)
    for edge in colluding_controller["edges"]:
        if edge["pc"] == 0x26:
            edge["pc"] = 0x25
    for row in colluding["root_events"] + colluding["lifetime_events"]:
        for ref in row["occurrences"]:
            if ref["pc"] == 0x26:
                ref["pc"] = 0x25
    reject(colluding, "colluding controller and dictionary",
           changed_controller=colluding_controller)

    unknown = copy.deepcopy(dictionary)
    unknown["semantic_value"] = 0
    reject(unknown, "unknown schema field")

    wrong_type = copy.deepcopy(dictionary)
    wrong_type["root_events"][0]["occurrences"][0]["occurrence"] = True
    reject(wrong_type, "numeric bool/int coercion")
    require(convictions == 10, "D1 event mutation count changed")
    return convictions


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
    parser.add_argument("--d1-controller-edges", type=Path)
    parser.add_argument("--d1-event-dictionary", type=Path)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--rtl-source-contract", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    require((args.pool_requirements is None) == (args.pool_out is None),
            "--pool-requirements and --pool-out must be used together")
    require((args.d1_controller_edges is None) == (args.candidate is None),
            "--d1-controller-edges and --candidate must be used together")
    if args.d1_event_dictionary is not None:
        require(args.d1_controller_edges is not None
                and args.pool_requirements is not None,
                "D1 event dictionary requires controller, candidate and "
                "pool requirements")
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
    if args.rtl_source_contract is not None:
        result["rtl_source_mutations"] = check_h095_r84_source_contract(
            args.rtl_source_contract)
        result["rtl_source_files"] = len(COMBINED_SOURCE_SHA256)
    if args.d1_controller_edges is not None:
        controller = load_json(args.d1_controller_edges)
        candidate = load_d1_candidate(args.candidate)
        validate_d1_controller_edges(controller, manifest, candidate)
        result["controller_edges"] = controller["counts"]["edges"]
        result["controller_mutations"] = check_d1_controller_mutations(
            controller, manifest, candidate)
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
    if args.d1_event_dictionary is not None:
        dictionary = load_json(args.d1_event_dictionary)
        controller = load_json(args.d1_controller_edges)
        candidate = load_d1_candidate(args.candidate)
        requirements = load_json(args.pool_requirements)
        validate_d1_event_dictionary(
            dictionary, requirements, manifest, candidate, controller)
        result["event_mutations"] = check_d1_event_mutations(
            dictionary, requirements, manifest, candidate, controller)
        result.update({f"event_{key}": int(value)
                       for key, value in dictionary["counts"].items()})
    print("psg_exec_bindings: PASS "
          + " ".join(f"{key}={value}" for key, value in result.items()))
    print("boundary: structural source/source-completeness inventory only; "
          "controller/address/event relations may be included; no semantic values, "
          "pool transitions, adapter equivalence, "
          "generic integration, synthesis or area claim")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
