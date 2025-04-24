{ config, pkgs, lib, ... }:
let
  kubectl-forward = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/ljakimczuk/kubectl-forward/main/bin/kubectl-forward";
    hash = "sha256-2nLkitQK54ePm4PrYZ7YmySd4qmju+pzjTpZD6vL7RA=";
  };
  extraNodePackages = import (builtins.path { path = ../global_node_packages; }) { inherit pkgs; };
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
		".config/neofetch/config.conf".source = ../../neofetch.conf;
		".config/wezterm/wezterm.lua".source = ../../wezterm.lua;
		".config/sesh/sesh.toml".source = ../../sesh.toml;
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

    # Messaging applications
    slack
    discord

    # NodeJS related
    nodejs
    corepack

    # NodeJS global packages
    nodePackages.node2nix
    extraNodePackages."@anthropic-ai/claude-code-v0.2.45"
    extraNodePackages."serverless-v3.38.0"

    # Python related
    python3
    pipx
    uv

    # Ruby related
    cocoapods
    bundler
  ];

	programs = {
		lazygit.enable = true;

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

  home.activation.startup-application = lib.mkAfter ''
  /usr/local/bin/desktoppr ~/workspace/dotfiles/wallpapers/Cloudsnight-landscape.jpg
  '';
}
