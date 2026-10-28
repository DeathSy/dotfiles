{ config, lib, pkgs, ... }:

# Headroom compression proxy for CLIProxyAPI, on the gateway server only.
# Self-contained: drop its import line in nixpkgs/hosts/garage-server.nix to
# turn it off. Install the server with
# `uv tool install headroom-ai` (ai-bootstrap does it) and the CLIProxyAPI
# plugin with `cliproxyapi-headroom-build`.
let
  home = config.home.homeDirectory;
in
{
  launchd.agents.headroom = {
    enable = true;
    config = {
      # Same label as the hand-made agent it replaces, so home-manager takes it over.
      Label = "ai.headroom.proxy";
      ProgramArguments = [
        "${home}/.local/bin/headroom" "proxy"
        "--host" "127.0.0.1" "--port" "8787" "--lossless"
      ];
      EnvironmentVariables = {
        DO_NOT_TRACK = "1";
        HEADROOM_BEACON = "off";
      };
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${home}/Library/Logs/headroom/out.log";
      StandardErrorPath = "${home}/Library/Logs/headroom/err.log";
    };
  };

  # launchd won't create the log directory itself.
  home.activation.headroomLogs = lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
    run mkdir -p "${home}/Library/Logs/headroom"
  '';

  dotfiles.ai.bootstrap = ''
    echo "== Headroom"
    command -v headroom >/dev/null || try uv tool install headroom-ai
  '';

  # Builds the Headroom plugin for CLIProxyAPI from source and installs it
  # into CLIProxyAPI's plugin dir. Needs Go with cgo (Xcode CLT).
  home.packages = [ (pkgs.writeShellScriptBin "cliproxyapi-headroom-build" ''
    set -eu
    src=''${1:-''${XDG_CACHE_HOME:-$HOME/.cache}/cliproxyapi-headroom}
    if [ -d "$src/.git" ]; then
      git -C "$src" pull --ff-only
    else
      git clone https://github.com/testground-lab/cliproxyapi-headroom.git "$src"
    fi
    cd "$src"
    version=$(sed -n 's/^const version = "\(.*\)"/\1/p' plugin.go)
    arch=$(uname -m); [ "$arch" = x86_64 ] && arch=amd64
    CGO_ENABLED=1 go build -buildmode=c-shared -trimpath -ldflags="-s -w" -o dist/headroom.dylib .
    dest="$HOME/.cli-proxy-api/plugins/darwin/$arch"
    mkdir -p "$dest"
    cp dist/headroom.dylib "$dest/headroom-v$version.dylib"
    echo "Installed $dest/headroom-v$version.dylib; run: brew services restart cliproxyapi"
  '') ];
}
