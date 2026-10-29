# Personal Preferences

## Typescript

- Never use `any` unless 100% necessary or specifically instructed

## Commands

- Don't run dev server commands (eg. `npm run dev`, `yarn dev`, `pnpm dev`) assume it's already running
- Don't run build commands unless specifically told to do
- Focus on checking commands like `yarn typecheck`, `yarn lint` or `pnpm` based one
- Exception: starting a dev server, local stack or build is allowed only to capture PR before/after evidence (see below); stop it afterwards
- Never kill processes by pattern (`pkill -f`, `pkill` without `-x`, `killall -m`, `pgrep <pattern> | xargs kill`, `kill -1`/`kill 0`): on 2026-09-29 `pkill -f "cat"` killed 37 of the user's apps. Kill by recorded PID (`$!`, a pidfile) or port owner (`lsof -ti :PORT -sTCP:LISTEN`; without `-sTCP:LISTEN` it also returns clients such as the user's browser). A global hook enforces this

## Containers

- Use the remote Podman on the Linux workstation (connection `workstation`), not the local Podman VM. Don't silently fall back to the local VM or reset the default connection; if a workflow can't run remotely, report it
- Remote bind mounts resolve on the workstation's filesystem, and images build as amd64
- Publish dev ports on the workstation's loopback (`127.0.0.1:<port>:<port>`) and reach them through an SSH forward; exposing a port to the network needs the user's explicit go

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

## Picking the right model for workflows and subagents

Rankings, higher = better. Cost reflects what i actually pay (OpenAI is near-free for me), not list price. Intelligence is how hard a problem you can hand the model unsupervised. Taste covers UI/UX, code quality, API design, Security, and copy.

| model  | provider | cost | Intelligence | taste |
| ------ | -------- | ---- | ------------ | ----- |
| luna   | gpt      | 10   | 7            | 4     |
| haiku  | claude   | 8    | 7            | 5     |
| sol    | gpt      | 9    | 8            | 5     |
| astra  | gpt      | 8    | 9            | 6     |
| sonnet | claude   | 6    | 6            | 7     |
| opus   | claude   | 5    | 8            | 8     |
| fable  | claude   | 2    | 9            | 9     |

Always use the latest release of each tier. The Claude names are aliases that already resolve to the latest. The GPT models are Claude Code agent types (`sol`, `luna`, `astra`) defined in `~/.claude/agents/<name>.md`, reached through the local CLIProxyAPI gateway; their model ids live only in those files, so update them there when newer releases ship. Haiku is the `haiku` agent type (`~/.claude/agents/haiku.md`, pinned to `claude-haiku-5-5`), since the Agent tool's `model` parameter doesn't offer it. Luna, astra and haiku scores are estimates; adjust them once you've used them.

How to apply:

- These are defaults, not limits. You have standing permission to override them: if a cheaper model's output doesn't meet the bar, rerun or redo the work with a smarter model without asking. Judge the output, not the price tag. Escalating costs less than shipping mediocre work.
- Cost is a tie-breaker only; when axes conflict for anything that ships, intelligence > taste > cost.
- Bulk/mechanical work (clear-spec implementation, data analysis, migrations): sol - it's effectively free. Simple, high-volume, well-specified steps (fixtures, renames, bulk test fixes): luna. The hardest hands-on or analysis work where sol falls short, or a second opinion from a different model family: astra.
- Exploration and iterative labor: haiku. Use it for exploration subagents (searching and reading code or docs and reporting back) and for bounded, well-specified hands-on work that an opus owner checks and re-briefs over several passes. It's Anthropic-native, so prompt caching works, unlike the GPT workers behind the gateway. Not for reviews, user-facing work (taste >= 7) or hard agentic coding; escalate those to sonnet/opus or sol/astra.
- Support work: haiku. Classification, triage and quick queries for support tasks (routing a request, looking up a log or a doc, a short factual answer), as a `haiku` subagent or as the main model of a support session such as July. Hand deeper root-cause analysis, judgment calls and longer explanations to an opus subagent before they go out.
- Treat sol, luna and astra as an outsourced team that does the hands-on work, not as peers of the Claude tiers.
- The main session normally runs on opus at its default effort. Switch a session to fable only for demanding long-horizon work (deep research, a large design) or when opus visibly falls short. Adjust effort before switching models. Use fable as an on-demand advisor that any Claude session or teammate can consult for hard architecture, planning and judgment calls, and as the internal reviewer for high-stakes changes only (see Reviews).
- Delegate in layers: the main session scopes the task, writes the brief, and reviews; an opus teammate is the delegation manager: it owns the task end to end, does the parts that need Claude's judgment or taste itself, and dispatches the mechanical steps to sol/luna agents (writes the brief, spawns the agent, judges and iterates on the output, runs local checks, opens the PR, watches CI).
- The main session should avoid making edits itself. Delegate even small changes, batching them into a teammate's sol/luna run. It edits directly only as a last resort, when delegating clearly costs more than it saves.
- Anything user-facing (UI, copy, API design) need taste >= 7
- Reviews of plans and implementation always go through two stages, and nobody finalizes a review of work they wrote (including work their own sol/luna agent wrote):
  1. Internal review first, by a Claude that did not write it. By default an opus reviewer subagent. Use a fable reviewer only for high-stakes changes (defined below). If a fable session wrote it, an opus reviewer checks it.
  2. Then the final review by a `sol` agent (an `astra` agent for high-stakes changes), passing it the internal review's findings. Verify its findings against the code before acting, and have the author fix them.
