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
      default = "${config.home.homeDirectory}/workspace/dotfiles";
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

    bootstrap = mkOption {
      type = types.lines;
      default = "";
      internal = true;
      description = "Extra ai-bootstrap steps from other modules in this directory.";
    };
  };
}
