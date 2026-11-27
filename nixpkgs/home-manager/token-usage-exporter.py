#!/usr/bin/env python3
"""Count AI token usage from local session logs and Hermes' usage table into a node_exporter textfile.

Usage: token-usage-exporter <state.json> <output.prom>

Reads incrementally from
  ~/.claude/projects/**/*.jsonl  (Claude Code: appended bytes, message.usage per reply, deduped by message.id)
  ~/.codex/sessions/**/*.jsonl   (Codex: appended bytes, token_count events, last_token_usage per turn)
  ~/.gemini/antigravity-cli/conversations/*.db  (agy: new gen_metadata rows, protobuf; see agy_generation)
and re-reads Hermes' session_model_usage table each run (read-only, per-row counter deltas) from
  ~/.hermes/state.db and ~/.hermes/profiles/*/state.db
keeping monotonic totals in the state file, written as
  ai_tokens_total{client="claude-code|codex|agy|hermes",model,type="input|output|cache_read|cache_write"}  (counter)
On the first run every log file starts at its end; later, a file born since the last scan is read
from the start (skipping Claude records older than the file: resumed/forked sessions copy earlier
messages), while an older file seen for the first time (e.g. after the 30-day prune) starts at its
end. Each Hermes database baselines its current rows on first sight (adding nothing) so existing
history or a newly created profile does not spike.
"""

import hashlib
import json
import os
import sqlite3
import sys
import time
from datetime import datetime
from pathlib import Path

HOME = Path.home()
SOURCES = {"claude-code": HOME / ".claude/projects", "codex": HOME / ".codex/sessions"}
AGY_CONVERSATIONS = HOME / ".gemini/antigravity-cli/conversations"
HERMES_DIR = HOME / ".hermes"
HERMES_KINDS = ("input", "output", "cache_read", "cache_write")
RECENT_IDS = 20  # Claude writes one line per content block with the same message id, consecutively


def record_time(rec):
    t = rec.get("timestamp") if isinstance(rec, dict) else None
    if not isinstance(t, str):
        return None
    try:
        return datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def claude_usage(rec, seen, not_before=None):
    if not_before is not None:
        t = record_time(rec)
        if t is not None and t < not_before:
            return None  # a message copied in from an earlier session
    msg = rec.get("message") if isinstance(rec, dict) else None
    usage = msg.get("usage") if isinstance(msg, dict) else None
    mid = msg.get("id") if isinstance(msg, dict) else None
    if not isinstance(usage, dict) or not mid or mid in seen:
        return None
    seen.append(mid)
    del seen[:-RECENT_IDS]
    model = str(msg.get("model") or "unknown")
    if model == "<synthetic>":
        return None
    return model, {
        "input": usage.get("input_tokens"),
        "output": usage.get("output_tokens"),
        "cache_read": usage.get("cache_read_input_tokens"),
        "cache_write": usage.get("cache_creation_input_tokens"),
    }


def codex_usage(rec, state):
    payload = rec.get("payload") if isinstance(rec, dict) else None
    if not isinstance(payload, dict):
        return None
    if rec.get("type") == "turn_context" and payload.get("model"):
        state["model"] = str(payload["model"])
        return None
    if payload.get("type") != "token_count":
        return None
    info = payload.get("info") or {}
    last, total = info.get("last_token_usage"), info.get("total_token_usage")
    if not isinstance(last, dict):
        return None
    if total is not None and total == state.get("total"):
        return None  # Codex sometimes repeats a token_count event unchanged
    state["total"] = total
    cached = last.get("cached_input_tokens") or 0
    return state.get("model") or "codex", {
        "input": (last.get("input_tokens") or 0) - cached,  # OpenAI's input_tokens includes cached ones
        "output": last.get("output_tokens"),
        "cache_read": cached,
        "cache_write": last.get("cache_write_input_tokens"),
    }


def pb_fields(buf):
    """Minimal protobuf reader: yields (field number, value); value is int or bytes."""
    i, n = 0, len(buf)
    def varint():
        nonlocal i
        shift = result = 0
        while True:
            b = buf[i]; i += 1
            result |= (b & 0x7F) << shift
            if b < 0x80:
                return result
            shift += 7
    while i < n:
        key = varint()
        field, wire = key >> 3, key & 7
        if wire == 0:
            yield field, varint()
        elif wire == 2:
            size = varint(); yield field, buf[i:i + size]; i += size
        elif wire == 1:
            i += 8
        elif wire == 5:
            i += 4
        else:
            return