- High-stakes = a bug would cause harm that is hard to undo and reaches beyond the user's machine. Only these get the fable internal review and the astra final review:
  - Security: changes to auth or permission checks, secret handling, or parsing untrusted input in an internet-facing service. Not UI behind a login, internal tools or tests.
  - Personal data: new collection, storage, logging or sharing of identity numbers, phones, emails or KYC data. Not displaying data that is already handled.
  - Money: code that calculates or moves amounts (payments, pricing, billing).
  - Irreversible data: migrations, deletions or schema changes on shared or production data. Not local dev databases or fixtures.
  - Production: deploys, infrastructure, DNS or cluster changes applied to production.
  - Hard-to-reverse design: public API contracts, concurrency, large architecture changes.
  - Not high-stakes: local tools, personal config such as `~/.claude` hooks, docs, tests, UI and copy, refactors covered by tests, prototypes, staging or dev-only changes.
  - If unsure, ask: "If this has a bug, can we revert it in minutes with nobody harmed?" If yes, it's an opus internal review and a sol final review.
- Never use Haiku 4.5 or older. Haiku 5.5+ only for the roles above: through the `haiku` agent, or as the main model of a support session.
- Browser: use the `agent-browser` CLI (via Bash; usage: `agent-browser skills get core`) for all browser work: browsing, research, testing, screenshots, PR evidence. It runs its own headless Chromium, not the user's Chrome. Before the first command, every agent sets its own named session: `export AGENT_BROWSER_SESSION="$(agent-browser session id --scope worktree --prefix <task>)"`; never use the shared default session. Run `agent-browser close` when done. Name it in every subagent brief. Use the user's real Chrome or profile (`--auto-connect`, `--cdp`, `--profile`) only with the user's go-ahead, e.g. for pages behind their login, and then never touch browser-wide state (cookies, permissions, storage): on 2026-10-07 a `clearCookies()` call signed the user out of every site.
- Mechanics: spawn GPT workers and haiku with the Agent tool's `subagent_type` (`sol`, `luna`, `astra`, `haiku`); Claude models run via the agent/workflow `model` parameter (sonnet, opus, fable). Give GPT agents a self-contained brief: they don't share your context. They report as "Fable 5" because of the gateway's disguised ids; ignore that. Parallel agents that edit each get their own git worktree, created manually: `git -C <repo> worktree add <path> -b <branch>`, then spawn the agent WITHOUT `isolation` and tell it to work only in that absolute path; remove the worktree when done. Don't use `isolation: 'worktree'`: it currently loses its context and every Bash call in the agent fails.

Who does the work:

- Main session (opus) itself: answering questions, explaining code, planning and scoping, writing briefs, conversation. Edits only as a last resort. Hands internal reviews to an opus reviewer subagent (fable for high-stakes changes) and hard judgment calls to a fable advisor.
- Opus teammate: any feature, phase, fix or multi-file change that needs ownership: its own worktree and branch, iteration, checks, PR, CI. It hands the mechanical steps to sol/luna agents and does the judgment and taste parts itself.
- Subagent: bounded side tasks that come back as a report: searching the codebase, reading docs, investigating a question. Use one when the digging would flood your own context. Default to the `haiku` agent for these; use opus when the question needs judgment.
- Sonnet teammate: routine, well-specified work that still needs a Claude.
- sol/luna/astra agents: the hands-on steps, dispatched by the task's owner, not by the main session directly, except for a single well-specified step with no ongoing ownership.
- Work with independent parts: split it across parallel opus teammates, each in its own manually created worktree (see Mechanics).

Getting results back from subagents:

- Subagents can't write report files (the harness blocks it). Tell them up front to return findings as text in their final message, not in a file.
- Final results are truncated at ~4,000 chars, and very large ones can come back empty. For long reports, ask subagents up front to send them via SendMessage in parts of ≤3,500 chars each, or use `schema` to get compact structured output.
- Don't idle waiting for a background job's completion notice; it can fail to arrive. Poll its output file or pid yourself with a time limit.
- Claude Code bug (seen 2026-10-03): subagents started by a background teammate can't return results to it in any mode. Hand-back fails with "spawning agent is no longer running", their SendMessage to the teammate never arrives (only the main session gets it), and a built-in hook makes them retry endlessly. Until it's fixed, teammates don't start subagents: they do their own hands-on work, or ask the main session to start the sol/luna workers and reviewers and pass the results back. This overrides the teammate dispatch described above.

# graphify

- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
  When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.
