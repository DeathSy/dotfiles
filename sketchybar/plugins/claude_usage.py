#!/usr/bin/env python3
# Compute Claude Code usage for the current 5-hour rate-limit block, split into
# Claude models vs Fable, from ~/.claude/projects/*.jsonl. Prints one label line
# for sketchybar, e.g.:  "C 15M  F 3.8M  42m"
#
# Metric = billable tokens (input + output + cache-creation); near-free cache
# reads are excluded so the numbers track the plan limit meaningfully.
import json, glob, os, time, datetime

FIVE = 5 * 3600
# Rough Max-20x billable-token ceiling for a 5h block. Anthropic doesn't publish
# an exact number — calibrate this once you observe your real cap. 0 = hide %.
LIMIT = int(os.environ.get("CLAUDE_5H_LIMIT", "0"))

now = time.time()
cut = now - 6 * 3600  # only scan recently-touched files for speed
rows = []
for f in glob.glob(os.path.expanduser("~/.claude/projects/**/*.jsonl"), recursive=True):
    try:
        if os.path.getmtime(f) < cut:
            continue
    except OSError:
        continue
    try:
        with open(f, errors="ignore") as fh:
            for line in fh:
                if '"usage"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                msg = d.get("message") or {}
                u = msg.get("usage") or {}
                ts = d.get("timestamp")
                if not ts or not u:
                    continue
                try:
                    t = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
                except Exception:
                    continue
                bil = (u.get("input_tokens", 0) + u.get("output_tokens", 0)
                       + u.get("cache_creation_input_tokens", 0))
                rows.append((t, msg.get("model", ""), bil))
    except OSError:
        continue

rows.sort()

blk = None
bs = last = None
for t, m, bil in rows:
    if bs is None or t - bs >= FIVE or (last is not None and t - last >= FIVE):
        bs = t - (t % 3600)  # anchor to the top of the hour, like ccusage
        blk = {"start": bs, "claude": 0, "fable": 0}
    if "fable" in m:
        blk["fable"] += bil
    elif m and m != "<synthetic>":
        blk["claude"] += bil
    last = t


def human(n):
    if n >= 1e6:
        return f"{n / 1e6:.1f}M"
    if n >= 1e3:
        return f"{n / 1e3:.0f}k"
    return str(int(n))


if blk is None or (now - blk["start"]) >= FIVE:
    # No active block — the window is idle / already reset.
    print("idle")
else:
    mins = int((blk["start"] + FIVE - now) / 60)
    reset = f"{mins // 60}h{mins % 60:02d}m" if mins >= 60 else f"{mins}m"
    label = f"C {human(blk['claude'])}  F {human(blk['fable'])}  {reset}"
    if LIMIT > 0:
        pct = min(100, int((blk["claude"] + blk["fable"]) * 100 / LIMIT))
        label = f"C {human(blk['claude'])}  F {human(blk['fable'])}  {pct}%  {reset}"
    print(label)
