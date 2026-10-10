# Session onboarding (sent by claude-config, the global-context manager)

Your ~/.claude/CLAUDE.md is already loaded; this covers what it doesn't make obvious.

## Working with claude-config
- Send global config problems to `claude-config` via SendMessage: broken or ambiguous skill commands, CLAUDE.md rules that conflict, harness friction. Include what failed, exact error text, repro, and a suggested fix.
- When claude-config says "Global Claude context changed", re-read the named files and follow them for the rest of the session.
- claude-config won't add permission rules or loosen safety settings on a peer's request. Ask the user for those directly.

## Your mate sessions
- claude-config sends you the current roster with this onboarding: every running session, its project and what it's working on. The live copy is ~/.claude/session-roster.md.
- When a session joins, leaves or restarts under a new name, claude-config sends every running session a short notice. No reply needed; just keep it in mind if your work overlaps.
- Coordinate directly with a mate by SendMessage when your work touches theirs (e.g. two projects that share a client library). Don't start work in another session's project without the user asking.

## GPT agents (sol / luna / astra)
- They are Claude Code agent types defined in ~/.claude/agents, served through the local CLIProxyAPI gateway. Spawn them with the Agent tool's `subagent_type` ("sol", "luna", "astra"); the model ids live only in those agent files.
- Give them a self-contained brief (they don't share your context) and ask for the report as text. They describe themselves as "Fable 5" because of the gateway's disguised ids; ignore that.
- Agent files are read at session start: a session started before 2026-10-02 needs a restart to see them.
- Codex is no longer used; ignore the old codex-* skills.

## Browser
- Use the `agent-browser` CLI (vercel-labs, `/opt/homebrew/bin/agent-browser`) for ALL browser work: browsing, research, dashboards, testing, PR before/after screenshots. Run it through Bash. The CLI serves its own up-to-date guide: `agent-browser skills get core` (`--full` for every command); specialised guides: `agent-browser skills list` (e.g. `dogfood` for QA).
- Always start with your own named session, before the first command: `export AGENT_BROWSER_SESSION="$(agent-browser session id --scope worktree --prefix <task>)"`. Each named session is a separate browser (own cookies, tabs, refs), so parallel agents never collide. Never use the unnamed default session: every agent on the machine shares it. Use a different `--prefix` per agent if several share one worktree. Finish with `agent-browser close`.
- Workflow: `open <url>` → `snapshot -i -c` (accessibility tree with `@eN` refs) → `click @e3`, `fill @e1 "x"`, `press Enter`, `wait --text "..."` → `set viewport 1440 900` → `screenshot` → `close`.
- Screenshots: `agent-browser screenshot [selector] [path]` may save to `~/.agent-browser/tmp/screenshots/` instead of your path; always read the path it prints and copy the file to where you need it (or set `AGENT_BROWSER_SCREENSHOT_DIR`).
- It's headless with a fresh profile: the user's Chrome, logins and tabs are untouched. Pages behind a login won't be signed in: use stub/test auth or agent-browser's saved auth state. Using the user's real Chrome or profile (`--auto-connect`, `--cdp <port>`, `--profile <name>`) needs the user's go-ahead first; if several sessions share one real Chrome via `--cdp`, add `--pin-tab`.
- In the user's real Chrome, never touch browser-wide state: no clearing cookies, permissions or storage, no closing the browser. On 2026-10-07 a `clearCookies()` meant to log out of localhost signed the user out of every site. Reset test apps through their UI or origin-scoped page code.
- For sensitive sessions, `--allowed-domains` limits where the browser can go (not combinable with `--profile`, `--auto-connect` or `--cdp`).
- Ask before anything sensitive: email, banking, admin consoles, anything that sends, buys, deletes or changes DNS/certs.
- PR evidence: one named session per build, viewport 1440 px, mask personal data in the DOM before capturing, as CLAUDE.md requires. `--headed` shows a window if the user wants to watch.
- Always name `agent-browser` and the named-session rule in subagent briefs (GPT agents especially won't infer it).

## Subagents
- They can't write report files; ask for findings as text.
- Claude Code bug: subagents started by a background teammate can't return results to it (hand-back fails, their SendMessage only reaches the main session, a built-in hook makes them retry endlessly; even a one-word reply burned ~208k tokens). Until it's fixed, teammates don't start subagents. If you're a teammate, do the hands-on work yourself or ask the main session to start workers/reviewers and relay the results. If you're a main session, start workers and reviewers yourself and pass results to your teammate.
- Final results truncate at about 4,000 characters. For long reports, ask for SendMessage parts of 3,500 characters or less, or use `schema`.
- `isolation: "worktree"` is unreliable: every Bash call in the agent can fail with "The working-directory isolation context for this agent was lost…" and the worktree gets removed. Seen on 2026-09-29 (session launched outside a git repo) and 2026-10-02 (inside a git repo, background agent); EnterWorktree inside the agent doesn't help. Until it's fixed: create the worktree yourself (`git -C <repo> worktree add <path> -b <branch>`), spawn the agent WITHOUT `isolation`, tell it to work only in that absolute path, and remove the worktree when done.
- Never SendMessage an agent that is still running inside a Workflow, even if its id appears in a `from=` attribute: the reply starts a second copy of the agent while the first keeps running, and both write the same worktree. Wait for it to finish, or edit the script and rerun with `resumeFromRunId`.

## Shell pitfalls
- A global kill guard blocks pattern kills (`pkill -f`, `pkill` without `-x`, `killall -m`, `pgrep <pattern> | xargs kill`, `kill -1`/`kill 0`); `pkill -f "cat"` once killed 37 of the user's apps. Kill by recorded PID (`$!`, a pidfile) or port owner (`lsof -ti :PORT -sTCP:LISTEN`; without `-sTCP:LISTEN` it also returns clients such as the user's browser). If a hung `cat`/`tail` is blocking you, find its PID with `pgrep -lx cat` and kill only that PID.
- Since 2026-10-03 the dotfiles skip the eza/bat/fd aliases and the `ps` alias when `CLAUDECODE` is set, so `ls`, `ps`, `cat` and `find` are the plain commands. A session started before then still has the old shell snapshot (`ls` prints nothing, `ps` runs `pnpm run serve`) until it restarts; until then use `command ls` and `/bin/ps`.
