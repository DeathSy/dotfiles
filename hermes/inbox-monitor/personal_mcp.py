#!/usr/bin/python3 -I
"""personal: the owner's own data tools for Hermes chat (Slack as the owner, Gmail, Reminders, GitHub PRs).

The owner chose to give July (chat) full access to their personal data, so nothing here is masked and the
arguments are by value. What chat must NOT reach is the inbox monitor's bookkeeping: this server has no
window/finish/seen/tracked tools, never reads or writes the monitor's state.json, and reminders it creates
are not tracked by the monitor. It reuses inbox_mcp.py's Slack/Gmail/Reminders plumbing and its JSON-RPC
loop; the Slack user token still comes from the Keychain inside the process and never appears in output.
"""
import importlib.machinery, importlib.util, json, os, re, sys, time, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
_loader = importlib.machinery.SourceFileLoader("inbox_mcp", os.path.join(HERE, "inbox_mcp.py"))
_spec = importlib.util.spec_from_loader("inbox_mcp", _loader)
base = importlib.util.module_from_spec(_spec)
_loader.exec_module(base)

ToolError, slack, run, PY = base.ToolError, base.slack, base.run, base.PY
CHANNEL_RE = re.compile(r"^[CDG][A-Z0-9]{6,}$")
TS_RE = re.compile(r"^\d{10}\.\d{6}$")
EMOJI_RE = re.compile(r"^[a-z0-9_+\-']{1,64}$")
REMINDERS_JS = os.path.join(HERE, "reminders.js")


def row(channel, m):
    return {"channel": channel, "ts": m["ts"], "thread_ts": m.get("thread_ts"), "user": m.get("user"),
            "user_name": base.user_name(m.get("user")) or m.get("username"), "bot": bool(m.get("bot_id")),
            "reply_count": m.get("reply_count"), "text": base.message_text(m)[:4000]}


def check_ids(channel, ts=None):
    if not CHANNEL_RE.match(channel or "") or (ts is not None and not TS_RE.match(ts or "")):
        raise ToolError("channel must be a Slack channel id (C…/D…/G…) and ts like 1795089919.310379")


# ── Slack (as the owner) ──────────────────────────────────────────────────────

def t_slack_search(query, count=20):
    r = slack("search.messages", query=query, sort="timestamp", sort_dir="desc", count=max(1, min(int(count), 100)))
    out = []
    for m in r.get("messages", {}).get("matches", []):
        ch = m.get("channel", {})
        x = row(ch.get("id"), m)
        x.update(channel_name=ch.get("name"), permalink=m.get("permalink"))
        out.append(x)
    return {"query": query, "total": r.get("messages", {}).get("total"), "results": out}


def t_slack_thread(channel, thread_ts):
    check_ids(channel, thread_ts)
    msgs, cursor = [], None
    while True:
        r = slack("conversations.replies", channel=channel, ts=thread_ts, limit=200, cursor=cursor)
        msgs += r.get("messages", [])
        cursor = r.get("response_metadata", {}).get("next_cursor")
        if not cursor or len(msgs) > 1000:
            break
    return {"channel": channel, "thread_ts": thread_ts, "messages": [row(channel, m) for m in msgs[-200:]]}


def t_slack_history(channel, oldest=None, latest=None, limit=50):
    check_ids(channel)
    for v in (oldest, latest):
        if v is not None and not re.fullmatch(r"\d{9,10}(\.\d{1,6})?", str(v)):
            raise ToolError("oldest/latest must be unix times like 1795089919 or 1795089919.310379")
    r = slack("conversations.history", channel=channel, oldest=oldest, latest=latest,
              limit=max(1, min(int(limit), 200)), inclusive="true")
    return {"channel": channel, "messages": [row(channel, m) for m in reversed(r.get("messages", []))],
            "has_more": r.get("has_more", False)}


def t_slack_react(channel, ts, emoji):
    check_ids(channel, ts)
    if not EMOJI_RE.match(emoji or ""):
        raise ToolError("emoji must be a Slack emoji name without colons")
    try:
        slack("reactions.add", channel=channel, timestamp=ts, name=emoji)
    except ToolError as e:
        if "already_reacted" not in str(e):
            raise
    return {"reacted": f"{channel}:{ts}", "emoji": emoji}


# ── Gmail ─────────────────────────────────────────────────────────────────────

def gmail(*args):
    rc, out, err = run([PY, base.GMAIL, *[str(a) for a in args]], timeout=240)
    if rc != 0:
        raise ToolError("fetch_gmail failed: " + (err.strip().splitlines()[-1] if err.strip() else f"exit {rc}"))
    return json.loads(out)


def hexid(v):
    if not re.fullmatch(r"[0-9a-f]{10,20}", v or ""):
        raise ToolError("Gmail ids are 10-20 hex characters")
    return v


