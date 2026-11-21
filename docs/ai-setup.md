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

`nixpkgs/home-manager/ai/hermes.nix`, imported by `nixpkgs/hosts/garage-hq.nix`
with the Home Manager module of the `hermes-agent` flake input. The input is
pinned to the release tag v0.23.3 (released 2026-11-20) and `flake.nix` applies
`nixpkgs/home-manager/ai/hermes-pnpm-macos.patch` (upstream PR #150967, still
open): without it the pnpm dependency hash differs on macOS and the build
fails. Drop the patch once a release contains the fix.

It runs the Hermes gateway, the owner's always-on agent as a Slack DM bot, as
the `org.nix-community.home.hermes-agent` LaunchAgent and writes
`~/.hermes/config.yaml` (0600) from `services.hermes-agent.settings` on every
rebuild.

- **Model:** the CLIProxyAPI gateway as the custom provider `cliproxy`
  (`anthropic_messages`): Sonnet for chat and the monitor, Haiku for titles.
- **Secrets:** `pass` is the source of truth; activation copies each entry
  into the login Keychain (`security -i` on stdin, read back to check, an
  empty or missing entry never overwrites). Rebuild from the console session:
  over SSH the Keychain may refuse the write and activation says so.

  | pass entry | Keychain service/account | read by |
  |---|---|---|
  | `ai/cliproxyapi-key` | `hermes-agent/cliproxy-api-key` | Hermes (`secrets.command`) |
  | `hermes/slack-bot-token` (xoxb) | `hermes-agent/slack-bot-token` | Hermes, dead-man check |
  | `hermes/slack-app-token` (xapp) | `hermes-agent/slack-app-token` | Hermes |
  | `hermes/slack-owner-id` (`U…`) | `hermes-agent/slack-owner-id` | Hermes (`SLACK_ALLOWED_USERS`), dead-man check |
  | `hermes/slack-user-token` (xoxp) | `inbox-monitor/slack-user-token` | the inbox and personal MCP servers (inside their processes) |
  | `hermes/api-server-key` | `hermes-agent/api-server-key` | Hermes (`API_SERVER_KEY`), the 8443 publishing check |
  | `hermes/dashboard-password` | `hermes-agent/dashboard-password-hash` (scrypt hash) | Hermes dashboard sign-in |

  No secret is in `~/.hermes/.env`, `config.yaml` or the Nix store. Not
  secret but personal: the owner's Slack id is in the generated `config.yaml`
  (admin gating) and the colleagues' ids are in the secrets helper, both in
  the local Nix store from the private overlay; neither is in the public repo. After adding or rotating a token: rebuild (or run
  `hermes-keychain-sync` at the console), then
  `launchctl kickstart -k gui/$UID/org.nix-community.home.hermes-agent`.
  The sync prints one line per item it changes and a summary ("N updated, M
  unchanged, K failed, S missing"), and writes the same, without values, to
  `~/.local/state/hermes-keychain-sync.log`. An entry it can't decrypt (gpg
  passphrase prompt not answered) is reported as failed and the rebuild says
  so; before 2026-11-20 that case printed only "pass entry … not found", which
  is how a rotated Slack user token once stayed stale.
- **Start:** launchd runs `/bin/zsh`, which waits until the Keychain answers
  (exit 75 and a launchd retry every 30 s otherwise), starts the gateway as
  its child and forwards TERM/INT/HUP to that pid. zsh stays the job's root
  process, so macOS attributes the monitor's Reminders automation to "zsh"
  (allowed once in Privacy & Security → Automation) and not to a nix-store
  Python that changes with every update.
- **Access (accepted risk):** chat sessions get every toolset Hermes ships
  for Slack, terminal and files included, on the local backend as the owner's
  macOS user, by the owner's choice. A chat turn can therefore read the
  Keychain items above, change files and send data anywhere; approvals
  (`approvals.mode: manual`) are a heuristic for dangerous commands, not a
  boundary. The guards that remain: only `SLACK_ALLOWED_USERS` (the owner and
  the listed colleagues) is answered and other DMs are ignored; cron jobs never
  auto-approve; chat is offered only the `personal` MCP server, not the
  monitor's `inbox` server (its terminal could still run that code directly,
  which is part of the accepted risk); the monitor's code and skill are read-only in
  the Nix store, so they can't be rewritten by accident.
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
  `SLACK_HOME_CHANNEL` is July's DM with the owner
  (`dotfiles.ai.hermes.slackHomeChannel`).
