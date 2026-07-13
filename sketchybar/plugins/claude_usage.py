#!/usr/bin/env python3
# Claude Code usage for sketchybar, mirroring `/usage`:
#   - session: current 5-hour block, all models combined  -> "S 51%"
#   - weekly Fable: Fable billable over the last 7 days     -> "F 12%"
#   plus the session reset countdown, e.g. "S 51%  F 12%  21m".
#
# Metric = billable tokens (input + output + cache-creation). Limits come from
# CLAUDE_5H_LIMIT (session) and FABLE_WEEK_LIMIT (weekly Fable); 0 => show the
# raw token volume instead of a %. The weekly figure is cached (~15 min) so the
# heavier 7-day scan doesn't run on every refresh.
import json, glob, os, time, datetime

FIVE = 5 * 3600
WEEK = 7 * 86400
SESSION_LIMIT = int(os.environ.get("CLAUDE_5H_LIMIT", "0"))
FABLE_WEEK_LIMIT = int(os.environ.get("FABLE_WEEK_LIMIT", "0"))
CACHE = os.path.expanduser("~/.cache/claude_usage_weekly")

now = time.time()


def scan(cut):
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
    return rows


# --- session: current 5h block, all models combined ---
rows = sorted(scan(now - 6 * 3600))
bs = last = None
blk = None
for t, m, bil in rows:
    if bs is None or t - bs >= FIVE or (last is not None and t - last >= FIVE):
        bs = t - (t % 3600)
        blk = {"start": bs, "tot": 0}
    if m and m != "<synthetic>":
        blk["tot"] += bil
    last = t

# --- weekly Fable: cached, recompute at most every 15 min ---
fable_week = None
try:
    if now - os.stat(CACHE).st_mtime < 900:
        fable_week = int(open(CACHE).read().strip() or 0)
except OSError:
    pass
if fable_week is None:
    fable_week = sum(bil for t, m, bil in scan(now - WEEK) if "fable" in m)
    try:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        open(CACHE, "w").write(str(fable_week))
    except OSError:
        pass


def human(n):
    return f"{n / 1e6:.1f}M" if n >= 1e6 else f"{n / 1e3:.0f}k"


def show(n, lim):
    return f"{min(100, int(n * 100 / lim))}%" if lim > 0 else human(n)


parts = []
reset = None
if blk and (now - blk["start"]) < FIVE:
    parts.append(f"S {show(blk['tot'], SESSION_LIMIT)}")
    mins = int((blk["start"] + FIVE - now) / 60)
    reset = f"{mins // 60}h{mins % 60:02d}m" if mins >= 60 else f"{mins}m"
else:
    parts.append("S idle")

parts.append(f"F {show(fable_week, FABLE_WEEK_LIMIT)}")
if reset:
    parts.append(reset)

print("  ".join(parts))
