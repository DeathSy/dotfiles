{ pkgs, ... }:
{
	programs.tmux = {
		enable = true;
		terminal = "tmux-256color";
		prefix = "C-a";
		keyMode = "vi";
    shell = "${pkgs.zsh}/bin/zsh";
		extraConfig = ''
      # Reload config keymap
			unbind r
			bind r source-file ~/.config/tmux/tmux.conf

      set-option -g default-shell "${pkgs.zsh}/bin/zsh"
      set-option -g default-command "${pkgs.zsh}/bin/zsh"

      # Truecolor passthrough — without this, tmux clamps to 256 colors and
      # catppuccin (in nvim, etc.) renders as a washed-out approximation.
      set -ag terminal-overrides ",*:Tc"
      set -as terminal-features ",*:RGB"
      # Synchronized output (DECSET 2026) — lets nvim/TUIs batch redraws so
      # tmux doesn't tear/flicker. WezTerm supports it.
      set -as terminal-features ",*:sync"

      # More visible pane borders (defaults are too dark against the bg)
      set -g pane-border-style "fg=#a6adc8"
      set -g pane-active-border-style "fg=#cba6f7"

      set -g status-style "bg=default"
      set -g status-bg default

			set -sg escape-time 0
			set -g mouse on
			set-option -g status-position top
			set-option -g renumber-windows on
			set-option -g allow-rename off
			set -s set-clipboard on
			set -s set-clipboard external
			set -g base-index 1
			set -g pane-base-index 1
			set -g status-keys vi
			set-window-option -g pane-base-index 1
			set-option -g renumber-windows on
			set-option -g detach-on-destroy off
			set-option -g focus-events on
			set-option -g aggressive-resize on

			# Notify when a background agent rings the bell (Claude Code: finished
			# / waiting for input). The window gets a bell flag in the status bar.
			set-option -g monitor-bell on
			set-option -g bell-action other
			set-option -g visual-bell off
			set-window-option -g monitor-activity off

			# AI agent (Claude Code) management
			# prefix C : jump to this project's claude agent, or spawn one (model picker)
			bind-key C display-popup -E -w 40% -h 40% "$HOME/.config/tmux/agent.sh"
			# prefix A : fuzzy-switch between running agents across all sessions
			bind-key A display-popup -E -w 70% -h 50% "$HOME/.config/tmux/agent-switch.sh"
			# prefix e : open the claude-squad agent dashboard (jump to it if open)
			bind-key e run-shell "$HOME/.config/tmux/squad.sh"

			# prefix Tab : toggle an IDE-style session sidebar that follows you
			# across sessions/windows (persistent-feeling left panel of sessions).
			bind-key Tab run-shell "$HOME/.config/tmux/ide-toggle.sh"
			set-hook -g client-session-changed 'run-shell "$HOME/.config/tmux/ide-ensure.sh"'
			set-hook -g after-select-window 'run-shell "$HOME/.config/tmux/ide-ensure.sh"'

			# auto rename window
			set-option -g status-interval 5
			set-option -g automatic-rename on
			set-option -g automatic-rename-format '#{b:pane_current_path}'

			# Vim motion in tmux using prefix
			setw -g mode-keys vi
			bind-key -T copy-mode-vi v send-keys -X begin-selection
			# bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel
			bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle

      set-window-option -g mode-keys vi

			bind-key | split-pane -h -c "#{pane_current_path}"
			bind-key - split-pane -v -c "#{pane_current_path}"
			bind-key c new-window -c "$HOME/workspace"
      bind-key o display-popup -E lf

			# Zoom motion
			unbind z
			bind-key m resize-pane -Z

      bind-key "s" run-shell "tmux display-popup -E -w 80% -h 71% -B 'sesh connect \"$(
        sesh list --icons | fzf --border=rounded --color=bg:-1,gutter:-1,border:#f5c2e7,preview-bg:-1 \
        --no-sort --ansi --border-label \" sesh \" --prompt \"⚡  \" \
        --header \"  ^a all ^t tmux ^g configs ^x zoxide ^d tmux kill ^f find\" \
        --bind \"tab:down,btab:up\" \
        --bind \"ctrl-a:change-prompt(⚡  )+reload(sesh list --icons)\" \
        --bind \"ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons)\" \
        --bind \"ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)\" \
        --bind \"ctrl-x:change-prompt(📁  )+reload(sesh list -z --icons)\" \
        --bind \"ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)\" \
        --bind \"ctrl-d:execute(tmux kill-session -t {2..})+change-prompt(⚡  )+reload(sesh list --icons)\" \
        --preview-window \"right:55%\" \
        --preview \"sesh preview {}\"
      )\"'"
		'';
		plugins = with pkgs; [
			tmuxPlugins.sensible
			tmuxPlugins.yank
			tmuxPlugins.open
			tmuxPlugins.sessionist

			tmuxPlugins.vim-tmux-navigator
      {
        plugin = tmuxPlugins.mkTmuxPlugin {
          pluginName = "neolazygit";
          version = "863bb60";
          src = pkgs.fetchFromGitHub {
            owner = "AngryMorrocoy";
            repo = "tmux-neolazygit";
            rev = "863bb604550f6e599456082b14a9d91f4dabebdf";
            hash = "sha256-fXlBqc3nIEOcdL8Q1OOYb6javnwF9mT3gtgP3NpDPdw=";
          };
          # Rename its option out of the "@open*" namespace, which the
          # tmux-open plugin claims for search engines. Without this, tmux-open
          # reads "@open-lazygit" as a key binding and errors on every reload.
          postInstall = ''
            substituteInPlace $target/neolazygit.tmux \
              --replace '@open-lazygit' '@lazygit-key'
          '';
        };
        extraConfig = ''
        set -g @lazygit-key 'g'
        '';
      }
      {
        plugin = tmuxPlugins.mkTmuxPlugin {
          pluginName = "floax";
          version = "864ceb9";
          src = pkgs.fetchFromGitHub {
            owner = "omerxx";
            repo = "tmux-floax";
            rev = "864ceb9372cb496eda704a40bb080846d3883634";
            sha256 = "sha256-vG8UmqYXk4pCvOjoSBTtYb8iffdImmtgsLwgevTu8pI=";
          };
        };
        extraConfig = ''
        set -g @floax-bind 't'
        '';
      }
			{
				plugin = tmuxPlugins.catppuccin;
				extraConfig = ''
				set -g @catppuccin_flavour 'mocha'
        set -g @catppuccin_window_status_style "rounded"
        # Brighter inactive pane border (catppuccin's default blends into the bg)
        set -g @catppuccin_pane_border_style "fg=#a6adc8"

				set -g @catppuccin_window_left_separator ""
				set -g @catppuccin_window_right_separator " "
				set -g @catppuccin_window_middle_separator " █"
				set -g @catppuccin_window_number_position "right"

				set -g @catppuccin_window_default_fill "number"
				set -g @catppuccin_window_current_fill "number"

        set -g @catppuccin_window_default_text "#W"
        set -g @catppuccin_window_text "#W#{?window_bell_flag, 🔔,}"
        set -g @catppuccin_window_current_text "#W#{?window_bell_flag, 🔔,}"

				set -g @catppuccin_status_modules_right "session"
				set -g @catppuccin_status_left_separator  " "
				set -g @catppuccin_status_right_separator ""
				set -g @catppuccin_status_fill "icon"
				set -g @catppuccin_status_connect_separator "no"

        set -g status-left ""
        set -g status-right ""
        set -ag status-right "#{E:@catppuccin_status_session}"
				'';
			}
			{
				plugin = tmuxPlugins.resurrect;
				extraConfig = ''
				set -g @resurrect-strategy-vim 'session'
				set -g @resurrect-strategy-nvim 'session'
				set -g @resurrect-capture-pane-contents 'on'
				'';
			}
		];
	};
}
