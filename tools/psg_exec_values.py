#!/usr/bin/env python3
"""Prove R.84 value lineage from manifest-bound live RTL observations.

The large full-PSG trace is streamed as adjacent pre/post-NBA pairs.  The
manifest names raw producer and consumer fields; this checker only compares
those observed fields, memory movement, literal word slices, retained values,
fold-stack transfers and dry publication.  It contains no waveform, filter,
record-transition or candidate write-data evaluator.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterator

from psg_exec_bindings import (check_dq, check_execwave, check_manifest,
                               check_multiplier, load_jsonl, require)


Json = dict[str, Any]
RootKey = tuple[int, ...]
GuardTuple = tuple[int, ...]

GLOBAL_GUARDS = (
    "guard_wavetable", "guard_reverb", "guard_audible", "guard_blend",
    "guard_restart", "guard_clear", "guard_play", "guard_amplitude",
    "guard_noise", "guard_brown", "guard_hidden",
)

HOLD_CARRIED_FIELDS = (
    "state_q", "state_mem_r", "state_mem_w", "seq_q", "dq_result",
    "dq_live_r", "dq_visit", "m_res", "smp_a", "smp_b", "wt_p1",
    "wt_q1", "wt_prod", "wt_z", "gz_s1_r", "mx_new", "mx_old",
    "arm_new_w51", "arm_old_w51", "bl_res", "bl_cnt", "s_phase",
    "s_phase2", "s_old_phase", "old_q0", "s_noise_lp", "mx_filt",
    "mix_leaf", "lfsr", "lfsr2", "z_eval", "nz_step", "nz_neg17",
    "nz_pos17", "nz2_sign", "mul_busy", "dq_busy", "ring_rd", "ring_q",
    "ring_q_old", "fstk0", "fstk1", "fstk2", "fsel", "fpend",
    "ffin", "fmc", "fdsti", "fold_fda", "fold_fdb", "fold_a",
    "fold_b", "fold_sub", "fold_cin", "phase_alu_y", "f_under",
    "fdiv5_q", "mxs_new", "mxs_old", "dry16", "pcm",
)

HOLD_TRANSACTION_FIELDS = (
    "state_read", "state_write", "wave_primary", "wave_secondary",
    "wave_old_primary", "wave_old_secondary", "aram_issue", "dq_start",
    "dq_start_old", "dq_done", "dq_old_take", "mul_start", "ring_read",
    "ring_take_current", "ring_take_old", "ring_write", "leaf_commit",
    "lfsr_commit", "fold_step", "fold_write", "dry_valid",
)

COORDINATE_FIELDS = (
    "edge", "sample", "multipump", "bank", "slot", "pph", "cap",
    "hold", "state_read", "state_ra", "state_write", "state_wa",
    "state_wd", "syn_addr", "wave_primary", "wave_secondary", "wave_old_primary",
    "wave_old_secondary", "aram_issue", "dq_start", "dq_start_old",
    "dq_start_ready", "dq_done", "dq_old_take", "mul_start", "mul_mode", "mul_short",
    "nz_req_old", "nz_req_live",
    "ring_read", "ring_take_current", "ring_take_old", "ring_write",
    "ring_addr", "ring_rp", "ring_current_level", "ring_old_level",
    "ring_current_addr", "ring_old_addr",
    "leaf_commit", "lfsr_commit", "fold_step", "fold_write",
    "fold_write_dst", "dry_valid",
    *GLOBAL_GUARDS,
)


def raw_int(value: Any) -> int:
    return int(value, 16) if isinstance(value, str) else int(value)


def signed_word(value: int, width: int) -> int:
    value &= (1 << width) - 1
    return value - (1 << width) if value & (1 << (width - 1)) else value


def iter_pairs(path: Path) -> Iterator[tuple[Json, Json]]:
    """Stream one adjacent pre/post pair at a time without loading the trace."""
    pending: Json | None = None
    last_edge = -1
    rows = 0
    with path.open() as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            row = json.loads(line)
            require(isinstance(row, dict),
                    f"{path}:{line_number}: expected a JSON object")
            require(row.get("schema") == "psg_legacy_value_v1",
                    f"{path}:{line_number}: wrong value schema")
            rows += 1
            if row.get("phase") == "pre":
                require(pending is None,
                        f"{path}:{line_number}: pre before pending post")
                require(row["edge"] == last_edge + 1,
                        f"{path}:{line_number}: non-contiguous edge")
                pending = row
                continue
            require(row.get("phase") == "post" and pending is not None,
                    f"{path}:{line_number}: post without pre")
            for field in COORDINATE_FIELDS:
                require(row[field] == pending[field],
                        f"edge {row['edge']}: coordinate {field} drift")
            require(row["multipump"] == 1,
                    f"edge {row['edge']}: trace is not HX8K multipump")
            yield pending, row
            last_edge = row["edge"]
            pending = None
    require(rows > 0 and pending is None and rows % 2 == 0,
            f"{path}: empty or incomplete value stream")


class ValueProof:
    def __init__(self, manifest: Json) -> None:
        self.manifest = manifest
        self.roots = {row["name"]: row for row in manifest["roots"]}
        self.writes = {row["action"]: row for row in manifest["fixed_writes"]}
        require(len(self.roots) == 30 and len(self.writes) == 18,
                "unexpected value manifest topology")
        self.cap_indices = manifest["source_contract"]["cap_indices"]
        self.noise_phases = manifest["source_contract"]["noise_phases"]
        self.fixed_guard_obligations: dict[str, tuple[str, ...]] = {}
        for action, row in self.writes.items():
            obligations = row["source_binding"]["guard_obligations"]
            fields = tuple(obligation["field"] for obligation in obligations)
            require(fields and len(fields) == len(set(fields))
                    and set(fields) <= set(GLOBAL_GUARDS),
                    f"fixed write {action}: invalid guard obligations")
            self.fixed_guard_obligations[action] = fields

        self.endpoint_by_event: dict[str, list[tuple[str, str, Json]]] = \
            defaultdict(list)
        self.service_roots: dict[str, tuple[str, str]] = {}
        for name, root in self.roots.items():
            binding = root["source_binding"]
            require(binding["producer_event"] == root["producer_event"]
                    and binding["consumer_event"] == root["consumer_event"],
                    f"root {name}: structural source binding drift")
            # Structural events name the candidate lifetime (for example a
            # service issue at LOAD); raw observations name the later legacy
            # edge where that result is actually visible (for example
            # NZ_LIVE).  Requiring those names to coincide would reject every
            # multi-cycle service rather than proving its observed endpoints.
            for role in ("producer", "consumer"):
                spec = binding[f"{role}_observation"]
                require(spec["event"] and spec["phase"] in {"pre", "post"}
                        and spec["field"],
                        f"root {name}: incomplete {role} observation")
                require(int(spec["physical_width"]) == int(root["width"])
                        and bool(spec["physical_signed"]) == bool(root["signed"]),
                        f"root {name}: {role} physical typing drift")
                self.endpoint_by_event[spec["event"]].append(
                    (name, role, spec))
            require(binding["producer_observation"]
                    != binding["consumer_observation"],
                    f"root {name}: producer and consumer are the same endpoint")
            transaction = binding.get("transaction")
            if transaction is not None:
                self.service_roots[name] = (transaction["service"],
                                            transaction["kind"])

        self.write_actions: dict[int, list[str]] = defaultdict(list)
        for row in sorted(manifest["fixed_writes"], key=lambda item: item["pc"]):
            for endpoint in ("source_observation", "consumer_observation"):
                spec = row["source_binding"][endpoint]
                require(spec["physical_width"] == 16
                        and spec["physical_signed"] is False,
                        f"fixed write {row['action']}: physical typing drift")
            if row["source_binding"]["event"] == "state_write":
                self.write_actions[int(row["destination"])].append(row["action"])
        require(sum(map(len, self.write_actions.values())) == 14,
                "manifest state-write source count changed")

        self.root_producers: Counter[str] = Counter()
        self.root_consumers: Counter[str] = Counter()
        self.root_joins: Counter[str] = Counter()
        self.root_slots: dict[str, set[int]] = defaultdict(set)
        self.root_banks: dict[str, set[int]] = defaultdict(set)
        self.root_bank_slots: dict[str, set[tuple[int, int]]] = defaultdict(set)
        self.root_guards: dict[str, set[int]] = defaultdict(set)
        self.root_values: dict[str, dict[tuple[int, int], int]] = \
            defaultdict(dict)
        self.pending_endpoints: dict[tuple[str, RootKey], dict[str, int]] = \
            defaultdict(dict)
        self.pending_meta: dict[tuple[str, RootKey], tuple[int, int]] = {}
        self.pending_service_keys: dict[str, RootKey] = {}
        self.current_event_keys: dict[tuple[str, str], RootKey] = {}
        self.service_txid: Counter[str] = Counter()
        self.service_issues: Counter[str] = Counter()
        self.service_results: Counter[str] = Counter()
        self.service_takes: Counter[str] = Counter()
        self.service_issue_guards: dict[str, set[int]] = defaultdict(set)
        self.service_issue_bank_slots: dict[str, set[tuple[int, int]]] = \
            defaultdict(set)
        self.mul_active: tuple[str, str, RootKey] | None = None
        self.dq_active: tuple[str, str, RootKey] | None = None
        self.wave_stage: tuple[str, str, RootKey, int] | None = None
        self.ring_active: dict[str, tuple[str, RootKey, int]] = {}

        self.fixed_sources: dict[tuple[str, int, int],
                                 tuple[int, GuardTuple]] = {}
        self.fixed_identities: Counter[str] = Counter()
        self.fixed_bank_slots: dict[str, set[tuple[int, int]]] = defaultdict(set)
        self.fixed_voice_classes: dict[str, set[str]] = defaultdict(set)
        self.fixed_source_guards: dict[str, dict[str, set[int]]] = \
            defaultdict(lambda: defaultdict(set))
        self.fixed_commit_guards: dict[str, dict[str, set[int]]] = \
            defaultdict(lambda: defaultdict(set))
        self.fixed_guard_pairs: dict[str,
                                     set[tuple[GuardTuple, GuardTuple]]] = \
            defaultdict(set)
        self.write_occurrences: Counter[tuple[int, int, int]] = Counter()

        self.state_read_words: set[int] = set()
        self.state_write_words: set[int] = set()
        self.global_guard_values: dict[str, set[int]] = defaultdict(set)
        self.voice_classes: set[str] = set()
        self.next_state_key: tuple[int, int] | None = None
        self.last_sample: int | None = None
        self.right_censored_producers = 0
        self.prior_hold_post: Json | None = None
        self.prior_hold_service: tuple[tuple[str, RootKey], ...] | None = None
        self.held_pairs = 0
        self.fold_starts: Counter[int] = Counter()
        self.fold_stack_writes = 0
        self.fold_nodes = [tuple(map(int, row))
                           for row in manifest["source_contract"]["fold_nodes"]]
        require(self.fold_nodes == [(0, 1, 0), (2, 3, 2), (0, 2, 0),
                                    (4, 5, 4), (6, 7, 6), (4, 6, 4),
                                    (0, 4, 0)],
                "fold-node contract changed")
        self.fold_leaves: dict[tuple[int, int], int] = {}
        self.fold_values: dict[int, dict[int, int]] = defaultdict(dict)
        self.fold_node_index: Counter[int] = Counter()
        self.fold_active_node: dict[int, tuple[int, int, int, int]] = {}
        self.fold_sequence_checks = 0
        self.dry_samples: set[int] = set()
        self.pcm_publications = 0
        self.state_txid = 0
        self.state_transactions = 0
        self.value_pairs = 0

    @staticmethod
    def guard_tuple(pre: Json) -> GuardTuple:
        return tuple(int(pre[field]) for field in GLOBAL_GUARDS)

    @staticmethod
    def ring_expected_address(pre: Json, kind: str) -> int:
        require(kind in {"current", "old"}, f"unknown ring kind {kind}")
        rp = int(pre["ring_rp"])
        level = int(pre[f"ring_{kind}_level"])
        require(0 <= rp < 732 and 0 <= level < 4,
                f"edge {pre['edge']}: invalid ring address inputs")
        tap = ((rp - 366) % 732) if level == 1 else rp
        expected = int(pre["slot"]) * 732 + tap
        require(int(pre[f"ring_{kind}_addr"]) == expected,
                f"edge {pre['edge']}: {kind} ring address/input mismatch")
        return expected

    def service_opportunity(self, name: str, pre: Json) -> bool:
        active = self.guard_active(self.roots[name], pre)
        self.service_issue_guards[name].add(int(active))
        if active:
            self.service_issue_bank_slots[name].add(
                (int(pre["bank"]), int(pre["slot"])))
        return active

    def allocate_service(self, name: str, service: str, kind: str,
                         pre: Json, identity: RootKey = ()) -> RootKey:
        require(self.service_roots.get(name) == (service, kind),
                f"root {name}: service transaction metadata drift")
        require(name not in self.pending_service_keys,
                f"root {name}: prior service transaction is still pending")
        txid = self.service_txid[service]
        self.service_txid[service] += 1
        key: RootKey = (txid, *identity)
        self.pending_service_keys[name] = key
        self.service_issues[name] += 1
        return key

    def service_event(self, name: str, event: str, key: RootKey) -> None:
        require(self.pending_service_keys.get(name) == key,
                f"root {name}: {event} has the wrong transaction key")
        self.current_event_keys[(name, event)] = key
        self.service_results[name] += 1

    def advance_services(self, pre: Json, post: Json) -> set[str]:
        """Derive result events only from live request/result/take strobes."""
        self.current_event_keys = {}
        events: set[str] = set()

        # The built-in wave core has two registered boundaries.  A request at
        # edge N is visible in z_eval after edge N+1; the queue is shifted only
        # across actual adjacent traced edges.
        prior_wave = self.wave_stage
        self.wave_stage = None
        if prior_wave is not None:
            name, event, key, issue_edge = prior_wave
            require(int(pre["edge"]) == issue_edge + 1,
                    f"root {name}: wave result edge is not adjacent")
            self.service_event(name, event, key)
            events.add(event)

        wave_issues = (
            ("wave_0_issue", "WAVE_RESULT_0", "primary", "wave_primary"),
            ("wave_1_issue", "WAVE_RESULT_1", "secondary", "wave_secondary"),
            ("wave_2_issue", "WAVE_RESULT_2", "old_primary", "wave_old_primary"),
            ("wave_3_issue", "WAVE_RESULT_3", "old_secondary", "wave_old_secondary"),
        )
        for name, event, kind, strobe in wave_issues:
            if not pre[strobe]:
                continue
            active = self.service_opportunity(name, pre)
            if active:
                require(self.wave_stage is None,
                        f"edge {pre['edge']}: multiple wave issues")
                key = self.allocate_service(name, "wave", kind, pre)
                self.wave_stage = (name, event, key, int(pre["edge"]))

        # ARAM is a synchronous read: the addressed byte is visible after the
        # same captured edge, then a later walker edge consumes it.
        cap = raw_int(pre["cap"])
        aram_rows = (
            ("aram_0_issue", "ARAM_RESULT_0", "base0", "W0"),
            ("aram_1_issue", "ARAM_RESULT_1", "adjacent1", "W1"),
            ("aram_2_issue", "ARAM_RESULT_2", "base2", "W2"),
            ("aram_3_issue", "ARAM_RESULT_3", "adjacent3", "W3"),
        )
        for name, event, kind, cap_name in aram_rows:
            if not (cap & (1 << int(self.cap_indices[cap_name]))):
                continue
            active = self.service_opportunity(name, pre)
            if active:
                require(pre["aram_issue"],
                        f"root {name}: active ARAM opportunity did not issue")
                key = self.allocate_service(name, "aram", kind, pre)
                # Address is part of the transaction identity even though the
                # root key remains the monotonic transaction number.
                require(0 <= int(pre["syn_addr"]) < 8192,
                        f"root {name}: invalid ARAM address")
                self.service_event(name, event, key)
                events.add(event)

        # DQ is a chained one-outstanding recurrence.  The old-context request
        # may launch on the same edge that reports the live result, so consume
        # done before accepting the new request.
        if pre["dq_done"]:
            require(self.dq_active is not None,
                    f"edge {pre['edge']}: DQ done without an active request")
            name, event, key = self.dq_active
            self.service_event(name, event, key)
            events.add(event)
            self.dq_active = None
        if pre["dq_start"]:
            require(pre["dq_start_ready"],
                    f"edge {pre['edge']}: rejected DQ request in value trace")
            if pre["dq_start_old"]:
                name, event, kind = "dq_old_issue", "DQ_RESULT_OLD", "old"
                # The same edge captures the preceding live result.
                live_key = self.pending_service_keys.get("dq_live_issue")
                require(live_key is not None,
                        f"edge {pre['edge']}: live DQ capture lacks transaction")
                self.current_event_keys[("dq_live_issue", "DQ_CAPTURE_LIVE")] = \
                    live_key
                events.add("DQ_CAPTURE_LIVE")
            else:
                name, event, kind = "dq_live_issue", "DQ_RESULT_LIVE", "live"
            require(self.service_opportunity(name, pre),
                    f"root {name}: unconditional DQ request inactive")
            key = self.allocate_service(name, "dq", kind, pre)
            require(self.dq_active is None,
                    f"edge {pre['edge']}: overlapping DQ requests")
            self.dq_active = (name, event, key)

        # The multi-pumped multiplier acknowledges one request by dropping the
        # slow-domain busy level.  This edge, not a CAP label, creates the
        # result event and transaction/value association.
        if pre["mul_busy"] and not post["mul_busy"]:
            require(self.mul_active is not None,
                    f"edge {pre['edge']}: multiplier ack without request")
            name, event, key = self.mul_active
            self.service_event(name, event, key)
            events.add(event)
            self.mul_active = None

        mul_opportunities: list[tuple[str, str, str]] = []
        if pre["nz_req_old"]:
            mul_opportunities = [("noise_old_issue", "MUL_RESULT_NZ_OLD", "nz_old")]
        elif pre["nz_req_live"]:
            mul_opportunities = [("noise_live_issue", "MUL_RESULT_NZ_LIVE", "nz_live")]
        elif cap & (1 << int(self.cap_indices["W4"])):
            mul_opportunities = [
                ("mul_primary_interp", "MUL_RESULT_PRIMARY_INTERP", "primary_interp"),
                ("mul_live_w4", "MUL_RESULT_LIVE_W4", "live_w4"),
            ]
        elif cap & (1 << int(self.cap_indices["W15"])):
            mul_opportunities = [
                ("mul_old_interp", "MUL_RESULT_OLD_INTERP", "old_interp"),
                ("mul_live_recip", "MUL_RESULT_LIVE_RECIP", "live_recip"),
            ]
        elif cap & (1 << int(self.cap_indices["W27"])):
            mul_opportunities = [
                ("mul_live_w27", "MUL_RESULT_LIVE_W27", "live_w27"),
                ("mul_old_w27", "MUL_RESULT_OLD_W27", "old_w27"),
            ]
        elif cap & (1 << int(self.cap_indices["W40"])):
            mul_opportunities = [
                ("mul_arm_recip", "MUL_RESULT_ARM_RECIP", "arm_recip")]
        elif cap & (1 << int(self.cap_indices["W75"])):
            mul_opportunities = [
                ("mul_blend", "MUL_RESULT_BLEND", "blend")]
        chosen: tuple[str, str, str] | None = None
        for row in mul_opportunities:
            name = row[0]
            if self.service_opportunity(name, pre):
                require(chosen is None,
                        f"edge {pre['edge']}: multiple active multiplier roots")
                chosen = row
        if pre["mul_start"]:
            require(chosen is not None,
                    f"edge {pre['edge']}: unclassified multiplier request")
            require(not pre["mul_busy"] and self.mul_active is None,
                    f"edge {pre['edge']}: overlapping multiplier request")
            name, event, kind = chosen
            key = self.allocate_service(name, "mul", kind, pre)
            self.mul_active = (name, event, key)
        elif chosen is not None:
            require(False, f"root {chosen[0]}: active multiplier opportunity did not issue")

        # Ring read/capture transactions are keyed by kind, slot and the real
        # issue address.  The current take coincides with the old issue, so it
        # must compare against the saved current address rather than that
        # edge's ring_addr field.
        if pre["ring_take_current"]:
            if "current" in self.ring_active:
                name, key, address = self.ring_active.pop("current")
                require(address == self.ring_expected_address(pre, "current")
                        and key[1:] == (0, int(pre["slot"]), address),
                        f"edge {pre['edge']}: current ring transaction drift")
                self.service_event(name, "RING_RESULT_CURRENT", key)
                events.add("RING_RESULT_CURRENT")
            else:
                require(not self.guard_active(self.roots["ring_current"], pre),
                        f"edge {pre['edge']}: active current ring take lacks issue")
        if pre["ring_take_old"]:
            if "old" in self.ring_active:
                name, key, address = self.ring_active.pop("old")
                require(address == self.ring_expected_address(pre, "old")
                        and key[1:] == (1, int(pre["slot"]), address),
                        f"edge {pre['edge']}: old ring transaction drift")
                self.service_event(name, "RING_RESULT_OLD", key)
                events.add("RING_RESULT_OLD")
            else:
                require(not self.guard_active(self.roots["ring_old"], pre),
                        f"edge {pre['edge']}: active old ring take lacks issue")
        if pre["ring_read"]:
            kind = "old" if pre["ring_take_current"] else "current"
            name = "ring_old" if kind == "old" else "ring_current"
            active = self.service_opportunity(name, pre)
            if active:
                address = self.ring_expected_address(pre, kind)
                require(int(pre["ring_addr"]) == address,
                        f"edge {pre['edge']}: {kind} ring issue address drift")
                kind_tag = 1 if kind == "old" else 0
                key = self.allocate_service(
                    name, "ring", kind, pre,
                    (kind_tag, int(pre["slot"]), address))
                require(kind not in self.ring_active,
                        f"root {name}: overlapping ring request")
                self.ring_active[kind] = (name, key, address)
        return events

    def event_names(self, pre: Json, post: Json) -> set[str]:
        events: set[str] = set()
        events.update(self.advance_services(pre, post))
        pph = int(pre["pph"])
        for name, phase in self.noise_phases.items():
            if pph == int(phase):
                events.add(name)
        cap = raw_int(pre["cap"])
        for name, index in self.cap_indices.items():
            if cap & (1 << int(index)):
                events.add(name)
        if pre["ring_read"]:
            events.add("RING1")
        if pre["ring_take_current"]:
            events.add("RING2")
        if pre["ring_take_old"]:
            events.add("RING3")
        if pre["state_write"]:
            events.add("STATE_WRITE")
        if pre["leaf_commit"]:
            events.add("LEAF_COMMIT")
        return events

    def guard_active(self, root: Json, pre: Json) -> bool:
        guard = root["guard"]
        if guard == "always":
            return True
        field, sense = {
            "wavetable": ("guard_wavetable", True),
            "wavetable&&play": ("guard_wavetable", True),
            "!wavetable": ("guard_wavetable", False),
            "blend_count!=64": ("guard_blend", True),
            "reverb": ("guard_reverb", True),
            "audible": ("guard_audible", True),
        }[guard]
        active = bool(pre[field]) == sense
        if guard == "wavetable&&play":
            active = active and bool(pre["guard_play"])
        return active

    def extract(self, spec: Json, pre: Json, post: Json) -> int:
        row = pre if spec["phase"] == "pre" else post
        field = spec["field"]
        if "selected_by" in spec:
            field = (spec["field_when_one"] if pre[spec["selected_by"]]
                     else spec["field_when_zero"])
        if field == "leaf_words":
            raw = ((raw_int(row["leaf_hi"]) & 3) << 16) \
                | raw_int(row["leaf_lo"])
            return signed_word(raw, 18)
        require(field in row, f"edge {pre['edge']}: trace lacks field {field}")
        return raw_int(row[field])

    def fits_root(self, name: str, value: int) -> None:
        root = self.roots[name]
        width = int(root["width"])
        if root["signed"]:
            require(-(1 << (width - 1)) <= value < (1 << (width - 1)),
                    f"root {name}: {value} exceeds signed-{width}")
        else:
            require(0 <= value < (1 << width),
                    f"root {name}: {value} exceeds unsigned-{width}")

    def observe_endpoint(self, name: str, role: str, spec: Json,
                         pre: Json, post: Json,
                         key_override: RootKey | None = None) -> None:
        root = self.roots[name]
        active = self.guard_active(root, pre)
        if role == "producer" and name not in self.service_roots:
            self.root_guards[name].add(int(active))
        if not active and not root["source_binding"]["observe_inactive"]:
            return
        producer_spec = root["source_binding"]["producer_observation"]
        consumer_spec = root["source_binding"]["consumer_observation"]
        same_event = producer_spec["event"] == consumer_spec["event"]
        if name in self.service_roots:
            if role == "producer":
                key = self.current_event_keys.get((name, spec["event"]))
                require(key is not None,
                        f"root {name}: producer lacks live result transaction")
            else:
                key = self.current_event_keys.get(
                    (name, spec["event"]), self.pending_service_keys.get(name))
                require(key is not None,
                        f"root {name}: consumer lacks live issue transaction")
        else:
            key = key_override or (
                (int(pre["sample"]), int(pre["slot"]), int(pre["edge"]))
                if same_event else (int(pre["sample"]), int(pre["slot"])))
        value = self.extract(spec, pre, post)
        self.fits_root(name, value)
        endpoint = self.pending_endpoints[(name, key)]
        require(role not in endpoint,
                f"root {name}: duplicate {role} at key {key}")
        endpoint[role] = value
        if role == "producer":
            self.root_producers[name] += 1
            self.pending_meta[(name, key)] = (int(pre["bank"]),
                                              int(pre["slot"]))
        else:
            self.root_consumers[name] += 1
        if set(endpoint) != {"producer", "consumer"}:
            return
        require(endpoint["producer"] == endpoint["consumer"],
                f"root {name}: producer {endpoint['producer']} != "
                f"consumer {endpoint['consumer']} at {key}")
        bank, slot = self.pending_meta.pop((name, key))
        self.root_joins[name] += 1
        self.root_slots[name].add(slot)
        self.root_banks[name].add(bank)
        self.root_bank_slots[name].add((bank, slot))
        group_key = (int(pre["sample"]), slot)
        if Counter(row["group"] for row in self.roots.values())[root["group"]] > 1:
            prior = self.root_values[name].get(group_key)
            require(prior is None or prior == endpoint["producer"],
                    f"root {name}: multiple values at {group_key}")
            self.root_values[name][group_key] = endpoint["producer"]
        del self.pending_endpoints[(name, key)]
        if name in self.service_roots:
            require(self.pending_service_keys.pop(name) == key,
                    f"root {name}: joined the wrong service transaction")
            self.service_takes[name] += 1

    def process_event(self, event: str, pre: Json, post: Json,
                      key_override: RootKey | None = None) -> None:
        for name, role, spec in self.endpoint_by_event.get(event, []):
            self.observe_endpoint(name, role, spec, pre, post, key_override)

    def check_hold(self, pre: Json, post: Json) -> bool:
        if not pre["hold"]:
            self.prior_hold_post = None
            self.prior_hold_service = None
            return False
        require(not any(pre[field] for field in HOLD_TRANSACTION_FIELDS),
                f"edge {pre['edge']}: held edge leaked a transaction")
        require(all(pre[field] == post[field] for field in HOLD_CARRIED_FIELDS),
                f"edge {pre['edge']}: carried value moved during hold")
        if self.prior_hold_post is not None:
            require(all(self.prior_hold_post[field] == pre[field]
                        for field in HOLD_CARRIED_FIELDS),
                    f"edge {pre['edge']}: carried value drifted between holds")
            require(all(self.prior_hold_post[field] == pre[field]
                        for field in ("bank", "slot", "pph", "cap")),
                    f"edge {pre['edge']}: held coordinates drifted")
            require(self.prior_hold_service
                    == tuple(sorted(self.pending_service_keys.items())),
                    f"edge {pre['edge']}: held service tags drifted")
        self.prior_hold_post = post
        self.prior_hold_service = tuple(sorted(self.pending_service_keys.items()))
        self.held_pairs += 1
        return True

    def voice_classes_for(self, pre: Json) -> set[str]:
        if not pre["guard_play"]:
            return {"stopped"}
        if not pre["guard_amplitude"]:
            classes = {"playing_zero"}
        else:
            classes = {"playing_nonzero"}
        if pre["guard_audible"]:
            classes.add("audible")
        if pre["guard_hidden"]:
            classes.add("hidden")
        return classes

    def fixed(self, action: str, producer: int, consumer: int,
              pre: Json, source_guards: GuardTuple | None = None) -> None:
        row = self.writes[action]
        require(0 <= producer < (1 << 16) and producer == consumer,
                f"fixed write {action}: source/consumer mismatch")
        commit_guards = self.guard_tuple(pre)
        if source_guards is None:
            source_guards = commit_guards
        require(len(source_guards) == len(GLOBAL_GUARDS),
                f"fixed write {action}: incomplete source guard tuple")
        self.fixed_guard_pairs[action].add((source_guards, commit_guards))
        for index, field in enumerate(GLOBAL_GUARDS):
            self.fixed_source_guards[action][field].add(source_guards[index])
            self.fixed_commit_guards[action][field].add(commit_guards[index])
        self.fixed_identities[action] += 1
        self.fixed_bank_slots[action].add((int(pre["bank"]), int(pre["slot"])))
        if action.startswith("STORE_LEAF_"):
            self.fixed_voice_classes[action].update(self.voice_classes_for(pre))

    def leaf_consumer(self, binding: Json, pre: Json, post: Json) -> int:
        field = binding["consumer_by_slot"][str(int(pre["slot"]))]
        require(field in post,
                f"edge {pre['edge']}: leaf consumer field {field} absent")
        raw18 = raw_int(post[field]) & 0x3ffff
        if binding["consumer_slice"] == "low16":
            return raw18 & 0xffff
        require(binding["consumer_slice"] == "sign_hi16",
                "unknown leaf consumer slice")
        return (((0xfffc if raw18 & 0x20000 else 0)
                 | ((raw18 >> 16) & 0x3)) & 0xffff)

    def capture_fixed_sources(self, events: set[str], pre: Json,
                              post: Json) -> None:
        key = (int(pre["sample"]), int(pre["slot"]))
        for action, row in self.writes.items():
            binding = row["source_binding"]
            spec = binding["source_observation"]
            if spec["event"] not in events or spec["event"] == "STATE_WRITE":
                continue
            source = self.extract(spec, pre, post)
            if binding["event"] == "leaf_commit":
                consumer = self.leaf_consumer(binding, pre, post)
                self.fixed(action, source, consumer, pre)
            else:
                source_key = (action, *key)
                require(source_key not in self.fixed_sources,
                        f"fixed write {action}: duplicate source at {key}")
                self.fixed_sources[source_key] = (source,
                                                  self.guard_tuple(pre))

    def check_memory(self, pre: Json, post: Json) -> None:
        if pre["state_read"]:
            txkey = (self.state_txid, int(pre["state_ra"]))
            self.state_txid += 1
            require(raw_int(post["state_q"]) == raw_int(pre["state_mem_r"]),
                    f"edge {pre['edge']}: state_q missed addressed memory {txkey}")
            self.state_transactions += 1
            self.state_read_words.add(int(pre["state_ra"]) & 0x3f)
        if not pre["state_write"]:
            return
        key = (int(pre["sample"]), int(pre["slot"]))
        word = int(pre["state_wa"]) & 0x3f
        source = raw_int(pre["state_wd"])
        consumer = raw_int(post["state_mem_w"])
        require(source == consumer,
                f"edge {pre['edge']}: state write missed memory")
        self.state_transactions += 1
        self.state_write_words.add(word)

        cap_actions = {int(row["destination"]): action
                       for action, row in self.writes.items()
                       if row["source_binding"]["event"] == "cap"}
        if word in cap_actions:
            action = cap_actions[word]
            source_key = (action, *key)
            require(source_key in self.fixed_sources,
                    f"fixed write {action}: missing CAP source at {key}")
            fixed_source, source_guards = self.fixed_sources.pop(source_key)
            require(fixed_source == source,
                    f"fixed write {action}: CAP source changed before commit")
        else:
            occurrence_key = (*key, word)
            occurrence = self.write_occurrences[occurrence_key]
            actions = self.write_actions.get(word, [])
            require(occurrence < len(actions),
                    f"edge {pre['edge']}: unbound state write word {word}")
            action = actions[occurrence]
            self.write_occurrences[occurrence_key] += 1
            binding = self.writes[action]["source_binding"]
            require(binding["event"] == "state_write"
                    and int(binding["word"]) == word,
                    f"fixed write {action}: manifest word drift")
            source_guards = self.guard_tuple(pre)
        self.fixed(action, source, consumer, pre, source_guards)

    def check_fold(self, pre: Json, post: Json) -> None:
        sample = int(pre["sample"])
        slot = int(pre["slot"])
        if pre["leaf_commit"]:
            self.fold_leaves[(sample, slot)] = int(pre["mix_leaf"])
            self.fold_values[sample][slot] = int(pre["mix_leaf"])

        fmc = int(pre["fmc"])
        if fmc == 1:
            index = self.fold_node_index[sample]
            require(index < len(self.fold_nodes),
                    f"sample {sample}: too many fold nodes")
            left, right, destination = self.fold_nodes[index]
            values = self.fold_values[sample]
            require(left in values and right in values,
                    f"sample {sample}: node {index} operands are not live")
            require(int(pre["fold_fda"]) == values[left]
                    and int(pre["fold_fdb"]) == values[right],
                    f"sample {sample}: node {index} operand lineage mismatch")
            expected_fsel = (0, 1, 3, 1, 2, 4, 3)[index]
            expected_fpend = (0, 1, 0, 0, 2, 1, 0)[index]
            expected_ffin = index >= 4
            expected_dst = {0: 0, 2: 1, 4: 1, 6: 2}[destination]
            require(int(pre["fsel"]) == expected_fsel
                    and int(pre["fpend"]) == expected_fpend
                    and bool(pre["ffin"]) == expected_ffin
                    and int(pre["fdsti"]) == expected_dst,
                    f"sample {sample}: node {index} fold control mismatch")
            self.fold_active_node[sample] = (index, left, right, destination)
            self.fold_starts[sample] += 1
            self.fold_node_index[sample] += 1

        if pre["fold_write"]:
            destination = int(pre["fold_write_dst"])
            field = ("fstk0", "fstk1", "fstk2")[destination]
            require(int(post[field]) == int(pre["phase_alu_y"]),
                    f"edge {pre['edge']}: explicit fold write missed ALU output")
            require(all(int(pre[other]) == int(post[other])
                        for other in ("fstk0", "fstk1", "fstk2")
                        if other != field),
                    f"edge {pre['edge']}: fold write changed another stack word")
            self.fold_stack_writes += 1

        if fmc == 9:
            require(sample in self.fold_active_node,
                    f"sample {sample}: fold completion lacks active node")
            index, _left, _right, destination = \
                self.fold_active_node.pop(sample)
            physical = {0: "fstk0", 2: "fstk1", 4: "fstk1", 6: "fstk2"}[
                destination]
            self.fold_values[sample][destination] = int(pre[physical])
            self.fold_sequence_checks += 1

        if pre["dry_valid"]:
            require(self.fold_node_index[sample] == len(self.fold_nodes)
                    and sample not in self.fold_active_node,
                    f"sample {sample}: dry publication preceded fold completion")
            require(int(pre["dry16"]) == int(pre["fstk0_low16"]),
                    f"edge {pre['edge']}: dry publication missed fold root")
            require(int(post["pcm"]) == int(pre["dry16"]),
                    f"edge {pre['edge']}: PCM missed dry publication")
            self.dry_samples.add(int(pre["sample"]))
            self.pcm_publications += 1

    def check_pair(self, pre: Json, post: Json) -> None:
        sample = int(pre["sample"])
        if self.last_sample is not None and sample > self.last_sample + 1:
            self.censor_lfsr_boundary("trace segment gap")
            require(not self.pending_service_keys and self.mul_active is None
                    and self.dq_active is None and self.wave_stage is None
                    and not self.ring_active,
                    "trace segment ended with a live service transaction")
        self.last_sample = sample
        self.value_pairs += 1
        for field in GLOBAL_GUARDS:
            self.global_guard_values[field].add(int(pre[field]))
        self.voice_classes.update(self.voice_classes_for(pre))
        if self.check_hold(pre, post):
            return

        self.check_memory(pre, post)
        events = self.event_names(pre, post)
        self.capture_fixed_sources(events, pre, post)
        for event in sorted(events):
            self.process_event(event, pre, post)

        visit_key = (int(pre["sample"]), int(pre["slot"]))
        if pre["state_read"] and self.next_state_key is not None \
                and visit_key != self.next_state_key:
            source_key = self.next_state_key
            self.process_event("NEXT_STATE_READ", pre, post, source_key)
            self.next_state_key = None
        if "W0" in events:
            require(self.next_state_key is None,
                    f"edge {pre['edge']}: prior LFSR source lacked consumer")
            self.next_state_key = visit_key
        self.check_fold(pre, post)

    def censor_lfsr_boundary(self, reason: str) -> None:
        require(self.next_state_key is not None,
                f"{reason}: bounded segment lacks final LFSR producers")
        censored = {
            (name, self.next_state_key)
            for name in ("lfsr_next", "lfsr2_next")
        }
        require(set(self.pending_endpoints) == censored,
                f"{reason}: unmatched root endpoints remain")
        for key in censored:
            require(set(self.pending_endpoints[key]) == {"producer"},
                    f"{reason}: right-censored root is not producer-only")
            del self.pending_endpoints[key]
            del self.pending_meta[key]
        self.right_censored_producers += len(censored)
        self.next_state_key = None

    def finish(self) -> dict[str, int]:
        # The final traced slot commits its post-W0 LFSRs after the last dry
        # publication, while their NEXT_STATE_READ consumer belongs to the
        # following sample and is outside the bounded stream.  Admit exactly
        # those two producer-only endpoints as an explicit right censor; no
        # other root or partially observed endpoint may escape the join.
        self.censor_lfsr_boundary("bounded stream end")
        require(not self.pending_endpoints,
                f"unmatched root endpoints: {sorted(self.pending_endpoints)[:8]}")
        require(not self.fixed_sources,
                f"unconsumed fixed sources: {sorted(self.fixed_sources)[:8]}")
        require(not self.pending_service_keys and self.mul_active is None
                and self.dq_active is None and self.wave_stage is None
                and not self.ring_active,
                "bounded stream ended with a live service transaction")
        all_bank_slots = {(bank, slot) for bank in (0, 1) for slot in range(8)}
        for name, root in self.roots.items():
            require(self.root_producers[name] > 0,
                    f"root {name}: no producer observation")
            require(self.root_consumers[name] > 0,
                    f"root {name}: no consumer observation")
            require(self.root_joins[name] > 0,
                    f"root {name}: no producer/consumer identity")
            require(self.root_bank_slots[name] == all_bank_slots,
                    f"root {name}: active identity misses a bank/slot class")
            guards = (self.service_issue_guards[name]
                      if name in self.service_roots else self.root_guards[name])
            if root["guard"] != "always":
                require(guards == {0, 1},
                        f"root {name}: issue/take guard classes incomplete")
            if name in self.service_roots:
                require(self.service_issues[name] == self.service_results[name]
                        == self.service_takes[name] == self.root_joins[name],
                        f"root {name}: service issue/result/take imbalance")

        groups: dict[str, list[str]] = defaultdict(list)
        for name, root in self.roots.items():
            groups[root["group"]].append(name)
        require(len(groups) == 27, "value-group count changed")
        group_identity_checks = 0
        for group, names in groups.items():
            if len(names) == 1:
                continue
            key_sets = [set(self.root_values[name]) for name in names]
            require(key_sets and all(keys == key_sets[0] for keys in key_sets),
                    f"group {group}: root transaction keys differ")
            for key in key_sets[0]:
                values = {self.root_values[name][key] for name in names}
                require(len(values) == 1,
                        f"group {group}: value mismatch at {key}: {values}")
                group_identity_checks += len(names) - 1

        missing_fixed_guards: list[str] = []
        for action in self.writes:
            require(self.fixed_identities[action] > 0,
                    f"fixed write {action}: no live source identity")
            require(self.fixed_bank_slots[action] == all_bank_slots,
                    f"fixed write {action}: misses a bank/slot class")
            require(bool(self.fixed_guard_pairs[action]),
                    f"fixed write {action}: no source/commit guard tuple")
            for field in self.fixed_guard_obligations[action]:
                if self.fixed_source_guards[action][field] != {0, 1}:
                    missing_fixed_guards.append(
                        f"{action}:{field}="
                        f"{sorted(self.fixed_source_guards[action][field])}")
                require(bool(self.fixed_commit_guards[action][field]),
                        f"fixed write {action}: commit predicate {field} absent")
        require(not missing_fixed_guards,
                "fixed-write source guard coverage incomplete: "
                + ", ".join(missing_fixed_guards))
        leaf_classes = {"audible", "hidden", "stopped", "playing_zero",
                        "playing_nonzero"}
        for action in ("STORE_LEAF_LO", "STORE_LEAF_HI"):
            require(leaf_classes <= self.fixed_voice_classes[action],
                    f"fixed write {action}: leaf voice classes incomplete")
        require(set(range(10, 24)) == self.state_write_words,
                "persistent state write words changed")
        require(set(range(10, 24)) <= self.state_read_words
                and set(range(24, 32)) <= self.state_read_words
                and {26, 30} <= self.state_read_words,
                "state reads miss oscillator or parameter-bank words")
        require(self.held_pairs == 3,
                f"expected three held legacy pairs, got {self.held_pairs}")
        for field in GLOBAL_GUARDS:
            require(self.global_guard_values[field] == {0, 1},
                    f"global guard {field} misses a class")
        require({"audible", "hidden", "stopped", "playing_zero",
                 "playing_nonzero"} <= self.voice_classes,
                f"voice classes incomplete: {sorted(self.voice_classes)}")
        require(len(self.dry_samples) >= 199,
                "fewer than 199 completed dry publications")
        require(all(self.fold_starts[sample] == 7
                    for sample in self.dry_samples),
                "a published sample does not contain seven fold starts")
        require(self.fold_sequence_checks == 7 * len(self.dry_samples),
                "ordered fold-node completion count changed")
        require(self.fold_stack_writes > 0,
                "fold stack value transfer coverage is empty")
        require(self.pcm_publications == len(self.dry_samples),
                "PCM publication count changed")
        return {
            "dry_publications": len(self.dry_samples),
            "fixed_guard_obligations": sum(
                len(fields) for fields in self.fixed_guard_obligations.values()),
            "fixed_writes": len(self.fixed_identities),
            "fold_stack_writes": self.fold_stack_writes,
            "group_identity_checks": group_identity_checks,
            "groups": len(groups),
            "held_pairs": self.held_pairs,
            "pcm_publications": self.pcm_publications,
            "roots": len(self.root_joins),
            "right_censored_producers": self.right_censored_producers,
            "service_transactions": sum(self.service_takes.values()),
            "state_transactions": self.state_transactions,
            "value_pairs": self.value_pairs,
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="prove R.84 manifest-bound live RTL value lineage")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--values", type=Path, required=True)
    parser.add_argument("--mul", type=Path, required=True)
    parser.add_argument("--dq", type=Path, required=True)
    parser.add_argument("--execwave", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    manifest = json.loads(args.manifest.read_text())
    require(isinstance(manifest, dict), "manifest is not one JSON object")
    check_manifest(manifest)

    proof = ValueProof(manifest)
    for pre, post in iter_pairs(args.values):
        proof.check_pair(pre, post)
    stats = proof.finish()

    mul_stats = check_multiplier(load_jsonl(args.mul))
    dq_stats = check_dq(load_jsonl(args.dq))
    execwave_stats = check_execwave(load_jsonl(args.execwave))
    stats.update(mul_stats)
    stats.update(dq_stats)
    stats.update(execwave_stats)
    primitive_bound = 0
    for root in manifest["roots"]:
        owner = root["owner"]
        if "service:mul" in owner:
            require(mul_stats["mul_fast_pairs"] > 0,
                    f"root {root['name']}: multiplier cadence unproved")
            primitive_bound += 1
        elif "service:dq" in owner:
            require(dq_stats["dq_pairs"] > 0,
                    f"root {root['name']}: DQ cadence unproved")
            primitive_bound += 1
        elif "service:wave" in owner or "service:aram" in owner:
            require(execwave_stats["wave_joins"] > 0
                    and execwave_stats["aram_joins"] > 0,
                    f"root {root['name']}: wave/ARAM cadence unproved")
            primitive_bound += 1
    stats["primitive_structural_roots"] = primitive_bound

    print("psg_exec_values: PASS "
          + " ".join(f"{key}={stats[key]}" for key in sorted(stats)))
    print("boundary: manifest-bound raw RTL producer/consumer identities; "
          "primitive traces contribute cadence/freeze proof only; no semantic "
          "equations, candidate write data, integration, synthesis or area claim")


if __name__ == "__main__":
    main()
