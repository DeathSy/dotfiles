#!/usr/bin/python3 -I
"""Tests for hc-worker: pure tidy layout logic, RPC edit/retry loop, and CLI option handling.

Run: /usr/bin/python3 -I -B nixpkgs/home-manager/ai/tests/test_hc_worker.py
"""
import copy
import importlib.util
import io
import json
import os
import re
import subprocess
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
MOD_PATH = os.path.join(os.path.dirname(HERE), "hc-worker.py")
SPEC = importlib.util.spec_from_file_location("hc_worker", MOD_PATH)
hw = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(hw)


def blk(bid, term, weight=None):
    node = {"type": "block", "id": bid, "content": {"terminal": term}}
    if weight is not None:
        node["size"] = {"weight": weight}
    return node


def row(rid, children, weight=None):
    node = {"type": "row", "id": rid, "children": children}
    if weight is not None:
        node["size"] = {"weight": weight}
    return node


def col(cid, children, weight=None):
    node = {"type": "column", "id": cid, "children": children}
    if weight is not None:
        node["size"] = {"weight": weight}
    return node


def make_doc(root, *, space_id="sp1", tab_id="tb1", extra_tabs=None, extra_spaces=None):
    tabs = [{"id": tab_id, "name": "", "root": root}]
    if extra_tabs:
        tabs.extend(extra_tabs)
    spaces = [{"id": space_id, "name": "work", "folder": "/tmp", "tabs": tabs}]
    if extra_spaces:
        spaces.extend(extra_spaces)
    return {"spaces": spaces}


