#!/usr/bin/python3 -I
"""Test harness for july_task.py: loads the module, swaps its globals (paths, hc, the Slack transport) from
the JT_* environment of THIS runner, then calls its main(). The installed script reads none of this.

JT_CONFIG, JT_STATE_DIR, JT_HC, JT_PROJECTS (Claude transcripts), JT_INPUT_DIR, JT_START_WAIT, JT_MAX_PAGES, JT_DIALOG_WAIT;
JT_SLACK_LOG (every Slack call is appended as JSON), JT_SLACK_REPLIES (conversations.replies answers: one
response, or a list of pages chained by cursor), JT_SLACK_FAIL (comma-separated methods that fail) and
JT_SLACK_FAIL_ERROR (the Slack error they fail with).
"""
import importlib.util, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("july_task", os.path.join(os.path.dirname(HERE), "july_task.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
env = os.environ
m.STATE_DIR = env["JT_STATE_DIR"]
m.HC = env["JT_HC"]
m.CLAUDE_PROJECTS = env["JT_PROJECTS"]
m.INPUT_DIR = env["JT_INPUT_DIR"]
m.START_WAIT = int(env.get("JT_START_WAIT", "5"))
m.DIALOG_WAIT = int(env.get("JT_DIALOG_WAIT", "3"))
m.CLAUDE_JSON = env.get("JT_CLAUDE_JSON", m.CLAUDE_JSON)
m.START_BUDGET = int(env.get("JT_START_BUDGET", m.START_BUDGET))
m.MAX_PAGES = int(env.get("JT_MAX_PAGES", m.MAX_PAGES))
m.RELAY_IDLE = int(env.get("JT_RELAY_IDLE", m.RELAY_IDLE))
FAIL = set(filter(None, env.get("JT_SLACK_FAIL", "").split(",")))


def transport(method, params):
    with open(env["JT_SLACK_LOG"], "a") as f:
        f.write(json.dumps({"method": method, **params}, ensure_ascii=False) + "\n")
    if method in FAIL:
        raise m.Fail(f"Slack {method}: {env.get('JT_SLACK_FAIL_ERROR', 'test failure')}")
    if method == "conversations.replies":
        if not env.get("JT_SLACK_REPLIES"):
            return {"ok": True, "messages": []}
        with open(env["JT_SLACK_REPLIES"]) as f:
            data = json.load(f)
        if isinstance(data, list):  # pages: cursor "p<n>" selects page n
            n = int((params.get("cursor") or "p0")[1:])
            page = dict(data[n])
            if n + 1 < len(data):
                page["response_metadata"] = {"next_cursor": f"p{n + 1}"}
            return page
        return data
    return {"ok": True, "ts": f"{m.now():.6f}", "permalink": "https://slack.invalid/test"}


m.TRANSPORT = transport
m.main(sys.argv[1:], config=env["JT_CONFIG"])
