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
  JSON does not remove it from the live file. `hooks` is merged per event:
  the repo's entries first, then the live entries other tools added (Moshi
  adds its own to most events), so a rebuild no longer drops those. The
  repo's entries of the last merge are kept in
  `~/.local/state/claude-settings-merge/managed-hooks.json`; an entry that
  was in there but is no longer in the repo (removed or changed) is dropped
  from the live file. Repo entries removed before that file first existed
  aren't recognised and stay; delete them from the live file by hand.
- Merges `~/.codex/config.toml` the same way (`codex/config.base.toml` ←
  `codex.settings` and `codex.trustedProjects`), backing up to `~/.codex/backups/`. `codex-config-sync`
  redoes it by hand.
- With `dotfiles.ai.gateway.enable`: points Claude Code at the CLIProxyAPI
  gateway on `127.0.0.1:8317` (`ANTHROPIC_BASE_URL`, gateway model discovery,
  and `ANTHROPIC_AUTH_TOKEN` from `pass`). What answers on that port depends on
  the host (see [Gateway hosts](#gateway-hosts)).
- Installs `agent-browser` and `googleworkspace-cli` (`gws`) with Homebrew.

Open Design, the local LLM tunnel and Auto Browser (workstation services)
were retired on 2026-11-20 in favour of `agent-browser`; drop their leftover
MCP entries with `claude mcp remove -s user auto-browser` and
`claude mcp remove -s user open-design`.

`settings.json` keys the public layer manages: `$schema`, `env.*` (agent
teams, function hooks, timeouts, context and autocompact limits, telemetry
off, claude.ai MCP servers off), `permissions.deny`,
`hooks`, `enabledPlugins`, `extraKnownMarketplaces`, `effortLevel`,
`modelSettings`, `tui`, `editorMode`, `skipDangerousModePermissionPrompt`,
`skipAutoPermissionPrompt`, `skipWorkflowUsageWarning`,
`agentPushNotifEnabled`.

With the gateway enabled (every host) it also manages `env.ANTHROPIC_BASE_URL`,
`env.CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` and
`env.ANTHROPIC_AUTH_TOKEN`; the private overlay adds `model`.

## Gateway hosts

The gateway (CLIProxyAPI with the OAuth logins, plus Headroom) runs on the AI
hub, **garage-hq**, which took it over from garage-server (see
[Moving the gateway server to garage-hq](#moving-the-gateway-server-to-garage-hq)).
Its host file imports `nixpkgs/nix-darwin/ai-hub.nix`, which declares the
`cliproxyapi` brew service (started on every rebuild unless
`dotfiles.ai.gateway.server.startService` is off) and sets
`dotfiles.ai.gateway.server.enable`, and `ai/headroom.nix`. On the hub a
rebuild also:

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
so Claude Code and `settings.json` work the same as
on the server, the gateway stays bound to the server's `127.0.0.1`, and the
forward is only reachable from that Mac itself. It runs with
`BatchMode=yes`, `StrictHostKeyChecking=yes`, `ExitOnForwardFailure=yes`, 15 s
keepalives and no connection sharing; launchd restarts it at most every 30 s.
Log: `~/Library/Logs/cliproxyapi-tunnel.log`. There is no fallback: while the
tunnel or the server is down, Claude Code on that Mac fails
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
it the hub role without clients and with its `cliproxyapi` never started
by Homebrew (`gateway.server.startService = false`), so a rebuild couldn't run
a second live copy of the logins, while garage-server kept serving every Mac.
The second, merged in step 5 (the `garage-hq-cutover` branches of this repo
and the private one), turned garage-server into a client like garage, dropped
that garage-hq setting and set `tunnel.host = "garage-hq"`. Steps 3 to 5
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
   `kill "$(cat /tmp/gateway-bridge.pid)"` if you started the bridge, so its
   `cliproxyapi-tunnel` starts on the free 8317), garage-hq, then garage.
   On garage-server and garage, `lsof -nP -iTCP:8317 -sTCP:LISTEN` shows
   `ssh`; repeat the model list against 8317 and run one `claude -p` prompt.
6. Hand the session coordination over; it is per Mac. The SessionStart hook
   (`claude/hooks/global-manager-intro.sh`) points each session at the
   `claude-config` session on its own Mac, SendMessage only reaches sessions
   on the same Mac, and `~/.claude/session-roster.md` (claude-config's shared
   notes) is a local file. Ask the old `claude-config` on garage-server to
   write its open items into those notes, copy them over (`scp -p
   ~/.claude/session-roster.md garage-hq:.claude/`), then start a
   `claude-config` session on garage-hq that takes the notes over. Once the
   sessions left on garage-server have wound down, close the old one. Skills
   that drive local apps (the iMessage channel) need those apps signed in and
   granted access on garage-hq first.
7. Once it has worked for a while, clean up garage-server as in steps 5 and 6
   of [Moving the personal Mac to the tunnel](#moving-the-personal-mac-to-the-tunnel)
   (`brew uninstall cliproxyapi`, `uv tool uninstall headroom-ai`, then
   archive or delete the old config, logins, Headroom logs and cache).

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
  the record, the address was reused by a new terminal and it's skipped with
  the command to run by hand (a record without `created_ms` resumes as
  before). Whether `created_ms` also survives a full core restart is
  unverified; if it doesn't, every terminal is skipped this way. It doesn't run at login: herdr-core may not be up yet, and
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

## Hermes Agent (garage-hq)

`nixpkgs/home-manager/ai/hermes.nix`, imported by `nixpkgs/hosts/garage-hq.nix`.
Hermes itself is a normal, mutable install from its official installer, not a
Nix package: the code in `~/.hermes/hermes-agent`, the command
`~/.local/bin/hermes`, updated with `hermes update` (or the dashboard). The
dashboard and the apps can install skills, plugins and MCP servers and edit
`config.yaml`; nothing reverts that except our own rules (below).

The gateway, the owner's always-on agent as a Slack DM bot, runs as Hermes' own
launchd job `ai.hermes.gateway` (written by `hermes gateway install`, kept
current by Hermes). Because Hermes knows that job, `hermes gateway restart`,
the dashboard's System page, `hermes update` and every client that needs a
gateway (`hermes chat`, the TUI, the apps) start or restart that job instead of
spawning a second, unmanaged gateway (`com.nousresearch.hermes.runtime.*`,
launched through `osascript`). The repo adds around it:

- `hermes-config-check`: our config rules (secrets helper, MCP servers,
  toolset allowlists, Slack admin gating, the owner's API-posted Slack
  messages, approvals, dashboard sign-in, the skills, loopback API server in
  `.env`). Activation runs it with `--fix` on
  every rebuild. launchd runs it every 30 minutes and whenever `config.yaml`
  or `.env` change (`--auto`): it restores the security subset at once (Slack
  gating, `platforms.slack.extra.api_human_users`, approvals, toolset lists, MCP servers, secrets helper, dashboard
  sign-in, `.env`), DMs the owner what it restored, and restarts the gateway
  with `hermes gateway restart` (drains running turns) when a restored
  setting is read only at gateway start (`slack.*`, `platforms.*`,
  `mcp_servers.*`, `secrets.*`, `.env`; toolsets and approvals are re-read per turn). Other
  problems are reported by DM when unchanged for 20 minutes (and once when
  they clear): secret-looking keys in `config.yaml`/`.env` (names only), more
  than one gateway process, a gateway not under `ai.hermes.gateway`, any
  loaded unmanaged runtime job, a dashboard or API listener beyond loopback,
  and any chat platform whose toolsets, resolved by Hermes' own resolver,
  include the monitor's `inbox` server. Settings outside the rules (model, memory, `terminal.cwd`, …)
  are seeded once and then belong to Hermes and the owner.
- Stable links for `config.yaml`: `~/.local/bin/hermes-secrets` (the secrets
  helper) and `~/.local/share/hermes-inbox/{code,skills,chat-skills,extra-skills/N}`.
- The dashboard job `com.ksotis.hermes-dashboard` (written as a real plist by
  activation, with `hermes dashboard` itself as ProgramArguments so Hermes'
  update recognises it), tailscale serve, the Keychain sync, the dead-man.

Install (done once, 2026-11-21, replacing the Nix-packaged Hermes): pause the
monitor, back up `~/.hermes` (`tar` without `hermes-agent/` and `tools/` to
`~/.local/state/hermes-backup-<ts>.tgz`, 0600), boot out the old jobs, remove
`~/.hermes/.managed`, run the official installer with `--skip-setup` (no setup
wizard and no service prompt; it adds nothing to the shell files because
`~/.zprofile` already has its PATH line), `hermes gateway install`, rebuild,
`hermes-inbox-jobs`, then `hermes-config-check` until it prints OK. What the
installer touches: `~/.hermes/hermes-agent` (git checkout), `~/.hermes/tools`
(pinned uv), `~/.local/bin/hermes`, a local install receipt under
`~/.hermes/telemetry/shared_metrics/pending_installs` (sent only if shared
metrics are on), `~/.hermes/{.env,config.yaml}` only when missing, and
`brew install git` if git were missing. Its post-install maintenance syncs
bundled skills, migrates `config.yaml` to the new version and installs
default plugins.

- **Model:** the CLIProxyAPI gateway as the custom provider `cliproxy`
  (`anthropic_messages`): Sonnet for chat and the monitor, Haiku for titles. The
  side tasks (vision, compression, background review, curator) are pinned to
  `cliproxy` too and the config check restores them: `provider: main` resolved to a
  generic "custom" provider without an endpoint, so vision failed with "connection
  error on custom". Images pass through CLIProxy and Headroom (tested 2026-11-21).
- **Secrets:** `pass` is the source of truth; activation copies each entry
  into the login Keychain (`security -i` on stdin, read back to check, an
  empty or missing entry never overwrites). Rebuild from the console session:
  over SSH the Keychain may refuse the write and activation says so.

  | pass entry | Keychain service/account | read by |
  |---|---|---|
  | `ai/cliproxyapi-key` | `hermes-agent/cliproxy-api-key` | Hermes (`secrets.command`) |
  | `hermes/slack-bot-token` (xoxb) | `hermes-agent/slack-bot-token` | Hermes, dead-man check, the personal MCP server (July's own Slack messages) |
  | `hermes/slack-app-token` (xapp) | `hermes-agent/slack-app-token` | Hermes |
  | `hermes/slack-owner-id` (`U…`) | `hermes-agent/slack-owner-id` | Hermes (`SLACK_ALLOWED_USERS`), dead-man check |
  | `hermes/slack-user-token` (xoxp) | `inbox-monitor/slack-user-token` | the inbox and personal MCP servers (inside their processes) |
  | `hermes/api-server-key` | `hermes-agent/api-server-key` | Hermes (`API_SERVER_KEY`), the 8443 publishing check |
  | `hermes/dashboard-password` | `hermes-agent/dashboard-password-hash` (scrypt hash) | Hermes dashboard sign-in |
  | `hermes/dashboard-session-token` (32+ chars) | `hermes-agent/dashboard-session-token` | Hermes dashboard token-mode sign-in (`HERMES_DASHBOARD_SESSION_TOKEN`) |

  No secret is in `~/.hermes/.env`, `config.yaml` or the Nix store (the
  dashboard's API-keys page could write one into `.env`;
  `hermes-config-check` reports it). Not
  secret but personal: the owner's Slack id is in `config.yaml`
  (admin gating) and the colleagues' ids are in the secrets helper, both in
  the local Nix store from the private overlay; neither is in the public repo. After adding or rotating a token: rebuild (or run
  `hermes-keychain-sync` at the console), then `hermes gateway restart`
  (between monitor cycles).
  The sync prints one line per item it changes and a summary ("N updated, M
  unchanged, K failed, S missing"), and writes the same, without values, to
  `~/.local/state/hermes-keychain-sync.log`. An entry it can't decrypt (gpg
  passphrase prompt not answered) is reported as failed and the rebuild says
  so; before 2026-11-20 that case printed only "pass entry … not found", which
  is how a rotated Slack user token once stayed stale.
- **Start:** Hermes' job runs the gateway through `/usr/bin/osascript` (its
  Local Network wrapper), so macOS attributes the monitor's Reminders
  automation to osascript (allowed in Privacy & Security → Automation). Until
  2026-11 a `/bin/zsh` wrapper (Keychain preflight, "zsh" in TCC) did this; a
  locked Keychain now only means the gateway starts without its keys until
  the next restart, which the dead-man reports.
- **Access (accepted risk):** chat sessions get every toolset Hermes ships
  for Slack, terminal and files included, on the local backend as the owner's
  macOS user, by the owner's choice. A chat turn can therefore read the
  Keychain items above, change files and send data anywhere; approvals
  (`approvals.mode: smart`, the owner's choice on 2026-11-23 so colleagues'
  code exploration doesn't wait for him: the `auxiliary.approval` model, Sonnet
  via the gateway, approves low-risk commands, denies clearly dangerous ones and
  escalates the rest to the owner; `approvals.smart_policy` makes it always escalate data egress, secret reads, installs, git push/merge and cluster, cloud or database changes) are a heuristic for dangerous commands, not a
  boundary. The guards that remain: only `SLACK_ALLOWED_USERS` (the owner and
  the listed colleagues) is answered and other DMs are ignored; cron jobs never
  auto-approve; chat is offered only the `personal` MCP server, not the
  monitor's `inbox` server (its terminal could still run that code directly,
  which is part of the accepted risk); the monitor's code and skill are read-only in
  the Nix store, so they can't be rewritten by accident. With the mutable
  install a chat turn or the dashboard can also change `config.yaml`, install
  plugins or run `hermes update`; `hermes-config-check` restores the
  security rules within seconds (or at worst 30 minutes) and the rest at the
  next rebuild. Keeping `inbox` out of chat is tool-list hygiene, not a
  boundary: a chat turn's terminal can edit `config.yaml` or run
  `inbox_mcp.py` itself.
- **Inbox monitor:** `hermes/inbox-monitor/` (code, generic skill, README).
  Everything personal (the owner's names, ids, lists, query templates, known
  not-tasks) is in `~/.local/state/inbox-monitor/config.json` (0600) and
  reaches the model through the `window` tool, so nothing personal is in the
  repo or the world-readable store. Run `hermes-inbox-jobs` after the first
  switch: it creates the monitor job paused (every 5 min, Sonnet, toolset
  `mcp-inbox` only, its response and failure notices kept local) and the
  daily prune job, removes the retired `inbox-digest` job, and checks them;
  rerun it any time to correct them. Reminders are the monitor's only output
  (no Slack summary). `hermes cron resume inbox-monitor` starts it. The
  monitor skips messages from `config.json` `exclude_users` (July's own bot
  user, so its channel replies never become reminders) and
  `exclude_channels` (July's DM with the owner).
- **Slack app:** `hermes/slack-manifest.json`, the full `hermes slack manifest
  --agent-view` output for the existing app "July" (slash commands without
  request URLs, which Socket Mode doesn't need; files, group DMs, reactions). July answers in DMs, in Slack's agent view
  ("Agents & AI apps" must be on for the workspace) and in channels it is
  invited to when @mentioned (`slack.require_mention`, no free-response
  channels); only `SLACK_ALLOWED_USERS` (the owner and the listed colleagues)
  is answered anywhere.
  Hermes subscribes to `message.channels`/`message.groups` so it can follow up
  in a thread it was mentioned in, so the gateway receives every message in
  the channels July is invited to (it answers none of them unprompted). In a
  channel thread Hermes adds up to 30 earlier thread messages as context;
  messages from people outside the allowlist are tagged `[unverified]` and
  the model is told not to follow them, which is a prompt-level guard only.
  User scopes cover the monitor's search, history and reactions.
  Messages the owner posts through another Slack app with their user token
  (the Claude app: they carry `app_id` and no `client_msg_id`) look like bot
  messages to Hermes and used to be dropped. The config check therefore
  keeps `platforms.slack.extra.api_human_users` at the owner's member id
  (`dotfiles.ai.hermes.ownerSlackId`, private overlay), so the owner's API
  posts count as human. It covers only the owner; colleagues who post that
  way are still dropped. Trust: anything that posts with the owner's user
  token (Claude app sessions, any other app the owner authorised, or
  anyone holding that token) is now treated as the owner, who is
  July's Slack admin (`/approve`, `/deny`).
  `SLACK_HOME_CHANNEL` is July's DM with the owner
  (`dotfiles.ai.hermes.slackHomeChannel`).
- **Dashboard:** with `dotfiles.ai.hermes.dashboardPublicUrl` (private
  overlay) set, `hermes dashboard` runs as `com.ksotis.hermes-dashboard`
  on 127.0.0.1:9119 and activation maps the tailnet URL to it with
  `tailscale serve --https=443` (tailnet only, never Funnel; an existing,
  different mapping on 443 is left alone with a warning). The non-loopback
  `dashboard.public_url` engages the sign-in gate on the loopback listener;
  sign-in is the bundled password provider (user = the macOS user name,
  password from `pass hermes/dashboard-password`, hashed in Hermes' scrypt
  format (`hermes-dashboard-password.py`) at activation into the Keychain item
  `hermes-agent/dashboard-password-hash`, kept while it still matches and the
  dashboard restarted when it changes; a random token-signing secret in
  `hermes-agent/dashboard-session-secret`). Without the hash the dashboard
  refuses to start. Sessions: access tokens last 12 hours, refresh tokens 30
  days. The provider signs them with a key derived from the username, the
  password hash and the secret, so changing the password (rebuild, which
  restarts the dashboard) ends every existing sign-in. To end them without
  changing the password, delete the secret
  (`security delete-generic-password -s hermes-agent -a dashboard-session-secret`),
  rebuild, and `launchctl kickstart -k gui/$UID/com.ksotis.hermes-dashboard`.
  Turning the dashboard off removes the tailscale serve mapping only if it is
  exactly ours; if `tailscale serve status` can't be read, nothing is changed.
  Checked: the login page, `/api/config`, `/api/env`,
  `/api/sessions` and `/api/ws` answer 302/401 without a session, a wrong
  password gets 401, an unknown `Host` gets 400. `/api/status` stays
  public by Hermes' design (version, gateway state, profile names; no
  config or secrets). The dashboard's Config and API-keys pages write
  `config.yaml` and `~/.hermes/.env`: changes to our rules are restored by
  the check (security subset at once, the rest at the next rebuild), anything else
  stays; secrets don't belong in `.env` here. Phone: open the URL in a
  browser with Tailscale on; there is no first-party Hermes mobile app in
  v0.23.3. Hermes Desktop (macOS) can attach to it under Settings →
  Connections as a remote gateway.
- **API server:** with `dotfiles.ai.hermes.apiServer` the gateway also runs
  Hermes' OpenAI-compatible API server (`/v1/chat/completions`, `/v1/responses`,
  `/v1/runs`, `/api/jobs`, `/api/sessions`, …) on 127.0.0.1:8642, published on
  the tailnet at `https://<dashboard host>:8443` by the same tailscale serve
  logic (never Funnel). Token-mode clients (Hermes Desktop's remote gateway,
  the Nous mobile app's Bot Mode) sign in to the dashboard backend with
  `HERMES_DASHBOARD_SESSION_TOKEN` (pass `hermes/dashboard-session-token`, at
  least 32 characters from the keychain-sync charset, e.g. `openssl rand -hex
  32`): bearer on REST and `?token=` on `/api/ws`. It works next to the
  password sign-in, and `hermes dashboard` includes everything `hermes serve`
  offers, so the same backend serves both. In the app: backend address
  `https://<dashboard host>` (no port), auth "Session token". The dashboard
  URL itself (port 443) also routes `/v1`
  to the API server, so one URL serves both: the Nous mobile app's chat uses
  `/v1/…` with the API key, and its Bot Mode signs in to the dashboard there.
  On 443 only `/v1/*` reaches the API server; its `/api/*` and `/health`
  routes are shadowed by the dashboard's, so clients that need them use 8443. Every request needs `Authorization: Bearer <key>`; the
  key is `pass hermes/api-server-key` → Keychain `hermes-agent/api-server-key`
  → `API_SERVER_KEY` via secrets.command, and the API server refuses to start
  without it. `/health` answers without a key. API sessions get Hermes' API
  toolset plus the `personal` MCP server. The key must be at least 16
  characters from `A-Za-z0-9._~+/=-` (what `hermes-keychain-sync` accepts),
  e.g. `openssl rand -hex 32`; without it in the Keychain the 8443 mapping is
  removed. The key is full remote control of the agent,
  including its cron jobs (the Jobs API can edit or run the inbox monitor):
  treat it like the dashboard password. Rotate: `pass insert -f
  hermes/api-server-key`, `hermes-keychain-sync`, `hermes gateway restart`.
- **Colleagues (owner's choice):** `dotfiles.ai.hermes.colleagueSlackIds`
  (private overlay) are added to `SLACK_ALLOWED_USERS` next to the owner. They
  get the same agent as the owner: every tool, the terminal, the `personal`
  data server and the owner's accounts, in the same Hermes profile (a separate
  profile would only separate memory and persona, so it isn't used). Each person has their own
  sessions (DMs per user; `group_sessions_per_user` keeps channel sessions
  per user too), but built-in memory is per profile, so `MEMORY.md` and
  `USER.md` (which describes the owner) are shared; the persona tells July
  that USER.md is the owner's. Colleagues are regular users for slash
  commands (`slack.user_allowed_commands`: chat and session commands only)
  and the owner is the only admin (`allow_admin_from`), so only the owner can
  run `/approve` or `/deny`, i.e. answer a dangerous-command approval, even
  for a colleague's own command (`approvals.approvers` stays at its default,
  because a narrowed list always lets the requester approve). This is not a
  security boundary against a colleague: July's terminal runs as the owner's
  macOS user, so a colleague can have it read the Keychain (the API key, the
  Slack user token, the dashboard secrets), call the API server at
  127.0.0.1:8642 (where host-side approvals apply), or edit the monitor's
  state and code. That follows from giving colleagues the terminal.
- **No code changes (an instruction, not enforced):** July's persona
  (`dotfiles.ai.hermes.soulFile` → `~/.hermes/SOUL.md`; `hermes-config-check
  --fix` at each rebuild installs it when the live file is missing or is
  still exactly the copy it installed last, whose hash is kept in
  `~/.local/state/inbox-monitor/.soul-installed`. A live file edited by hand
  is left alone: `hermes-config-check` (without `--quiet`) notes it so you
  can merge by hand. Hashes are over the file's bytes. The live file is
  hashed again right before the rename, so an edit saved during a run
  survives; only a save in the instant between that check and the rename
  could be lost. A missing file is seeded with `link()`, which never
  replaces one. Runs take a lock, so activation's `--fix` and launchd's
  `--auto` don't interleave, and temp files have unique names. Tests:
  `/usr/bin/python3 -I -B nixpkgs/home-manager/ai/tests/test_hermes_config_check_soul.py`. A live file seeded before the hash was kept, or
  copied in by hand, counts as edited until it equals the overlay once: copy
  the overlay over it (`install -m 600 <store SOUL.md> ~/.hermes/SOUL.md`)
  after checking the diff, and the next rebuild records its hash. The
  AppMan support
  assistant) tells it never to write, change or commit code or open PRs itself
  (it may start a coding task session, below);
  reading code to answer is fine. By the owner's choice nothing enforces this:
  everyone, colleagues included, has the terminal and the file tools, which
  can edit and commit anything the macOS user can.
- **Coding tasks in herdr (`july-task`):** with
  `dotfiles.ai.hermes.taskProjects` (private overlay: name -> repo or folder of
  repos) July may start a Claude Code main session for a coding task, though
  it still writes no code itself. Code: `hermes/inbox-monitor/july_task.py`,
  installed as the `july-task` command, plus the launchd monitor
  `com.ksotis.july-tasks` (every minute, log `~/Library/Logs/july-tasks.log`).
  State: `~/.local/state/july-tasks/tasks.json` (0600, locked). If it ever
  stops parsing, repair it in place, or stop the tasks first. Moving it away
  while sessions run makes the monitor remove their terminals as orphans.
  - **Start:** after the requester confirms the project and the exact task
    text, July writes the text with its file tool to a new file in
    `~/.cache/july-task-input/` and runs `july-task start <project> [--repo
    <dir>] --file <file>` in its terminal. The CLI reads the file and removes it.
    The file must sit inside that folder (real path checked), be opened
    without following a link, and be the caller's own regular file of at most
    64 KB. The same holds for `--file` on `send`, `post`, `ask`, `done` and `blocked`. The
    folder is kept at mode 0700. A heredoc
    isn't used: a line of the task text could end it and run the rest as shell.
    By the owner's decision, `approvals.smart_policy` approves `july-task`
    commands without him (the CLI enforces its own allowlist, cap and secret
    checks). This applies only when the whole command line is a single
    `july-task` invocation or a single write of a file under
    `~/.cache/july-task-input`, with no other command, pipe, `;`, `&&`, `||`,
    substitution or redirection. Chained commands are judged by the normal
    rules, and the approval model escalates when unsure. Setting or unsetting
    `HERMES_SESSION_*` or `HC_*` variables (`env -u` included) is always
    escalated, and the ESCALATE rules win. Hermes passes each turn's Slack context to terminal
    commands as `HERMES_SESSION_*` (platform, chat, thread ts, actor), so the
    CLI takes the requester and the thread from there, not from the model.
    Only `HERMES_SESSION_ACTOR_ID` names the sender, never `USER_ID`: in a
    shared thread Hermes blanks the actor when a second person's message folds
    into a running turn, while `USER_ID` stays the first sender. With a blank
    actor ("mixed senders") `start`, `stop` and `status` refuse, and `send`
    relays the message labelled "sender unknown: not a go", and only to the
    thread's own task (a `--task` naming another task is refused).
    It refuses people outside the owner and colleague list, unknown projects,
    text that looks like a secret, a second running task in the same thread,
    and a fourth running task. It starts `~/.local/bin/claude --model opus
    --permission-mode auto -n july-<project>-<4 hex> --session-id <uuid>
    "<brief>"` with `hc run --bg --no-parent --outlive-parent --label
    july-task=1 --label july-launch=<random id>` in the project. The launch id
    ties every terminal to this launch. The brief tells the session to put the
    same label on each terminal it starts. Nothing is killed, typed into or
    trusted without that label (below). The absolute path keeps hc from reading the
    command as a template. The terminal's address is saved right after `hc run`. If the launcher dies
    before that, the monitor finds the terminal by its launch label.
    Then it waits up to 120 s for the first message to land (Hermes' terminal
    tool allows a command 180 s). If the command dies midway, the monitor takes
    over: after about 4 minutes it adopts a session whose first message arrived,
    posting the start message, and removes one whose message didn't. It also
    removes labelled task terminals whose launch id no task knows once they
    are 10 minutes old. A send during startup is refused until it finishes. The
    folder a task runs in must resolve (`git rev-parse --show-toplevel`) to a
    git repo inside the selected project; otherwise `start` refuses before
    anything is launched. A `.git` entry alone isn't enough (a broken
    worktree pointer fails), and neither is a project folder inside a bigger
    repo. For a project that is a folder of repos (saas, bmw) this means
    `--repo <path to the repo>`, for example `--repo billing/mac-exchange`,
    and the persona tells July to always pass one. A linked worktree counts as
    its own repo.
    A `stop` that lands while `start` is still launching
    marks the task stopped, and `start` then removes the new terminal itself.
    Task ids must be `july-<configured project>-<4 hex>`, so a helper such as
    `july-pcs-ab12-feed` never passes for one. The task text sits between delimiters with a random
    nonce, and display names are reduced to one plain line.
    The brief holds the task and the rules: follow `~/.claude/CLAUDE.md`, work
    autonomously, report through `july-task`, never post secrets, and stop at
    "PR opened and reviews done" without merging (below). A whole `start`, tab
    work included, stays under 165 s: Hermes gives a terminal command 180 s,
    and the start wait and tab work are cut to fit.
    Folder trust: Claude Code has no supported way to trust a folder for an
    interactive session (only `-p` skips the question), so before the launch
    July runs the owner's own `claude-trust-repo` (claude.nix), the helper his
    `claude` shell wrapper runs at every start. July passes the toplevel it
    validated above. Afterwards it reads `~/.claude.json` back (read-only),
    and if a folder other than exactly that toplevel became trusted under one
    of the OTHER mapped projects, the start fails before launch. Anywhere
    else, such as the owner trusting a repo by hand at the same moment, it is
    only logged. An already-trusted repo skips the helper. The helper marks a git repo trusted in
    `~/.claude.json` only if its GitHub owner is on
    `dotfiles.ai.claude.trustedRepoOwners`; every mapped repo is under
    appman-agm, which is on that list. It writes with jq and an atomic rename,
    as the wrapper always has, so the race with a running Claude Code saving
    the same file is the one the owner already accepts. Checked 2026-11-23:
    a subrepo whose `.claude/settings.local.json` pre-approves permissions
    started straight to idle after it. July never presses keys in a dialog.
    (Until 2026-11-23 it answered the trust screen with `down`/`enter`, which
    raced the screen's redraws and dropped keys.) A dialog that stays up for
    10 s (within the 120 s start budget) fails the start with a fixed
    description: "Claude's folder-trust question" (repo not trusted, e.g. an
    owner outside the list or not a git repo), "a login/auth dialog", "an MCP
    approval dialog" or "an unknown dialog". Never its text, which could hold
    a device code. hc errors carry only hc's error kind and exit code, never
    its output. July then posts
    a start message in the thread. When a colleague started the task, the owner
    gets a one-line DM.
  - **Autonomous, with takeover in herdr (owner's choice, 2026-11-23):** a
    task never waits for anyone in Slack. The brief tells the session to work
    on its own, make reasonable assumptions, list them in its result, and not
    ask and wait. It reports to its own thread as July:
    - `july-task post "<text>"`: an optional one-line milestone.
    - `july-task done "<summary>"`: the result once (what changed, PR link,
      both review stages, assumptions, what wasn't verified).
    - `july-task blocked "<what's needed>"`: only for something only a person
      can resolve (a decision for the owner, credentials, a login, a dialog).
      It is one line that mentions the owner and says "answer here or in its
      herdr tab". The session then stays idle and never polls Slack;
      whichever channel answers first wins.
    - `ask` is kept only as an alias of `post`, a note that doesn't block.
    - `--file` works for all of them. The task is found by the session's
      `$HC_TERMINAL_ID` and checked against that terminal's name and launch
      label, so a reused address can't post into an older task's thread.
    After `done` or `blocked` the task is `waiting`: it stays in its tab in the
    owner's Herdr app. He decides in either place: typing into the session
    there (takeover), or replying in the thread. July relays his reply with
    `send`.
  - **States:** `starting`, then `running` (working on its own), then `waiting`
    (reported done or blocked, or idle 15 min after a turn that posted
    nothing), then `takeover` (the owner typed into its tab). A waiting task
    whose session starts working again, e.g. its reviewer reported back, is
    `running` again. `stop` or a closed terminal ends it (`stopped`,
    `closed`, `failed`).
    - Only `starting` and `running` count toward the limit of 3, so tasks
      waiting for takeover don't block new ones. Taken-over tasks don't count
      either: the owner drives them. A waiting task that resumes on its own
      (its reviewer reported back) counts again. It can't be paused, so the
      count can briefly exceed 3, and new starts are refused until it's under.
      A second limit covers open tasks in any state (10): each idle one keeps
      a Claude session open, so a start beyond it is refused with the idle
      ones listed for `stop`. One task per thread still holds while a task is
      alive in any state.
    - Takeover is read from the Claude transcript: an input after the brief
      that doesn't come from July (`[Slack reply from …]`), hc workers
      (`<hc …>`) or teammates or tools (`<teammate-message>`, `<task-notification>`,
      `<system-reminder>`, `<local-command…>`, `<command-…>`) counts as the
      owner. So do his `!` shell commands (`<bash-input>`/`<bash-stdout>`
      entries). Compaction summaries (`isCompactSummary`, or text starting
      "This session is being continued…") and `isMeta` entries don't count.
      hc has no attach or keystroke signal, so this is a heuristic, and it
      only decides what July relays (nothing during a takeover) and who may
      stop the task: once taken over, only the owner can. It never decides
      what gets closed.
  - **Decisions and the merge gate, from herdr or Slack (owner's decision):**
    the session never merges, deploys, releases or pushes to a shared branch on
    its own. That holds also for the owner's own tasks, and whatever the
    repo's `.claude/settings*.json` pre-approves. It stops at "PR opened and
    reviews done", posts that once with `done`, and waits.
    - A decision or a merge go counts when the owner types it into the session
      in its herdr tab as a new message of his own, or when `july-task
      owner-go` lists his Slack reply saying it. A compaction summary, or
      anything that only restates an earlier go, is not a go; the brief says
      to ask again after a compaction.
    - What is enforced vs only instructed: nothing technical tells the
      owner's typing apart from other untagged input in the session. July's
      own terminal could type into it with plain `hc send`. So the smart
      approval policy escalates every `hc` command that types into, starts,
      stops or attaches to a terminal or writes core documents (`send`,
      `keys`, `run`, `kill`, `rm`, `interrupt`, `attach`, `connect`, `put`,
      `label`, `keep`, `file write/edit`, `exec`), and every `herdr` command
      that changes panes, tabs or workspaces. The single `july-task`
      invocations stay approved, since `july-task` drives hc itself with its
      own checks. The persona tells July to reach task sessions only through
      `july-task`. That escalation is a judgment by the approval model, and the
      merge rule itself is an instruction to the session, so neither is a hard
      boundary.
    - `owner-go` reads the thread from Slack with the bot token
      (`conversations.replies`). It lists, in full, only replies posted after
      the session's last `done`/`blocked` note whose Slack `user` is the
      owner's member id: not edited, no `bot_id`, no `app_id`, plain messages
      or ones also sent to the channel (`thread_broadcast`). The task records
      that note's ts.
    - If owner-go can't read every page (more than 100, or `has_more` without
      a cursor), it fails and assumes no go.
    - A relayed `[Slack reply from …]` line is not proof on its own: the brief
      tells the session to check with `owner-go`. Slack's own record is the
      proof, so a forged `HERMES_SESSION_ACTOR_ID` on `send` can't make one.
    - App-posted owner messages, for example from the Claude app, don't count:
      the task session holds the owner's Slack tools and could post a "go" as
      him.
    - A colleague's go never counts.
    - This is still an instruction to the session, not enforcement: it runs as
      the owner and could merge anyway.
  - **Monitor:** it reads the Claude transcript
    (`~/.claude/projects/*/<session-id>.jsonl`) incrementally and calls `hc
    get` per task, without an LLM.
    - When a running session ends a turn without posting and stays idle for
      15 min, it relays the turn's first line once ("… (more in its herdr
      tab)") and sets the task `waiting`. The 15 min are long enough that a
      session waiting for its reviewer isn't relayed. It doesn't relay when
      the session's last post came after its last tool call. Subagent
      (sidechain) entries are skipped. A reply that looks like it holds a
      secret is never stored: the state keeps only a flag and the message id,
      and the thread gets a "withheld" note.
    - A session at a dialog for 2 minutes (status blocked/error, not during a
      takeover) gets a one-line thread note, and the owner gets a DM with a
      fixed description of the dialog (never its text) and `hc attach
      <task>`. After 8 h of running the owner gets one DM.
    - Tasks are never closed automatically. A `waiting` or `takeover` task
      idle for 3 days gets one reminder line in its thread per idle stretch.
      A closed or exited terminal ends the task as `closed`: July tidies up
      its helpers and tab and posts one line.
    - Only hc's `not_found` (exit 3) counts as a terminal gone. Any other hc
      failure, such as a core restart, skips the cycle. One broken task record
      is logged and skipped, and the state is saved even when a step fails,
      so a post that went out is never repeated.
    - Thread messages and owner DMs that Slack refuses go into an outbox and
      are retried every minute for a day. Permanent errors
      (`channel_not_found`, `is_archived`, …) are dropped with a log line. The
      retry doesn't hold the state lock over the network.
    - Task records written by an older version in state `done` are read as
      `waiting`.
  - **Messages from the thread:** the requester's later messages reach July as
    usual. July relays the owner's replies unchanged with `july-task send`
    (colleagues' replies as information only). It never blocks the session. It finds the task by thread and takes only the
    requester or the owner. It types only into the task's own terminal while
    that still runs Claude Code (name, launch label, `claude` as the
    program, Claude's status reported). It refuses a session blocked at a
    dialog (`hc send` without `--force`) and a task that is starting or has
    ended. Each message is labelled `(owner)`, `(colleague)` or "sender
    unknown: not a go". A `waiting` task that gets a message is `running`
    again, which counts toward the limit.
    `status`, `list` and `stop` complete the set. `status` (it shows the last
    reply) and `stop` take only the requester or the owner. `list` shows every
    task's id, project, requester and state to anyone on the list. Outside
    Slack (the owner's own terminal) `--task <id>` names the task, and the
    caller counts as the owner.
  - **Cleanup:** only `july-task stop`, or the owner closing the task's
    terminal himself, ends a task. Its terminals are killed first: the task's
    own terminal only if its address, name and launch label all match, or,
    without a saved address, the terminal with the task's name and launch
    label. Helpers go only if named `<task>-…` and either carrying the launch
    label or being direct children of the verified root; a lookalike name
    alone is never enough. Then its tab is removed (below). A failing `hc rm`
    or tab removal is retried every minute. After 3 days of failures July
    gives up, logs what was left, and moves the record to history. Orphans
    are labelled task terminals whose launch id no task knows, removed after
    10 minutes with their helpers. Git worktrees and branches the session
    made are left alone.
  - **Tab in the Herdr app (owner's choice, 2026-11-23):** each task shows up
    as a new tab, named after the task, in its project's workspace in the
    owner's Herdr app on garage. The app keeps its layout in the core as the
    document `herdr-app` (`doc.get`/`doc.set` over `hc connect`; on disk in
    `~/.local/state/herdr-core/default/docs.json`): spaces, then tabs, then a
    tree of blocks that each name a terminal. Parent terminals play no part,
    so the task stays independent of the owner's sessions.
    - When the session is running, `july-task` records the new tab's and
      block's ids in the task first, with state `adding`, and only then writes
      the document. Every tab July writes is known by id; nothing is ever
      found or deleted by name.
    - It finds the project's space: the space named after the project if there
      is one, else one with a terminal labelled `where="<project> / …"`, else
      one with a terminal running under the project root. A space that merely
      holds a terminal working in another project loses to the named one. The
      space's own `folder` is stale and not used.
    - It appends one tab with one block for the task's terminal, and labels
      the terminal like the app does: `herdr.space`, `herdr.tab`,
      `where="<project> / <task id>"`, which is also what the app then writes.
      Label values come only from ids that pass a strict charset check; a space
      id that fails it means no tab. The space id goes into the task state
      (state `added`).
    - Writes are version-checked: when the app wrote in between, the CLI reads
      again and retries (5 times). If hc was unreachable, so it's unknown
      whether a write landed, the task stays `adding`. The next try first looks
      for the tab's id in the document, so it confirms the tab instead of
      writing it twice.
    - It never creates spaces and never touches other tabs or blocks. A missing
      or odd document, a race lost on every retry, or malformed data means no
      tab: only the `where` label, and the running task is never failed by this.
      Each distinct document problem is logged once, not every minute.
    - Cleanup (stop, the monitor's 24 h cleanup, an idle stop) kills the
      session's terminals first, under the state lock. It only marks the tab
      for removal. All document work runs afterwards, outside the lock,
      within a 60 s budget, so `stop` stays fast and never holds other commands
      up.
    - Removal deletes the recorded tab only in the recorded space, only with
      the task's name, and only with exactly the one-row, one-block layout July
      wrote (the app may add a `size` to the block). A tab that was moved,
      renamed or split, or has extra nodes or keys, is left alone and logged;
      that counts as settled.
    - A missing or unreadable document, a lost race or hc being down keeps the
      tab recorded for removal, and the monitor tries again every minute. The
      task record leaves the state only once its terminals and its tab are
      gone.
    - Checked live on 2026-11-23 with a pcs task: the tab appeared in the pcs
      workspace, the app relabelled the terminal `pcs / <task id>`, and after
      the stop the pcs space was identical to before.
  - **Tests:** `/usr/bin/python3 -I hermes/inbox-monitor/tests/test_july_task.py`
    (stdlib unittest, a fake `hc` in `tests/fake_hc.py`; no network,
    terminals or Keychain). The harness `tests/run_cli.py` loads the module
    and swaps its paths and Slack transport from outside. The installed
    script has no `--config` option and reads no test settings from the
    environment. Its config (`july-task.json`) sits next to it in its own
    store folder, so a session can't point it at a fake Slack or another
    owner.
  - **Risk (owner's choice):** the owner and the 12 colleagues can each start
    a coding agent that runs as the owner's macOS user, in the owner's repos
    and with his credentials (git and `gh` as Kittipong, the Keychain, Podman,
    the agent-browser, `~/.claude` settings, MCP servers), in Claude's auto mode,
    where the auto-mode classifier is the only per-action check. A
    colleague's task text becomes that agent's instructions. The agent can
    commit, push branches and open PRs as the owner. Merging, deploying and
    pushing to shared branches are forbidden only by the brief and by
    `~/.claude/CLAUDE.md`, both instructions, not enforcement. The
    requester and thread checks are guards against mix-ups, not a boundary.
    The model writes the command line and could set `HERMES_SESSION_*` itself,
    and a colleague already has July's terminal (above). What limits the risk:
    one confirmed task per thread, at most 3 running, the owner's DM for every
    colleague task, dialogs that only the owner can answer, and every action
    visible in the thread and in the herdr terminal (`hc attach <task>`).
    Trusting a repo at start (`claude-trust-repo`, for mapped projects) also
    loads that repo's `.claude/settings*.json`. Its allow rules, such as
    `Bash(git push:*)`, then run without the auto-mode classifier, and its
    hooks run as the owner. A colleague can thus reach whatever a mapped
    repo's committed settings pre-approve. The brief says such permissions
    don't lift the merge gate (only the owner's own instruction, in the
    session or verified by owner-go from Slack, is a go), but that is an
    instruction too.
- **Colleagues' dangerous commands:** only the owner can approve (above).
  Hermes posts the approval in the chat where it was raised and doesn't
  notify anyone else, so in a colleague's DM with July the owner never sees
  it; the command waits `approvals.timeout` (300 s) and is then denied. In a
  channel the owner is in, the owner can approve it there.
- **Personal data in chat (owner's choice):** chat (Slack, CLI/TUI/Desktop/
  dashboard, API server) gets the `personal` MCP server
  (`hermes/inbox-monitor/personal_mcp.py`): Slack search, threads, history and
  reactions as the owner (the user token stays inside the server), Gmail search,
  messages and threads, Reminders in any list (list, read, create, complete,
  update), GitHub PR state, Gmail attachments and Google Drive files
  (`gmail_attachment`, `drive_search`, `drive_fetch`: saved 0600 under
  `~/.cache/july-attachments` and `~/.cache/july-drive`, text extracted with macOS's
  own PDFKit/textutil and the XLSX XML; password-protected PDFs are reported as
  such), and Slack messages as July itself (`slack_bot_dm` to a
  member id or unique name, `slack_bot_post` to a channel July is in; bot token from
  the Keychain inside the server). Hermes ships no agent-callable send tool, hence
  these two; the persona sends to anyone but the requester only after they confirm
  the exact text. Its output is not masked, and chat sessions are
  kept for good, so whatever chat reads stays in `state.db`. It has none of the
  monitor's bookkeeping: no window/finish/seen/tracked tools, no access to the
  monitor's state, and reminders it creates are not tracked by the monitor.
- **MCP in chat:** Hermes can't exclude a single MCP server from a platform:
  a `platform_toolsets` list either names its MCP servers or gets all of them,
  and a platform with no list gets all of them too. Every chat surface (`slack`,
  `cli`, `api_server`, `acp`, `tui`, `webhook`) therefore has a list naming
  `mcp-personal`, which keeps the monitor's `inbox` server cron-only; to give
  chat another MCP server, add it in the dashboard and name it in those lists
  (the check keeps our entries and leaves yours).
- **Chat workspace:** chat sessions start in
  `dotfiles.ai.hermes.terminalCwd` (the AppMan SaaS workspace). Extra skill
  folders (`dotfiles.ai.hermes.extraSkillDirs`: the workspace's
  `.claude/skills` and a short map of it from the private overlay) and
  Claude Code's `graphify` skill (linked, not copied) are listed in each
  chat's skill index and load on demand; nothing is copied or indexed. Paste it into the app's App Manifest, reinstall, then store the
  tokens and the owner's member id in `pass` (table above) before rebuilding.
- **Dead-man check:** the `com.ksotis.inbox-monitor-deadman` LaunchAgent
  (`hermes/inbox-monitor/deadman.py`, every minute) DMs the owner once when
  the enabled monitor has had no successful cycle for an hour, and once when
  it recovers.
- **Slack safeguard:** the same agent restarts the gateway when Slack stays
  unhealthy. Hermes records a platform's state in `~/.hermes/gateway_state.json`,
  but the Slack adapter's own Socket Mode reconnects never reach that file, so
  the check reads both: a Slack state of retrying, fatal, connecting or
  disconnected, written by the running gateway, and the Socket Mode lines in
  `~/.hermes/logs/agent.log` since the last gateway start (bad: the adapter's
  "Socket Mode unhealthy" and "Socket Mode reconnect failed", slack_bolt's "Failed to connect", "Failed to run
  message listeners", "seems to be already closed"; good: "A new session …
  has been established", "Socket Mode connected"). Bad lines less than 3
  minutes apart are one outage, so a connection that comes back and drops
  again still counts as one. The outage is ongoing while the newest line is
  a bad one and less than 3 minutes old. Only the running gateway counts:
  when the `ai.hermes.gateway` job has no running process (stopped on
  purpose, or during an update) the check does nothing and never starts it,
  and a state-file entry counts only if a process of that job wrote it. After
  5 minutes it runs one `hermes gateway restart` (drains running turns) and
  DMs the owner. The restart is recorded before it runs, so a crash can't
  lead to a second one. The 10-minute verdict window starts when the restart
  (and its drain) has finished. Once Slack is healthy again, that restart
  is settled. If Slack still isn't healthy 10 minutes after the restart, or
  it goes down again for 5 minutes within an hour of the last automatic
  restart, the check stops restarting until Slack has recovered and DMs an
  alert. Slack counts as recovered only after 3 minutes of continuous
  health, so a flapping connection gets one alert, not one per flap. It
  then sends one "connected again" DM, if the alert got through. Failed DMs are retried every minute (the restart notice is
  queued, the alert is resent until it gets through). No more restarts
  happen while they fail, so a network outage longer than an hour still
  gets only one restart. If the check itself fails 10 times in a row, it DMs
  that once (retried until delivered). State: the `slack` key of
  `~/.local/state/inbox-monitor/.deadman.json`. The DMs go through July's own
  bot, so in a real Slack outage they arrive late or not at all.
  Why: on 2026-11-22 from 22:16 to about 22:22, Slack's routine five-hourly
  Socket Mode refresh hit a degraded internet link on garage-hq. The
  `apps.connections.open` connect timed out after 30 s. The inbox MCP's Slack
  calls, the LLM calls through CLIProxy and Gmail were slow or failing at the
  same time, and the Wi-Fi data-stall counter rose. Hermes' watchdog
  rebuilds the Socket Mode handler every 15 s while it reports disconnected,
  which cuts off slow reconnects; upstream PR NousResearch/hermes-agent#96478
  (a grace period) was still open at the time. Known Hermes bugs where only a
  restart helps, such as a reconnect that keeps retrying a closed aiohttp
  session (#85574, #83662), show up as the same log lines.
- **Data:** Slack and email text the monitor reads is masked by its MCP
  server (emails, also percent-encoded; Thai phone numbers in the usual
  separators; 13-digit ids; last 4 characters kept) before Hermes sees it.
  Names are not masked, so work-list titles in the DM can name people. Hermes stores it in `~/.hermes/state.db`
  (sessions, full-text index), `~/.hermes/cron/output/` and
  `~/.hermes/cache/spillover/`; the prune job deletes monitor sessions and
  run documents after 1 day, and all spilled tool output (chat's too) after
  1 day. Chat sessions are kept for good
  (`sessions.auto_prune: false`); `security.redact_secrets` masks key-shaped
  values in chat, logs and tool output. Expected size: about 288 monitor runs
  a day at roughly 50-150 KB each, so 15-45 MB of monitor sessions at any
  time, plus chat history growing with use; SQLite does not shrink the file
  after deletes. Chat's `session_search` can find monitor sessions until they
  are pruned (it can't be scoped by source). The reminders themselves live in
  Reminders (iCloud) until the owner deletes them.
- **Logs:** `~/Library/Logs/hermes-agent{,.err}.log` (capped at 5 MB by the
  prune job), `~/Library/Logs/inbox-monitor-deadman.log`, `~/.hermes/logs/`
  (rotated by Hermes).