- **Dashboard:** with `dotfiles.ai.hermes.dashboardPublicUrl` (private
  overlay) set, `hermes dashboard` runs as `org.nix-community.home.hermes-backend`
  on 127.0.0.1:9119 and activation maps the tailnet URL to it with
  `tailscale serve --https=443` (tailnet only, never Funnel; an existing,
  different mapping on 443 is left alone with a warning). The non-loopback
  `dashboard.public_url` engages the sign-in gate on the loopback listener;
  sign-in is the bundled password provider (user = the macOS user name,
  password from `pass hermes/dashboard-password`, hashed with Hermes' scrypt
  helper at activation into the Keychain item
  `hermes-agent/dashboard-password-hash`, kept while it still matches and the
  dashboard restarted when it changes; a random token-signing secret in
  `hermes-agent/dashboard-session-secret`). Without the hash the dashboard
  refuses to start. Sessions: access tokens last 12 hours, refresh tokens 30
  days. The provider signs them with a key derived from the username, the
  password hash and the secret, so changing the password (rebuild, which
  restarts the dashboard) ends every existing sign-in. To end them without
  changing the password, delete the secret
  (`security delete-generic-password -s hermes-agent -a dashboard-session-secret`),
  rebuild, and `launchctl kickstart -k gui/$UID/org.nix-community.home.hermes-backend`.
  Turning the dashboard off removes the tailscale serve mapping only if it is
  exactly ours; if `tailscale serve status` can't be read, nothing is changed.
  Checked: the login page, `/api/config`, `/api/env`,
  `/api/sessions` and `/api/ws` answer 302/401 without a session, a wrong
  password gets 401, an unknown `Host` gets 400. `/api/status` stays
  public by Hermes' design (version, gateway state, profile names; no
  config or secrets). The dashboard's Config and API-keys pages write
  `config.yaml` and `~/.hermes/.env`: a rebuild overwrites the keys Nix
  declares there (other keys survive), and secrets don't belong in `.env`
  here, so change settings in this repo instead. Phone: open the URL in a
  browser with Tailscale on; there is no first-party Hermes mobile app in
  v0.23.3. Hermes Desktop (macOS) can attach to it under Settings →
  Connections as a remote gateway.
- **API server:** with `dotfiles.ai.hermes.apiServer` the gateway also runs
  Hermes' OpenAI-compatible API server (`/v1/chat/completions`, `/v1/responses`,
  `/v1/runs`, `/api/jobs`, `/api/sessions`, …) on 127.0.0.1:8642, published on
  the tailnet at `https://<dashboard host>:8443` by the same tailscale serve
  logic (never Funnel). The dashboard URL itself (port 443) also routes `/v1`
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
  hermes/api-server-key`, `hermes-keychain-sync`, kickstart the gateway.
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
  (`dotfiles.ai.hermes.soulFile` → `~/.hermes/SOUL.md`, the AppMan support
  assistant) tells it never to write, change or commit code or open PRs;
  reading code to answer is fine. By the owner's choice nothing enforces this:
  everyone, colleagues included, has the terminal and the file tools, which
  can edit and commit anything the macOS user can.
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
  update), and GitHub PR state. Its output is not masked, and chat sessions are
  kept for good, so whatever chat reads stays in `state.db`. It has none of the
  monitor's bookkeeping: no window/finish/seen/tracked tools, no access to the
  monitor's state, and reminders it creates are not tracked by the monitor.
- **MCP in chat:** Hermes can't exclude a single MCP server from a platform:
  a `platform_toolsets` list either names its MCP servers or gets all of them.
  The chat lists name `mcp-personal`, which keeps the monitor's `inbox` server
  cron-only; to give chat another MCP server, add it to `mcp_servers` and name
  it in the `slack`, `cli` and `api_server` lists too.
- **Chat workspace:** chat sessions start in
  `dotfiles.ai.hermes.terminalCwd` (the AppMan SaaS workspace). Extra skill
  folders (`dotfiles.ai.hermes.extraSkillDirs`: the workspace's
  `.claude/skills` and a short map of it from the private overlay) and
  Claude Code's `graphify` skill (linked, not copied) are listed in each
  chat's skill index and load on demand; nothing is copied or indexed. Paste it into the app's App Manifest, reinstall, then store the
  tokens and the owner's member id in `pass` (table above) before rebuilding.
- **Dead-man check:** the `com.ksotis.inbox-monitor-deadman` LaunchAgent
  (every 30 min) DMs the owner once when the enabled monitor has had no
  successful cycle for an hour, and once when it recovers.
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
