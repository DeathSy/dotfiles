local wezterm = require("wezterm")

local config = {}

if wezterm.config_builder then
	config = wezterm.config_builder()
end

-- Settings --
config.color_scheme = "Catppuccin Mocha (Gogh)"
config.font = wezterm.font_with_fallback({
	{ family = "FiraCode Nerd Font", scale = 1.1 },
})
config.font_size = 12
-- config.window_background_opacity = 0.9
config.window_decorations = "RESIZE"
config.window_close_confirmation = "NeverPrompt"
config.scrollback_lines = 3000
config.default_workspace = "home"
config.enable_tab_bar = false
config.window_padding = {
	left = 10,
	top = 10,
	right = 10,
	bottom = 10,
}

return config
