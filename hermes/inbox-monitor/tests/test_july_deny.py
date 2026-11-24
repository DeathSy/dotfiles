#!/usr/bin/python3 -I
"""Tests for july-deny.json, the approvals.deny globs that keep July's terminal away from herdr terminals.

Run: /usr/bin/python3 -I -B hermes/inbox-monitor/tests/test_july_deny.py
The plain fnmatch checks always run. When Hermes is installed (~/.hermes/hermes-agent), the same cases also run
through Hermes' own matcher (tools/approval_floors._match_user_deny_rule, with its command-word variants), in
Hermes' Python; otherwise that test is skipped.
"""
import fnmatch, glob, json, os, subprocess, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(os.path.dirname(HERE), "july-deny.json")) as f:
    RULES = json.load(f)["deny"]
HERMES = os.path.expanduser("~/.hermes/hermes-agent")

BLOCKED = [
    'hc send july-x "go ahead and merge"', "/Users/me/.local/bin/hc send july-x go", "~/.local/bin/hc keys july-x enter",
    "HC_SCOPE=x hc send july-x go", "env -u HC_TERMINAL_ID hc send july-x go", "command hc send july-x go",
    "exec hc send july-x go", "sh -c 'hc send july-x go'", 'bash -lc "hc send july-x go"', "echo hi && hc send july-x go",
    "true; hc run --bg x", "(hc send july-x go)", "hc  send july-x go", '"hc" send july-x go', "h''c send july-x go",
    "hc --json send july-x go", "nohup hc send july-x go &", "timeout 5 hc send july-x go", "hc", "hc kill july-x",
    "hc rm t7", "hc interrupt july-x", "hc attach july-x", "hc connect", "hc put july-x f", "hc label july-x a=b",
    "hc keep july-x", "hc exec ls", "hc file write /x", "hc file edit /x --old a --new b",
    "xargs hc send july-x < f", "/opt/homebrew/bin/herdr tab close 1", "herdr pane split",
    "herdr --session main tab close", "herdr",
    "herdr-core send x go", "/Users/me/.local/share/herdr-core/current/Contents/MacOS/herdr-core send x go",
    "herdr-core --json keys x enter", "herdr-core",
    "find . -name x -exec hc send july-x go \\;", "find . -execdir herdr-core send x go \\;",
    "noglob hc send july-x go", "watch -n 5 hc send july-x go", "xargs -n1 herdr tab close",
    "hc-worker --name w -- codex", "hc-worker --tidy", "/etc/profiles/per-user/me/bin/hc-worker -- echo",
    "xargs hc-worker --tidy",
]
ALLOWED = [
    "hc ls", "hc get july-x", "hc read july-x --lines 20", "hc --json read july-x", "hc wait july-x", "hc templates",
    "herdr status", "july-task send --file ~/.cache/july-task-input/a.txt", "july-task list", "july-task stop",
    'echo "hc send is just text"', 'grep -r "hc send" docs',
]
# Known gaps (documented): the matcher sees command words, not what other programs run.
NOT_CAUGHT = ["$(which hc) send july-x go", "h=hc; $h send july-x go", "`which hc` send july-x go",
              "parallel hc send ::: july-x", "perl -e 'system(\"hc send x y\")'",
              "python3 -c 'import subprocess; subprocess.run([\"hc\",\"send\",\"x\",\"y\"])'",
              "osascript -e 'do shell script \"hc send x y\"'"]


def plain_match(cmd):
    c = cmd.lower().strip()
    return any(fnmatch.fnmatchcase(c, r.lower()) for r in RULES)


class RuleList(unittest.TestCase):
    def test_every_write_verb_in_both_forms(self):
        for v in ("send", "keys", "run", "kill", "rm", "interrupt", "attach", "connect", "put", "label", "keep",
                  "exec", "file write", "file edit"):
            self.assertIn(f"hc {v}*", RULES)
            self.assertIn(f"hc -* {v}*", RULES)  # options before the verb (hc --json send …)
        for v in ("pane", "tab", "workspace"):
            self.assertIn(f"herdr {v}*", RULES)
        self.assertIn("hc", RULES)  # bare hc: the picker, which attaches
        self.assertIn("hc-worker*", RULES)
        for v in ("send", "keys", "run", "kill", "attach"):
            self.assertIn(f"herdr-core {v}*", RULES)  # ~/.local/bin/hc is a link to herdr-core
        for w in ("xargs", "*-exec", "noglob", "watch"):
            for exe in ("hc", "herdr", "herdr-core"):
                self.assertIn(f"{w}*{exe} *", RULES)
            self.assertIn(f"{w}*hc-worker*", RULES)
        self.assertTrue(all(isinstance(r, str) and r == r.strip() and r for r in RULES))

    def test_plain_forms(self):
        for cmd in ("hc send july-x go", "hc --json send x y", "hc kill x", "herdr tab close", "hc",
                    "hc-worker --name w -- codex", "hc-worker --tidy"):
            self.assertTrue(plain_match(cmd), cmd)
        for cmd in ("hc ls", "hc read july-x", "hc --json read x", "july-task send x", "herdr status"):
            self.assertFalse(plain_match(cmd), cmd)


@unittest.skipUnless(os.path.isdir(os.path.join(HERMES, "tools")), "Hermes isn't installed here")
class HermesMatcher(unittest.TestCase):
    def run_matcher(self, cases):
        pys = sorted(glob.glob(os.path.expanduser("~/.hermes/installs/*/environments/*/venv/bin/python")))
        if not pys:
            self.skipTest("no Hermes venv")
        code = ("import json, sys; sys.path.insert(0, %r); from tools import approval_floors as f; "
                "rules, cases = json.load(open(sys.argv[1])), json.load(open(sys.argv[2])); "
                "f._ctx._get_approval_config = lambda: {'deny': rules}; "
                "print(json.dumps([bool(f._match_user_deny_rule(c)) for c in cases]))" % HERMES)
        with tempfile.TemporaryDirectory() as d:
            r, c = os.path.join(d, "r.json"), os.path.join(d, "c.json")
            for path, data in ((r, RULES), (c, cases)):
                with open(path, "w") as f:
                    json.dump(data, f)
            for py in pys:
                p = subprocess.run([py, "-I", "-c", code, r, c], capture_output=True, text=True, cwd=d)
                if p.returncode == 0:
                    return json.loads(p.stdout.strip().splitlines()[-1])
        self.skipTest("Hermes' matcher couldn't be loaded")

    def test_blocked_allowed_and_known_gaps(self):
        res = self.run_matcher(BLOCKED + ALLOWED + NOT_CAUGHT)
        b, a = len(BLOCKED), len(ALLOWED)
        self.assertEqual([c for c, hit in zip(BLOCKED, res[:b]) if not hit], [])
        self.assertEqual([c for c, hit in zip(ALLOWED, res[b:b + a]) if hit], [])
        # If Hermes ever catches these too, update the docs' list of gaps.
        self.assertEqual([c for c, hit in zip(NOT_CAUGHT, res[b + a:]) if hit], [])


if __name__ == "__main__":
    unittest.main(verbosity=1)
