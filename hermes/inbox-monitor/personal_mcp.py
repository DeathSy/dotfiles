#!/usr/bin/python3 -I
"""personal: the owner's own data tools for Hermes chat (Slack as the owner, Gmail, Reminders, GitHub PRs),
plus sending Slack messages as July (the bot: slack_bot_dm, slack_bot_post; Hermes ships no send tool) and
Gmail attachments / Google Drive files (gmail_attachment, drive_search, drive_fetch) through the owner's gws login.

The owner chose to give July (chat) full access to their personal data, so nothing here is masked and the
arguments are by value. What chat must NOT reach is the inbox monitor's bookkeeping: this server has no
window/finish/seen/tracked tools, never reads or writes the monitor's state.json, and reminders it creates
are not tracked by the monitor. It reuses inbox_mcp.py's Slack/Gmail/Reminders plumbing and its JSON-RPC
loop; the Slack user token still comes from the Keychain inside the process and never appears in output.
"""
import base64, importlib.machinery, importlib.util, json, os, re, subprocess, sys, time, urllib.parse, urllib.request, \
    uuid, zipfile, xml.etree.ElementTree as ET

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


# ── Slack as the bot (July) ───────────────────────────────────────────────────
# Messages July sends in its own name. The persona requires showing the exact text to the requester and
# their confirmation before anything goes to someone else. The bot token is read from the Keychain here
# and never returned.

_bot_token, _members = [], []
USER_RE = re.compile(r"^[UW][A-Z0-9]{6,}$")


