{ config, pkgs, ... }: {
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
		".config/aerospace/aerospace.toml".source = ../../aerospace.toml;
		".config/wezterm/wezterm.lua".source = ../../wezterm.lua;
	};

	programs = {
		lazygit.enable = true;

		zoxide = {
			enable = true;
			enableZshIntegration = true;
		};

		bun = {
			enable = true;
		};

    direnv = {
      enable = true;
    };
	};
}
