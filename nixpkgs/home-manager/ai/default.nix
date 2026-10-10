{ config, lib, ... }:

# AI tooling: Claude Code, Codex and the bootstrap command. Private bits
# (secrets, project paths, internal URLs) come from the private layer through
# the options below; see docs/ai-setup.md.
{
  imports = [
    ./claude.nix
    ./codex.nix
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

    claude.settingsOverlays = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = ''
        JSON files deep-merged over claude/settings.base.json, in order.
        "@HOME@" is replaced with the home directory.
      '';
    };

    claude.secretEnv = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = { ANTHROPIC_AUTH_TOKEN = "cliproxyapi/api-key"; };
      description = "settings.json env vars read from `pass` (var name -> pass entry) at activation.";
    };

    codex.configOverlays = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = ''
        TOML files deep-merged over codex/config.base.toml, in order.
        "@HOME@" is replaced with the home directory.
      '';
    };

    bootstrap = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Extra shell appended to `ai-bootstrap`. The helpers mcp_user,
        mcp_local and plugin_install are available.
      '';
    };
  };
}