# ── Reminders (any list; not tracked by the monitor) ─────────────────────────

def rem(*args):
    rc, out, err = run(["/usr/bin/osascript", "-l", "JavaScript", REMINDERS_JS, *[str(a) for a in args]], timeout=120)
    try:
        r = json.loads(out)
    except ValueError:
        raise ToolError("Reminders: " + (err.strip() or f"exit {rc}"))
    if isinstance(r, dict) and "error" in r:
        raise ToolError("Reminders: " + r["error"])
    return r


def t_reminder_create(list, title, notes="", due="-", priority="none", flagged=False):
    if due != "-" and not re.fullmatch(r"\d{4}-\d{2}-\d{2}(T\d{2}:\d{2})?", due):
        raise ToolError("due must be YYYY-MM-DD, YYYY-MM-DDTHH:MM or -")
    marker = f"· chat:{uuid.uuid4().hex[:12]} ·"  # unique, so the duplicate check never matches; never monitor-tracked
    body = (notes.rstrip() + "\n\n" if notes.strip() else "") + f"— added from chat {marker}"
    return rem("create", list, title, body, due, priority, "flag" if flagged else "noflag", marker, list)


def t_reminder_update(id, field, value):
    if field == "flagged":
        return rem("update", id, "flag", "flag" if str(value).lower() in ("1", "true", "yes", "flag") else "noflag")
    return rem("update", id, field, value)


def t_gh_pr_state(repo, number):
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo or ""):
        raise ToolError("repo must be owner/name")
    rc, out, err = run([base.GH, "pr", "view", str(int(number)), "-R", repo, "--json",
                        "state,mergedAt,title,url,author,reviewDecision"], timeout=60)
    if rc != 0:
        raise ToolError("gh: " + (err.strip().splitlines() or [f"exit {rc}"])[-1])
    return json.loads(out)


S = base.S
STR, INT, BOOL = {"type": "string"}, {"type": "integer"}, {"type": "boolean"}
opt = base.optional

TOOLS = {
    "slack_search": ("Search Slack as the owner (Slack search syntax: in:#channel, from:@user, to:me, after:YYYY-MM-DD…).",
                     opt(S(query=STR, count=INT), "count"), t_slack_search),
    "slack_thread": ("Read a Slack thread (channel id + the thread's ts).", S(channel=STR, thread_ts=STR), t_slack_thread),
    "slack_history": ("Read a Slack conversation (channel or DM id), optionally between unix times oldest/latest.",
                      opt(S(channel=STR, oldest=STR, latest=STR, limit=INT), "oldest", "latest", "limit"),
                      t_slack_history),
    "slack_react": ("React to a Slack message as the owner.", S(channel=STR, ts=STR, emoji=STR), t_slack_react),
    "gmail_search": ("Search the owner's Gmail (Gmail query syntax, e.g. 'from:x newer_than:7d', 'in:inbox is:unread').",
                     opt(S(query=STR, count=INT), "count"),
                     lambda query, count=20: gmail("--search", query, max(1, min(int(count), 50)))),
    "gmail_message": ("One email with its decoded text body.", S(message_id=STR),
                      lambda message_id: gmail("--body", hexid(message_id))),
    "gmail_thread": ("Every message of an email thread.", S(thread_id=STR),
                     lambda thread_id: gmail("--thread", hexid(thread_id))),
    "reminder_lists": ("Names of the owner's Reminders lists.", S(), lambda: rem("lists")),
    "reminders_open": ("Open reminders in a list (titles, due, priority, flag).", S(list=STR),
                       lambda list: rem("open", list)),
    "reminder_get": ("One reminder by id, with notes.", S(id=STR), lambda id: rem("get", id)),
    "reminder_create": ("Create a reminder in any list. due: YYYY-MM-DD, YYYY-MM-DDTHH:MM or -. "
                        "priority: high|medium|low|none.",
                        opt(S(list=STR, title=STR, notes=STR, due=STR,
                              priority={"type": "string", "enum": ["high", "medium", "low", "none"]}, flagged=BOOL),
                            "notes", "due", "priority", "flagged"),
                        t_reminder_create),
    "reminder_complete": ("Mark a reminder completed (by id).", S(id=STR), lambda id: rem("complete", id)),
    "reminder_update": ("Change a reminder's priority (high|medium|low|none), flagged (true/false) or due (date).",
                        S(id=STR, field={"type": "string", "enum": ["priority", "flagged", "due"]}, value=STR),
                        t_reminder_update),
    "gh_pr_state": ("State of a GitHub pull request.", S(repo=STR, number=INT), t_gh_pr_state),
}

base.SERVER.update(name="personal", tools=TOOLS, mask=False, lease=False)

if __name__ == "__main__":
    base.main()
