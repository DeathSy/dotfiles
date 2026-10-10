{ config, lib, pkgs, ... }:

let
  cfg = config.dotfiles.ai;
  src = ../../../claude;
  base = lib.importJSON (src + "/settings.base.json");
  inherit (config.lib.file) mkOutOfStoreSymlink;

  entries = type: dir: lib.attrNames (lib.filterAttrs (_: t: t == type) (builtins.readDir (src + "/${dir}")));

  # Paths under ~/.claude that link into the repo checkout.
  linked = [ "CLAUDE.md" "onboarding.md" ]
    ++ map (f: "agents/${f}") (lib.filter (lib.hasSuffix ".md") (entries "regular" "agents"))
    ++ map (f: "hooks/${f}") (entries "regular" "hooks")
    ++ map (d: "skills/${d}/SKILL.md") (entries "directory" "skills");

  # agent-browser ships its skill with the CLI, version-matched.
  agentBrowserSkill = "/opt/homebrew/opt/agent-browser/libexec/lib/node_modules/agent-browser/skills/agent-browser/SKILL.md";

  passDir = config.programs.password-store.settings.PASSWORD_STORE_DIR or "";
  overlay = pkgs.writeText "claude-settings-overlay.json" (builtins.toJSON cfg.claude.settingsOverlay);

  # Deep-merge live settings.json <- settings.base.json <- settingsOverlay <- secrets from pass.
  # Keys the repo manages win; everything else Claude Code wrote stays.
  settingsMerge = pkgs.writeShellScriptBin "claude-settings-merge" ''
    set -uo pipefail
    PATH=${lib.makeBinPath [ pkgs.jq pkgs.coreutils config.programs.password-store.package ]}:$PATH
    ${lib.optionalString (passDir != "") "export PASSWORD_STORE_DIR=${lib.escapeShellArg passDir}"}
    target="$HOME/.claude/settings.json"
    fail() { echo "claude-settings-merge: $*; $target left unchanged" >&2; exit 1; }

    live='{}'
    if [ -e "$target" ]; then
      live=$(jq . "$target") || fail "live file is not valid JSON"
    fi

    secrets=""
    ${lib.concatStrings (lib.mapAttrsToList (name: entry: ''
      v=$(timeout 60 pass show ${lib.escapeShellArg entry} | head -n 1) && [ -n "$v" ] \
        || fail "pass show ${entry} failed"
      secrets+=$(printf '%s' "$v" | jq -Rs --arg k ${lib.escapeShellArg name} '{env: {($k): .}}')$'\n' \
        || fail "jq failed"
    '') cfg.claude.secretEnv)}

    merged=$({
      printf '%s\n' "$live"
      cat ${src + "/settings.base.json"} ${overlay}
      printf '%s' "$secrets"
    } | jq -s 'reduce .[] as $x ({}; . * $x)') || fail "merge failed"

    if [ -e "$target" ] && printf '%s\n' "$merged" | cmp -s - <(jq . "$target"); then
      exit 0
    fi

    mkdir -p "$HOME/.claude/backups"
    [ -e "$target" ] && cp -p "$target" "$HOME/.claude/backups/settings.json.dotfiles-$(date +%Y%m%d-%H%M%S)"
    tmp=$(mktemp "$target.XXXXXX") || fail "mktemp failed"
    printf '%s\n' "$merged" > "$tmp" && chmod 644 "$tmp" && mv "$tmp" "$target" || { rm -f "$tmp"; fail "write failed"; }
    echo "claude-settings-merge: updated $target"
  '';

  mcpList = map (s: { scope = "user"; dir = ""; } // s)
      (lib.mapAttrsToList (name: s: s // { inherit name; }) cfg.mcp.userServers)
    ++ map (s: { scope = "local"; } // s) cfg.mcp.projectServers;

  # Adds the MCP servers listed in a JSON file ([{scope, dir, name, transport,
  # url, command}]) with `claude mcp add`, skipping ones ~/.claude.json
  # already has. Never rewrites ~/.claude.json itself.
  mcpAdd = pkgs.writeShellScriptBin "ai-mcp-add" ''
    set -u
    PATH=${lib.makeBinPath [ pkgs.jq ]}:$HOME/.local/bin:/opt/homebrew/bin:$PATH
    list=''${1:-${pkgs.writeText "mcp-servers.json" (builtins.toJSON mcpList)}}
    rc=0
    mapfile -t servers < <(jq -c '.[]' "$list")
    for s in "''${servers[@]}"; do
      name=$(jq -r .name <<<"$s"); scope=$(jq -r .scope <<<"$s"); dir=$(jq -r .dir <<<"$s")
      transport=$(jq -r .transport <<<"$s"); url=$(jq -r '.url // ""' <<<"$s")
      mapfile -t cmd < <(jq -r '.command[]' <<<"$s")
      label="$name''${dir:+ ($dir)}"
      if [ "$scope" = local ] && [ ! -d "$dir" ]; then echo "mcp $label: not checked out, skipped"; continue; fi
      if jq -e --arg d "$dir" --arg n "$name" \
        '(if $d == "" then .mcpServers else .projects[$d].mcpServers end // {})[$n] != null' \
        "$HOME/.claude.json" >/dev/null 2>&1; then
        echo "mcp $label: exists"; continue
      fi
      if [ "$transport" = stdio ]; then args=("$name" -- "''${cmd[@]}")
      else args=(--transport "$transport" "$name" "$url"); fi
      if ( { [ -z "$dir" ] || cd "$dir"; } && claude mcp add -s "$scope" "''${args[@]}" ); then
        echo "mcp $label: added"
      else
        echo "mcp $label: failed" >&2; rc=1
      fi
    done
    exit $rc
  '';

  # One-off, idempotent setup that needs logins or network: run by hand
  # after a rebuild (see docs/ai-setup.md). Safe to re-run.
  bootstrap = pkgs.writeShellScriptBin "ai-bootstrap" ''
    set -u
    PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
    jq=${pkgs.jq}/bin/jq
    failed=()
    try() { "$@" || { echo "  failed: $*" >&2; failed+=("$*"); }; }
    in_dir() { (cd "$1" && shift && "$@"); }

    # plugin_install <plugin@marketplace> [user|local] [project dir]
    plugin_install() {
      local id=$1 scope=''${2:-user} dir=''${3:-}
      if "$jq" -e --arg p "$id" --arg d "$dir" \
        '.plugins[$p] // [] | any(if $d == "" then .scope == "user" else .projectPath == $d end)' \
        "$HOME/.claude/plugins/installed_plugins.json" >/dev/null 2>&1; then
        echo "plugin $id: installed"; return
      fi
      if [ -n "$dir" ]; then
        [ -d "$dir" ] || { echo "plugin $id: $dir not checked out, skipped"; return; }
        try in_dir "$dir" claude plugin install -s "$scope" "$id"
      else try claude plugin install -s "$scope" "$id"; fi
    }
    marketplace_add() { # <name> <owner/repo>
      if "$jq" -e --arg n "$1" 'has($n)' "$HOME/.claude/plugins/known_marketplaces.json" >/dev/null 2>&1; then
        echo "marketplace $1: known"; return
      fi
      try claude plugin marketplace add "$2"
    }

    echo "== CLI tools"
    command -v claude >/dev/null || try sh -c 'curl -fsSL https://claude.ai/install.sh | bash'
    command -v graphify >/dev/null || try uv tool install graphifyy

    echo "== Skills from source"
    [ -e "$HOME/.claude/skills/find-skills" ] \
      || try npx -y skills add vercel-labs/skills -g -a claude-code -s find-skills -y
    [ -e "$HOME/.claude/skills/frontend-design" ] \
      || try npx -y skills add anthropics/skills -g -a claude-code -s frontend-design -y
    [ -e "$HOME/.claude/skills/graphify" ] || try graphify install --platform claude

    echo "== Plugins"
    marketplace_add claude-plugins-official anthropics/claude-plugins-official
    ${lib.concatStrings (lib.mapAttrsToList (name: m: ''
      marketplace_add ${lib.escapeShellArgs [ name m.source.repo ]}
    '') base.extraKnownMarketplaces)}
    ${lib.concatMapStrings (id: ''
      plugin_install ${lib.escapeShellArg id}
    '') (lib.attrNames base.enabledPlugins)}

    ${lib.concatMapStrings (p: ''
      plugin_install ${lib.escapeShellArgs [ p.plugin "local" p.dir ]}
    '') cfg.claude.projectPlugins}

    echo "== MCP servers"
    try ${mcpAdd}/bin/ai-mcp-add

    ${cfg.bootstrap}

    if [ ''${#failed[@]} -gt 0 ]; then
      echo "ai-bootstrap: ''${#failed[@]} step(s) failed:" >&2
      printf '  %s\n' "''${failed[@]}" >&2
      exit 1
    fi
    echo "ai-bootstrap: done"
  '';
in
{
  home.file = lib.listToAttrs (map (p: lib.nameValuePair ".claude/${p}" {
    source = mkOutOfStoreSymlink "${cfg.repoPath}/claude/${p}";
  }) linked) // {
    ".claude/skills/agent-browser/SKILL.md".source = mkOutOfStoreSymlink agentBrowserSkill;
  };

  home.packages = [ settingsMerge mcpAdd bootstrap ];

  dotfiles.ai.mcp.userServers = {
    figma.url = "https://mcp.figma.com/mcp";
    monday.url = "https://mcp.monday.com/mcp";
    shadcn-ui = {
      transport = "stdio";
      command = [ "sh" "-c" ''exec npx @jpisnice/shadcn-ui-mcp-server --github-api-key "$(pass show github/personal)"'' ];
    };
  };

  # Move live files that are about to become links out of the way, so
  # home-manager doesn't leave *.backup copies (a SKILL.md.backup is harmless,
  # but this keeps one dated backup dir per rebuild).
  home.activation.claudeBackupLinked = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    claudeBackup="$HOME/.claude/backups/dotfiles-$(date +%Y%m%d-%H%M%S)"
    for f in ${lib.escapeShellArgs (linked ++ [ "skills/agent-browser/SKILL.md" ])}; do
      p="$HOME/.claude/$f"
      if [ -e "$p" ] && [ ! -L "$p" ]; then
        run mkdir -p "$claudeBackup/$(dirname "$f")"
        run mv "$p" "$claudeBackup/$f"
      fi
    done
  '';

  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [[ -v DRY_RUN ]]; then
      echo "Would merge ~/.claude/settings.json"
    else
      ${settingsMerge}/bin/claude-settings-merge || warnEcho "claude settings merge skipped (see above)"
    fi
  '';
}
