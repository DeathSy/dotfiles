#!/usr/bin/env python3
"""Count AI token usage from local session logs into a node_exporter textfile.

Usage: token-usage-exporter <state.json> <output.prom>

Reads only what was appended since the last run (byte offset per file) from
  ~/.claude/projects/**/*.jsonl  (Claude Code: message.usage per reply, deduped by message.id)
  ~/.codex/sessions/**/*.jsonl   (Codex: token_count events, last_token_usage per turn)
and keeps monotonic totals in the state file, written as
  ai_tokens_total{provider,model,type="input|output|cache_read|cache_write"}  (counter)
Files seen for the first time start at their end, so totals count from the first run on.
"""

import json
import os
import sys
import time
from pathlib import Path

HOME = Path.home()
SOURCES = {"claude": HOME / ".claude/projects", "codex": HOME / ".codex/sessions"}
RECENT_IDS = 200  # Claude writes one line per content block with the same message id; keep a short memory


def claude_usage(rec, seen):
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
    last = (payload.get("info") or {}).get("last_token_usage")
    if not isinstance(last, dict):
        return None
    cached = last.get("cached_input_tokens") or 0
    return state.get("model") or "codex", {
        "input": (last.get("input_tokens") or 0) - cached,  # OpenAI's input_tokens includes cached ones
        "output": last.get("output_tokens"),
        "cache_read": cached,
        "cache_write": last.get("cache_write_input_tokens"),
    }


def scan(state):
    files, totals = state.setdefault("files", {}), state.setdefault("totals", {})
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
            if entry is None:
                files[key] = {"offset": st.st_size, "ino": st.st_ino, "mtime": st.st_mtime}
                continue
            if st.st_mtime < since and st.st_size == entry["offset"]:
                continue
            if st.st_ino != entry.get("ino") or st.st_size < entry["offset"]:
                entry.update(offset=0, ino=st.st_ino, seen=[], ctx={})  # replaced or truncated file
            with path.open("rb") as fh:
                fh.seek(entry["offset"])
                data = fh.read()
            end = data.rfind(b"\n") + 1  # only complete lines; a half-written line waits for the next run
            seen, ctx = entry.setdefault("seen", []), entry.setdefault("ctx", {})
            for line in data[:end].splitlines():
                if b'"usage"' not in line and b"token_count" not in line and b"turn_context" not in line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                got = claude_usage(rec, seen) if provider == "claude" else codex_usage(rec, ctx)
                if got is None:
                    continue
                model, counts = got
                for kind, n in counts.items():
                    if isinstance(n, (int, float)) and n > 0:
                        k = f"{provider}|{model}|{kind}"
                        totals[k] = totals.get(k, 0) + n
            entry["offset"] += end
            entry["mtime"] = st.st_mtime
    # Forget files untouched for 30 days (their offsets aren't needed any more).
    cutoff = time.time() - 30 * 86400
    for key in [k for k, v in files.items() if v.get("mtime", 0) < cutoff]:
        del files[key]
    state["last_scan"] = time.time()


def esc(v):
    return str(v).replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def render(totals):
    lines = ["# HELP ai_tokens_total Tokens used, counted from local Claude Code and Codex session logs.",
             "# TYPE ai_tokens_total counter"]
    for k, n in sorted(totals.items()):
        provider, model, kind = k.split("|")
        lines.append(f'ai_tokens_total{{provider="{esc(provider)}",model="{esc(model)}",type="{esc(kind)}"}} {int(n)}')
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
