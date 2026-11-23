#!/usr/bin/python3 -I
"""A fake `hc` for test_july_task.py: terminals live in the JSON file $FAKE_HC_STATE.

Supports what july_task.py uses: run, get, ls, kill, rm, send, wait, read, keys. Exit 3 + not_found like
the real hc. FAKE_HC_DOWN=1 makes every command fail as if the core were unavailable; FAKE_HC_RM_FAIL=1 makes rm fail. On `run` with
--session-id it writes a transcript under $FAKE_HC_TRANSCRIPTS (unless FAKE_HC_NO_TRANSCRIPT=1); on `wait`
it copies $FAKE_HC_SNAPSHOT_FROM to $FAKE_HC_SNAPSHOT_TO (to see the task state during a start).
FAKE_HC_RUN_STATUS sets a new claude terminal's status (e.g. blocked), FAKE_HC_SCREENS (a JSON list) gives
successive `read` screens, FAKE_HC_KEYS_UNBLOCK=1 makes `enter` (after a `down`) clear a blocked status, and FAKE_HC_STUCK_KEYS=1
makes `down` move nothing. `connect` serves doc.get/doc.set from state["docs"] (version-checked);
state["doc_conflicts"] = n makes the next n doc.set calls lose a race to "the app" (which appends tab
tbAPPWROTE to the first space).
"""
import json, os, re, shutil, sys, time

PATH = os.environ["FAKE_HC_STATE"]


def rj(path):
    with open(path) as f:
        return json.load(f)


def wj(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, indent=1)


def load():
    return rj(PATH) if os.path.exists(PATH) else {"next": 1, "terminals": []}


def save(s):
    wj(PATH, s)


def out(v, code=0):
    print(json.dumps(v))
    sys.exit(code)


def find(s, ref):
    hits = [t for t in s["terminals"] if t["address"] == ref] or \
        [t for t in s["terminals"] if t.get("name") == ref and t["state"] == "live"]
    if not hits:
        out({"error": {"kind": "not_found", "message": f"no terminal {ref!r}"}}, 3)
    return hits[0]


