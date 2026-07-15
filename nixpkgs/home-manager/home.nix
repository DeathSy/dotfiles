{ config, pkgs, lib, ... }:
let
  kubectl-forward = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/ljakimczuk/kubectl-forward/main/bin/kubectl-forward";
    hash = "sha256-2nLkitQK54ePm4PrYZ7YmySd4qmju+pzjTpZD6vL7RA=";
  };

  # Drop AeroSpace "phantom" windows (stale refs to closed windows that show as
  # empty black tiles) without a disruptive full restart: for each app that
  # AeroSpace tracks more windows than it really has, close the extra
  # empty-title windows by id. Finder holds phantoms in its own accessibility
  # tree that close-by-id can't reach, so relaunch it as a fallback.
  clear-phantoms = pkgs.writeShellScriptBin "clear-phantoms" ''
    export PATH="/run/current-system/sw/bin:/usr/bin:/bin:$PATH"

    aerospace list-windows --all --format '%{app-name}' 2>/dev/null | sort -u \
    | while IFS= read -r app; do
        [ -n "$app" ] || continue
        as=$(aerospace list-windows --all --format '%{app-name}' 2>/dev/null | grep -Fxc "$app")
        real=$(osascript -e "tell application \"System Events\" to tell process \"$app\" to count windows" 2>/dev/null)
        case "$real" in ""|*[!0-9]*) continue ;; esac
        excess=$(( as - real ))
        [ "$excess" -gt 0 ] || continue
        aerospace list-windows --all --format '%{window-id}|%{app-name}|%{window-title}' 2>/dev/null \
        | awk -F'|' -v a="$app" '$2==a && $3=="" {print $1}' \
        | head -n "$excess" \
        | while IFS= read -r wid; do aerospace close --window-id "$wid" 2>/dev/null || true; done
      done

    fas=$(aerospace list-windows --all --format '%{app-name}' 2>/dev/null | grep -Fxc Finder)
    freal=$(osascript -e 'tell application "System Events" to tell process "Finder" to count windows' 2>/dev/null || echo 0)
    [ "''${fas:-0}" -gt "''${freal:-0}" ] && killall Finder 2>/dev/null || true
  '';
in
{
  home.username = "ksotis";

  home.stateVersion = "24.05";

  programs.home-manager.enable = true;
  programs.home-manager.path = "$HOME/.config/nix-darwin/nixpkgs/";

	home.file = {
		".config/ascii_arts" = {
			source = ../../ascii_arts;
			recursive = true;
		};
		".config/sketchybar" = {
			source = ../../sketchybar;
			recursive = true;
		};
		".config/nvim" = {
			source = ../../nvim;
			recursive = true;
		};
		".config/fastfetch/config.jsonc".source = ../../fastfetch.jsonc;
		".config/tmux/agent.sh" = { source = ../../tmux/agent.sh; executable = true; };
		".config/tmux/agent-switch.sh" = { source = ../../tmux/agent-switch.sh; executable = true; };
		".config/tmux/agent-notify.sh" = { source = ../../tmux/agent-notify.sh; executable = true; };
		".config/tmux/squad.sh" = { source = ../../tmux/squad.sh; executable = true; };
		".config/tmux/ide-sidebar.sh" = { source = ../../tmux/ide-sidebar.sh; executable = true; };
		".config/tmux/ide-ensure.sh" = { source = ../../tmux/ide-ensure.sh; executable = true; };
		".config/tmux/ide-toggle.sh" = { source = ../../tmux/ide-toggle.sh; executable = true; };
		".config/wezterm/wezterm.lua".source = ../../wezterm.lua;
		".config/sesh/sesh.toml".source = ../../sesh.toml;
    ".sleep" = {
      text = ''
        #!/bin/bash
        ${pkgs.podman}/bin/podman machine stop
      '';
      executable = true;
    };
    ".wakeup" = {
      text = ''
        #!/bin/bash
        ${pkgs.podman}/bin/podman machine start

        # Clear AeroSpace phantom windows that accumulate across sleep/wake
        # (closed windows shown as empty black tiles). Non-disruptive: closes
        # just the phantoms by id instead of restarting the whole WM.
        ( sleep 3; ${clear-phantoms}/bin/clear-phantoms ) &
      '';
      executable = true;
    };
	};

  home.packages = with pkgs; [
    # Kubernetes related applications
    (writeShellScriptBin "kubectl-forward" (builtins.readFile kubectl-forward))
    kubectl
    kubectx
    minikube
    k9s
    sesh

    # Container related applications
    podman
    podman-compose

    # Data storage applications
    postgresql
    tableplus
    redis

    # Utilities applications
    awscli2
    gh
    clear-phantoms

    discord

    # Python related
    python3
    pipx
    uv

    # Ruby related
    cocoapods
    bundler
  ];

	programs = {
		lazygit = {
			enable = true;
			# Catppuccin Mocha theme (matches nvim/wezterm/tmux)
			settings = {
				gui = {
					nerdFontsVersion = "3";
					theme = {
						activeBorderColor = [ "#cba6f7" "bold" ];
						inactiveBorderColor = [ "#a6adc8" ];
						optionsTextColor = [ "#89b4fa" ];
						selectedLineBgColor = [ "#313244" ];
						cherryPickedCommitFgColor = [ "#cba6f7" ];
						cherryPickedCommitBgColor = [ "#313244" ];
						markedBaseCommitFgColor = [ "#cba6f7" ];
						markedBaseCommitBgColor = [ "#313244" ];
						unstagedChangesColor = [ "#f38ba8" ];
						defaultFgColor = [ "#cdd6f4" ];
						searchingActiveBorderColor = [ "#f9e2af" ];
					};
				};
				authorColors = { "*" = "#b4befe"; };
			};
		};

		zoxide = {
			enable = true;
			enableZshIntegration = true;
		};

		bun = {
			enable = true;
		};

    go = {
      enable = true;
    };
	};

  launchd.agents.sleepwatcher = {
    enable = true;
    config = {
      ProgramArguments = [
        "/opt/homebrew/bin/sleepwatcher"
        "-V"
        "-s" "${config.home.homeDirectory}/.sleep"
        "-w" "${config.home.homeDirectory}/.wakeup"
      ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };

  home.activation.startup-application = lib.mkAfter ''
  /usr/local/bin/desktoppr ~/workspace/dotfiles/wallpapers/Cloudsnight-landscape.jpg
  '';
}
