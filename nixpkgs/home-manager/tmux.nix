{ pkgs, ... }:
{
	programs.tmux = {
		enable = true;
		terminal = "tmux-256color";
		prefix = "C-a";
		keyMode = "vi";
		extraConfig = ''
		# Reload config keymap
			unbind r
			bind r source-file ~/.tmux.conf

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

			# Zoom motion
			unbind z
			bind-key m resize-pane -Z

			# Tmux session with sesh and fzf-tmux
			unbind s
			bind-key s run-shell "sesh connect \"$(
				sesh list | fzf-tmux -p 55%,60% \
					--no-sort --border-label ' sesh ' --prompt '⚡  ' \
					--header '  ^a all ^t tmux ^g configs ^x zoxide ^d tmux kill ^f find' \
					--bind 'tab:down,btab:up' \
					--bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list)' \
					--bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t)' \
					--bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -c)' \
					--bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z)' \
					--bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' \
					--bind 'ctrl-d:execute(tmux kill-session -t {})+change-prompt(⚡  )+reload(sesh list)'
			)\""
		'';
		plugins = with pkgs; [
			tmuxPlugins.sensible
			tmuxPlugins.yank
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
        };
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

				set -g @catppuccin_status_default "on"
				set -g @catppuccin_status_background "default"

				set -g @catppuccin_window_left_separator ""
				set -g @catppuccin_window_right_separator " "
				set -g @catppuccin_window_middle_separator " █"
				set -g @catppuccin_window_number_position "right"

				set -g @catppuccin_window_default_fill "number"
				set -g @catppuccin_window_default_text "#W"

				set -g @catppuccin_window_current_fill "number"
				set -g @catppuccin_window_current_text "#W"

				set -g @catppuccin_status_modules_right "session"
				set -g @catppuccin_status_left_separator  " "
				set -g @catppuccin_status_right_separator ""
				set -g @catppuccin_status_fill "icon"
				set -g @catppuccin_status_connect_separator "no"
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