def pb_get(buf, *path):
    """First value at a field path, e.g. pb_get(b, 1, 4, 2)."""
    for depth, want in enumerate(path):
        for field, value in pb_fields(buf):
            if field == want:
                if depth == len(path) - 1:
                    return value
                if not isinstance(value, bytes):
                    return None
                buf = value
                break
        else:
            return None
    return None


def agy_generation(blob):
    """One agy generation (gen_metadata.data). Field 1.4 looks like Codeium's ModelUsageStats
    (inferred from agy 1.5.14, 2026-11-24): 2 input, 3 output, 4 cache write, 5 cache read
    (proto3 leaves zeros off the wire, so a missing count is 0); 1.19 is the model."""
    try:
        usage, model = pb_get(blob, 1, 4), pb_get(blob, 1, 19)
        if not isinstance(usage, bytes):
            return None
        f = {k: v for k, v in pb_fields(usage) if isinstance(v, int)}
    except IndexError:
        return None
    return (model.decode("utf-8", "replace") if isinstance(model, bytes) else "gemini"), {
        "input": f.get(2, 0), "output": f.get(3, 0), "cache_write": f.get(4, 0), "cache_read": f.get(5, 0)}


def scan_agy(files, totals, first_run, since):
    if not AGY_CONVERSATIONS.is_dir():
        return
    for path in AGY_CONVERSATIONS.glob("*.db"):
        try:
            st = path.stat()
            wal = path.with_name(path.name + "-wal")
            mtime = max(st.st_mtime, wal.stat().st_mtime if wal.exists() else 0)
        except OSError:
            continue
        key, born = str(path), getattr(st, "st_birthtime", st.st_mtime)
        entry = files.get(key)
        if entry is not None and mtime < since:
            continue
        if entry is None and mtime < time.time() - 30 * 86400:
            continue  # pruned and untouched: don't reopen it every run
        try:
            db = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=2)
            try:
                if entry is None:
                    start = -1
                    if first_run or born < since:
                        start = db.execute("select coalesce(max(idx), -1) from gen_metadata").fetchone()[0]
                    entry = files[key] = {"gen_idx": start, "mtime": mtime}
                rows = db.execute("select idx, data from gen_metadata where idx > ? order by idx",
                                  (entry["gen_idx"],)).fetchall()
            finally:
                db.close()
        except sqlite3.Error:
            continue
        for idx, blob in rows:
            got = agy_generation(blob) if isinstance(blob, bytes) else None
            if got is not None:
                model, counts = got
                for kind, n in counts.items():
                    if n > 0:
                        k = f"agy|{model}|{kind}"
                        totals[k] = totals.get(k, 0) + n
            entry["gen_idx"] = idx
        entry["mtime"] = mtime


def hermes_dbs():
    override = os.environ.get("TOKEN_USAGE_HERMES_DB")
    if override:
        return [Path(override).expanduser()]
    paths = [HERMES_DIR / "state.db"]
    profiles = HERMES_DIR / "profiles"
    if profiles.is_dir():
        paths.extend(sorted(profiles.glob("*/state.db")))
    return paths


def valid_hermes_rows(entry):
    if not isinstance(entry, dict):
        return None
    rows = entry.get("rows")
    if not isinstance(rows, dict):
        return None
    for k, v in rows.items():
        if not isinstance(k, str) or not isinstance(v, list) or len(v) != 4:
            return None
        if not all(isinstance(x, int) and not isinstance(x, bool) for x in v):
            return None
    return rows


