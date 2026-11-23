#!/usr/bin/python3 -I
"""Tests for hermes-config-check's SOUL.md sync: the block runs by itself with fake globals.

Run: /usr/bin/python3 -I -B nixpkgs/home-manager/ai/tests/test_hermes_config_check_soul.py
"""
import hashlib, os, shutil, tempfile, types, unittest


def read(path, mode="r"):
    with open(path, mode) as f:
        return f.read()

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = read(os.path.join(os.path.dirname(HERE), "hermes-config-check.py"))
BLOCK = SRC[SRC.index('soul = spec.get("soul")'):SRC.index("# ── resolved toolsets")]
HELPERS = SRC[SRC.index("def private_tmp("):SRC.index("def run(")]


def sha(b):
    return hashlib.sha256(b).hexdigest()


class SoulSync(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.home = os.path.join(self.d, "hermes")
        self.state = os.path.join(self.d, "state")
        os.makedirs(self.home)
        os.makedirs(self.state)
        self.overlay = os.path.join(self.d, "SOUL.md")
        self.live = os.path.join(self.home, "SOUL.md")
        self.mark = os.path.join(self.state, ".soul-installed")

    def tearDown(self):
        shutil.rmtree(self.d)

    def write(self, data):
        with open(self.live, "wb") as f:
            f.write(data)

    def run_block(self, fix=True, overlay=b"NEW\n", live=None, installed=None, hook=None):
        with open(self.overlay, "wb") as f:
            f.write(overlay)
        if live is not None:
            with open(self.live, "wb") as f:
                f.write(live)
        if installed is not None:
            with open(self.mark, "w") as f:
                f.write(sha(installed))
        notes = []
        ns = {"os": os, "hashlib": hashlib, "tempfile": tempfile, "a": types.SimpleNamespace(fix=fix),
              "spec": {"soul": self.overlay, "state_file": os.path.join(self.state, ".config-check.json")},
              "home": self.home, "changes": [], "problems": [], "say": notes.append}
        exec(HELPERS, ns)
        if hook:  # runs when the new copy has been written to its temp file, i.e. right before the rename
            orig = ns["private_tmp"]

            def private_tmp(path, data):
                tmp = orig(path, data)
                if path == self.live:
                    hook()
                return tmp
            ns["private_tmp"] = private_tmp
        exec(BLOCK, ns)
        live_now = read(self.live, "rb") if os.path.exists(self.live) else None
        leftovers = [n for n in os.listdir(self.home) if n.startswith(".SOUL.md.")]
        return live_now, ns["changes"], ns["problems"], notes, leftovers

    def test_seed_when_missing(self):
        live, changes, _, _, left = self.run_block()
        self.assertEqual((live, changes, left), (b"NEW\n", ["SOUL.md seeded"], []))
        self.assertEqual(read(self.mark), sha(b"NEW\n"))
        self.assertEqual(os.stat(self.live).st_mode & 0o777, 0o600)

    def test_seed_never_replaces_a_file_that_appeared_meanwhile(self):
        live, changes, _, notes, left = self.run_block(hook=lambda: self.write(b"MINE\n"))
        self.assertEqual((live, changes, left), (b"MINE\n", [], []))
        self.assertIn("appeared during this run", notes[0])

    def test_update_when_live_is_the_copy_installed_last(self):
        live, changes, _, _, _ = self.run_block(live=b"OLD\n", installed=b"OLD\n")
        self.assertEqual((live, changes), (b"NEW\n", ["SOUL.md updated from the overlay"]))

    def test_an_edit_saved_during_the_run_is_kept(self):
        live, changes, _, notes, left = self.run_block(live=b"OLD\n", installed=b"OLD\n",
                                                       hook=lambda: self.write(b"EDITED\n"))
        self.assertEqual((live, changes, left), (b"EDITED\n", [], []))
        self.assertIn("changed during this run", notes[0])

    def test_local_edits_are_left_alone(self):
        live, changes, _, notes, _ = self.run_block(live=b"EDITED\n", installed=b"OLD\n")
        self.assertEqual((live, changes), (b"EDITED\n", []))
        self.assertIn("local edits", notes[0])

    def test_hashes_are_over_bytes_crlf_included(self):
        # A CRLF copy installed last is recognised by its bytes (text mode would read it as LF and miss).
        live, changes, _, _, _ = self.run_block(overlay=b"NEW\n", live=b"OLD\r\n", installed=b"OLD\r\n")
        self.assertEqual((live, changes), (b"NEW\n", ["SOUL.md updated from the overlay"]))
        live, changes, _, notes, _ = self.run_block(overlay=b"NEW\n", live=b"OLD\n", installed=b"OLD\r\n")
        self.assertEqual(live, b"OLD\n")
        self.assertIn("local edits", notes[0])

    def test_equal_file_records_the_hash_once(self):
        live, changes, _, _, _ = self.run_block(live=b"NEW\n")
        self.assertEqual((live, changes), (b"NEW\n", []))
        self.assertEqual(read(self.mark), sha(b"NEW\n"))

    def test_check_only_mode_writes_nothing(self):
        live, changes, problems, notes, _ = self.run_block(fix=False, live=b"OLD\n", installed=b"OLD\n")
        self.assertEqual((live, changes), (b"OLD\n", []))
        self.assertIn("older overlay version", notes[0])
        os.unlink(self.live)
        live, changes, problems, _, _ = self.run_block(fix=False)
        self.assertIsNone(live)
        self.assertIn("missing", problems[0])


if __name__ == "__main__":
    unittest.main(verbosity=1)
