# AI setup

What the `nixpkgs/home-manager/ai/` modules manage, and the manual steps on a
new Mac.

## Layers

- **Public (this repo):** Claude Code instructions, agents, hooks and own
  skills (`claude/`), generic Claude Code settings (`claude/settings.base.json`),
  generic Codex settings (`codex/config.base.toml`), the Headroom LaunchAgent,
  Homebrew packages, and the `ai-bootstrap` command.
- **Private (`~/workspace/dotfiles-private`, a separate private repo):** the
  gateway model and proxy URL, plugin config with internal URLs, Codex project
  trust entries, per-project MCP servers, and the CLIProxyAPI config template.
  It sets the `dotfiles.ai.*` options (see `nixpkgs/home-manager/ai/default.nix`).
  Secrets stay in `pass` and are read at activation.

The flake's `private` input defaults to the empty `private-stub/`, so the
public repo evaluates on its own. `rebuild` (zsh function) overrides it with
the private checkout when it exists:

```sh
sudo darwin-rebuild switch --flake ~/workspace/dotfiles \
  --override-input private path:$HOME/workspace/dotfiles-private
```

## What a rebuild does

- Links `~/.claude/{CLAUDE.md,onboarding.md}`, `~/.claude/agents/*.md`,
  `~/.claude/hooks/*` and `~/.claude/skills/<own skill>/SKILL.md` to the files
  in the checkout at `~/workspace/dotfiles/claude/` (not the Nix store), so
  editing them in place edits the repo. Live files that were real files are
  moved to `~/.claude/backups/dotfiles-<timestamp>/` first.
- Links `~/.claude/skills/agent-browser/SKILL.md` to the skill that ships with
  the Homebrew `agent-browser` CLI.
- Merges `~/.claude/settings.json`: live file ← `claude/settings.base.json` ←
  private overlays ← secrets from `pass`. Keys from the repo win; anything else
  Claude Code wrote stays. The previous file is copied to
  `~/.claude/backups/settings.json.dotfiles-<timestamp>` when it changes. If
  `jq` or `pass` fails, the file is left alone with a warning. Run
  `claude-settings-merge` to redo it by hand. Removing a key from the base
  JSON does not remove it from the live file.
- Merges `~/.codex/config.toml` the same way (`codex/config.base.toml` ←
  private overlay), backing up to `~/.codex/backups/`. `codex-config-sync`
  redoes it by hand.
- Writes `/opt/homebrew/etc/cliproxyapi.conf` from the private template, only
  if the file doesn't exist yet (CLIProxyAPI rewrites it itself).
- Installs `agent-browser`, `googleworkspace-cli` (`gws`) and `cliproxyapi`
  (started as a brew service) with Homebrew, and runs the Headroom proxy as
  the `ai.headroom.proxy` LaunchAgent. To drop Headroom, remove the
  `ai/headroom.nix` line from `flake.nix` (and the `plugins.configs.headroom`
  block from the CLIProxyAPI config).

`settings.json` keys the public layer manages: `$schema`, `env.*` (agent
teams, function hooks, timeouts, context and autocompact limits, telemetry
off, claude.ai MCP servers off), `permissions.deny`, `skillOverrides`,
`hooks`, `enabledPlugins`, `extraKnownMarketplaces`, `effortLevel`,
`modelSettings`, `tui`, `editorMode`, `skipDangerousModePermissionPrompt`,
`skipAutoPermissionPrompt`, `skipWorkflowUsageWarning`,
`agentPushNotifEnabled`.

The `sol`, `luna` and `astra` agents use model ids that only resolve through
the CLIProxyAPI gateway (`ANTHROPIC_BASE_URL`, set by the private layer).

## New machine

1. Run `./init.sh` from this repo (installs Nix, Homebrew, nix-darwin).
2. Restore GPG and `pass`: import the GPG key named in
   `nixpkgs/home-manager/password-store.nix`, then clone the password store to
   `~/.password-store`. Entries used:
   - `cliproxyapi/api-key`: the CLIProxyAPI client key (also Claude Code's
     `ANTHROPIC_AUTH_TOKEN`)
   - `cliproxyapi/management-secret`: the CLIProxyAPI management key (plain
     text; CLIProxyAPI hashes it on load)
   - `github/personal`: GitHub token (shadcn-ui MCP server, registry token)
3. Clone the private repo to `~/workspace/dotfiles-private`, open a new shell
   and run `rebuild`.
4. Log in:
   - `claude` (first run), and `codex login`
   - CLIProxyAPI OAuth accounts: `cliproxyapi --claude-login`,
     `cliproxyapi --codex-login` (and any other providers you use). The login
     files land in `~/.cli-proxy-api/*.json`; never commit them.
   - `gws auth login`
5. Run `ai-bootstrap`. It installs what Nix and Homebrew don't cover (the
   `claude` native installer, `graphify`, the Headroom server), skills from
   their sources (find-skills, frontend-design, graphify), Claude Code
   marketplaces and plugins, and MCP servers (user scope; the private layer
   adds per-project ones). It skips anything already present and can be
   re-run.
6. Build the Headroom plugin for CLIProxyAPI: `cliproxyapi-headroom-build`,
   then `brew services restart cliproxyapi`.
7. Authenticate the HTTP MCP servers (figma, monday, and per-project ones)
   from `/mcp` inside Claude Code, and run `/slack` once to log in to the Slack
   plugin.
