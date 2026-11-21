{ config, lib, pkgs, ... }:

# AI tooling: Claude Code, Codex, the CLIProxyAPI gateway and the bootstrap
# command. Everything installs from here; a private module only sets the data
# options below (see docs/ai-setup.md). With the defaults the public repo
# works on its own.
let
  mcpServer = with lib; {
    transport = mkOption {
      type = types.enum [ "http" "sse" "stdio" ];
      default = "http";
    };
    url = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Server URL (http/sse).";
    };
    command = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Command and arguments (stdio).";
    };
    headersHelper = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Shell command printing a JSON object of request headers (http/sse); Claude Code runs it at connect time.";
    };
  };
in
{
  imports = [
    ./claude.nix
    ./codex.nix
    ./gateway.nix
  ];

  options.dotfiles.ai = with lib; {
    repoPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/studio/personal/dotfiles";
      description = ''
        Checkout of this repo. ~/.claude files link here (not into the Nix
        store), so edits made in place show up as repo diffs.
      '';
    };

    claude.settingsOverlay = mkOption {
      type = (pkgs.formats.json { }).type;
      default = { };
      description = "Extra settings.json keys, deep-merged over claude/settings.base.json.";
    };

    claude.secretEnv = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = { ANTHROPIC_AUTH_TOKEN = "ai/cliproxyapi-key"; };
      description = "settings.json env vars read from `pass` at activation (var name -> pass entry).";
    };

    claude.projectPlugins = mkOption {
      type = types.listOf (types.submodule {
        options.dir = mkOption { type = types.str; description = "Project directory."; };
        options.plugin = mkOption { type = types.str; description = "plugin@marketplace"; };
      });
      default = [ ];
      description = "Plugins ai-bootstrap installs in local scope for one project.";
    };

    claude.extraSkillDirs = mkOption {
      type = types.attrsOf (types.strMatching "/.*");
      default = { };
      example = { my-skill = "/path/to/private-repo/claude/skills/my-skill"; };
      description = "Skill folders kept outside this repo (skill name -> absolute path), each linked as ~/.claude/skills/<name> so edits show up in their own repo.";
    };

    claude.trustedRepoOwners = mkOption {
      type = types.listOf (types.strMatching "[A-Za-z0-9][A-Za-z0-9-]*");
      default = [ ];
      example = [ "octocat" ];
      description = "GitHub owners whose repos `claude` marks trusted before it starts (claude-trust-repo), so Claude Code doesn't ask about folder trust. Empty turns it off.";
    };

    mcp.userServers = mkOption {
      type = types.attrsOf (types.submodule { options = mcpServer; });
      default = { };
      description = "User-scope MCP servers ai-bootstrap adds (name -> server).";
    };

    mcp.projectServers = mkOption {
      type = types.listOf (types.submodule {
        options = mcpServer // {
          dir = mkOption { type = types.str; description = "Project directory."; };
          name = mkOption { type = types.str; };
        };
      });
      default = [ ];
      description = "Local-scope (per-project) MCP servers ai-bootstrap adds.";
    };

    codex.settings = mkOption {
      type = (pkgs.formats.toml { }).type;
      default = { };
      description = "Extra config.toml keys, deep-merged over codex/config.base.toml.";
    };

    codex.trustedProjects = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Project paths Codex trusts.";
    };

    hermes = {
      dashboardPublicUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://garage-hq.example.ts.net";
        description = ''
          The tailnet HTTPS URL of the Hermes dashboard (ai/hermes.nix, garage-hq
          only). Set: the dashboard runs on loopback, `tailscale serve` maps this
          URL to it, and sign-in is required. Null: no dashboard.
        '';
      };
      apiServer = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Run Hermes' OpenAI-compatible API server on 127.0.0.1:8642 (key from pass
          hermes/api-server-key) and, with dashboardPublicUrl set, publish it on the
          tailnet at HTTPS port 8443 via tailscale serve.
        '';
      };
      ownerSlackId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The owner's Slack member id: the only one who may answer approvals (approvals.approvers).";
      };
      colleagueSlackIds = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Slack member ids of colleagues July answers too (added to SLACK_ALLOWED_USERS
          next to the owner). They get the same agent as the owner, data included.
        '';
      };
      soulFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "July's persona, installed as ~/.hermes/SOUL.md (replaces Hermes' default identity).";
      };
      slackHomeChannel = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "SLACK_HOME_CHANNEL for Hermes (the bot's DM channel with the owner).";
      };
      terminalCwd = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Where Hermes chat sessions start (terminal.cwd).";
      };
      extraSkillDirs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "More skills.external_dirs for Hermes (folders of SKILL.md skill folders).";
      };
    };

    bootstrap = mkOption {
      type = types.lines;
      default = "";
      internal = true;
      description = "Extra ai-bootstrap steps from other modules in this directory.";
    };
  };
}
