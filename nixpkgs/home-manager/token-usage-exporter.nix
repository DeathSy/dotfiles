# garage-hq only (where the Claude Code and Codex sessions run): every 60 s
# counts tokens appended to the local session logs and writes ai_tokens_total
# to node_exporter's textfile directory (see token-usage-exporter.py, docs/monitoring.md).
{ config, pkgs, ... }:
let
  home = config.home.homeDirectory;
in
{
  launchd.agents.token-usage-exporter = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.python3}/bin/python3"
        "-I"
        "${./token-usage-exporter.py}"
        "${home}/.local/state/token-usage-exporter/state.json"
        "${home}/.local/state/node-exporter/textfile/ai_tokens.prom"
      ];
      RunAtLoad = true;
      StartInterval = 60;
      StandardOutPath = "${home}/Library/Logs/token-usage-exporter.log";
      StandardErrorPath = "${home}/Library/Logs/token-usage-exporter.log";
    };
  };
}