class TidyTests(unittest.TestCase):
    def test_observed_shape_1_single_worker_side_by_side(self):
        # App splits single pane into root row [t2v 0.5, t8c 0.5]
        doc = make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]))
        before = copy.deepcopy(doc)
        res = hw.tidy(doc, "sp1", "tb1", "t2v", lambda a: a == "t8c")
        self.assertIsNotNone(res)
        self.assertEqual(doc, before)  # input untouched

        new_root = res["spaces"][0]["tabs"][0]["root"]
        self.assertEqual(new_root["type"], "row")
        self.assertEqual(new_root["id"], "tb1")
        self.assertEqual(len(new_root["children"]), 2)
        self.assertEqual(new_root["children"][0], blk("p1", "t2v", 0.7))

        right = new_root["children"][1]
        self.assertEqual(right["type"], "column")
        self.assertRegex(right["id"], r"^s[0-9a-f]{32}$")
        self.assertEqual(right["size"], {"weight": 0.3})
        self.assertEqual(right["children"], [blk("p2", "t8c", 1.0)])

    def test_observed_shape_2_second_worker_reuses_column_id(self):
        # App splits inside existing column: row [t2v 0.7, col(s_keep, 0.3) [row 1.0 [t8c, t8d]]]
        doc = make_doc(row("tb1", [
            blk("p1", "t2v", 0.7),
            col("s_keep", [row("s_inner", [blk("p2", "t8c", 0.5), blk("p3", "t8d", 0.5)], 1.0)], 0.3),
        ]))
        res = hw.tidy(doc, "sp1", "tb1", "t2v", lambda a: a in {"t8c", "t8d"})
        self.assertIsNotNone(res)
        new_root = res["spaces"][0]["tabs"][0]["root"]
        self.assertEqual(new_root, row("tb1", [
            blk("p1", "t2v", 0.7),
            col("s_keep", [blk("p2", "t8c", 0.5), blk("p3", "t8d", 0.5)], 0.3),
        ]))

    def test_three_workers_nested_row_and_column_flattened(self):
        doc = make_doc(row("tb1", [
            blk("p1", "t2v", 0.7),
            col("s_col", [
                blk("p2", "t8c", 0.5),
                row("s_r", [
                    blk("p3", "t8d", 0.5),
                    col("s_c", [blk("p4", "t8e", 1.0)], 0.5),
                ], 0.5),
            ], 0.3),
        ]))
        res = hw.tidy(doc, "sp1", "tb1", "t2v", lambda a: a in {"t8c", "t8d", "t8e"})
        self.assertIsNotNone(res)
        right = res["spaces"][0]["tabs"][0]["root"]["children"][1]
        self.assertEqual(right["id"], "s_col")
        self.assertEqual(right["size"], {"weight": 0.3})
        self.assertEqual([b["id"] for b in right["children"]], ["p2", "p3", "p4"])
        self.assertEqual([b["content"]["terminal"] for b in right["children"]], ["t8c", "t8d", "t8e"])
        for b in right["children"]:
            self.assertAlmostEqual(b["size"]["weight"], 1.0 / 3.0)

    def test_already_tidy_returns_none_with_float_tolerance(self):
        doc = make_doc(row("tb1", [
            blk("p1", "t2v", 0.699999988),
            col("s_col", [
                blk("p2", "t8c", 0.333333343),
                blk("p3", "t8d", 0.333333313),
                blk("p4", "t8e", 0.333333343),
            ], 0.300000012),
        ]))
        self.assertIsNone(hw.tidy(doc, "sp1", "tb1", "t2v", lambda a: True))

    def test_foreign_terminal_returns_none(self):
        doc = make_doc(row("tb1", [
            blk("p1", "t2v", 0.5),
            blk("p2", "t8c", 0.25),
            blk("p3", "t99", 0.25),
        ]))
        self.assertIsNone(hw.tidy(doc, "sp1", "tb1", "t2v", lambda a: a == "t8c"))

    def test_duplicate_blocks_return_none(self):
        doc_dup_worker = make_doc(row("tb1", [
            blk("p1", "t2v", 0.4),
            blk("p2", "t8c", 0.3),
            blk("p3", "t8c", 0.3),
        ]))
        self.assertIsNone(hw.tidy(doc_dup_worker, "sp1", "tb1", "t2v", lambda a: True))

        doc_dup_parent = make_doc(row("tb1", [
            blk("p1", "t2v", 0.4),
            blk("p2", "t2v", 0.3),
            blk("p3", "t8c", 0.3),
        ]))
        self.assertIsNone(hw.tidy(doc_dup_parent, "sp1", "tb1", "t2v", lambda a: True))

    def test_parent_missing_or_only_parent_returns_none(self):
        no_parent = make_doc(row("tb1", [blk("p2", "t8c", 0.5), blk("p3", "t8d", 0.5)]))
        self.assertIsNone(hw.tidy(no_parent, "sp1", "tb1", "t2v", lambda a: True))

        only_parent = make_doc(row("tb1", [blk("p1", "t2v", 1.0)]))
        self.assertIsNone(hw.tidy(only_parent, "sp1", "tb1", "t2v", lambda a: True))

    def test_invalid_tree_cases_return_none(self):
        bad_roots = [
            # unknown node type
            row("tb1", [blk("p1", "t2v", 0.5), {"type": "tabs", "id": "x", "children": [blk("p2", "t8c")]}]),
            # extra key on row
            {**row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]), "extra": 1},
            # extra key on block
            row("tb1", [blk("p1", "t2v", 0.5), {**blk("p2", "t8c", 0.5), "extra": 1}]),
            # extra key on content
            row("tb1", [blk("p1", "t2v", 0.5), {"type": "block", "id": "p2", "content": {"terminal": "t8c", "x": 1}}]),
            # bad size: 0, negative, bool, NaN, inf, string, extra key
            row("tb1", [blk("p1", "t2v", 0), blk("p2", "t8c", 0.5)]),
            row("tb1", [blk("p1", "t2v", -0.5), blk("p2", "t8c", 0.5)]),
            row("tb1", [blk("p1", "t2v", True), blk("p2", "t8c", 0.5)]),
            row("tb1", [blk("p1", "t2v", float("nan")), blk("p2", "t8c", 0.5)]),
            row("tb1", [blk("p1", "t2v", float("inf")), blk("p2", "t8c", 0.5)]),
            row("tb1", [blk("p1", "t2v", "0.5"), blk("p2", "t8c", 0.5)]),
            row("tb1", [blk("p1", "t2v", 0.5), {"type": "block", "id": "p2", "content": {"terminal": "t8c"}, "size": {"weight": 0.5, "x": 1}}]),
            # empty children
            row("tb1", [blk("p1", "t2v", 0.5), col("c1", [])]),
            # root not a row
            col("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]),
            # root id != tab id
            row("tb_other", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]),
            # non-string id
            row("tb1", [blk(123, "t2v", 0.5), blk("p2", "t8c", 0.5)]),
        ]
        for bad in bad_roots:
            with self.subTest(bad=bad):
                self.assertIsNone(hw.tidy(make_doc(bad), "sp1", "tb1", "t2v", lambda a: True))

    def test_missing_space_or_tab_returns_none(self):
        doc = make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]))
        self.assertIsNone(hw.tidy(doc, "sp_missing", "tb1", "t2v", lambda a: True))
        self.assertIsNone(hw.tidy(doc, "sp1", "tb_missing", "t2v", lambda a: True))
        self.assertIsNone(hw.tidy({"bad": 1}, "sp1", "tb1", "t2v", lambda a: True))

    def test_other_spaces_and_tabs_untouched(self):
        other_tab = {"id": "tb2", "name": "other", "root": row("tb2", [blk("px", "t9a", 1.0)]), "custom": [1, 2]}
        other_space = {"id": "sp2", "name": "s2", "folder": "/other", "tabs": [
            {"id": "tb3", "name": "", "root": row("tb3", [blk("py", "t9b", 1.0)])},
        ]}
        doc = make_doc(
            row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]),
            extra_tabs=[other_tab],
            extra_spaces=[other_space],
        )
        doc["extra_top"] = {"keep": True}
        res = hw.tidy(doc, "sp1", "tb1", "t2v", lambda a: a == "t8c")
        self.assertIsNotNone(res)
        self.assertEqual(res["extra_top"], {"keep": True})
        self.assertEqual(res["spaces"][0]["tabs"][1], other_tab)
        self.assertEqual(res["spaces"][1], other_space)


