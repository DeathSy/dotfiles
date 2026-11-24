# Personal Preferences

## Typescript

- Never use `any` unless 100% necessary or specifically instructed

## Commands

- Don't run dev server commands (eg. `npm run dev`, `yarn dev`, `pnpm dev`) assume it's already running
- Don't run build commands unless specifically told to do
- Focus on checking commands like `yarn typecheck`, `yarn lint` or `pnpm` based one
- Exception: starting a dev server, local stack or build is allowed only to capture PR before/after evidence (see below); stop it afterwards
- Never kill processes by pattern (`pkill -f`, `pkill` without `-x`, `killall -m`, `pgrep <pattern> | xargs kill`, `kill -1`/`kill 0`): on 2026-09-29 `pkill -f "cat"` killed 37 of the user's apps. Kill by recorded PID (`$!`, a pidfile) or port owner (`lsof -ti :PORT -sTCP:LISTEN`; without `-sTCP:LISTEN` it also returns clients such as the user's browser). A global hook enforces this
- When the user asks to install software on a Mac (Homebrew formula or cask, global CLI tool, app, launch agent), declare it in ~/studio/personal/dotfiles instead of only installing it by hand. The repo's CLAUDE.md says which file each kind goes in; a home-manager module meant for one Mac is imported from that host's `nixpkgs/hosts/<host>.nix` (`home-manager.users.ksotis.imports`), not the shared list in flake.nix. Not project dependencies (package.json, pyproject), one-off runs (npx, uvx) or tools inside containers; if it's already declared, say so. Work in a worktree under ~/studio/personal/dotfiles-wt/ (the main checkout is live config) with the usual reviews, then merge it into the main checkout so the user's rebuild picks it up. The user runs the rebuild (it needs sudo); push or open a PR only with their go. Install it by hand as well only if the user wants it right away

## Containers

