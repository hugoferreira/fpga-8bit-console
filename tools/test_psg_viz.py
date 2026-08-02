#!/usr/bin/env python3
"""Focused regression tests for the source-derived PSG visualization model."""

import copy
import json
import os
import tempfile
import unittest

import psg_viz as viz


MUX = """
always_comb begin
  wmul_start = 1'b0;
  wmul_a = '0;
  (* parallel_case *) case (1'b1)
    ((cap[CAP_ALPHA] || renamed_req) && feature_on): begin
      wmul_start = 1'b1;
      wmul_a = source_a;
      wmul_b = 12'd17;
      wmul_mode = 3'd1;
    end
    cap[CAP_BETA]: if (count != 7'd3) begin
      wmul_start = 1'b1;
      wmul_a = source_b;
      wmul_b = narrow_b;
      wmul_mode = 3'd2;
      wmul_short = 1'b1;
    end
    default: ;
  endcase
end
""".splitlines()


class SourceShapeTests(unittest.TestCase):
    def test_direct_requests_are_discovered_without_known_names(self):
        lines = [
            "localparam int AUX_PHASE = 19;",
            "wire renamed_req = enabled",
            "                   && (pph == 9'(AUX_PHASE));",
        ]
        self.assertEqual(viz.parse_phase_requests(lines),
                         {"renamed_req": "AUX_PHASE"})

    def test_request_mux_derives_selectors_and_guards(self):
        arms = viz.parse_mul_arms(MUX, {"renamed_req": "AUX_PHASE"})
        self.assertEqual(set(arms), {"CAP_ALPHA", "renamed_req", "CAP_BETA"})
        self.assertEqual(arms["CAP_ALPHA"]["variants"][0]["guard"], "feature_on")
        self.assertEqual(arms["renamed_req"]["variants"][0]["guard"], "feature_on")
        beta = arms["CAP_BETA"]["variants"][0]
        self.assertEqual(beta["guard"], "count != 7'd3")
        self.assertEqual(beta["modes"], [2])
        self.assertTrue(beta["short"])

    def test_phase_parsers_ignore_cast_width(self):
        lines = [
            "case   ( pph )",
            "  11'(PWORK + 2): begin",
            "    value <= state_q;",
            "  end",
            "endcase",
            "if (pph == 13'd27) pulse <= 1'b1;",
        ]
        blocks = viz.parse_pph_cases(lines)
        self.assertEqual(blocks[0]["arms"][0]["key"], "PWORK + 2")
        events = viz.parse_pph_events(lines, 0, len(lines), "test")
        self.assertEqual([event["expr"] for event in events], ["27"])

    def test_write_phases_follow_assignment_cone_and_variant_guard(self):
        lines = [
            "wire late_write = !REALTIME_PREVIEW",
            "                  && (pph == 9'(PLAST - 1));",
            "assign state_sample_we = in_store_window || late_write;",
        ]
        self.assertEqual(viz.signal_phase_exprs(lines, "state_sample_we"),
                         {"PLAST - 1": "hw"})

    def test_product_consumers_follow_helpers_and_direct_phases(self):
        lines = """
wire signed [16:0] scaled = m_res[22:6];
task apply_result(input logic run);
  if (run) sink <= scaled;
endtask
cap[CAP_USE]: begin
  apply_result(1'b1);
end
if (pph == 10'(AUX_PHASE))
  other_sink <= scaled;
""".splitlines()
        closure = viz.result_closure(lines)
        self.assertIn("apply_result", closure)
        self.assertEqual(viz.product_consumers(
            lines, viz.parse_cap_arms(lines), closure), {"CAP_USE"})
        self.assertEqual(viz.phase_product_consumers(lines, closure),
                         {"AUX_PHASE"})

    def test_profiles_come_from_live_guards(self):
        arms = viz.parse_mul_arms(MUX, {"renamed_req": "AUX_PHASE"})
        profiles, overflow = viz.derive_profiles(arms)
        self.assertEqual(overflow, [])
        self.assertEqual(len(profiles), 4)
        self.assertEqual(sum(bool(viz.active_variants(arms["CAP_ALPHA"], p))
                             for p in profiles), 2)
        self.assertEqual(sum(bool(viz.active_variants(arms["CAP_BETA"], p))
                             for p in profiles), 2)

    def test_operand_width_follows_ternary_branches(self):
        widths = {"left": 9, "right": 12}
        self.assertEqual(viz.operand_width(
            "choose ? {3'b0, left} : 12'(right)", widths),
            (12, "signal", None))

    def test_pipeline_depths_are_read_from_source_contracts(self):
        self.assertEqual(viz.state_read_latency([
            "always_ff @(posedge clk)",
            "  state_q <= state_m[state_ra];",
        ]), 1)
        with self.assertRaises(RuntimeError):
            viz.state_read_latency([
                "always_ff @(posedge clk)",
                "  state_pipe <= state_m[state_ra];",
                "  state_q <= state_pipe;",
            ])
        self.assertEqual(viz.wave_pipeline_stages([
            "// Three-stage computed-wave pipeline.",
        ]), 3)

    def test_straight_runs_do_not_depend_on_state_order(self):
        seq = {
            "states": [{"name": name} for name in "ABCDX"],
            "transitions": [
                {"from": "A", "to": "B", "guards": []},
                {"from": "B", "to": "C", "guards": []},
                {"from": "C", "to": "D", "guards": []},
            ],
        }
        want = [["A", "B", "C", "D"]]
        self.assertEqual(viz.straight_runs(seq), want)
        seq["states"].reverse()
        self.assertEqual(viz.straight_runs(seq), want)

    def test_trace_summary_distinguishes_stalls_and_forward_jumps(self):
        schedules = {"hw": {"n": 6}, "preview": {"n": 3}}
        rows = [
            {"cycle": 10, "pph": 0, "prun": 1},
            {"cycle": 11, "pph": 1, "prun": 1},
            {"cycle": 12, "pph": 1, "prun": 1},
            {"cycle": 13, "pph": 4, "prun": 1},
        ]
        summary = viz.summarise_trace(
            viz.normalize_trace_records(rows), schedules)["hw"]
        self.assertEqual(summary["counts"], [1, 2, 0, 0, 1, 0])
        self.assertEqual(summary["stalls"], [0, 1, 0, 0, 0, 0])
        self.assertEqual(summary["skipped"], [0, 0, 1, 1, 0, 0])
        self.assertEqual(summary["jumps"],
                         [{"from": 1, "to": 4, "count": 1}])

    def test_trace_loader_accepts_budget_testbench_jsonl(self):
        handle, path = tempfile.mkstemp(suffix=".jsonl")
        try:
            with os.fdopen(handle, "w") as stream:
                stream.write(json.dumps({"cycle": 1, "pph": 0,
                                         "prun": 1, "schedule": "preview"})
                             + "\n")
                stream.write(json.dumps({"cycle": 2, "pph": 1,
                                         "prun": 1, "schedule": "preview"})
                             + "\n")
            trace = viz.load_trace(path, {"hw": {"n": 6},
                                          "preview": {"n": 3}})
            self.assertEqual(trace["records"], 2)
            self.assertEqual(trace["schedules"]["preview"]["counts"],
                             [1, 1, 0])
            streamed, metadata = viz.trace_row_stream(path, eager_limit=0)
            self.assertEqual(metadata, {})
            self.assertEqual([row["pph"] for row in streamed], [0, 1])
        finally:
            os.unlink(path)

    def test_semantic_clusters_follow_edges_not_state_names_or_enum_order(self):
        seq = {
            "states": [{"name": name, "cluster_hint": ""}
                       for name in ["RENAMED_Z", "ALPHA", "MID", "OMEGA"]],
            "transitions": [
                {"from": "ALPHA", "to": "MID", "guards": [], "line": 1},
                {"from": "MID", "to": "OMEGA",
                 "guards": [{"kind": "if", "cond": "take"}], "line": 2},
                {"from": "OMEGA", "to": "RENAMED_Z", "guards": [], "line": 3},
            ],
        }
        viz.semantic_clusters(seq)
        want = {frozenset(cluster["members"]) for cluster in seq["clusters"]}
        self.assertEqual(want, {frozenset({"ALPHA", "MID"}),
                                frozenset({"OMEGA", "RENAMED_Z"})})
        seq["states"].reverse()
        viz.semantic_clusters(seq)
        self.assertEqual({frozenset(cluster["members"])
                          for cluster in seq["clusters"]}, want)


