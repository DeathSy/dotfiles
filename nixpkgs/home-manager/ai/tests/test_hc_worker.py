#!/usr/bin/python3 -I
"""Tests for hc-worker: pure tidy layout logic, anchor/descendant walk, RPC retry loop, and CLI.

Run: /usr/bin/python3 -I -B nixpkgs/home-manager/ai/tests/test_hc_worker.py
"""
import copy
import importlib.util
import io
import json
import os
import subprocess
import sys
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
        doc = make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]))
        before = copy.deepcopy(doc)
        res, status = hw.tidy(doc, "sp1", "tb1", "t2v", lambda a: a == "t8c")
        self.assertEqual(status, "tidied")
        self.assertIsNotNone(res)
        self.assertEqual(doc, before)

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
        doc = make_doc(row("tb1", [
            blk("p1", "t2v", 0.7),
            col("s_keep", [row("s_inner", [blk("p2", "t8c", 0.5), blk("p3", "t8d", 0.5)], 1.0)], 0.3),
        ]))
        res, status = hw.tidy(doc, "sp1", "tb1", "t2v", lambda a: a in {"t8c", "t8d"})
        self.assertEqual(status, "tidied")
        self.assertEqual(res["spaces"][0]["tabs"][0]["root"], row("tb1", [
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
        res, status = hw.tidy(doc, "sp1", "tb1", "t2v", lambda a: a in {"t8c", "t8d", "t8e"})
        self.assertEqual(status, "tidied")
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
        self.assertEqual(hw.tidy(doc, "sp1", "tb1", "t2v", lambda a: True), (None, "already_tidy"))

    def test_root_size_preserved_and_already_tidy_with_root_size_returns_none(self):
        tidy_with_size = make_doc(row("tb1", [
            blk("p1", "t2v", 0.7),
            col("s_col", [blk("p2", "t8c", 1.0)], 0.3),
        ], weight=1.0))
        self.assertEqual(hw.tidy(tidy_with_size, "sp1", "tb1", "t2v", lambda a: True), (None, "already_tidy"))

        untidy_with_size = make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)], weight=1.0))
        res, status = hw.tidy(untidy_with_size, "sp1", "tb1", "t2v", lambda a: a == "t8c")
        self.assertEqual(status, "tidied")
        self.assertEqual(res["spaces"][0]["tabs"][0]["root"]["size"], {"weight": 1.0})

    def test_foreign_terminal_returns_none(self):
        doc = make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.25), blk("p3", "t99", 0.25)]))
        self.assertEqual(hw.tidy(doc, "sp1", "tb1", "t2v", lambda a: a == "t8c"), (None, "refused"))

    def test_duplicate_blocks_return_none(self):
        doc_dup_worker = make_doc(row("tb1", [blk("p1", "t2v", 0.4), blk("p2", "t8c", 0.3), blk("p3", "t8c", 0.3)]))
        self.assertEqual(hw.tidy(doc_dup_worker, "sp1", "tb1", "t2v", lambda a: True), (None, "refused"))

        doc_dup_parent = make_doc(row("tb1", [blk("p1", "t2v", 0.4), blk("p2", "t2v", 0.3), blk("p3", "t8c", 0.3)]))
        self.assertEqual(hw.tidy(doc_dup_parent, "sp1", "tb1", "t2v", lambda a: True), (None, "refused"))

    def test_duplicate_space_ids_or_tab_ids_return_none(self):
        dup_spaces = make_doc(
            row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]),
            extra_spaces=[{"id": "sp1", "name": "dup", "folder": "/x", "tabs": []}],
        )
        self.assertEqual(hw.tidy(dup_spaces, "sp1", "tb1", "t2v", lambda a: True), (None, "refused"))

        dup_tabs = make_doc(
            row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]),
            extra_tabs=[{"id": "tb1", "name": "dup", "root": row("tb1", [blk("px", "t9", 1.0)])}],
        )
        self.assertEqual(hw.tidy(dup_tabs, "sp1", "tb1", "t2v", lambda a: True), (None, "refused"))

        dup_tabs_other_space = make_doc(
            row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]),
            extra_spaces=[{"id": "sp2", "name": "s2", "folder": "/x", "tabs": [
                {"id": "tb9", "name": "", "root": row("tb9", [blk("px", "t9a", 1.0)])},
                {"id": "tb9", "name": "", "root": row("tb9", [blk("py", "t9b", 1.0)])},
            ]}],
        )
        self.assertEqual(hw.tidy(dup_tabs_other_space, "sp1", "tb1", "t2v", lambda a: True), (None, "refused"))

    def test_parent_missing_or_only_parent_returns_none(self):
        no_parent = make_doc(row("tb1", [blk("p2", "t8c", 0.5), blk("p3", "t8d", 0.5)]))
        self.assertEqual(hw.tidy(no_parent, "sp1", "tb1", "t2v", lambda a: True), (None, "refused"))

        only_parent = make_doc(row("tb1", [blk("p1", "t2v", 1.0)]))
        self.assertEqual(hw.tidy(only_parent, "sp1", "tb1", "t2v", lambda a: True), (None, "already_tidy"))

    def test_invalid_tree_cases_return_none(self):
        bad_roots = [
            row("tb1", [blk("p1", "t2v", 0.5), {"type": "tabs", "id": "x", "children": [blk("p2", "t8c")]}]),
            {**row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]), "extra": 1},
            row("tb1", [blk("p1", "t2v", 0.5), {**blk("p2", "t8c", 0.5), "extra": 1}]),
            row("tb1", [blk("p1", "t2v", 0.5), {"type": "block", "id": "p2", "content": {"terminal": "t8c", "x": 1}}]),
            row("tb1", [blk("p1", "t2v", 0), blk("p2", "t8c", 0.5)]),
            row("tb1", [blk("p1", "t2v", -0.5), blk("p2", "t8c", 0.5)]),
            row("tb1", [blk("p1", "t2v", True), blk("p2", "t8c", 0.5)]),
            row("tb1", [blk("p1", "t2v", float("nan")), blk("p2", "t8c", 0.5)]),
            row("tb1", [blk("p1", "t2v", float("inf")), blk("p2", "t8c", 0.5)]),
            row("tb1", [blk("p1", "t2v", float("-inf")), blk("p2", "t8c", 0.5)]),
            row("tb1", [blk("p1", "t2v", "0.5"), blk("p2", "t8c", 0.5)]),
            row("tb1", [blk("p1", "t2v", 0.5), {"type": "block", "id": "p2", "content": {"terminal": "t8c"}, "size": {"weight": 0.5, "x": 1}}]),
            row("tb1", [blk("p1", "t2v", 0.5), col("c1", [])]),
            col("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]),
            row("tb_other", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]),
            row("tb1", [blk(123, "t2v", 0.5), blk("p2", "t8c", 0.5)]),
        ]
        for bad in bad_roots:
            with self.subTest(bad=bad):
                self.assertEqual(hw.tidy(make_doc(bad), "sp1", "tb1", "t2v", lambda a: True), (None, "refused"))

    def test_invariant_failure_raises_fail_not_assertion_error(self):
        doc = make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]))
        orig_deepcopy = copy.deepcopy

        def corrupt_deepcopy(obj, *args, **kwargs):
            copied = orig_deepcopy(obj, *args, **kwargs)
            if isinstance(copied, dict) and "spaces" in copied:
                copied["tampered"] = True
            return copied

        with mock.patch.object(copy, "deepcopy", side_effect=corrupt_deepcopy):
            with self.assertRaises(hw.Fail):
                hw.tidy(doc, "sp1", "tb1", "t2v", lambda a: a == "t8c")

    def test_missing_space_or_tab_returns_none(self):
        doc = make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]))
        self.assertEqual(hw.tidy(doc, "sp_missing", "tb1", "t2v", lambda a: True), (None, "refused"))
        self.assertEqual(hw.tidy(doc, "sp1", "tb_missing", "t2v", lambda a: True), (None, "refused"))
        self.assertEqual(hw.tidy({"bad": 1}, "sp1", "tb1", "t2v", lambda a: True), (None, "refused"))

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
        res, status = hw.tidy(doc, "sp1", "tb1", "t2v", lambda a: a == "t8c")
        self.assertEqual(status, "tidied")
        self.assertEqual(res["extra_top"], {"keep": True})
        self.assertEqual(res["spaces"][0]["tabs"][1], other_tab)
        self.assertEqual(res["spaces"][1], other_space)


