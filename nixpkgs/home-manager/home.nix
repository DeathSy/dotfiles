{ config, pkgs, lib, ... }:
let
  kubectl-forward = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/ljakimczuk/kubectl-forward/main/bin/kubectl-forward";
    hash = "sha256-2nLkitQK54ePm4PrYZ7YmySd4qmju+pzjTpZD6vL7RA=";
  };
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