class LiveModelTests(unittest.TestCase):
    def test_live_model_is_complete_without_named_request_exceptions(self):
        walk = viz.extract_walk()
        self.assertGreater(walk["voice_count"], 0)
        self.assertTrue(walk["phase_requests"])
        self.assertTrue(set(walk["phase_requests"]) <= set(walk["mul_arms"]))
        self.assertEqual(walk["mul_service"], "psg_mulmp")
        self.assertEqual(walk["mul_radix_bits"], 1)
        self.assertEqual(walk["mul_iters"], {0: 8, 1: 10, 2: 12, 3: 9})
        self.assertEqual((walk["mul_ready_gap"],
                          walk["mul_short_ready_gap"]), (5, 4))
        for schedule in walk["schedules"].values():
            self.assertEqual(schedule["n"], schedule["params"]["PLAST"] + 1)

        seq = viz.layout_fsm(viz.extract_seq())
        self.assertTrue(seq["clusters"])
        self.assertTrue(all(node.get("cluster") for node in seq["states"]))
        expected_runs = viz.straight_runs(seq)
        reversed_seq = copy.deepcopy(seq)
        reversed_seq["states"].reverse()
        self.assertEqual(viz.straight_runs(reversed_seq), expected_runs)

        model = {"walk": walk, "seq": seq}
        model["findings"] = viz.analyse(model)
        for schedule in walk["schedules"].values():
            graph = viz.build_dependency_graph(
                schedule, walk["mul_arms"], walk["profiles"])
            self.assertTrue(graph["nodes"])
            if schedule is walk["schedules"]["hw"]:
                self.assertTrue({"product", "record"} <=
                                {edge["kind"] for edge in graph["edges"]})
        width_finding = next(f for f in model["findings"]
                             if f["id"] == "mul-width")
        self.assertEqual(
            width_finding["measure"]["constant operands too wide for issued shape"],
            0)
        slack_finding = next(f for f in model["findings"]
                             if f["id"] == "mul-slack")
        self.assertEqual(slack_finding["measure"]["max slack found"], 0)
        self.assertEqual({row[3] for row in slack_finding["table"]["rows"]},
                         {4, 5})
        for schedule in walk["schedules"].values():
            self.assertFalse([p["pph"] for p in schedule["phases"]
                              if p["klass"] == "unexplained"])

        preview_floor = next(f for f in model["findings"]
                             if f["id"] == "floor-preview")
        self.assertEqual(len(preview_floor["table"]["rows"]), 1)

        for variant in ("hw", "preview"):
            occupancy = next(f for f in model["findings"]
                             if f["id"] == f"occupancy-{variant}")
            phases = walk["schedules"][variant]["phases"]
            self.assertEqual(
                occupancy["measure"]["phases with record/wave/product holders"],
                sum(bool(p["holders"]) for p in phases))
            self.assertEqual(
                occupancy["measure"]["nominal full-path phase positions/sample"],
                len(phases) * walk["voice_count"])
            if variant == "preview":
                self.assertEqual(len(occupancy["table"]["rows"]), 1)
            for row in occupancy["table"]["rows"]:
                self.assertEqual(row[1], row[2] + row[3])

            for row in walk["cycle_accounting"][variant]:
                self.assertEqual(
                    row["scheduled"],
                    len(row["occupied"]) + len(row["conditional"])
                    + len(row["blocked"]) + len(row["unattributed"]))


if __name__ == "__main__":
    unittest.main()