def bot(method, **params):
    if not _bot_token:
        rc, out, _ = run([base.SECURITY, "find-generic-password", "-s", "hermes-agent", "-a", "slack-bot-token", "-w"],
                         timeout=10)
        if rc != 0 or not out.strip().startswith("xoxb-"):
            raise ToolError("Slack bot token not available (Keychain item hermes-agent/slack-bot-token)")
        _bot_token.append(out.strip())
    data = urllib.parse.urlencode({k: v for k, v in params.items() if v is not None}).encode()
    req = urllib.request.Request(f"https://slack.com/api/{method}", data=data,
                                 headers={"Authorization": f"Bearer {_bot_token[0]}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = json.load(r)
    except (OSError, ValueError) as e:
        raise ToolError(f"Slack {method}: {e.__class__.__name__}")
    if not body.get("ok"):
        raise ToolError(f"Slack {method}: {body.get('error', 'unknown error')}")
    return body


def find_user(who):
    """A member id, or a unique match on Slack handle / display name / real name (case-insensitive)."""
    who = (who or "").strip().lstrip("@")
    if USER_RE.match(who):
        return who, None
    if not _members:
        cursor = None
        while True:
            r = bot("users.list", limit=200, cursor=cursor)
            _members.extend(m for m in r.get("members", []) if not m.get("deleted") and not m.get("is_bot"))
            cursor = (r.get("response_metadata") or {}).get("next_cursor")
            if not cursor:
                break
    key = who.lower()
    names = lambda m: {m.get("name", "").lower(), (m.get("profile") or {}).get("display_name", "").lower(),
                       (m.get("real_name") or "").lower()}
    hits = [m for m in _members if key in names(m)] or [m for m in _members if any(key in n for n in names(m) if n)]
    if len(hits) != 1:
        cands = ", ".join(f"{m.get('real_name') or m.get('name')} ({m['id']})" for m in hits[:8])
        raise ToolError(f"{'no' if not hits else len(hits)} Slack members match {who!r}" + (f": {cands}" if hits else
                        "; use the member id"))
    return hits[0]["id"], hits[0].get("real_name") or hits[0].get("name")


def permalink(channel, ts):
    try:
        return bot("chat.getPermalink", channel=channel, message_ts=ts).get("permalink")
    except ToolError:
        return None


def t_slack_bot_dm(user, text):
    if not (text or "").strip():
        raise ToolError("text is empty")
    uid, name = find_user(user)
    channel = bot("conversations.open", users=uid)["channel"]["id"]
    ts = bot("chat.postMessage", channel=channel, text=text)["ts"]
    return {"sent_as": "July (bot)", "to": name or uid, "user": uid, "channel": channel, "ts": ts,
            "permalink": permalink(channel, ts)}


def t_slack_bot_post(channel, text, thread_ts=None):
    if not (text or "").strip():
        raise ToolError("text is empty")
    ch = (channel or "").strip()
    if ch.startswith("#"):
        want, cursor, found = ch[1:].lower(), None, None
        while not found:
            r = bot("conversations.list", types="public_channel,private_channel", exclude_archived="true",
                    limit=200, cursor=cursor)
            found = next((c["id"] for c in r.get("channels", []) if c.get("name", "").lower() == want), None)
            cursor = (r.get("response_metadata") or {}).get("next_cursor")
            if not cursor:
                break
        if not found:
            raise ToolError(f"no channel named {ch} visible to July")
        ch = found
    check_ids(ch, thread_ts)
    ts = bot("chat.postMessage", channel=ch, text=text, thread_ts=thread_ts)["ts"]
    return {"sent_as": "July (bot)", "channel": ch, "ts": ts, "thread_ts": thread_ts, "permalink": permalink(ch, ts)}


# ── Files: Gmail attachments, Google Drive (with the owner's gws login) ─────────
# Saved privately under ~/.cache (0700 dirs, 0600 files); text is extracted where macOS can do it without
# extra software: PDF (PDFKit), DOCX/DOC/RTF/ODT/HTML (textutil), XLSX (its XML), CSV/TXT as they are.

ATT_DIR, DRIVE_DIR = os.path.expanduser("~/.cache/july-attachments"), os.path.expanduser("~/.cache/july-drive")
DOCS_JS = os.path.join(HERE, "docs_text.js")
EXPORT = {"application/vnd.google-apps.document": ("text/plain", ".txt"),
          "application/vnd.google-apps.presentation": ("text/plain", ".txt"),
          "application/vnd.google-apps.spreadsheet": ("text/csv", ".csv"),
          "application/vnd.google-apps.drawing": ("application/pdf", ".pdf")}
TEXT_MAX = 60000


def gws_json(*args):
    rc, out, err = run([base.GWS, *args], timeout=180)
    if rc != 0:  # gws also prints "Using keyring backend: keyring" on stderr: that line is not an error
        msg = [l for l in err.strip().splitlines() if l.strip() and "Using keyring backend" not in l]
        raise ToolError("gws failed: " + (msg[-1][:300] if msg else f"exit {rc}"))
    return json.loads(out) if out.strip() else {}


def gws_download(folder, name, *args):
    # gws writes --output only inside its working directory: run it there with a bare file name.
    os.makedirs(folder, mode=0o700, exist_ok=True)
    p = subprocess.run([base.GWS, *args, "-o", name], capture_output=True, text=True, timeout=300, cwd=folder)
    if p.returncode != 0:
        msg = [l for l in p.stderr.strip().splitlines() if l.strip() and "Using keyring backend" not in l]
        raise ToolError("gws failed: " + (msg[-1][:300] if msg else f"exit {p.returncode}"))
    path = os.path.join(folder, name)
    os.chmod(path, 0o600)
    return path


def safe_name(name):
    return (re.sub(r"[^\w.\- ]+", "_", name or "file").strip() or "file")[:150]


def xlsx_text(path):
    with zipfile.ZipFile(path) as z:
        ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
        shared = []
        if "xl/sharedStrings.xml" in z.namelist():
            for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", ns):
                shared.append("".join(t.text or "" for t in si.iter("{%s}t" % ns["m"])))
        out = []
        for n in sorted(x for x in z.namelist() if re.match(r"xl/worksheets/sheet\d+\.xml$", x)):
            out.append(f"## {n.split('/')[-1][:-4]}")
            for row in ET.fromstring(z.read(n)).iter("{%s}row" % ns["m"]):
                cells = []
                for c in row.findall("m:c", ns):
                    v = c.find("m:v", ns)
                    t = c.find("m:is/m:t", ns)
                    val = (t.text if t is not None else v.text if v is not None else "") or ""
                    if c.get("t") == "s" and val.isdigit() and int(val) < len(shared):
                        val = shared[int(val)]
                    cells.append(val.replace("\t", " "))
                out.append("\t".join(cells))
        return "\n".join(out)


def extract_text(path, mime=""):
    ext = os.path.splitext(path)[1].lower()
    try:
        if ext == ".pdf" or mime == "application/pdf":
            rc, out, err = run(["/usr/bin/osascript", "-l", "JavaScript", DOCS_JS, "pdf", path], timeout=120)
            r = json.loads(out or "{}")
            if r.get("locked"):
                return None, "the PDF is password-protected: its text can't be read without the password"
            if "error" in r:
                return None, "PDF text: " + r["error"]
            return r.get("text", ""), None if r.get("text", "").strip() else "the PDF has no text layer (scanned image)"
        if ext in (".docx", ".doc", ".rtf", ".odt", ".html", ".htm", ".webarchive"):
            p = subprocess.run(["/usr/bin/textutil", "-convert", "txt", "-stdout", path], capture_output=True, text=True,
                               timeout=120)
            return (p.stdout, None) if p.returncode == 0 else (None, "textutil could not read it")
        if ext == ".xlsx":
            return xlsx_text(path), None
        if ext in (".txt", ".csv", ".md", ".json", ".xml", ".log") or mime.startswith("text/"):
            return open(path, errors="replace").read(), None
    except (OSError, ValueError, zipfile.BadZipFile, ET.ParseError, subprocess.TimeoutExpired) as e:
        return None, f"text extraction failed ({e.__class__.__name__})"
    return None, f"no text extraction for {ext or mime or 'this file type'}; the file is saved"


def with_text(path, mime=""):
    text, note = extract_text(path, mime)
    out = {"saved": path, "bytes": os.path.getsize(path)}
    if text is not None:
        out["text"] = text[:TEXT_MAX]
        out["truncated"] = len(text) > TEXT_MAX
    if note:
        out["note"] = note
    return out


def parts(payload):
    yield payload
    for p in payload.get("parts", []) or []:
        yield from parts(p)


def t_gmail_attachment(message_id, attachment=None):
    mid = hexid(message_id)
    msg = gws_json("gmail", "users", "messages", "get", "--params", json.dumps({"userId": "me", "id": mid, "format": "full"}))
    atts = [p for p in parts(msg.get("payload", {})) if (p.get("body") or {}).get("attachmentId") and p.get("filename")]
    if not atts:
        raise ToolError("this email has no attachments")
    # Default: the first real document, not an inline signature image.
    docs = [p for p in atts if not (p.get("mimeType") or "").startswith("image/")] or atts
    pick = [p for p in atts if attachment in (p["body"]["attachmentId"], p["filename"])] if attachment else docs[:1]
    if not pick:
        raise ToolError("no attachment matches; this email has: " + ", ".join(p["filename"] for p in atts))
    p = pick[0]
    d = gws_json("gmail", "users", "messages", "attachments", "get", "--params",
                 json.dumps({"userId": "me", "messageId": mid, "id": p["body"]["attachmentId"]}))
    os.makedirs(ATT_DIR, mode=0o700, exist_ok=True)
    path = os.path.join(ATT_DIR, f"{mid}-{safe_name(p['filename'])}")
    with open(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "wb") as f:
        f.write(base64.urlsafe_b64decode(d["data"] + "=" * (-len(d["data"]) % 4)))
    out = with_text(path, p.get("mimeType", ""))
    out.update(filename=p["filename"], mime=p.get("mimeType"), others=[a["filename"] for a in atts if a is not p])
    return out


def t_drive_search(query, count=20):
    q = query.strip()
    if not re.search(r"\b(contains|=|in parents|mimeType|modifiedTime|trashed)\b", q):  # plain words
        w = q.replace("\\", "").replace("'", "\\'")
        q = f"(name contains '{w}' or fullText contains '{w}')"
    r = gws_json("drive", "files", "list", "--params", json.dumps({
        "q": f"{q} and trashed = false", "pageSize": max(1, min(int(count), 50)), "corpora": "allDrives",
        "supportsAllDrives": True, "includeItemsFromAllDrives": True, "orderBy": "modifiedTime desc",
        "fields": "files(id,name,mimeType,modifiedTime,webViewLink,owners(displayName))"}))
    return r.get("files", [])


def t_drive_fetch(file_id):
    if not re.fullmatch(r"[A-Za-z0-9_-]{10,}", file_id or ""):
        raise ToolError("file_id must be a Drive file id")
    meta = gws_json("drive", "files", "get", "--params", json.dumps(
        {"fileId": file_id, "supportsAllDrives": True, "fields": "id,name,mimeType,modifiedTime,size"}))
    name, mime = safe_name(meta["name"]), meta["mimeType"]
    if mime == "application/vnd.google-apps.folder":
        return {"folder": meta["name"], "files": t_drive_search(f"'{file_id}' in parents", 50)}
    if mime in EXPORT:
        emime, ext = EXPORT[mime]
        path = gws_download(DRIVE_DIR, f"{file_id}-{name}{ext}", "drive", "files", "export", "--params",
                            json.dumps({"fileId": file_id, "mimeType": emime}))
        out = with_text(path, emime)
    elif mime.startswith("application/vnd.google-apps."):
        raise ToolError(f"{mime} can't be downloaded or exported")
    else:
        path = gws_download(DRIVE_DIR, f"{file_id}-{name}", "drive", "files", "get", "--params",
                            json.dumps({"fileId": file_id, "alt": "media", "supportsAllDrives": True}))
        out = with_text(path, mime)
    out.update(name=meta["name"], mime=mime, modified=meta.get("modifiedTime"))
    return out


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
    "slack_bot_dm": ("Send a Slack DM AS JULY (the bot) to a member (id like U…, or a unique handle/name). Only after "
                     "the requester has seen and confirmed the exact text when the recipient is someone else.",
                     S(user=STR, text=STR), t_slack_bot_dm),
    "slack_bot_post": ("Post AS JULY (the bot) in a channel July is in (C…/G… id or #name), optionally in a thread. "
                       "Only after the requester has confirmed the exact text.",
                       opt(S(channel=STR, text=STR, thread_ts=STR), "thread_ts"), t_slack_bot_post),
    "gmail_search": ("Search the owner's Gmail (Gmail query syntax, e.g. 'from:x newer_than:7d', 'in:inbox is:unread').",
                     opt(S(query=STR, count=INT), "count"),
                     lambda query, count=20: gmail("--search", query, max(1, min(int(count), 50)))),
    "gmail_message": ("One email with its decoded text body.", S(message_id=STR),
                      lambda message_id: gmail("--body", hexid(message_id))),
    "gmail_thread": ("Every message of an email thread.", S(thread_id=STR),
                     lambda thread_id: gmail("--thread", hexid(thread_id))),
    "gmail_attachment": ("Save an email attachment (message_id from gmail_search/gmail_message; attachment = its "
                         "filename or attachmentId, default the first) to ~/.cache/july-attachments and return its text "
                         "(PDF, DOCX/DOC/RTF, XLSX, text) when it has one.",
                         opt(S(message_id=STR, attachment=STR), "attachment"), t_gmail_attachment),
    "drive_search": ("Search the owner's Google Drive (plain words match names and contents; Drive query syntax also "
                     "works, e.g. \"name contains 'PM-CF-001'\"). Newest first.",
                     opt(S(query=STR, count=INT), "count"), t_drive_search),
    "drive_fetch": ("Save a Drive file by id to ~/.cache/july-drive and return its text: Google Docs/Slides as text, "
                    "Sheets as CSV, PDFs/Office files as-is plus their text. A folder id lists its files.",
                    S(file_id=STR), t_drive_fetch),
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