class AnchorAndDescendantTests(unittest.TestCase):
    def test_find_anchor_walks_same_tab_labels_up_to_depth_4(self):
        same = {"herdr.space": "sp1", "herdr.tab": "tb1"}
        other = {"herdr.space": "sp1", "herdr.tab": "tb_other"}
        terms = {
            "other_tab": {"labels": other},
            "main": {"parent": "other_tab", "labels": same},
            "rev": {"parent": "main", "labels": same},
            "w1": {"parent": "rev", "labels": same},
            "w2": {"parent": "w1", "labels": same},
            "w3": {"parent": "w2", "labels": same},
            "w4": {"parent": "w3", "labels": same},  # 5 hops from main
        }
        # Stops at main because other_tab has different labels
        self.assertEqual(hw.find_anchor("rev", "sp1", "tb1", terms.get), "main")
        self.assertEqual(hw.find_anchor("w3", "sp1", "tb1", terms.get), "main")  # 4 hops
        self.assertEqual(hw.find_anchor("w4", "sp1", "tb1", terms.get), "rev")   # capped at 4 hops

    def test_is_descendant_walks_up_to_depth_4_and_handles_cycles(self):
        terms = {
            "main": {},
            "d1": {"parent": "main"},
            "d2": {"parent": "d1"},
            "d3": {"parent": "d2"},
            "d4": {"parent": "d3"},
            "d5": {"parent": "d4"},
            "cyc1": {"parent": "cyc2"},
            "cyc2": {"parent": "cyc1"},
        }
        self.assertTrue(hw.is_descendant_of("d1", "main", terms.get))
        self.assertTrue(hw.is_descendant_of("d2", "main", terms.get))
        self.assertTrue(hw.is_descendant_of("d4", "main", terms.get))
        self.assertFalse(hw.is_descendant_of("d5", "main", terms.get))
        self.assertFalse(hw.is_descendant_of("cyc1", "main", terms.get))
        self.assertFalse(hw.is_descendant_of("unknown", "main", terms.get))


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

    def test_hc_connect_and_hc_run_decode_with_errors_replace_and_strip_hc_env(self):
        captured = []

        def fake_run(cmd, **kwargs):
            captured.append((cmd, kwargs))
            return subprocess.CompletedProcess(cmd, 0, stdout="ok", stderr="")

        with mock.patch.dict(os.environ, {"HC_TERMINAL_ID": "t2v", "HC_SOCKET": "/tmp/s", "PATH": "/usr/bin"}, clear=True):
            with mock.patch.object(subprocess, "run", side_effect=fake_run):
                self.assertEqual(hw.hc_connect("hi\n", hc="/fake/hc"), (0, "ok"))
                self.assertEqual(hw.hc_run(["--bg", "--", "echo"], hc="/fake/hc"), (0, "ok", ""))

        conn_cmd, conn_kw = captured[0]
        self.assertEqual(conn_cmd, ["/fake/hc", "connect"])
        self.assertEqual(conn_kw["timeout"], 10)
        self.assertEqual(conn_kw["errors"], "replace")
        self.assertNotIn("HC_TERMINAL_ID", conn_kw["env"])
        self.assertNotIn("HC_SOCKET", conn_kw["env"])
        self.assertIn("PATH", conn_kw["env"])

        run_cmd, run_kw = captured[1]
        self.assertEqual(run_cmd, ["/fake/hc", "run", "--bg", "--", "echo"])
        self.assertEqual(run_kw["errors"], "replace")

        # End-to-end check that invalid UTF-8 bytes do not raise UnicodeDecodeError
        p = subprocess.run([sys.executable, "-I", "-c", "import sys; sys.stdout.buffer.write(b'\\xff{\"address\":\"t8c\"}\\n')"],
                           capture_output=True, encoding="utf-8", errors="replace")
        self.assertEqual(p.returncode, 0)
        self.assertIn("\ufffd", p.stdout)

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

        res = hw.edit_doc(lambda v: hw.tidy(v, "sp1", "tb1", "t2v", lambda a: a in {"t8c", "t8d"})[0], rpc=fake_rpc)
        self.assertEqual(gets, [1, 2])
        self.assertEqual([v for v, _ in sets], [1, 2])
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

        with self.assertRaises(hw.Fail) as ctx:
            hw.edit_doc(lambda v: hw.tidy(v, "sp1", "tb1", "t2v", lambda a: a == "t8c")[0], rpc=fake_rpc)
        self.assertEqual(calls, {"get": 5, "set": 5})
        self.assertIn("5 tries", str(ctx.exception))

    def test_edit_doc_stops_before_call_past_deadline(self):
        doc = make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]))
        t, calls = [0.0], []

        def slow_rpc(method, params):
            calls.append(method)
            t[0] += 12.0
            return {"version": 1, "value": copy.deepcopy(doc)}

        with self.assertRaises(hw.Fail) as ctx:
            hw.edit_doc(lambda v: hw.tidy(v, "sp1", "tb1", "t2v", lambda a: a == "t8c")[0],
                        rpc=slow_rpc, deadline=10.0, clock=lambda: t[0])
        self.assertIn("out of time", str(ctx.exception))
        self.assertEqual(calls, ["doc.get"])


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

    def test_option_handling_puts_added_flags_and_labels_before_caller_opts(self):
        terms = {
            "t2v": {"address": "t2v", "labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}},
            "t8c": {"address": "t8c", "parent": "t2v"},
        }
        seen_run = []
        raw_out = '{"address":"t8c","name":"w1","parent":"t2v","state":"live"}\n'
        doc_state = {"version": 1, "value": make_doc(row("tb1", [blk("p1", "t2v", 1.0)]))}
        polls = [0]

        def fake_rpc(method, params):
            if method == "doc.get":
                polls[0] += 1
                if polls[0] >= 3:
                    doc_state["value"] = make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]))
                return copy.deepcopy(doc_state)
            doc_state["version"] += 1
            doc_state["value"] = params["value"]
            return {}

        rc, out, err = self.run_cli(
            ["--bg", "--name", "w1", "--cwd", "/tmp", "--", "codex", "--full"],
            run_hc=lambda a: (seen_run.append(a), (0, raw_out, ""))[1],
            get_term=terms.get,
            rpc=fake_rpc,
        )
        self.assertEqual(rc, 0)
        self.assertEqual(out, raw_out)
        self.assertEqual(err, "")
        self.assertEqual(seen_run[0], [
            "--json", "--no-notify",
            "--label=herdr.space=sp1", "--label=herdr.tab=tb1",
            "--bg", "--name", "w1", "--cwd", "/tmp",
            "--", "codex", "--full",
        ])
        final_root = doc_state["value"]["spaces"][0]["tabs"][0]["root"]
        self.assertEqual(final_root["children"][0]["size"], {"weight": 0.7})
        self.assertEqual(final_root["children"][1]["type"], "column")
        self.assertEqual(final_root["children"][1]["size"], {"weight": 0.3})

    def test_reviewer_starts_stage2_worker_anchored_on_main_session_and_preserves_order(self):
        same = {"herdr.space": "sp1", "herdr.tab": "tb1"}
        terms = {
            "t_main": {"address": "t_main", "labels": same},
            "t_rev": {"address": "t_rev", "parent": "t_main", "labels": same},
            "t_w1": {"address": "t_w1", "parent": "t_rev", "labels": same},
        }
        # App split t_rev into row [t_rev, t_w1] inside right column
        doc_state = {"version": 2, "value": make_doc(row("tb1", [
            blk("p_main", "t_main", 0.7),
            col("s_col", [row("s_r", [blk("p_rev", "t_rev", 0.5), blk("p_w1", "t_w1", 0.5)], 1.0)], 0.3),
        ]))}

        def fake_rpc(method, params):
            if method == "doc.get":
                return copy.deepcopy(doc_state)
            doc_state["value"] = params["value"]
            return {}

        rc, out, err = self.run_cli(
            ["--name", "w1", "--", "codex"],
            env={"HC_TERMINAL_ID": "t_rev"},
            run_hc=lambda a: (0, '{"address":"t_w1"}\n', ""),
            get_term=terms.get,
            rpc=fake_rpc,
        )
        self.assertEqual((rc, err), (0, ""))
        # Main session stays left at 0.7; right column has reviewer above stage-2 worker
        self.assertEqual(doc_state["value"]["spaces"][0]["tabs"][0]["root"], row("tb1", [
            blk("p_main", "t_main", 0.7),
            col("s_col", [blk("p_rev", "t_rev", 0.5), blk("p_w1", "t_w1", 0.5)], 0.3),
        ]))

        # --tidy called from reviewer uses the exact same anchor (already tidy -> silent)
        rc2, out2, err2 = self.run_cli(
            ["--tidy"],
            env={"HC_TERMINAL_ID": "t_rev"},
            get_term=terms.get,
            rpc=fake_rpc,
        )
        self.assertEqual((rc2, out2, err2), (0, "", ""))

    def test_template_before_double_dash_gets_flags_and_labels_prepended(self):
        terms = {"t2v": {"address": "t2v", "labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}}}
        seen_run = []
        rc, out, err = self.run_cli(
            ["--name", "x", "reviewer", "--bg", "--parent", "foo", "--", "task"],
            run_hc=lambda a: (seen_run.append(a), (0, "no-addr\n", ""))[1],
            get_term=terms.get,
        )
        self.assertEqual((rc, out, err), (0, "no-addr\n", ""))
        self.assertEqual(seen_run[0], [
            "--bg", "--json", "--no-notify",
            "--label=herdr.space=sp1", "--label=herdr.tab=tb1",
            "--name", "x", "reviewer", "--bg", "--parent", "foo",
            "--", "task",
        ])

    def test_refuses_parent_no_parent_and_on_options(self):
        cases = [
            ["--parent", "t1", "--", "echo"],
            ["--parent=t1", "--", "echo"],
            ["--no-parent", "--", "echo"],
            ["--on", "remote", "--", "echo"],
            ["--on=remote", "--", "echo"],
        ]
        for argv in cases:
            called = []
            with self.subTest(argv=argv):
                rc, out, err = self.run_cli(argv, run_hc=lambda a: (called.append(a), (0, "", ""))[1])
                self.assertEqual(rc, 2)
                self.assertEqual(called, [])
                self.assertIn("cannot pass", err)

        # Value of --name equal to --parent is allowed (not parsed as --parent flag)
        seen = []
        rc, _, _ = self.run_cli(["--name", "--parent", "--", "echo"],
                                run_hc=lambda a: (seen.append(a), (0, "no-addr\n", ""))[1],
                                get_term=lambda a: {"labels": {}})
        self.assertEqual(rc, 0)
        self.assertEqual(seen[0], ["--bg", "--json", "--no-notify", "--name", "--parent", "--", "echo"])

    def test_value_opts_exact_set(self):
        self.assertEqual(hw.VALUE_OPTS, {"--name", "--cwd", "--timeout"})
        self.assertEqual(hw.parse_options(["--name", "--bg", "--cwd", "--json", "--timeout", "--no-notify"]),
                         ["--bg", "--json", "--no-notify"])

    def test_poll_timeout_is_4s(self):
        self.assertEqual(hw.POLL_TIMEOUT, 4.0)
        doc = make_doc(row("tb1", [blk("p1", "t2v", 1.0)]))
        t = [0.0]
        rc, out, err = self.run_cli(
            ["--", "echo"],
            run_hc=lambda a: (0, '{"address":"t8c"}\n', ""),
            get_term=lambda a: {"labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}},
            rpc=lambda m, p: {"version": 1, "value": copy.deepcopy(doc)},
            clock=lambda: t[0],
            sleep=lambda dt: t.__setitem__(0, t[0] + dt),
        )
        self.assertEqual(rc, 0)
        self.assertAlmostEqual(t[0], 4.0)
        self.assertIn("did not appear", err)

    def test_overall_20s_budget_across_poll_and_tidy_with_slow_connect(self):
        terms = {
            "t2v": {"address": "t2v", "labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}},
            "t8c": {"address": "t8c", "parent": "t2v"},
        }
        t, calls = [0.0], []
        doc_with_worker = make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]))

        def slow_connect(payload):
            req = json.loads(payload.splitlines()[1])
            calls.append((req["method"], t[0]))
            # poll1: t=0..3 (not there), sleep 0.25 -> 3.25; poll2: 3.25..13.25 (appears); edit get: 13.25..21.25 -> past 20s
            t[0] += 3.0 if len(calls) == 1 else (10.0 if len(calls) == 2 else 8.0)
            doc = make_doc(row("tb1", [blk("p1", "t2v", 1.0)])) if len(calls) == 1 else doc_with_worker
            return 0, json.dumps({"jsonrpc": "2.0", "id": 2, "result": {"version": 1, "value": doc}}) + "\n"

        rc, out, err = self.run_cli(
            ["--", "echo"],
            run_hc=lambda a: (0, '{"address":"t8c"}\n', ""),
            get_term=terms.get,
            rpc=lambda m, p: hw.doc_call(m, p, connect=slow_connect),
            clock=lambda: t[0],
            sleep=lambda dt: t.__setitem__(0, t[0] + dt),
        )
        self.assertEqual(rc, 0)
        self.assertEqual(out, '{"address":"t8c"}\n')
        self.assertIn("out of time", err)
        self.assertTrue(all(start < 20.0 for _, start in calls))
        self.assertNotIn("doc.set", [m for m, _ in calls])

    def test_hc_down_stops_immediately_without_retries(self):
        terms = {"t2v": {"address": "t2v", "labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}}}
        calls = []

        def down_rpc(method, params):
            calls.append(method)
            raise hw.Fail("hc connect: TimeoutExpired")

        rc, out, err = self.run_cli(
            ["--", "echo"],
            run_hc=lambda a: (0, '{"address":"t8c"}\n', ""),
            get_term=terms.get,
            rpc=down_rpc,
        )
        self.assertEqual(rc, 0)
        self.assertEqual(calls, ["doc.get"])
        self.assertIn("hc connect: TimeoutExpired", err)

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
                self.assertEqual(seen_run[0], ["--bg", "--json", "--no-notify", "--name", "w1", "--", "echo"])
                self.assertEqual(rpc_calls, [])

    def test_parent_hc_get_failure_prints_note_and_starts_without_labels(self):
        seen_run, rpc_calls = [], []
        rc, out, err = self.run_cli(
            ["--name", "w1", "--", "echo"],
            run_hc=lambda a: (seen_run.append(a), (0, '{"address":"t8c"}\n', ""))[1],
            get_term=lambda a: None,
            rpc=lambda m, p: (rpc_calls.append(m), {})[1],
        )
        self.assertEqual(rc, 0)
        self.assertEqual(out, '{"address":"t8c"}\n')
        self.assertIn("without Herdr tab labels", err)
        self.assertEqual(seen_run[0], ["--bg", "--json", "--no-notify", "--name", "w1", "--", "echo"])
        self.assertEqual(rpc_calls, [])

    def test_exits_with_hc_run_code_on_failure_and_signal(self):
        rpc_calls = []
        rc, out, err = self.run_cli(
            ["--", "false"],
            run_hc=lambda a: (17, '{"error":"nope"}\n', "hc failed\n"),
            get_term=lambda a: {"labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}},
            rpc=lambda m, p: (rpc_calls.append(m), {})[1],
        )
        self.assertEqual((rc, out, err, rpc_calls), (17, '{"error":"nope"}\n', "hc failed\n", []))

        # Negative return code (killed by signal 15 -> 128 + 15 = 143)
        rc2, _, _ = self.run_cli(
            ["--", "sleep"],
            run_hc=lambda a: (-15, "", ""),
            get_term=lambda a: {"labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}},
            rpc=lambda m, p: (rpc_calls.append(m), {})[1],
        )
        self.assertEqual((rc2, rpc_calls), (143, []))

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
        self.assertEqual((rc, out, err, run_calls, sleep_calls), (0, "", "", [], []))
        final_root = doc_state["value"]["spaces"][0]["tabs"][0]["root"]
        self.assertEqual(final_root["children"][0]["size"], {"weight": 0.7})
        self.assertEqual(final_root["children"][1]["size"], {"weight": 0.3})

    def test_tidy_mode_prints_note_on_refusal_and_nothing_when_already_tidy(self):
        terms = {
            "t2v": {"address": "t2v", "labels": {"herdr.space": "sp1", "herdr.tab": "tb1"}},
            "t8c": {"address": "t8c", "parent": "t2v"},
            "t99": {"address": "t99", "parent": "other"},
        }
        already = make_doc(row("tb1", [blk("p1", "t2v", 0.7), col("s1", [blk("p2", "t8c", 1.0)], 0.3)]))
        rc, out, err = self.run_cli(["--tidy"], get_term=terms.get, rpc=lambda m, p: {"version": 1, "value": already})
        self.assertEqual((rc, out, err), (0, "", ""))

        refused_docs = [
            make_doc(row("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t99", 0.5)])),
            make_doc(col("tb1", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)])),
            make_doc(row("tb_other", [blk("p1", "t2v", 0.5), blk("p2", "t8c", 0.5)]), tab_id="tb_other"),
        ]
        for doc in refused_docs:
            with self.subTest(doc=doc):
                rc, out, err = self.run_cli(["--tidy"], get_term=terms.get, rpc=lambda m, p: {"version": 1, "value": doc})
                self.assertEqual((rc, out), (0, ""))
                self.assertEqual(len(err.strip().splitlines()), 1)
                self.assertIn("tab left unchanged", err)

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
