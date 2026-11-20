#!/usr/bin/python3 -I
"""inbox: a local stdio MCP server for the inbox monitor (a Hermes cron job).

- Structured tools only: argv is built in code and nothing goes through a shell.
- By reference: the window comes from state, Slack searches are fixed templates from config.json, and
  threads, histories, email bodies and reactions only accept ids this cycle's results (or tracked
  reminders) returned. Text from messages can't steer the tools elsewhere.
- The Slack user token is read from the login Keychain (service inbox-monitor) by this process only; it is
  never in Hermes' environment or in any output.
- Everything returned is masked (emails, Thai phone numbers, 13-digit ids; last 4 chars kept). The
  mailbox owner's address shows as ME, and fetch_gmail.py adds me_in / from_me / from_domain before
  masking.
Stdlib only; MCP's newline-delimited JSON-RPC over stdin/stdout. Code is read-only in the Nix store;
state and config.json live in $INBOX_STATE_DIR (default ~/.local/state/inbox-monitor).
"""
import importlib.machinery, importlib.util, json, os, re, subprocess, sys, time, urllib.error, urllib.parse, \
    urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
IM = os.path.join(HERE, "im")
GMAIL = os.path.join(HERE, "fetch_gmail.py")
PY = sys.executable
GWS = os.environ.get("INBOX_GWS", "/opt/homebrew/bin/gws")
GH = os.environ.get("INBOX_GH", "gh")
SECURITY = "/usr/bin/security"

_loader = importlib.machinery.SourceFileLoader("im_mod", IM)
_spec = importlib.util.spec_from_loader("im_mod", _loader)
im_mod = importlib.util.module_from_spec(_spec)
_loader.exec_module(im_mod)
mask, CONFIG, LISTS, STATE_DIR = im_mod.mask, im_mod.CONFIG, list(im_mod.LISTS), im_mod.STATE_DIR

OWNER = CONFIG.get("owner_slack_id", "")
QUERIES = CONFIG.get("queries", {})            # name -> Slack search query (fixed templates)
EXCLUDE_CHANNELS = set(CONFIG.get("exclude_channels", []))   # e.g. the Hermes bot's DM with the owner
GH_OWNERS = set(CONFIG.get("gh_owners", []))
CHANNEL_RE = re.compile(r"^[CDG][A-Z0-9]{6,}$")
TS_RE = re.compile(r"^\d{10}\.\d{6}$")
MAX_TEXT = 1500          # chars kept per Slack message
MAX_THREAD = 60          # thread messages returned (first + latest)
MAX_PAGES = 10

# Ids this cycle's tool results handed out; reset by `window`. Tracked reminders are added too.
known = {"slack": set(), "threads": set(), "gmail": set(), "gmail_threads": set()}
cycle = {}


class ToolError(Exception):
    pass


# ── subprocess helpers ────────────────────────────────────────────────────────

def run(argv, timeout=180, stdin=None):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, input=stdin, cwd=STATE_DIR)
    except subprocess.TimeoutExpired:
        raise ToolError(f"{os.path.basename(argv[1] if argv[0] == PY else argv[0])} timed out after {timeout} s")
    return p.returncode, p.stdout, p.stderr


def im(*args):
    rc, out, err = run([PY, IM, *[str(a) for a in args]])
    try:
        return json.loads(out)
    except ValueError:
        raise ToolError(mask((out or err).strip()[-800:]) or f"im exited {rc}")


_self_email = []


def self_email():
    if not _self_email:
        rc, out, _ = run([GWS, "gmail", "users", "getProfile", "--params", '{"userId":"me"}'], timeout=60)
        try:
            _self_email.append(json.loads(out[out.index("{"):])["emailAddress"].lower())
        except (ValueError, KeyError):
            raise ToolError("could not read the Gmail profile")
    return _self_email[0]


