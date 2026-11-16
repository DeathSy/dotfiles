# AI setup

What the `nixpkgs/home-manager/ai/` modules manage, and the manual steps on a
new Mac.

## Layers

- **Public (this repo): everything that installs or runs.** Claude Code
  instructions, agents, hooks and own skills (`claude/`), generic Claude Code
  settings (`claude/settings.base.json`), generic Codex settings
  (`codex/config.base.toml`), the CLIProxyAPI config template
  (`cliproxyapi/config.yaml`), the merge and activation steps, the Headroom
  LaunchAgent and plugin build, Homebrew packages, and the `ai-bootstrap` and
  `ai-mcp-add` commands.
- **Private (`~/studio/personal/dotfiles-private`, a separate private repo): data
  only.** One home-manager module that sets the `dotfiles.ai.*` options
  (`nixpkgs/home-manager/ai/default.nix`, `gateway.nix`):
  `gateway.enable`, `gateway.tunnel.host` (the gateway server's SSH alias),
  `claude.settingsOverlay` (gateway model id, internal settings),
  `claude.projectPlugins`, `mcp.projectServers`, `codex.trustedProjects`. All
  options default to empty, so the public repo works without it.
- **Secrets** stay in `pass` and are read at activation.

The flake's `private` input defaults to the empty `private-stub/`, so the
public repo evaluates on its own. `rebuild` (zsh function) overrides it with
the private checkout when it exists:

```sh
sudo darwin-rebuild switch --flake ~/studio/personal/dotfiles \
  --override-input private path:$HOME/studio/personal/dotfiles-private
```

## What a rebuild does

**Before the first rebuild, merge `ai-setup` into `main` and pull it into
`~/studio/personal/dotfiles`.** The `~/.claude` links point at that checkout. If
`claude/CLAUDE.md` isn't there, activation stops before touching `~/.claude`.

- Links `~/.claude/{CLAUDE.md,onboarding.md}`, `~/.claude/agents/*.md`,
  `~/.claude/hooks/*` and `~/.claude/skills/<own skill>/SKILL.md` to the files
  in the checkout at `~/studio/personal/dotfiles/claude/` (not the Nix store), so
  editing them in place edits the repo. A live real file in the way (on the
  first rebuild, or after an editor that saves by renaming replaced a link) is
  renamed to `<file>.backup` by home-manager, with a warning naming it: diff
  it against the repo copy, then delete it (a leftover `.backup` makes the
  next rebuild stop).
- Links `~/.claude/skills/agent-browser/SKILL.md` to the skill that ships with
  the Homebrew `agent-browser` CLI.
- Links each `dotfiles.ai.claude.extraSkillDirs` entry (set in a private
  overlay) as the whole folder `~/.claude/skills/<name>`, for skills that
  can't live in this repo. Activation stops if a folder has no `SKILL.md`
  yet (merge and pull that repo first); a real folder in the way is renamed
  to `<name>.backup` like the files above.
- Merges `~/.claude/settings.json`: live file ← `claude/settings.base.json` ←
  `dotfiles.ai.claude.settingsOverlay` ← secrets from `pass`. Keys from the repo win; anything else
  Claude Code wrote stays. The file is kept at mode 600 (it holds the token);
  the previous version is copied to
  `~/.claude/backups/settings.json.dotfiles-<timestamp>.<random>` when it
  changes; backups are mode 600 and only the latest 5 are kept. If
  `jq` or `pass` fails, the file is left alone with a warning. Run
  `claude-settings-merge` to redo it by hand. Removing a key from the base
  JSON does not remove it from the live file.
- Merges `~/.codex/config.toml` the same way (`codex/config.base.toml` ←
  `codex.settings` and `codex.trustedProjects`), backing up to `~/.codex/backups/`. `codex-config-sync`
  redoes it by hand.
- With `dotfiles.ai.gateway.enable`: points Claude Code at the CLIProxyAPI
  gateway on `127.0.0.1:8317` (`ANTHROPIC_BASE_URL`, gateway model discovery,
  and `ANTHROPIC_AUTH_TOKEN` from `pass`). What answers on that port depends on
  the host (see [Gateway hosts](#gateway-hosts)).
- Installs `agent-browser` and `googleworkspace-cli` (`gws`) with Homebrew.

`settings.json` keys the public layer manages: `$schema`, `env.*` (agent
teams, function hooks, timeouts, context and autocompact limits, telemetry
off, claude.ai MCP servers off), `permissions.deny`, `skillOverrides`,
`hooks`, `enabledPlugins`, `extraKnownMarketplaces`, `effortLevel`,
`modelSettings`, `tui`, `editorMode`, `skipDangerousModePermissionPrompt`,
`skipAutoPermissionPrompt`, `skipWorkflowUsageWarning`,
`agentPushNotifEnabled`.

With the gateway enabled (every host) it also manages `env.ANTHROPIC_BASE_URL`,
`env.CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` and
`env.ANTHROPIC_AUTH_TOKEN`; the private overlay adds `model`.

The `sol`, `luna` and `astra` agents use model ids that only resolve through
the CLIProxyAPI gateway.

## Gateway hosts

The gateway (CLIProxyAPI with the OAuth logins, plus Headroom) runs on the AI
hub, **garage-hq**, which took it over from garage-server (see
[Moving the gateway server to garage-hq](#moving-the-gateway-server-to-garage-hq)).
Its host file imports `nixpkgs/nix-darwin/ai-hub.nix`, which declares the
`cliproxyapi` brew service (started on every rebuild unless
`dotfiles.ai.gateway.server.startService` is off), sets
`dotfiles.ai.gateway.server.enable` and turns on the workstation services (steps 10 to 12 of [New machine](#new-machine)),
and `ai/headroom.nix`. On the hub a rebuild also:

- writes `/opt/homebrew/etc/cliproxyapi.conf` from `cliproxyapi/config.yaml`
  (client key and management key from `pass`, mode 600), only if the file
  doesn't exist yet or is still the example Homebrew installs (kept as
  `cliproxyapi.conf.example`); CLIProxyAPI rewrites it itself. The template binds the proxy to
  `127.0.0.1`; an existing config keeps its own `host`.
- runs the Headroom proxy as the `ai.headroom.proxy` LaunchAgent, adds
  the Headroom server to `ai-bootstrap` and installs
  `cliproxyapi-headroom-build`. To drop Headroom, remove the `ai/headroom.nix`
  import from the host file (and the `plugins.configs.headroom` block from the
  CLIProxyAPI config).

Every other host (**garage**, the personal Mac, and **garage-server**, which
still never sleeps) gets no CLIProxyAPI, config,
management key, OAuth logins or Headroom; it keeps only the client key from
`pass`. Instead the `org.nix-community.home.cliproxyapi-tunnel` LaunchAgent
runs Apple's `/usr/bin/ssh -N -L 127.0.0.1:8317:127.0.0.1:8317 <tunnel.host>`,
so Claude Code, the sol/luna/astra agents and `settings.json` work the same as
on the server, the gateway stays bound to the server's `127.0.0.1`, and the
forward is only reachable from that Mac itself. It runs with
`BatchMode=yes`, `StrictHostKeyChecking=yes`, `ExitOnForwardFailure=yes`, 15 s
keepalives and no connection sharing; launchd restarts it at most every 30 s.
Log: `~/Library/Logs/cliproxyapi-tunnel.log`. There is no fallback: while the
tunnel or the server is down, Claude Code and the GPT agents on that Mac fail
to connect.

The private overlay enables the gateway for every host, so it must also set
`dotfiles.ai.gateway.tunnel.host` to an SSH alias for the server (for example
`garage-hq`); without it a client's configuration fails to evaluate with an
assertion naming the option. The server ignores it. The tailnet (MagicDNS)
name works as the alias when the user name is the same on both Macs and the
key needs no passphrase. Otherwise
map the alias to the real host and user in `~/.ssh/config` (never in this
repo).

garage-hq keeps Tailscale SSH **off** (Moshi needs macOS's own SSH server), so
clients log in with Remote Login and a key in garage-hq's
`~/.ssh/authorized_keys`. The launchd tunnel can't reach gpg-agent or prompt,
so a key with a passphrase must have it in the Keychain
(`ssh-add --apple-use-keychain ~/.ssh/id_ed25519`), and the alias reads it
from there:

```
Host garage-hq
  HostName <server's tailnet name or address>
  User <user>
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  UseKeychain yes
  AddKeysToAgent yes
```

Check it the way launchd runs it:
`env -i HOME=$HOME /usr/bin/ssh -o BatchMode=yes -o StrictHostKeyChecking=yes garage-hq true`.

### Moving the personal Mac to the tunnel

Do these in order; the old local gateway on the personal Mac keeps serving
Claude Code until step 4.

1. On the personal Mac, add the alias first (the block above, and the
   passphrase in the Keychain if the key has one). On garage-hq, turn on
   Remote Login (System Settings → General → Sharing, only for its user),
   then from the personal Mac add its public key with
   `ssh-copy-id -i ~/.ssh/id_ed25519.pub garage-hq` (this also records the
   host key). Tailscale SSH stays off there (see above). For a server that uses Tailscale
   SSH instead, the tailnet policy's SSH rule must use action `accept`: `check`
   asks for a browser login from time to time, which the launchd tunnel can't
   do. Check that the
   server has every OAuth account the personal Mac used
   (the same number of login files as the personal Mac,
   `ls ~/.cli-proxy-api/*.json | wc -l` on both; the file names hold account
   emails, so don't list them; log in with `cliproxyapi --claude-login` etc.
   if one is missing).
2. On the personal Mac, check the login the way launchd runs it:
   `env -i HOME=$HOME /usr/bin/ssh -o BatchMode=yes -o StrictHostKeyChecking=yes garage-hq true`
   must succeed without any prompt (if it says "Host key verification
   failed", run `ssh garage-hq true` once first).
3. Test the whole path on a spare port, without touching the old gateway:
   `ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:18317:127.0.0.1:8317 garage-hq`
   in one terminal, and in another
   `pass show ai/cliproxyapi-key | sed -n '1s/^/Authorization: Bearer /p' | curl -fsS -H @- http://127.0.0.1:18317/v1/models | jq -r '.data[].id'`
   (the key goes through stdin, not the command line). It must list the
   Claude and GPT models you use; an HTTP 401 error means the personal Mac's
   `ai/cliproxyapi-key` doesn't match the server's config. Stop the test
   tunnel.
4. Set `tunnel.host` in the private overlay and `rebuild`. The rebuild removes
   the Headroom LaunchAgent but leaves the old `cliproxyapi` service running
   (Homebrew cleanup is off), so the tunnel retries with
   `Address already in use` in its log. Run `brew services stop cliproxyapi`;
   within 30 s `lsof -nP -iTCP:8317 -sTCP:LISTEN` shows `ssh`. Repeat the
   step 3 request against port 8317 and run one `claude -p` prompt. If either
   fails, go back with
   `launchctl bootout gui/$(id -u)/org.nix-community.home.cliproxyapi-tunnel`
   and `brew services start cliproxyapi`, then read the tunnel log. A rebuild
   doesn't reload an unchanged tunnel; once fixed, stop the old service again
   and run
   `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/org.nix-community.home.cliproxyapi-tunnel.plist`.
5. Once both checks pass, uninstall the old gateway (Homebrew cleanup is off,
   so the rebuild leaves it installed): `brew uninstall cliproxyapi` and
   `uv tool uninstall headroom-ai`.
6. Optional, once the tunnel has worked for a while: archive (or deliberately
   delete) what only the old gateway used:
   `/opt/homebrew/etc/cliproxyapi.conf` (holds the management key),
   `~/.cli-proxy-api/` (OAuth logins and the Headroom plugin),
   `~/Library/Logs/headroom/` and `~/.cache/cliproxyapi-headroom/`. Nothing
   removes them automatically, and `uninstall.sh` only removes `cliproxyapi`
   on garage-hq.

### Moving the gateway server to garage-hq

garage-hq took the hub over from garage-server in two changes. The first gave
it the hub role without clients, without Open Design's reverse tunnel
(`openDesign.gatewayTunnel = false`) and with its `cliproxyapi` never started
by Homebrew (`gateway.server.startService = false`), so a rebuild couldn't run
a second live copy of the logins, while garage-server kept serving every Mac.
The second, merged in step 5 (the `garage-hq-cutover` branches of this repo
and the private one), turned garage-server into a client like garage, dropped
both garage-hq settings and set `tunnel.host = "garage-hq"`. Steps 3 to 5
take the gateway away from garage-server and garage, so they ran by hand in a
plain terminal, not through Claude Code there. The steps, kept for a
rollback:

1. Set up garage-hq as in [New machine](#new-machine) with
   `./init.sh garage-hq`, skipping the CLIProxyAPI logins in step 6. Its
   `cliproxyapi` is installed but stays stopped. Build the Headroom plugin
   there with `cliproxyapi-headroom-build` (step 8); don't copy the dylib,
   and skip step 8's `brew services restart cliproxyapi` (and the restarts
   the build command and the rebuild suggest): garage-hq's gateway starts
   only in step 3.
   Give garage-hq the `workstation` alias (copy its `~/.ssh/config` block) and
   a key the workstation accepts, with the host key in known_hosts; the
   `auto-browser-tunnel`, `open-design-tunnel` and `local-llm-tunnel` logs
   must stay quiet.
2. Do steps 1 and 2 of [Moving the personal Mac to the tunnel](#moving-the-personal-mac-to-the-tunnel)
   with garage-hq as the server and both garage and garage-server as
   clients: Remote Login on garage-hq with each client's key in its
   `authorized_keys` (the move itself ran over Tailscale SSH; garage-hq turned
   it off afterwards for Moshi), and on each client `ssh garage-hq true`
   once, then `ssh -o BatchMode=yes -o StrictHostKeyChecking=yes garage-hq true`
   without a prompt.
3. Move the logins. From here until step 5 (or the bridge after step 4) every
   Mac but garage-hq is without a gateway. Stop garage-server's gateway first,
   since OAuth refresh tokens can rotate and two live copies can invalidate
   each other: there `brew services stop cliproxyapi`, and
   `lsof -nP -iTCP:8317 -sTCP:LISTEN` must show nothing. Don't rebuild
   garage-server before step 5: Homebrew would start the service again. On
   garage-hq the same `lsof` must show nothing too. Then on garage-server
   (never print these files):

   ```sh
   ssh garage-hq 'umask 077; mkdir -p ~/.cli-proxy-api'
   scp -q -p ~/.cli-proxy-api/*.json garage-hq:.cli-proxy-api/
   scp -q -p /opt/homebrew/etc/cliproxyapi.conf garage-hq:/opt/homebrew/etc/
   ssh garage-hq 'chmod 600 ~/.cli-proxy-api/*.json /opt/homebrew/etc/cliproxyapi.conf'
   ```

   Then `brew services start cliproxyapi` on garage-hq.
4. Check garage-hq before moving any client: from garage-server, the
   spare-port test of step 3 of [Moving the personal Mac to the tunnel](#moving-the-personal-mac-to-the-tunnel)
   with `garage-hq` as the destination (model list, key from `pass` via
   stdin), then one `claude -p` prompt on garage-hq.

   Optional bridge until step 5: on garage-server run
   `ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8317:127.0.0.1:8317 garage-hq & echo $! > /tmp/gateway-bridge.pid`.
   garage-server's Claude Code gets the gateway back, and garage's existing
   tunnel reaches garage-hq through it.
5. Merge both `garage-hq-cutover` branches and pull BOTH repos on each Mac.
   Before each `rebuild`, check that it will point at garage-hq:
   `nix eval --raw ~/studio/personal/dotfiles#darwinConfigurations.$(scutil --get LocalHostName).config.home-manager.users.ksotis.dotfiles.ai.gateway.tunnel.host --override-input private path:$HOME/studio/personal/dotfiles-private`
   must print `garage-hq`. Then `rebuild` in this order: garage-server (first
   `kill "$(cat /tmp/gateway-bridge.pid)"` if you started the bridge; its
   reverse tunnel stops, freeing the workstation's port, and its
   `cliproxyapi-tunnel` starts on the free 8317), garage-hq (opens the
   reverse tunnel; while the workstation still holds a stale listener it
   retries every 30 s, see step 11 of [New machine](#new-machine)), then garage.
   On garage-server and garage, `lsof -nP -iTCP:8317 -sTCP:LISTEN` shows
   `ssh`; repeat the model list against 8317 and run one `claude -p` prompt.
6. Hand the session coordination over; it is per Mac. The SessionStart hook
   (`claude/hooks/global-manager-intro.sh`) points each session at the
   `claude-config` session on its own Mac, SendMessage only reaches sessions
   on the same Mac, and `~/.claude/session-roster.md` is a local file. Ask
   the old `claude-config` on garage-server to write its open items into the
   roster, copy it over (`scp -p ~/.claude/session-roster.md
   garage-hq:.claude/`), then start a `claude-config` session on garage-hq
   that takes the roster over, keeping only the sessions that moved. Once the
   sessions left on garage-server have wound down, close the old one. Skills
   that drive local apps (the iMessage channel) need those apps signed in and
   granted access on garage-hq first.
7. Once it has worked for a while, clean up garage-server as in steps 5 and 6
   of [Moving the personal Mac to the tunnel](#moving-the-personal-mac-to-the-tunnel)
   (`brew uninstall cliproxyapi`, `uv tool uninstall headroom-ai`, then
   archive or delete the old config, logins, Headroom logs and cache), and
   drop the MCP servers it no longer reaches:
   `claude mcp remove -s user auto-browser` and
   `claude mcp remove -s user open-design`.

Rollback, only until step 7 (after it garage-server has no gateway left; set
it up as a new hub instead):

1. On garage-hq, `brew services stop cliproxyapi`.
2. On garage-server, copy the logins back, since garage-hq may have rotated
   them:
   `scp -q -p 'garage-hq:.cli-proxy-api/*.json' ~/.cli-proxy-api/ && chmod 600 ~/.cli-proxy-api/*.json`.
3. On garage-hq, set its copies aside so nothing can start them again:
   `a=~/.cli-proxy-api.archive-$(date +%F); mkdir -m 700 "$a" && mv ~/.cli-proxy-api/*.json "$a"/`.
4. Before step 5: kill the bridge if it runs, then
   `brew services start cliproxyapi` on garage-server. After step 5: revert
   the cutover in both repos, pull both on each Mac, and `rebuild` garage-hq,
   then garage-server, then garage. If garage-server's `cliproxyapi` came up
   while its tunnel still held 8317, run `brew services restart cliproxyapi`
   there.

## Resuming agents in herdr after a reboot

After a reboot or a herdr-core crash, herdr brings each kept terminal back
under the same address (`t3`) as a plain shell in its last folder; it never
re-runs the program. Only terminals with keep on come back: turn it on with
`hc keep <t>` (or start them with `hc run --keep`). To get the Claude Code
agents back:

- The `claude/hooks/herdr-agent-record.sh` hook (SessionStart and
  SessionEnd) records, for each herdr terminal, the conversation its
  foreground `claude` has open: `~/.claude/herdr-agents/<terminal>.<session
  id>.json` (folder mode 700, files 600) with the session id, folder,
  transcript path and the terminal's `keep` and `created_ms`. A new id after
  `/clear`, compaction or a fork replaces the terminal's record, and resuming
  a conversation in another terminal moves it there. The record is removed
  only when the session ends on purpose (quit, `/clear`, `/resume`, logout).
  A shutdown or restart SIGTERMs `claude` (SessionEnd reason `other`), so
  the record stays exactly then; so does a terminal closed with `hc kill`.
  Outside herdr, for `claude -p`/SDK runs (an agent's `claude -p` inherits
  its terminal's `HC_TERMINAL_ID`), subagents and anything herdr doesn't
  report as the terminal's foreground program, it does nothing. It asks
  `hc get` with a 2 s timeout and records anyway when hc doesn't answer.
- `agents-resurrect` reads `hc ls --json` and prints one line per recorded
  terminal: `resume` for terminals that are back as a shell (zsh, bash, sh,
  fish), `skip` with the reason otherwise (busy running another program such
  as `claude-code`, the same conversation newer in another terminal, record
  older than 30 days, folder or transcript gone). For a terminal that is
  gone it prints the `cd <folder> && claude -r <id>` line to run by hand. It
  warns about live `claude-code` terminals with keep off.
  `agents-resurrect --yes` types `cd <folder> && claude -r <session id>` into
  each `resume` terminal with `hc send`. `--prune` deletes the records of gone
  terminals and stale or unreadable ones. It fails with a message when `hc`
  is missing or herdr-core isn't running.
- `claude -r <id>` from a terminal restores the permission mode the
  conversation was in, so no mode is recorded or passed.
- Limits: it resumes the conversation, not a command or turn that was running
  when the Mac went down (ask the agent to carry on). Only terminals inside
  herdr on this Mac are covered, and only those with keep on. herdr keeps
  `created_ms` when it restores a kept terminal in place; if it differs from
  the record, the plan adds a note (unverified across a full core restart, so
  it's not a skip). It doesn't run at login: herdr-core may not be up yet, and
  typing into shells unprompted would surprise. Run it by hand after a reboot.

## New machine

1. Clone this repo over HTTPS (there's no SSH key yet) to
   `~/studio/personal/dotfiles`, the checkout the `~/.claude` links point at:
   `git clone https://github.com/DeathSy/dotfiles.git ~/studio/personal/dotfiles`.
   From there run `./init.sh <host>` (`garage`, `garage-server` or
   `garage-hq`; installs Nix, Homebrew and nix-darwin). This first switch uses
   the empty `private-stub/`.
2. Start Tailscale: `sudo brew services start tailscale`, then
   `sudo tailscale up --ssh --hostname=<host>`. `--ssh` turns on Tailscale SSH
   for logging in to this Mac over the tailnet. Leave it out (or turn it off
   later with `sudo tailscale set --ssh=false`) where you want Remote Login
   on the tailnet instead, as garage-hq does for Moshi.
3. `gh auth login`, choosing SSH as the git protocol and letting it generate
   and upload a key. Then switch the checkout to SSH:
   `git -C ~/studio/personal/dotfiles remote set-url origin git@github.com:DeathSy/dotfiles.git`.
4. Restore GPG and `pass`: import the GPG key named in
   `nixpkgs/home-manager/password-store.nix`, then clone the password store to
   `~/.password-store`. Entries used:
   - `ai/cliproxyapi-key`: the CLIProxyAPI client key (also Claude Code's
     `ANTHROPIC_AUTH_TOKEN`)
   - `ai/cliproxyapi-management-secret`: the CLIProxyAPI management key
     (plain text; CLIProxyAPI hashes it on load). Read on the hub only
   - `github/personal`: GitHub token (registry token)
   - `personal/excalidraw`: Excalidraw+ API key (optional; until it exists
     the `excalidraw` MCP server just fails to connect)
5. Clone the private repo to `~/studio/personal/dotfiles-private`, open a new
   shell and run `rebuild`.
6. Log in:
   - `claude` (first run), and `codex login`
   - On the hub only, the CLIProxyAPI OAuth accounts (a new hub can take the
     old one's instead, see
     [Moving the gateway server to garage-hq](#moving-the-gateway-server-to-garage-hq)):
     `cliproxyapi --claude-login`, `cliproxyapi --codex-login` (and any other
     providers you use). The login files land in `~/.cli-proxy-api/*.json`;
     never commit them. Other Macs set up the tunnel instead (see
     [Moving the personal Mac to the tunnel](#moving-the-personal-mac-to-the-tunnel)).
   - `gws auth login`. `gws` comes from the Homebrew `googleworkspace-cli`
     formula; if an older npm-global copy exists, remove it
     (`npm uninstall -g @googleworkspace/cli`) so the Homebrew one wins on
     `PATH`.
7. Run `ai-bootstrap`. It installs what Nix and Homebrew don't cover (the
   `claude` native installer, `graphify`, on the hub the Headroom server
   with its proxy extras: `uv tool install --python 3.13 'headroom-ai[all]'`,
   redone when the proxy can't import them), skills from their sources
   (find-skills, frontend-design, graphify), Claude Code
   marketplaces and plugins, and MCP servers (`ai-mcp-add`: the user-scope
   ones plus `mcp.projectServers`; it never rewrites `~/.claude.json`). It skips anything already present and can be
   re-run.
8. On the hub, build the Headroom plugin for CLIProxyAPI:
   `cliproxyapi-headroom-build`, then `brew services restart cliproxyapi`.
9. Authenticate the HTTP MCP servers (figma, monday, wispr-flow, ticktick, and
   per-project ones) from `/mcp` inside Claude Code, and run `/slack` once to
   log in to the Slack plugin. `excalidraw` needs no login: its `headersHelper`,
   `~/.local/bin/excalidraw-headers`, sends the key from `pass` at connect
   time. After changing its definition, run
   `claude mcp remove -s user excalidraw` and `ai-mcp-add` again.

   Folder trust: when `dotfiles.ai.claude.trustedRepoOwners` is set (in the
   private overlay), `claude` is a zsh function that first runs
   `claude-trust-repo`, which marks the current git repo trusted in
   `~/.claude.json` if its `origin` is a github.com repo (ssh or https) of one
   of those owners. Other repos, other hosts, and repos without an origin still
   get Claude Code's trust question; it's skipped inside Claude Code's own
   shells. Trust lets a repo's own `.claude` settings, hooks and MCP servers
   run, and the origin owner is only a hint: a fork of someone else's code
   under your account, a work org's repo, or an unpacked archive that carries
   a `.git/config` all pass. Run `claude-trust-repo <dir>` to trust an existing
   checkout by hand.
10. On the hub, Auto Browser (`dotfiles.ai.autoBrowser`, enabled in
   `nixpkgs/nix-darwin/ai-hub.nix`): the `auto-browser-tunnel` launchd agent
   forwards 127.0.0.1:18000 to port 8000 on the `workstation` SSH alias, whose
   host key must already be in known_hosts. `ai-mcp-add` registers the
   `auto-browser` user-scope MCP server; its `headersHelper`,
   `~/.local/bin/auto-browser-headers`, reads the agent token from `pass` at
   connect time (a non-prompting gpg-agent must work for Claude Code) and
   names the calling session in `X-Operator-Name`. `ai-mcp-add` never rewrites
   an existing entry, so after changing the server definition run
   `claude mcp remove -s user auto-browser` and `ai-mcp-add` again.
   Tunnel log: `~/Library/Logs/auto-browser-tunnel.log`.
11. On the hub, Open Design (`dotfiles.ai.openDesign`, enabled in
   `nixpkgs/nix-darwin/ai-hub.nix`): `ai-mcp-add` registers the
   `open-design` stdio MCP server, which runs `open-design/mcp.sh` on the
   `workstation` alias over SSH, so this Mac holds no token for it. The
   `open-design-tunnel` launchd agent forwards 127.0.0.1:7456 to the
   workstation's hardening proxy on 7457 for the web UI, which asks for the API
   token (`pass show workstation/open-design/api-token`). The local port must
   stay 7456: the app's preview URLs and origin check use it. Tunnel log:
   `~/Library/Logs/open-design-tunnel.log`. A second agent,
   `open-design-gateway-tunnel`, forwards the other way so Open Design's model
   calls reach this Mac's gateway: workstation 127.0.0.1:18317 to
   127.0.0.1:8317 here (gateway key still required). Only one Mac may own
   that port, so only a hub with `dotfiles.ai.openDesign.gatewayTunnel` runs
   it (default: on for a gateway server with the gateway enabled; a second
   one sets it to false). If the connection dies uncleanly, the workstation keeps the stale
   listener until its sshd notices (hours without `ClientAliveInterval`), and
   the agent retries every 30 s until then. Log:
   `~/Library/Logs/open-design-gateway-tunnel.log`.
12. On the hub, the local LLM server (`dotfiles.ai.localLlm`, enabled in
   `nixpkgs/nix-darwin/ai-hub.nix`): the `local-llm-tunnel` launchd agent
   forwards 127.0.0.1:18083 to a llama.cpp `llama-server` on the same port of
   the `workstation` alias's loopback (host key in known_hosts). The server has
   no API key and is started by hand there; while it's down, requests get a
   reset or empty reply. Tunnel log: `~/Library/Logs/local-llm-tunnel.log`.
