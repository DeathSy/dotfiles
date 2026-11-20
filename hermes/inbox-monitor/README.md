# Inbox monitor (Hermes cron job)

Every 5 minutes Hermes runs the `inbox-monitor` skill (private overlay) with one toolset, the local
`inbox` MCP server in this directory. It triages new Slack mentions, DMs and alert-channel messages and
new inbox emails for the owner into Apple Reminders. Installed read-only into the Nix store by
`nixpkgs/home-manager/ai/hermes.nix`; see `docs/ai-setup.md` → "Hermes Agent".

| File | What it does |
|---|---|
| `inbox_mcp.py` | stdio MCP server (stdlib only, `/usr/bin/python3`). Structured tools, ids by reference, masking. Calls Slack's Web API with the owner's user token from the Keychain item `inbox-monitor/slack-user-token`. |
| `im` | State bookkeeping (`state.json`) and the Reminders wrapper: window chunks, processed keys, run lease, create/complete/update with dedupe, the clipboard-reaction check. |
| `reminders.js` | JXA for Reminders.app (create, complete, update, open lists). |
| `fetch_gmail.py` | Gmail through `gws`: unseen inbox mail of the window, one body, one thread; adds `me_in`, `from_me`, `from_domain` before anything is masked. |

## State directory

`$INBOX_STATE_DIR`, default `~/.local/state/inbox-monitor` (mode 700), outside every repo:

- `state.json`: `last_check_epoch` (the next window starts here), processed Slack keys and Gmail ids
  (last 2000 each), the reminders this monitor created (`reminders`: key -> Reminders id, list, quadrant),
  `last_ok_at`, the run lease and the last 50 one-line summaries. No message content.
- `config.json` (0600, written by hand):

```json
{
  "slack_base": "https://<workspace>.slack.com/archives",
  "lists": ["<work list>", "<personal list>", "<side-project list>"],
  "owner_slack_id": "U…",
  "queries": {"mentions": "<@U…>", "dms": "to:me", "alert_x": "in:#alert_x"},
  "exclude_channels": ["D… (the Hermes bot's DM with the owner)"],
  "gh_owners": ["<GitHub owners whose PRs may be checked>"]
}
```

## Testing without writes

`INBOX_DRY_RUN=1` turns every write in `im` (state, Reminders, reactions) into a no-op that prints what it
would do; `INBOX_WINDOW_START=<epoch>` overrides the window start. Both reach the server through the
`mcp_servers.inbox.env` block.