def gmail(*args):
    rc, out, err = run([PY, GMAIL, *[str(a) for a in args]], timeout=240)
    if rc != 0:
        raise ToolError("fetch_gmail failed: " + mask(err.strip().splitlines()[-1] if err.strip() else f"exit {rc}"))
    return json.loads(re.sub(re.escape(self_email()), "ME", out, flags=re.I))


# ── Slack Web API (user token) ────────────────────────────────────────────────

_users, _token = {}, []


def slack_token():
    if not _token:
        rc, out, _ = run([SECURITY, "find-generic-password", "-s", "inbox-monitor", "-a", "slack-user-token", "-w"],
                         timeout=10)
        if rc != 0 or not out.strip().startswith("xoxp-"):
            raise ToolError("Slack user token not available (Keychain item inbox-monitor/slack-user-token)")
        _token.append(out.strip())
    return _token[0]


def slack(method, **params):
    data = urllib.parse.urlencode({k: v for k, v in params.items() if v is not None}).encode()
    for attempt in range(3):
        req = urllib.request.Request(f"https://slack.com/api/{method}", data=data,
                                     headers={"Authorization": f"Bearer {slack_token()}"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                body = json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 2:
                time.sleep(min(int(e.headers.get("Retry-After", "5")), 30))
                continue
            raise ToolError(f"Slack {method}: HTTP {e.code}")
        except OSError as e:
            raise ToolError(f"Slack {method}: {e.__class__.__name__}")
        if not body.get("ok"):
            raise ToolError(f"Slack {method}: {body.get('error', 'unknown error')}")
        return body
    raise ToolError(f"Slack {method}: rate limited (Slack status = failed)")


def user_name(uid):
    if not uid:
        return None
    if uid not in _users:
        try:
            u = slack("users.info", user=uid)["user"]
        except ToolError:
            return uid  # not cached: a transient failure shouldn't stick for the server's lifetime
        _users[uid] = u.get("real_name") or u.get("name") or uid
    return _users[uid]


def thread_ts_from(permalink):
    q = urllib.parse.parse_qs(urllib.parse.urlparse(permalink or "").query)
    return (q.get("thread_ts") or [None])[0]


def msg_row(channel, m, permalink=None, register=True):
    row = {"key": f"{channel}:{m['ts']}", "channel": channel, "ts": m["ts"],
           "thread_ts": m.get("thread_ts") or thread_ts_from(permalink),
           "user": m.get("user"), "user_name": user_name(m.get("user")) or m.get("username"),
           "bot": bool(m.get("bot_id")), "reply_count": m.get("reply_count"),
           "text": mask((m.get("text") or "")[:MAX_TEXT])}
    if register:  # search and thread rows only; history rows can't be used to walk a channel
        known["slack"].add(row["key"])
        known["threads"].add(f"{channel}:{row['thread_ts'] or m['ts']}")
    return row


def need_window():
    if "start" not in cycle:
        raise ToolError("call window first")
    return cycle["start"], cycle["end"]


def day(epoch):
    return time.strftime("%Y-%m-%d", time.localtime(epoch))


# ── tools ─────────────────────────────────────────────────────────────────────

def t_window():
    r = im("window")
    for k in known:
        known[k].clear()
    cycle.clear()
    if r.get("skip"):
        return r
    cycle.update(start=r["window_start"], end=r["window_end"])
    # The owner's profile (names, aliases, lists, known not-tasks) lives in config.json, not in the skill.
    r["profile"] = CONFIG.get("profile", "")
    return r


def t_tracked():
    items = im("tracked")
    for it in items if isinstance(items, list) else []:
        if it.get("channel") and it.get("thread_ts"):
            known["threads"].add(f"{it['channel']}:{it['thread_ts']}")
            known["slack"].add(f"{it['channel']}:{it['thread_ts']}")
        if it.get("thread_id"):
            known["gmail_threads"].add(it["thread_id"])
    return items


def t_slack_search(query_name):
    """search.messages over this cycle's window with a fixed query template; ts filtered exactly."""
    start, end = need_window()
    if query_name not in QUERIES:
        raise ToolError(f"unknown query_name; configured: {sorted(QUERIES)}")
    q = f"{QUERIES[query_name]} after:{day(start - 86400)} before:{day(end + 86400)}"
    rows, page, pages = [], 1, 1
    while page <= pages and page <= MAX_PAGES:
        r = slack("search.messages", query=q, sort="timestamp", sort_dir="asc", count=100, page=page)
        msgs = r.get("messages", {})
        pages = msgs.get("paging", {}).get("pages", 1)
        for m in msgs.get("matches", []):
            ch = m.get("channel", {})
            if not (start <= float(m["ts"]) <= end) or ch.get("id") in EXCLUDE_CHANNELS:
                continue
            if (ch.get("is_im") or ch.get("is_mpim")) and m.get("bot_id"):
                continue  # bots in DMs (including Hermes itself) are never asks
            row = msg_row(ch.get("id"), m, m.get("permalink"))
            row.update(channel_name=ch.get("name"), is_dm=bool(ch.get("is_im")), is_group_dm=bool(ch.get("is_mpim")))
            rows.append(row)
        page += 1
    return {"query_name": query_name, "results": rows, "complete": pages <= MAX_PAGES,
            "note": None if pages <= MAX_PAGES else f"only the first {MAX_PAGES} of {pages} pages were read"}


def t_slack_thread(key):
    """key: '<channel>:<thread_ts>' (or a message key) from this cycle's results or a tracked reminder."""
    if key not in known["threads"] and key not in known["slack"]:
        raise ToolError("unknown key: use a key or thread from this cycle's results or from tracked")
    channel, thread_ts = key.split(":", 1)
    msgs, cursor = [], None
    while True:
        r = slack("conversations.replies", channel=channel, ts=thread_ts, limit=200, cursor=cursor)
        msgs += r.get("messages", [])
        cursor = r.get("response_metadata", {}).get("next_cursor")
        if not cursor or len(msgs) > 1000:
            break
    total = len(msgs)
    if total > MAX_THREAD:
        msgs = msgs[:1] + msgs[-(MAX_THREAD - 1):]
    return {"channel": channel, "thread_ts": thread_ts, "total_messages": total,
            "omitted_middle": max(0, total - MAX_THREAD), "messages": [msg_row(channel, m) for m in msgs]}


def t_slack_history(key, hours_before, hours_after):
    """The conversation around a message from this cycle's results (at most 24 h each side)."""
    if key not in known["slack"]:
        raise ToolError("unknown key: use a message key from this cycle's results")
    channel, ts = key.split(":", 1)
    hb, ha = max(0, min(int(hours_before), 24)), max(0, min(int(hours_after), 24))
    t = float(ts)
    r = slack("conversations.history", channel=channel, oldest=str(t - hb * 3600), latest=str(t + ha * 3600),
              limit=100, inclusive="true")
    return {"channel": channel,
            "messages": [msg_row(channel, m, register=False) for m in reversed(r.get("messages", []))],
            "has_more": r.get("has_more", False)}


def t_react_clipboard(key):
    if key not in known["slack"]:
        raise ToolError("unknown key: use the message key the reminder was created from")
    channel, ts = key.split(":", 1)
    rc, _, err = run([PY, IM, "hook-reaction"],
                     stdin=json.dumps({"tool_input": {"channel_id": channel, "message_ts": ts, "emoji": "clipboard"}}))
    if rc != 0:
        raise ToolError("reaction refused: " + err.strip())
    try:
        slack("reactions.add", channel=channel, timestamp=ts, name="clipboard")
    except ToolError as e:
        if "already_reacted" not in str(e):
            raise
    return {"reacted": key}


def t_gmail_list():
    start, end = need_window()
    rows = gmail(start, end)
    for m in rows:
        known["gmail"].add(m["id"])
        known["gmail_threads"].add(m["threadId"])
    return rows


def t_gmail_body(message_id):
    if message_id not in known["gmail"]:
        raise ToolError("unknown message_id: use an id from this cycle's gmail_list")
    return gmail("--body", message_id)


def t_gmail_thread(thread_id):
    if thread_id not in known["gmail_threads"]:
        raise ToolError("unknown thread_id: use a threadId from gmail_list or tracked")
    msgs = gmail("--thread", thread_id)
    for m in msgs:
        known["gmail"].add(m["id"])
    return msgs


def t_gh_pr_state(repo, number):
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo or "") or repo.split("/")[0] not in GH_OWNERS:
        raise ToolError(f"repo must be owner/name with owner in {sorted(GH_OWNERS)}")
    rc, out, err = run([GH, "pr", "view", str(int(number)), "-R", repo, "--json", "state,mergedAt,title"], timeout=60)
    if rc != 0:
        raise ToolError("gh: " + mask((err.strip().splitlines() or [f"exit {rc}"])[-1]))
    return json.loads(out)


S = lambda **p: {"type": "object", "properties": p, "required": list(p), "additionalProperties": False}  # noqa: E731
STR, INT = {"type": "string"}, {"type": "integer"}
STRS = {"type": "array", "items": {"type": "string"}}
LIST = {"type": "string", "enum": LISTS}


def optional(schema, *names):
    schema["required"] = [n for n in schema["required"] if n not in names]
    return schema


TOOLS = {
    "window": ("Start of a cycle: window_start, window_end (a chunk of at most 24 h), catching_up. "
               "If it returns skip: true, stop and reply [SILENT].", S(), t_window),
    "tracked": ("Open reminders this monitor created, with user_note and the recheck flag.", S(), t_tracked),
    "checked": ("Record that these tracked reminder keys were re-verified now.",
                S(keys=STRS), lambda keys: im("checked", *keys)),
    "new_slack": ("Which '<channel_id>:<ts>' keys are not processed yet.",
                  S(keys=STRS), lambda keys: im("new-slack", *keys)),
    "seen": ("Mark keys processed (task or not). kind: slack or gmail.",
             S(kind={"type": "string", "enum": ["slack", "gmail"]}, keys=STRS),
             lambda kind, keys: im("seen", kind, *keys)),
    "finish": ("End of cycle. slack/email: ok or failed. Advances the window only if both ok and nothing is "
               "unfinished.",
               S(slack={"type": "string", "enum": ["ok", "failed"]}, email={"type": "string", "enum": ["ok", "failed"]},
                 summary=STR),
               lambda slack, email, summary: im("finish", slack, email, summary)),
    "open_reminders": ("Open reminders in a list (titles), to spot duplicates.", S(list=LIST),
                       lambda list: im("open", list)),
    "create_reminder": (
        "Create one reminder (one ask). key: slack:<channel_id>:<ts> or gmail:<message id> from this cycle's "
        "results, plus #2..#9 for further asks of the same source. quadrant: do-now|plan|delegate|borderline. "
        "due only from an explicit deadline (YYYY-MM-DD or YYYY-MM-DDTHH:MM, Bangkok) with due_from = the exact "
        "deadline words.",
        optional(S(key=STR, list=LIST, quadrant={"type": "string", "enum": ["do-now", "plan", "delegate", "borderline"]},
                   title=STR, ask=STR, sender=STR, close_when=STR, due=STR, due_from=STR, thread_ts=STR),
                 "due", "due_from", "thread_ts"),
        lambda key, list, quadrant, title, ask, sender, close_when, due=None, due_from=None, thread_ts=None:
        create(key, list, quadrant, title, ask, sender, close_when, due, due_from, thread_ts)),
    "complete_reminder": ("Mark a tracked reminder completed (auto-close or the user's decision).",
                          S(key=STR), lambda key: im("complete", key)),
    "update_reminder": ("Change a tracked reminder's quadrant or due date.",
                        S(key=STR, field={"type": "string", "enum": ["quadrant", "due"]}, value=STR),
                        lambda key, field, value: im("update", key, field, value)),
    "slack_search": ("Search Slack in this cycle's window (all pages) with a configured query: "
                     + ", ".join(sorted(QUERIES)) + ".",
                     S(query_name={"type": "string", "enum": sorted(QUERIES)}), t_slack_search),
    "slack_thread": ("Read a thread by '<channel>:<thread_ts>' from this cycle's results or tracked "
                     "(first message + latest 59 when long).", S(key=STR), t_slack_thread),
    "slack_history": ("The conversation around a message key from this cycle's results (hours 0-24 each side).",
                      S(key=STR, hours_before=INT, hours_after=INT), t_slack_history),
    "slack_react_clipboard": ("React :clipboard: on the message a reminder was just created from.",
                              S(key=STR), t_react_clipboard),
    "gmail_list": ("Unseen inbox emails in this cycle's window (no promotions/social/forums/updates). "
                   "me_in says whether ME is in To, CC or neither.", S(), t_gmail_list),
    "gmail_body": ("One email from this cycle's gmail_list, with its decoded text body.", S(message_id=STR),
                   t_gmail_body),
    "gmail_thread": ("Every message of an email thread from gmail_list or tracked, oldest first.",
                     S(thread_id=STR), t_gmail_thread),
    "gh_pr_state": ("State of a GitHub PR (OPEN/MERGED/CLOSED).", S(repo=STR, number=INT), t_gh_pr_state),
}


def create(key, lst, quadrant, title, ask, sender, close_when, due, due_from, thread_ts):
    source = key.split("#")[0]
    if source.startswith("slack:") and source[6:] not in known["slack"]:
        raise ToolError("key must come from this cycle's Slack results")
    if source.startswith("gmail:") and source[6:] not in known["gmail"]:
        raise ToolError("key must come from this cycle's gmail_list")
    return im("create", "--key", key, "--list", lst, "--quadrant", quadrant, "--title", title, "--ask", ask,
              "--from", sender, "--close-when", close_when,
              *(["--due", due, "--due-from", due_from or ""] if due else []),
              *(["--thread-ts", thread_ts] if thread_ts else []))


def masked(v):
    """Mask every decoded string (never the serialized JSON, where escapes would hide matches)."""
    if isinstance(v, str):
        return mask(v)
    if isinstance(v, list):
        return [masked(x) for x in v]
    if isinstance(v, dict):
        return {k: masked(x) for k, x in v.items()}
    return v


def handle(req):
    method, params = req.get("method"), req.get("params") or {}
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion", "2025-06-18"),
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "inbox", "version": "2.0"}}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": [{"name": n, "description": d, "inputSchema": s} for n, (d, s, _) in TOOLS.items()]}
    if method == "tools/call":
        name, args = params.get("name"), params.get("arguments") or {}
        if name not in TOOLS:
            return {"content": [{"type": "text", "text": f"unknown tool {name}"}], "isError": True}
        _, schema, fn = TOOLS[name]
        extra = set(args) - set(schema["properties"])
        if extra:
            return {"content": [{"type": "text", "text": f"unknown arguments: {sorted(extra)}"}], "isError": True}
        try:
            result = masked(fn(**args))
            is_error = isinstance(result, dict) and "error" in result and len(result) == 1
            return {"content": [{"type": "text", "text": json.dumps(result, ensure_ascii=False)}], "isError": is_error}
        except (ToolError, TypeError, ValueError) as e:
            return {"content": [{"type": "text", "text": mask(str(e))}], "isError": True}
        except Exception as e:  # noqa: BLE001
            return {"content": [{"type": "text", "text": f"internal error: {e.__class__.__name__}"}], "isError": True}
    if req.get("id") is None:
        return None  # notification
    raise LookupError(method)


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except ValueError:
            continue
        if not isinstance(req, dict):
            continue
        try:
            result = handle(req)
            if req.get("id") is None:
                continue
            resp = {"jsonrpc": "2.0", "id": req["id"], "result": result}
        except LookupError as e:
            resp = {"jsonrpc": "2.0", "id": req.get("id"), "error": {"code": -32601, "message": f"method not found: {e}"}}
        sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