- All containers, compose stacks and image builds run on garage-server's Podman VM: from garage-hq through connection `arm64` (over Thunderbolt, the default); on garage-server itself through its local `podman-machine-default`. If that connection is missing, report it instead of creating one or using another machine. Don't create or start a Podman VM on any other Mac, and don't change the default connection
- arm64 only: build and run arm64 images, and pass `--platform linux/arm64` to `podman pull`/`run`, and set `platform: linux/arm64` on every compose service, including those with `build` (the VM has Rosetta, so an amd64-only image would otherwise run silently). Never run or start an amd64 container, and don't pull amd64 images except as base images for the PCS cross-build below. If a task needs an amd64 image, report it; never add qemu, binfmt or other emulation. Exception, PCS only (repos under ~/workspace/pcs): images may be cross-built for linux/amd64 when the amd64 stage runs no RUN steps (COPY only, build stage on `$BUILDPLATFORM`, as in portal-web PR #119)
- Bind mounts resolve on garage-server, and only under its `/Users`, `/private` and `/var/folders` (the VM's `/tmp` is its own; use `/private/tmp`). Sync files to a scratch dir of your own there and mount absolute paths; never sync onto an existing path you don't own (e.g. ~/workspace/rpa is live). `podman build` uploads its context, so builds need no sync
- Ports: publish as `127.0.0.1:<port>:<port>` after checking the port is free (rpa uses 8080). On garage-server, check with local `lsof -nP -iTCP:<port> -sTCP:LISTEN` and use the port directly. From garage-hq, check both ends, then forward with `ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:<local-port>:127.0.0.1:<port> garage-server`. Exposing a port to the network needs the user's explicit go
- The VM is shared by every session and runs the rpa Steel stack (`rpa-*` containers: never touch them). Use your own compose project (`-p <task>`) and bring down only that; after a push, confirm the registry lists your digest; `rmi` only the tags you created (no `prune`). Changes to the VM itself (machine settings, restarts, Podman upgrades) need the user's go first and an announcement to claude-config. Pitfalls: ~/.claude/onboarding.md ("The shared container host")

## Package Manager

- Use yarn or npm if the project already use it, otherwise pnpm

## Tech Stack Preferences

- When uncertain, prefer: Tailwind, react, Typescript, Clerk, Vercel with Vite runtime

## Code Style

- Always strive for concise, simple solution
- If a problem can be solved in a simpler way, proposed it

## Opening PRs: before/after evidence

Every PR body gets a "Before / After" section, above the attribution lines, that says how the evidence was produced. Produce it by running the real code on the base branch vs the PR branch; never hand-write or invent it.

- UI change: screenshots. "Before" from a fresh worktree at the base branch (origin/main), "after" from the PR branch; same route, same data, 1440 px wide (taller viewport if the page scrolls inside a container), PNG ≤300 KB. One row per screen in a `Before | After` table, for every language whose copy changed. Capture with `agent-browser` in your own named session (see Browser below), one session per build. Feed both builds the same realistic data (real backend/normaliser output or the local stack), never invented mocks that could hide a bug. No source changes for capture. A new screen with no "before" gets its "after" plus a "before" of the page it was added to.
- Backend / no-UI change: before vs after request/response JSON, SQL, CLI output or log lines from running the real code on both branches.
- Docs change: the rendered before vs after of each changed section (screenshot of the rendered page, or quoted before/after text when it renders as plain Markdown). When the docs describe behavior, add a line confirming the code matches.
- Config change (CI, build, lint, env, dependencies, tooling): the observable effect before vs after: the resolved config, the command or CI output, or the behavior it changes (a lint rule firing, a job's new step, a dependency's resolved version).
- Hosting: `gh` can't upload attachments. Push images to an orphan branch `pr-assets` in the same repo under `<pr-number>/` (separate git worktree; `git checkout --orphan pr-assets` the first time, append afterwards; never merge it). Private repos return 404 on raw.githubusercontent.com, so link `https://github.com/<org>/<repo>/blob/<pinned commit sha>/<pr-number>/<file>.png?raw=true`, which keeps working after later pushes.
- Privacy: mask identity numbers, phone numbers and emails in the DOM before capture and in snippets (keep the last 4 characters); grep the PR body for 13-digit runs before posting.
- Say explicitly what was NOT verified (e.g. "mock mode only, not against the live API").

# General Preferences

## Roles

- Main session: the session the user works with in a project, opus at default effort. It talks with the user, splits requests into tasks on the board, writes briefs and starts workers. It commits each worker's changes on the task branch before review, runs checks, then opens the PR with before/after evidence (or merges locally where the project has no PR flow); pushing or merging shared branches follows the project's rules or the user's go. It does user-facing work (UI, copy, API design: taste >= 7) and high-stakes work itself. Switch to fable only for demanding long-horizon work (deep research, a large design) or when opus visibly falls short; adjust effort first. Any session can consult fable on hard architecture, planning and judgment calls.
- Workers: agy (Antigravity CLI, Gemini) and Codex (GPT) in herdr terminals (`hc`), one tier, mostly free. They do the standard jobs below.
- Reviewer: one long-lived Claude session per main session, `<session>-review`, runs both review stages (see Reviews). Nobody reviews their own work.
- Claude subagents: haiku (`subagent_type: "haiku"`) for exploration (searching and reading code or docs, reporting back) and support work (triage, routing, lookups, short factual answers; also as the main model of a support session such as July); opus when the question needs judgment or before a root-cause analysis goes out. Never Haiku 4.5 or older, and never haiku for reviews, user-facing or hard coding work. Other Claude models run via the agent/workflow `model` parameter.
- Opus teammate: only for a long multi-step task the main session hands off whole (own worktree and branch, checks, PR, CI). It drives its own workers, hands its tasks to the main session's reviewer via the main session, and reports to `main`.

## Models

Rankings, higher = better. Cost reflects what i actually pay (OpenAI and Google are near-free for me), not list price. Intelligence is how hard a problem you can hand the model unsupervised. Taste covers UI/UX, code quality, API design, Security, and copy.

| model                       | runs in     | cost | Intelligence | taste |
| --------------------------- | ----------- | ---- | ------------ | ----- |
| haiku                       | Claude Code | 8    | 7            | 5     |
| sonnet                      | Claude Code | 6    | 6            | 7     |
| opus                        | Claude Code | 5    | 8            | 8     |
| fable                       | Claude Code | 2    | 9            | 9     |
| Neon (`gemini-4-neon-high`) | agy         | 9    | 9            | 6     |
| Sol (`gpt-6.2-sol`)         | Codex       | 9    | 8            | 5     |
| Astra (`gpt-6.2-astra`)     | Codex       | 8    | 9            | 6     |
| DeepSeek V4.1 Flash (`openrouter/deepseek/deepseek-v4.1-flash`) | pi | 8 | 6 | 4 |

DeepSeek is paid per token through OpenRouter (about $0.3–0.6 per task), unlike the near-free Codex and agy (Artificial Analysis, Nov 2026: Intelligence 33, Coding Agent 37).

Who gets what:

- Standard coding (implement to spec, bug fixes, refactors), docs, slides and presentations: agy Neon high (`gemini-4-neon-xhigh` only for hard edits; ~21 min each). If agy hits its quota, rerun the brief in Codex Sol.
- Bulk/mechanical work (renames, fixtures, migrations, test fixes): Codex Sol at medium/high effort. DeepSeek in pi takes simple bulk work too and is the backup when Codex and agy are out of quota. Never DeepSeek for reviews, user-facing or high-stakes work.
- Hard analysis, investigations and second opinions without edits: Codex Astra xhigh.
- User-facing and high-stakes work: the main session (opus), or fable when needed.
- Don't use Luna.
- Always use the newest model of each tier: check `agy models`, `codex debug models` and `pi --list-models deepseek` and update the ids here. The Claude names are aliases that resolve to the latest. Neon, Sol, Astra, DeepSeek and haiku scores are estimates (Neon leads Artificial Analysis' Coding Agent Index, Astra its Intelligence Index, Nov 2026); adjust them after use.
- These are defaults, not limits: if output doesn't meet the bar, redo it with a stronger model without asking. Cost is a tie-breaker only; for anything that ships, intelligence > taste > cost.

## Task board

Only requests that change files go on the board. The main session splits them into tasks in `.claude/tasks-<session>.md` in the main checkout, kept out of git (add `.claude/tasks-*.md` to `$(git rev-parse --git-common-dir)/info/exclude`); several sessions can share a project. Only the main session writes it. Each entry has an id, title, worker (agy Neon, Codex Sol, Codex Astra or opus itself), worktree and branch, state (queued → working → ready for review → changes requested → done) and review result:

```
## T3 Fix login redirect
- worker: agy Neon
- worktree: ~/app-wt/t3, branch fix/login-redirect
- state: changes requested
- review: opus (stage 1): src/auth.ts:42 drops the query string; opus (stage 2): ok
```

## Reviews

- Every task gets two read-only reviews; every finding cites file:line. Trivial changes (a few lines, not high-stakes) the main session may make itself (stage 1 only). Plans are reviewed only for multi-step or non-obvious work, handed over as a file path. A re-review after fixes is stage 1 checking them.
  1. The reviewer session (opus). High-stakes: it starts a `model: "fable"` subagent. If fable wrote it, opus reviews.
  2. Never the author's family, given stage 1's findings: agy Neon high; if agy wrote it, a second, independent opus subagent. High-stakes: Codex Astra xhigh, or Neon xhigh if Codex wrote it. If Astra refuses (OpenAI's cyber filter), an independent fable subagent reviews instead (an exception to the different-family rule; if fable wrote it, Neon xhigh).
- The reviewer runs stage 2 itself (the worker in its own terminal, or the subagent), verifies its findings against the code, and reports both stages via SendMessage to the requesting session by its session name (not `main`, which only reaches Agent-tool teammates); the main session records them on the board and has the author fix them.
- Reviewer session: if it isn't running, the main session clears any leftover `--keep` terminal (see onboarding) and runs `hc-worker --name <session>-review --outlive-parent --keep --cwd <repo> -- claude --model opus -n <session>-review`, waits until it's idle, gives it a first turn (see onboarding), then confirms via ListAgents it's reachable under that name (else uses the name shown). It hands each task over via SendMessage when it reaches "ready for review": task id, worktree, author (worker and model), review mode (normal, high-stakes, or stage 1 only for trivial changes and re-reviews), brief or plan path, and the base branch if it isn't the default.
- Outside herdr, or if the reviewer session dies mid-review and can't be restarted: stage 1 is an opus reviewer subagent (fable for high-stakes; opus if fable wrote it), stage 2 a second, independent opus subagent.
- High-stakes = a bug would cause harm that's hard to undo and reaches beyond the user's machine. Only these get the fable and Astra reviews:
  - Security: changes to auth or permission checks, secret handling, or parsing untrusted input in an internet-facing service. Not UI behind a login, internal tools or tests.
  - Personal data: new collection, storage, logging or sharing of identity numbers, phones, emails or KYC data. Not displaying data that is already handled.
  - Money: code that calculates or moves amounts (payments, pricing, billing).
  - Irreversible data: migrations, deletions or schema changes on shared or production data. Not local dev databases or fixtures.
  - Production: deploys, infrastructure, DNS or cluster changes applied to production.
  - Hard-to-reverse design: public API contracts, concurrency, large architecture changes.
  - Not high-stakes: local tools, personal config such as `~/.claude` hooks, docs, tests, UI and copy, refactors covered by tests, prototypes, staging or dev-only changes.
  - If unsure, ask: "If this has a bug, can we revert it in minutes with nobody harmed?" If yes, it's an opus review and a Neon final review.

## Workers

- Only inside herdr (`test -n "${HC_TERMINAL_ID:-}"`); outside it, tell the user once and use Claude subagents (opus for standard coding and hard analysis, haiku or sonnet only for bulk work). How-to, flags and brief rules: ~/.claude/onboarding.md and `hc --skill`.
- One worker per worktree, created manually (`git -C <repo> worktree add <path> -b <branch>`, then `ai-trust-worktree`); workers edit only there. Remove the worktree when done. For Claude subagents, don't use `isolation: 'worktree'` (it loses context and every Bash call fails); spawn them without it and name the absolute path.

## Browser

- Use agent-browser for all browser work (via Bash; usage: `agent-browser skills get core`). It runs its own headless Chromium, not the user's Chrome. Use your own named session, never the shared default: get its id once with `agent-browser session id --scope worktree --prefix <task>`, then pass `--session <id>` on every agent-browser command (env vars don't persist between Bash calls). Run `agent-browser close` when done (never `close --all`; when attached to the user's real Chrome, close only your own tabs, never the browser). Name the browser rules in every subagent and worker brief. Use the user's real Chrome or profile (`--auto-connect`, `--cdp`, `--profile`) only with the user's go-ahead, and then never touch browser-wide state (cookies, permissions, storage): on 2026-10-07 a `clearCookies()` call signed the user out of every site. Never ask for passwords, OTP codes or other secrets in chat, nor type real credentials. For a page behind a login, use stub/test auth or a saved auth state the user named; otherwise ask the user (saved auth state, a Steel session (below), or their real Chrome with their go-ahead).
  - Steel (logged-in browser, garage-hq only; on other hosts, report it): only when a site needs a login the user saved in the rpa app, the user must step in (OTP, CAPTCHA, 2FA), or the account needs its saved proxy/user agent. Use only the account the user or brief names (never pick, create, connect, teach or delete accounts). Check `GET http://localhost:18080/api/browser` (if `busy` fills `total`, wait or ask), then `POST http://localhost:18080/api/accounts/<accountId>/agent-session`. Pass `--session <id> --cdp "<cdpUrl>"` on every agent-browser command except `close` (which only disconnects); never CDP `Browser.close`. On a 409, read the message and never end a session you didn't create. To let the user step in, send them `liveViewUrl` with `http://localhost:18080` replaced by `https://garage-server.tailcc88e8.ts.net`, and wait until they say they're done. When finished, `DELETE http://localhost:18080/api/agent-sessions/<sessionId>`, adding `?save=false` unless you logged in or refreshed the login. If localhost:18080 is down, report it; never use the tailnet URL or open your own forward. Details: "Agent sessions" in ~/workspace/rpa/README.md

## Getting results back from Claude subagents

- Subagents can't write report files (the harness blocks it). Tell them up front to return findings as text in their final message.
- Final results are truncated at ~4,000 chars; very large ones can come back empty. For long reports, ask subagents up front to send them via SendMessage in ≤3,500-char parts, or use `schema` for compact structured output.
- Don't idle waiting for a background job's completion notice; it may not arrive. Poll its output file or pid yourself with a time limit.
- Claude Code bug (seen 2026-10-03): subagents started by a background teammate can't return results to it (hand-back fails, their SendMessage reaches only the main session, a built-in hook makes them retry endlessly). Teammates don't start subagents: they work themselves, drive workers through herdr, or ask the main session to start Claude subagents and pass the results back.

# graphify

- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
  When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.
