#!/usr/bin/python3 -I
"""fetch_gmail.py <start> [<end>]  compact JSON of inbox emails between the epochs not yet in state.json's
                                  gmail_ids (skips Promotions/Social/Forums/Updates, flags calendar invites)
fetch_gmail.py --body <id>        one message with its decoded text body
fetch_gmail.py --thread <thread>  every message of a thread (oldest first), decoded bodies shortened"""
import base64, html, json, os, re, subprocess, sys
from email.utils import getaddresses

STATE_DIR = os.environ.get("INBOX_STATE_DIR") or os.path.expanduser("~/.local/state/inbox-monitor")
GWS = os.environ.get("INBOX_GWS", "/opt/homebrew/bin/gws")


def gws(resource, method, params):
    out = subprocess.run([GWS, "gmail", "users", resource, method, "--params", json.dumps(params)],
                         capture_output=True, text=True, check=True, timeout=60).stdout
    return json.loads(out[out.index("{"):])


def headers(m):
    return {x["name"]: x["value"] for x in m["payload"].get("headers", [])}


def my_address():
    out = subprocess.run([GWS, "gmail", "users", "getProfile", "--params", '{"userId":"me"}'],
                         capture_output=True, text=True, check=True, timeout=60).stdout
    return json.loads(out[out.index("{"):])["emailAddress"].lower()


def addresses(value):
    return [a.lower() for _, a in getaddresses([value or ""]) if a]


def recipients(h, me):
    """Computed before anything is masked, so To-vs-CC triage still works on masked output."""
    to, cc, frm = addresses(h.get("To")), addresses(h.get("Cc")), addresses(h.get("From"))
    return {"me_in": "to" if me in to else "cc" if me in cc else "none",
            "from_me": me in frm,
            "from_domain": frm[0].split("@")[-1] if frm else None}


def body_text(m):
    def parts(p):
        yield p
        for c in p.get("parts", []):
            yield from parts(c)

    def dec(p):
        d = p.get("body", {}).get("data")
        return base64.urlsafe_b64decode(d + "=" * (-len(d) % 4)).decode("utf-8", "replace") if d else ""

    ps = list(parts(m["payload"]))
    text = "\n".join(dec(p) for p in ps if p.get("mimeType") == "text/plain")
    if not text.strip():
        raw = "\n".join(dec(p) for p in ps if p.get("mimeType") == "text/html")
        text = html.unescape(re.sub(r"<[^>]+>", " ", re.sub(r"(?is)<(style|script).*?</\1>", "", raw)))
        text = re.sub(r"[ \t]+", " ", re.sub(r"\n\s*\n+", "\n\n", text))
    return text.strip()


def summary(m, limit, me):
    h = headers(m)
    return {"id": m["id"], "threadId": m["threadId"], "from": h.get("From"), "to": h.get("To"),
            "cc": h.get("Cc"), **recipients(h, me), "subject": h.get("Subject"), "date": h.get("Date"),
            "body": body_text(m)[:limit]}


def show(v):
    print(json.dumps(v, ensure_ascii=False, indent=1))


if len(sys.argv) == 3 and sys.argv[1] == "--body":
    show(summary(gws("messages", "get", {"userId": "me", "id": sys.argv[2], "format": "full"}), 6000, my_address()))
    sys.exit(0)

if len(sys.argv) == 3 and sys.argv[1] == "--thread":
    t = gws("threads", "get", {"userId": "me", "id": sys.argv[2], "format": "full"})
    me = my_address()
    show([summary(m, 1500, me) for m in t.get("messages", [])])
    sys.exit(0)

since = int(sys.argv[1])
until = int(sys.argv[2]) if len(sys.argv) > 2 else None
state = json.load(open(os.path.join(STATE_DIR, "state.json")))
me = my_address()
seen = set(state.get("gmail_ids", []))

q = f"in:inbox after:{since}{f' before:{until}' if until else ''} -category:promotions -category:social -category:forums -category:updates -from:me"
ids, token = [], None
while True:
    p = {"userId": "me", "q": q, "maxResults": 100}
    if token:
        p["pageToken"] = token
    r = gws("messages", "list", p)
    ids += [m["id"] for m in r.get("messages", [])]
    token = r.get("nextPageToken")
    if not token:
        break

res = []
for i in ids:
    if i in seen:
        continue
    m = gws("messages", "get", {"userId": "me", "id": i, "format": "metadata",
                                "metadataHeaders": ["From", "To", "Cc", "Subject", "Date", "List-Unsubscribe", "Content-Type"]})
    h = headers(m)
    subj = h.get("Subject", "")
    is_invite = "text/calendar" in json.dumps(m["payload"]) or subj.split(":")[0].strip() in (
        "Invitation", "Updated invitation", "Accepted", "Declined", "Tentatively Accepted", "Canceled event",
        "Invitation from Google Calendar")
    res.append({"id": i, "threadId": m["threadId"], "from": h.get("From"), "to": h.get("To"), "cc": h.get("Cc"),
                **recipients(h, me), "subject": subj, "date": h.get("Date"), "snippet": m.get("snippet"),
                "labels": m.get("labelIds", []), "bulk": "List-Unsubscribe" in h, "calendar_invite": is_invite})
if os.environ.get("INBOX_DRY_RUN") != "1":  # ./im finish checks that every one of these was marked seen
    tmp = os.path.join(STATE_DIR, ".pending_gmail.json.tmp")
    with open(tmp, "w") as f:
        json.dump([m["id"] for m in res], f)
    os.replace(tmp, os.path.join(STATE_DIR, ".pending_gmail.json"))
show(res)
