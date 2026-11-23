"""Pre-trust a git worktree for Codex and agy so workers skip the trust screen.

ai-trust-worktree <path>           add <path> to both trust lists
ai-trust-worktree --remove <path>  remove that exact path from both

Codex: [projects."<path>"] trust_level = "trusted" in ~/.codex/config.toml.
agy: <path> in trustedWorkspaces of ~/.gemini/antigravity-cli/settings.json
(both the real path and the path as typed, since agy stores either).
Both tools trust exact paths only (a trusted parent doesn't cover children).
Only those keys change; each file is rewritten atomically with its mode kept,
or neither is touched when anything fails.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

import tomlkit

PROG = "ai-trust-worktree"
HOME = os.path.expanduser("~")
CODEX = os.path.realpath(os.path.join(HOME, ".codex", "config.toml"))
AGY = os.path.realpath(os.path.join(HOME, ".gemini", "antigravity-cli", "settings.json"))


class Changed(Exception):
    pass


def fail(msg):
    sys.exit(f"{PROG}: {msg}; config files left unchanged")


def read(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return f.read()


def codex_trust(text, path):
    projects = tomlkit.parse(text or "").get("projects") or {}
    entry = projects.get(path)
    return entry.get("trust_level") if isinstance(entry, dict) else None


def codex_update(text, paths, remove):
    path = paths[0]
    src = text or ""
    if src and not src.endswith("\n"):  # so an appended table starts on its own line
        src += "\n"
    doc = tomlkit.parse(src)
    projects = doc.get("projects")
    if remove:
        entry = projects.get(path) if projects is not None else None
        if entry is None or entry.get("trust_level") != "trusted":
            return text
        del entry["trust_level"]
        if not entry:
            del projects[path]
        if not projects:
            del doc["projects"]
    else:
        if projects is None:
            doc["projects"] = tomlkit.table(is_super_table=True)
            projects = doc["projects"]
        entry = projects.get(path)
        if entry is None:
            entry = tomlkit.table()
            entry["trust_level"] = "trusted"
            entry.add(tomlkit.nl())
            projects[path] = entry
        elif entry.get("trust_level") != "trusted":
            entry["trust_level"] = "trusted"
        else:
            return text
    after = tomlkit.dumps(doc)
    trust = codex_trust(after, path)
    if (trust == "trusted") == remove:
        raise ValueError(f"projects.\"{path}\".trust_level is {trust!r} after the edit (inline projects table?)")
    return after


def agy_update(text, paths, remove):
    data = json.loads(text) if text and text.strip() else {}
    if not isinstance(data, dict):
        raise ValueError("top level is not an object")
    trusted = data.get("trustedWorkspaces", [])
    if not isinstance(trusted, list):
        raise ValueError("trustedWorkspaces is not a list")
    if remove:
        new = [p for p in trusted if p not in paths]
    else:
        new = trusted + [p for p in paths if p not in trusted]
    if new == trusted:
        return text
    data["trustedWorkspaces"] = new
    after = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    json.loads(after)
    return after


def write_temp(target, content):
    fd, tmp = tempfile.mkstemp(prefix="." + os.path.basename(target) + ".", dir=os.path.dirname(target))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        if os.path.exists(target):
            shutil.copymode(target, tmp)
    except BaseException:
        os.remove(tmp)
        raise
    return tmp


def plan_changes(jobs, remove):
    plan = []  # (target, before, after)
    for target, update, paths in jobs:
        try:
            before = read(target)
            after = update(before, paths, remove)
        except Exception as e:
            fail(f"{target}: {e}")
        if after != before:
            plan.append((target, before, after))
    return plan


class Partial(Exception):
    pass


def undo(done):
    """Put back the files already renamed; return the ones that couldn't be."""
    left = []
    for target, before, after in done:
        try:
            if read(target) != after:  # someone wrote it since: don't clobber that
                left.append(f"{target} (changed by another program since)")
                continue
            if before is None:
                os.remove(target)
                continue
            tmp = write_temp(target, before)
            try:
                os.replace(tmp, target)
            except OSError:
                os.remove(tmp)
                raise
        except OSError as e:
            left.append(f"{target} ({e})")
    return left


def apply(plan):
    """Rename each temp file into place if its target is unchanged; undo all on failure."""
    temps, done = [], []
    try:
        for target, _, after in plan:
            temps.append(write_temp(target, after))
        for (target, before, after), tmp in zip(plan, temps):
            if read(target) != before:
                raise Changed(f"{target} changed by another program during the edit")
            os.replace(tmp, target)
            done.append((target, before, after))
    except BaseException as e:
        for tmp in temps:
            if os.path.exists(tmp):
                os.remove(tmp)
        left = undo(done)
        if left:
            raise Partial(f"{e}; rollback incomplete, check: {'; '.join(left)}") from e
        raise


def main():
    args = sys.argv[1:]
    remove = bool(args) and args[0] == "--remove"
    if remove:
        args = args[1:]
    if len(args) != 1 or args[0].startswith("-"):
        sys.exit(f"usage: {PROG} [--remove] <path>")
    path = os.path.realpath(args[0])
    typed = os.path.abspath(args[0])

    if not remove:
        if not os.path.isdir(path):
            fail(f"{path} is not a directory")
        top = subprocess.run(["git", "-C", path, "rev-parse", "--show-toplevel"], capture_output=True, text=True, encoding="utf-8")
        if top.returncode != 0 or os.path.realpath(top.stdout.strip()) != path:
            fail(f"{path} is not the top of a git repo or worktree")

    jobs = []
    for target, update, paths, label in (
        (CODEX, codex_update, [path], "Codex"),
        (AGY, agy_update, list(dict.fromkeys([path, typed])), "agy"),
    ):
        if os.path.isdir(os.path.dirname(target)):
            jobs.append((target, update, paths))
        else:
            print(f"{PROG}: {os.path.dirname(target)} missing, skipping {label}")

    for attempt in range(3):
        plan = plan_changes(jobs, remove)
        try:
            apply(plan)
            break
        except Partial as e:
            sys.exit(f"{PROG}: {e}")
        except Changed as e:
            if attempt == 2:
                fail(f"{e} (3 tries)")
        except Exception as e:
            fail(f"writing: {e}")

    verb = "untrusted" if remove else "trusted"
    changed = ", ".join(t for t, _, _ in plan) or "nothing to change"
    print(f"{PROG}: {path} {verb} ({changed})")


main()