class RpcAndEditLoopTests(unittest.TestCase):
    def test_doc_call_framing_and_error_suppression(self):
        seen_in = []

        def fake_connect(text):
            seen_in.append(text)
            lines = [
                json.dumps({"jsonrpc": "2.0", "id": 1, "result": {"ok": True}}),
                json.dumps({
                    "jsonrpc": "2.0", "id": 2,
                    "error": {"code": -32000, "message": "SECRET_SERVER_TEXT_123", "data": {"kind": "weird_unlisted"}},
                }),
            ]
            return 0, "\n".join(lines) + "\n"

        with self.assertRaises(hw.Fail) as ctx:
            hw.doc_call("doc.get", {"name": "herdr-app"}, connect=fake_connect)
        self.assertEqual(str(ctx.exception), "doc.get: rpc error")
        self.assertNotIn("SECRET_SERVER_TEXT_123", str(ctx.exception))
        sent = [json.loads(line) for line in seen_in[0].splitlines()]
        self.assertEqual(sent[0]["method"], "hello")
        self.assertEqual(sent[1]["method"], "doc.get")

    def test_doc_call_known_kind_and_conflict(self):
        def make_conn(kind, msg):
            def conn(_text):
                return 0, json.dumps({
                    "jsonrpc": "2.0", "id": 2,
                    "error": {"code": -32000, "message": msg, "data": {"kind": kind}},
                }) + "\n"
            return conn

        with self.assertRaises(hw.DocConflict) as ctx:
            hw.doc_call("doc.set", {}, connect=make_conn("conflict", "SECRET_CONFLICT_MSG"))
        self.assertEqual(str(ctx.exception), "doc.set: conflict")
        self.assertNotIn("SECRET_CONFLICT_MSG", str(ctx.exception))

        with self.assertRaises(hw.Fail) as ctx2:
            hw.doc_call("doc.set", {}, connect=make_conn("unavailable", "SECRET_UNAVAIL_MSG"))
        self.assertEqual(str(ctx2.exception), "doc.set: unavailable")
        self.assertNotIn("SECRET_UNAVAIL_MSG", str(ctx2.exception))

    def test_hc_connect_strips_hc_env_vars(self):
        captured = {}

        def fake_run(cmd, **kwargs):
            captured["cmd"] = cmd
            captured["kwargs"] = kwargs
            return subprocess.CompletedProcess(cmd, 0, stdout="ok", stderr="")

        with mock.patch.dict(os.environ, {"HC_TERMINAL_ID": "t2v", "HC_SOCKET": "/tmp/s", "PATH": "/usr/bin"}, clear=True):
            with mock.patch.object(subprocess, "run", side_effect=fake_run):
                rc, out = hw.hc_connect("hi\n", hc="/fake/hc")
        self.assertEqual((rc, out), (0, "ok"))
        self.assertEqual(captured["cmd"], ["/fake/hc", "connect"])
        self.assertEqual(captured["kwargs"]["timeout"], 10)
        self.assertNotIn("HC_TERMINAL_ID", captured["kwargs"]["env"])
        self.assertNotIn("HC_SOCKET", captured["kwargs"]["env"])
        self.assertIn("PATH", captured["kwargs"]["env"])

    def test_edit_doc_conflict_then_success_rereads_and_recomputes(self):
        docs = [
            {"version": 1, "value": make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]))},
            {"version": 2, "value": make_doc(row("tb1", [
                blk("p1", "t2v", 0.7),
                col("s_new", [row("s_r", [blk("p2", "t8c", 0.5), blk("p3", "t8d", 0.5)], 1.0)], 0.3),
            ]))},
        ]
        gets, sets = [], []

        def fake_rpc(method, params):
            if method == "doc.get":
                cur = docs[len(gets)]
                gets.append(cur["version"])
                return copy.deepcopy(cur)
            sets.append((params["version"], params["value"]))
            if len(sets) == 1:
                raise hw.DocConflict("doc.set: conflict")
            return {}

        res = hw.edit_doc(lambda v: hw.tidy(v, "sp1", "tb1", "t2v", lambda a: a in {"t8c", "t8d"}), rpc=fake_rpc)
        self.assertEqual(gets, [1, 2])
        self.assertEqual([v for v, _ in sets], [1, 2])
        # Second write recomputed against v2 (both t8c and t8d, reusing s_new)
        right = res["spaces"][0]["tabs"][0]["root"]["children"][1]
        self.assertEqual(right["id"], "s_new")
        self.assertEqual([b["content"]["terminal"] for b in right["children"]], ["t8c", "t8d"])

    def test_edit_doc_five_conflicts_gives_up_with_fixed_message(self):
        doc = make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]))
        calls = {"get": 0, "set": 0}

        def fake_rpc(method, params):
            if method == "doc.get":
                calls["get"] += 1
                return {"version": calls["get"], "value": copy.deepcopy(doc)}
            calls["set"] += 1
            raise hw.DocConflict("doc.set: conflict")

        with self.assertRaises(hw.DocBusy) as ctx:
            hw.edit_doc(lambda v: hw.tidy(v, "sp1", "tb1", "t2v", lambda a: a == "t8c"), rpc=fake_rpc)
        self.assertEqual(calls, {"get": 5, "set": 5})
        self.assertIn("5 tries", str(ctx.exception))