def scan_hermes(state, totals):
    try:
        dbs = hermes_dbs()
    except Exception as exc:
        print(f"token-usage-exporter: hermes scan failed ({type(exc).__name__})", file=sys.stderr)
        return
    prev_all = state.get("hermes")
    hermes_state = dict(prev_all) if isinstance(prev_all, dict) else {}
    changed = False
    for path in dbs:
        try:
            if not path.is_file():
                continue
            db_key = os.path.abspath(path)
            db = sqlite3.connect(Path(db_key).as_uri() + "?mode=ro", uri=True, timeout=5)
            try:
                rows = db.execute(
                    "select session_id, model, billing_provider, billing_base_url, billing_mode, task, "
                    "input_tokens, output_tokens, cache_read_tokens, cache_write_tokens "
                    "from session_model_usage"
                ).fetchall()
            finally:
                db.close()
            prev_rows = valid_hermes_rows(hermes_state.get(db_key))
            current = {}
            deltas = {}
            for row in rows:
                key = hashlib.sha1(json.dumps(row[:6]).encode()).hexdigest()[:16]
                vals = [max(0, int(v or 0)) for v in row[6:]]
                current[key] = vals
                if prev_rows is None:
                    continue
                old = prev_rows.get(key, (0, 0, 0, 0))
                model = str(row[1] or "unknown").replace("|", "/")
                for kind, cur, was in zip(HERMES_KINDS, vals, old):
                    delta = cur - was if cur >= was else cur
                    if delta > 0:
                        k = f"hermes|{model}|{kind}"
                        deltas[k] = deltas.get(k, 0) + delta
        except Exception as exc:
            print(f"token-usage-exporter: hermes scan failed ({type(exc).__name__})", file=sys.stderr)
            continue
        for k, n in deltas.items():
            totals[k] = totals.get(k, 0) + n
        hermes_state[db_key] = {"rows": current}
        changed = True
    if changed:
        state["hermes"] = hermes_state


def scan(state):
    files, totals = state.setdefault("files", {}), state.setdefault("totals", {})
    first_run = "last_scan" not in state
    since = state.get("last_scan", 0) - 120
    for provider, root in SOURCES.items():
        if not root.is_dir():
            continue
        for path in root.rglob("*.jsonl"):
            try:
                st = path.stat()
            except OSError:
                continue
            key = str(path)
            entry = files.get(key)
            born = getattr(st, "st_birthtime", st.st_mtime)
            if entry is None:
                if first_run or born < since:
                    files[key] = {"offset": st.st_size, "ino": st.st_ino, "mtime": st.st_mtime}
                    continue
                entry = files[key] = {"offset": 0, "ino": st.st_ino, "mtime": 0, "from_start": True}
            if st.st_mtime < since and st.st_size == entry["offset"]:
                continue
            if st.st_ino != entry.get("ino") or st.st_size < entry["offset"]:
                entry.update(offset=0, ino=st.st_ino, seen=[], ctx={})  # replaced or truncated file
            try:
                with path.open("rb") as fh:
                    fh.seek(entry["offset"])
                    data = fh.read()
            except OSError:
                continue
            not_before = born - 120 if entry.get("from_start") else None
            end = data.rfind(b"\n") + 1  # only complete lines; a half-written line waits for the next run
            seen, ctx = entry.setdefault("seen", []), entry.setdefault("ctx", {})
            for line in data[:end].splitlines():
                if b'"usage"' not in line and b"token_count" not in line and b"turn_context" not in line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                got = claude_usage(rec, seen, not_before) if provider == "claude-code" else codex_usage(rec, ctx)
                if got is None:
                    continue
                model, counts = got
                for kind, n in counts.items():
                    if isinstance(n, (int, float)) and n > 0:
                        k = f"{provider}|{model}|{kind}"
                        totals[k] = totals.get(k, 0) + n
            entry["offset"] += end
            entry["mtime"] = st.st_mtime
    scan_agy(files, totals, first_run, since)
    scan_hermes(state, totals)
    # Forget files untouched for 30 days (their offsets aren't needed any more).
    cutoff = time.time() - 30 * 86400
    for key in [k for k, v in files.items() if v.get("mtime", 0) < cutoff]:
        del files[key]
    state["last_scan"] = time.time()


def esc(v):
    return str(v).replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def render(totals):
    lines = ["# HELP ai_tokens_total Tokens used, counted from local Claude Code, Codex and agy session logs and Hermes' usage table.",
             "# TYPE ai_tokens_total counter"]
    for k, n in sorted(totals.items()):
        provider, rest = k.split("|", 1)
        model, kind = rest.rsplit("|", 1)
        lines.append(f'ai_tokens_total{{client="{esc(provider)}",model="{esc(model)}",type="{esc(kind)}"}} {int(n)}')
    return "\n".join(lines) + "\n"


def write_atomic(path, text):
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


def main():
    state_path, output = Path(sys.argv[1]), sys.argv[2]
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        state = {}
    try:
        scan(state)
    except Exception as exc:
        print(f"token-usage-exporter: scan failed ({type(exc).__name__})", file=sys.stderr)
        return 1
    state_path.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(state_path, json.dumps(state))
    write_atomic(output, render(state.get("totals", {})))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