def main():
    args = [a for a in sys.argv[1:] if a != "--json"]
    cmd, rest = args[0], args[1:]
    if os.environ.get("FAKE_HC_DOWN") == "1":
        out({"error": {"kind": "unavailable", "message": "core restarting"}}, 1)
    s = load()
    if cmd == "connect":  # JSON-RPC lines: hello, doc.get, doc.set (version-checked)
        docs = s.setdefault("docs", {})
        for line in sys.stdin:
            req = json.loads(line)
            m, prm, rid = req["method"], req.get("params") or {}, req.get("id")
            if m == "hello":
                res = {"generation": 1}
            elif m == "doc.get":
                d = docs.get(prm["name"], {"value": None, "version": 0})
                res = {"value": d["value"], "version": d["version"]}
            elif m == "doc.set":
                d = docs.setdefault(prm["name"], {"value": None, "version": 0})
                if s.get("doc_conflicts", 0) > 0:  # the app writes in between
                    s["doc_conflicts"] -= 1
                    if isinstance(d["value"], dict) and d["value"].get("spaces"):
                        d["value"]["spaces"][0]["tabs"].append({"id": "tbAPPWROTE", "name": "", "root": {
                            "type": "row", "id": "tbAPPWROTE", "children": []}})
                    d["version"] += 1
                if prm["version"] != d["version"]:
                    print(json.dumps({"jsonrpc": "2.0", "id": rid, "error": {
                        "code": -32000, "message": "conflict", "data": {"kind": "conflict"}}}))
                    continue
                d["value"], d["version"] = prm["value"], d["version"] + 1
                s.setdefault("doc_writes", 0)
                s["doc_writes"] += 1
                res = {"version": d["version"]}
            else:
                res = {}
            print(json.dumps({"jsonrpc": "2.0", "id": rid, "result": res}))
        save(s)
        sys.exit(0)
    if cmd == "run":
        opts, i = {"labels": {}}, 0
        while i < len(rest) and rest[i] != "--":
            a = rest[i]
            if a in ("--name", "--cwd", "--parent", "--timeout", "--on"):
                opts[a[2:]] = rest[i + 1]
                i += 2
            elif a == "--label":
                k, v = rest[i + 1].split("=", 1)
                opts["labels"][k] = v
                i += 2
            else:
                i += 1
        argv = rest[i + 1:]
        t = {"address": f"t{s['next']}", "name": opts.get("name"), "state": "live", "parent": None,
             "labels": opts["labels"], "argv": argv, "cwd": opts.get("cwd"),
             "status": {"app": "claude-code", "state": os.environ.get("FAKE_HC_RUN_STATUS", "idle")}
             if argv and argv[0].endswith("claude") else None,
             "status_ms": int(time.time() * 1000), "created_ms": int(time.time() * 1000), "exit_code": None,
             "screen": "", "inbox": [], "keys": []}
        s["next"] += 1
        s["terminals"].append(t)
        save(s)
        if os.environ.get("FAKE_HC_STOP_ON_RUN"):  # a `july-task stop` landing while hc run starts it
            st = rj(os.environ["FAKE_HC_STOP_ON_RUN"])
            for task in st["tasks"].values():
                task["state"] = "stopped"
            wj(os.environ["FAKE_HC_STOP_ON_RUN"], st)
        if "--session-id" in argv and os.environ.get("FAKE_HC_TRANSCRIPTS") and \
                os.environ.get("FAKE_HC_NO_TRANSCRIPT") != "1":
            sid = argv[argv.index("--session-id") + 1]
            d = os.path.join(os.environ["FAKE_HC_TRANSCRIPTS"], "proj")
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, sid + ".jsonl"), "w") as f:
                f.write(json.dumps({"type": "user", "message": {"content": argv[-1]},
                                    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())}) + "\n")
        out({"address": t["address"], "name": t["name"], "state": "live"})
    if cmd == "get":
        out(find(s, rest[0]))
    if cmd == "ls":
        want = [r.split("=", 1) for j, r in enumerate(rest) if j and rest[j - 1] == "--label"]
        ts = [t for t in s["terminals"] if ("--all" in rest or t["state"] == "live")
              and all(t["labels"].get(k) == v for k, v in want)]
        out({"terminals": [{"address": t["address"]} for t in ts]})
    t = find(s, rest[0])
    if cmd == "kill":
        t.update(state="finished", exit_code=129)
    elif cmd == "rm":
        if os.environ.get("FAKE_HC_RM_FAIL") == "1":
            out({"error": {"kind": "busy", "message": "can't remove now"}}, 1)
        if t["state"] == "live":
            out({"error": {"kind": "live", "message": "still running"}}, 11)
        s["terminals"].remove(t)
    elif cmd == "send":
        t["inbox"].append(rest[-1])
    elif cmd == "label":
        for kv in rest[1:]:
            k, v = kv.split("=", 1)
            if v:
                t["labels"][k] = v
            else:
                t["labels"].pop(k, None)
    elif cmd == "keys":
        t["keys"].append(rest[1:])
        if "down" in rest[1:] and os.environ.get("FAKE_HC_STUCK_KEYS") != "1":
            t["moved"] = True  # the cursor moves to the next choice (applied to every later screen)
        if "enter" in rest[1:] and os.environ.get("FAKE_HC_KEYS_UNBLOCK") == "1" and t["status"] and t.get("moved"):
            t["status"]["state"] = "idle"
    elif cmd == "read":
        screens = os.environ.get("FAKE_HC_SCREENS")  # a JSON list: one screen per read, the last one stays
        if screens:
            seq = rj(screens)
            n = t.setdefault("reads", 0)
            t["screen"] = seq[min(n, len(seq) - 1)]
            t["reads"] = n + 1
        if t.get("moved"):
            t["screen"] = re.sub(r"❯( *(?:1\. )?No, exit)", r" \1", t["screen"])
            t["screen"] = re.sub(r" ( *)((?:2\. )?Yes, I trust this folder)", r"❯\1\2", t["screen"], count=1)
        save(s)
        print(t["screen"])
        sys.exit(0)
    elif cmd == "wait":
        if os.environ.get("FAKE_HC_SNAPSHOT_FROM"):
            shutil.copy(os.environ["FAKE_HC_SNAPSHOT_FROM"], os.environ["FAKE_HC_SNAPSHOT_TO"])
        out({"reason": "timeout", "status": (t["status"] or {}).get("state")})
    save(s)
    out({"ok": True, "address": t["address"]})


main()