class CliTests(unittest.TestCase):
    def run_cli(self, argv, *, env=None, run_hc=None, get_term=None, rpc=None, clock=None, sleep=None):
        out, err = io.StringIO(), io.StringIO()
        t = [0.0]

        def default_clock():
            return t[0]

        def default_sleep(dt):
            t[0] += dt

        rc = hw.main(
            argv,
            env={"HC_TERMINAL_ID": "t2v"} if env is None else env,
            run_hc=run_hc or (lambda a: (0, '{"address":"t8c"}\n', "")),
            get_term=get_term or (lambda a: None),
            rpc=rpc or (lambda m, p: {}),
            clock=clock or default_clock,
            sleep=sleep or default_sleep,
            out=out,
            err=err,
        )
        return rc, out.getvalue(), err.getvalue()

    def test_missing_hc_terminal_id_exits_2(self):
        rc, out, err = self.run_cli(["--", "echo", "hi"], env={})
        self.assertEqual(rc, 2)
        self.assertEqual(out, "")
        self.assertIn("HC_TERMINAL_ID", err)

    def test_help(self):
        rc, out, err = self.run_cli(["--help"], env={})
        self.assertEqual(rc, 0)
        self.assertIn("usage: hc-worker", out)
        self.assertEqual(err, "")

    def test_option_handling_adds_missing_flags_and_labels(self):
        terms = {
            "t2v": {"address": "t2v", "labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}},
            "t8c": {"address": "t8c", "parent": "t2v"},
        }
        seen_run = []
        raw_out = '{"address":"t8c","name":"w1","parent":"t2v","state":"live"}\n'
        doc_state = {"version": 1, "value": make_doc(row("tb1", [blk("p1", "t2v", 1.0)]))}
        polls = [0]

        def fake_run(args):
            seen_run.append(args)
            return 0, raw_out, ""

        def fake_rpc(method, params):
            if method == "doc.get":
                polls[0] += 1
                if polls[0] >= 3:
                    # App adds t8c on 3rd poll
                    doc_state["value"] = make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]))
                return copy.deepcopy(doc_state)
            doc_state["version"] += 1
            doc_state["value"] = params["value"]
            return {}

        rc, out, err = self.run_cli(
            ["--bg", "--name", "w1", "--cwd", "/tmp", "--", "codex", "--full"],
            run_hc=fake_run,
            get_term=terms.get,
            rpc=fake_rpc,
        )
        self.assertEqual(rc, 0)
        self.assertEqual(out, raw_out)
        self.assertEqual(err, "")
        # --bg was already present; --json and --no-notify added; labels added
        self.assertEqual(seen_run[0], [
            "--bg", "--name", "w1", "--cwd", "/tmp",
            "--json", "--no-notify",
            "--label=herdr.space=sp1", "--label=herdr.tab=tb1",
            "--", "codex", "--full",
        ])
        # Tab was tidied to 70/30
        final_root = doc_state["value"]["spaces"][0]["tabs"][0]["root"]
        self.assertEqual(final_root["children"][0]["size"], {"weight": 0.7})
        self.assertEqual(final_root["children"][1]["type"], "column")
        self.assertEqual(final_root["children"][1]["size"], {"weight": 0.3})

    def test_refuses_caller_herdr_labels(self):
        cases = [
            ["--label=herdr.space=sp1", "--", "echo"],
            ["--label", "herdr.tab=tb1", "--", "echo"],
            ["-l", "herdr.space=sp1", "--", "echo"],
            ["-l=herdr.tab=tb1", "--", "echo"],
            ["-lherdr.space=sp1", "--", "echo"],
        ]
        for argv in cases:
            called = []
            with self.subTest(argv=argv):
                rc, out, err = self.run_cli(argv, run_hc=lambda a: (called.append(a), (0, "", ""))[1])
                self.assertEqual(rc, 2)
                self.assertEqual(called, [])
                self.assertIn("herdr.", err)

    def test_no_labels_when_parent_has_none_or_invalid(self):
        for labels in ({}, {"herdr.space": "sp1"}, {"herdr.space": "bad space", "herdr.tab": "tb1"}):
            seen_run, rpc_calls = [], []
            with self.subTest(labels=labels):
                rc, out, err = self.run_cli(
                    ["--name", "w1", "--", "echo"],
                    run_hc=lambda a: (seen_run.append(a), (0, '{"address":"t8c"}\n', ""))[1],
                    get_term=lambda a: {"address": a, "labels": labels},
                    rpc=lambda m, p: (rpc_calls.append(m), {})[1],
                )
                self.assertEqual(rc, 0)
                self.assertEqual(out, '{"address":"t8c"}\n')
                self.assertEqual(err, "")
                self.assertEqual(seen_run[0], ["--name", "w1", "--bg", "--json", "--no-notify", "--", "echo"])
                self.assertEqual(rpc_calls, [])

    def test_exits_with_hc_run_code_on_failure(self):
        rpc_calls = []
        rc, out, err = self.run_cli(
            ["--", "false"],
            run_hc=lambda a: (17, '{"error":"nope"}\n', "hc failed\n"),
            get_term=lambda a: {"labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}},
            rpc=lambda m, p: (rpc_calls.append(m), {})[1],
        )
        self.assertEqual(rc, 17)
        self.assertEqual(out, '{"error":"nope"}\n')
        self.assertEqual(err, "hc failed\n")
        self.assertEqual(rpc_calls, [])

    def test_timeout_waiting_for_app_keeps_hc_run_exit_code(self):
        doc = make_doc(row("tb1", [blk("p1", "t2v", 1.0)]))
        rc, out, err = self.run_cli(
            ["--", "echo"],
            run_hc=lambda a: (0, '{"address":"t8c"}\n', ""),
            get_term=lambda a: {"labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}},
            rpc=lambda m, p: {"version": 1, "value": copy.deepcopy(doc)},
        )
        self.assertEqual(rc, 0)
        self.assertEqual(out, '{"address":"t8c"}\n')
        self.assertIn("did not appear", err)

    def test_server_error_text_never_printed_and_exit_code_unchanged(self):
        def fake_connect(_text):
            return 0, json.dumps({
                "jsonrpc": "2.0", "id": 2,
                "error": {"code": -1, "message": "DO_NOT_PRINT_THIS_SECRET", "data": {"kind": "internal"}},
            }) + "\n"

        rc, out, err = self.run_cli(
            ["--", "echo"],
            run_hc=lambda a: (0, '{"address":"t8c"}\n', ""),
            get_term=lambda a: {"labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}},
            rpc=lambda m, p: hw.doc_call(m, p, connect=fake_connect),
        )
        self.assertEqual(rc, 0)
        self.assertEqual(out, '{"address":"t8c"}\n')
        self.assertIn("doc.get: internal", err)
        self.assertNotIn("DO_NOT_PRINT_THIS_SECRET", err)

    def test_tidy_mode_runs_without_start_or_wait(self):
        terms = {
            "t2v": {"address": "t2v", "labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}},
            "t8c": {"address": "t8c", "parent": "t2v"},
        }
        doc_state = {"version": 4, "value": make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]))}
        run_calls, sleep_calls = [], []

        def fake_rpc(method, params):
            if method == "doc.get":
                return copy.deepcopy(doc_state)
            doc_state["value"] = params["value"]
            return {}

        rc, out, err = self.run_cli(
            ["--tidy"],
            run_hc=lambda a: (run_calls.append(a), (0, "", ""))[1],
            get_term=terms.get,
            rpc=fake_rpc,
            sleep=sleep_calls.append,
        )
        self.assertEqual(rc, 0)
        self.assertEqual((out, err, run_calls, sleep_calls), ("", "", [], []))
        final_root = doc_state["value"]["spaces"][0]["tabs"][0]["root"]
        self.assertEqual(final_root["children"][0]["size"], {"weight": 0.7})
        self.assertEqual(final_root["children"][1]["size"], {"weight": 0.3})

    def test_no_address_in_stdout_skips_tidy_and_keeps_exit_code(self):
        rpc_calls = []
        rc, out, err = self.run_cli(
            ["--", "echo"],
            run_hc=lambda a: (0, "not json\n", ""),
            get_term=lambda a: {"labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}},
            rpc=lambda m, p: (rpc_calls.append(m), {})[1],
        )
        self.assertEqual((rc, out, err, rpc_calls), (0, "not json\n", "", []))

    def test_five_conflicts_in_start_mode_prints_fixed_note_and_keeps_exit_code(self):
        doc = make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]))
        terms = {
            "t2v": {"address": "t2v", "labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}},
            "t8c": {"address": "t8c", "parent": "t2v"},
        }

        def fake_rpc(method, params):
            if method == "doc.get":
                return {"version": 1, "value": copy.deepcopy(doc)}
            raise hw.DocConflict("doc.set: conflict")

        rc, out, err = self.run_cli(
            ["--", "echo"],
            run_hc=lambda a: (0, '{"address":"t8c"}\n', ""),
            get_term=terms.get,
            rpc=fake_rpc,
        )
        self.assertEqual(rc, 0)
        self.assertEqual(out, '{"address":"t8c"}\n')
        self.assertIn("gave up after 5 tries", err)


if __name__ == "__main__":
    unittest.main(verbosity=1)
