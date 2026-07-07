{ pkgs, ... }: {

	programs.zsh = {
		enable = true;
		autosuggestion.enable = true;
		syntaxHighlighting.enable = true;

		sessionVariables = {
			GOPATH = "$HOME/go";
			GOBIN = "$GOPATH/bin";
			VISUAL = "nvim";
			EDITOR = "nvim";
      DOCKER_CMD = "podman";
      # Catppuccin Mocha palette for every fzf invocation (shell + fzf-lua)
      FZF_DEFAULT_OPTS = "--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8,fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc,marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8";
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

		plugins = [
			{
				name = "zsh-pnpm";
				file = "zsh-pnpm.plugin.zsh";
				src = pkgs.fetchFromGitHub {
					owner = "nekofar";
					repo = "zsh-pnpm";
					rev = "bf5e51c1ee73ff90c73746531a8a775224b7f0df";
					sha256 = "0ynbxqg66vr1dab4zixl51k26ylj7n5n055spyg3lfrfj5c5dxd6";
				};
			}
			{
				name = "omz-plugin-bun";
				file = "bun.plugin.zsh";
				src = pkgs.fetchFromGitHub {
					owner = "ntnyq";
					repo = "omz-plugin-bun";
					rev = "6a8e432d233f96a5e312ab3a7c657eefcf5b5f6c";
					sha256 = "14zfv1fawj3vr0a94hwxhgbn3gyyaf7l2cym1i8z0hkfk2i4y3zz";
				};
			}
		];

		shellAliases = {
			vim = "nvim";
			vi = "nvim";
			n = "nvim";

			lg = "lazygit";
			lk = "k9s";
			cs = "claude-squad";

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

      # When AeroSpace shortcuts stop working, a password box left macOS
      # "secure input" stuck on. Run `secureinput` to see which app holds it.
      secureinput() {
        local pid
        pid=$(LC_ALL=C ioreg -l -w 0 | grep -o '"kCGSSessionSecureInputPID"=[0-9]*' | grep -o '[0-9]*' | head -1)
        if [[ -z "$pid" || "$pid" == 0 ]]; then
          echo "✅ secure input is OFF — AeroSpace shortcuts should work"
        else
          echo "🔒 secure input is ON, held by PID $pid:"
          ps -p "$pid" -o pid=,comm=,args=
          echo "→ refocus that app and dismiss its password field (Esc / click away), or quit it, to release it"
        fi
      }

      export PATH="$HOME/.local/bin:$PATH"
      export NVM_DIR="$HOME/.nvm"
      [ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ] && source "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
      [ -s "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" ] && source "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm"
		'';
	};
}
