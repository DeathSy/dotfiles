{ pkgs, ... }: {

	programs.zsh = {
		enable = true;

		sessionVariables = {
			GOPATH = "$HOME/go";
			GOBIN = "$GOPATH/bin";
			VISUAL = "nvim";
			EDITOR = "nvim";
      DOCKER_CMD = "podman";
		};

		oh-my-zsh = {
			enable = true;
			plugins = [
				"git"
				"docker"
				"docker-compose"
				"yarn"
        "redis-cli"
			];
		};

		zplug = {
			enable = true;
			plugins = [
				{ name = "nekofar/zsh-pnpm"; }
				{ name = "ntnyq/omz-plugin-bun"; }
				{ name = "zsh-users/zsh-autosuggestions"; }
				{ name = "zsh-users/zsh-completions"; }
				{ name = "zsh-users/zsh-syntax-highlighting"; }
			];
		};

		shellAliases = {
			vim = "nvim";
			vi = "nvim";
			n = "nvim";

			lg = "lazygit";
			lk = "k9s";

      cat="bat";
      
      find="fd";

      ktx="kubectx";

      ls="eza --color=always --group-directories-first --icons";
      ll="eza -la --icons --octal-permissions --group-directories-first";
      l="eza -bGF --header --git --color=always --group-directories-first --icons";
      llm="eza -lbGd --header --git --sort=modified --color=always --group-directories-first --icons";
      la="eza --long --all --group --group-directories-first";
      lx="eza -lbhHigUmuSa@ --time-style=long-iso --git --color-scale --color=always --group-directories-first --icons";
      lS="eza -1 --color=always --group-directories-first --icons";
      lt="eza --tree --level=2 --color=always --group-directories-first --icons";
      "l."="eza -a | grep -E '^\.'";
      t = "sesh connect $(sesh list --icons | fzf --no-sort --ansi)";
		};

		initContent = ''
			eval "$(/opt/homebrew/bin/brew shellenv)"

			${pkgs.fastfetch}/bin/fastfetch

      # Lazily load the GitHub registry token only when a tool needs it,
      # instead of decrypting the secret into every shell on startup
      # (which also triggered a GPG prompt). Run `gh-token` before commands
      # that require GITHUB_REGISTRY_TOKEN.
      gh-token() { export GITHUB_REGISTRY_TOKEN="$(pass show github/personal)"; }

      export PATH="$HOME/.local/bin:$PATH"
      export NVM_DIR="$HOME/.nvm"
      [ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ] && source "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
      [ -s "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" ] && source "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm"
		'';
	};
}
