local wezterm = require("wezterm")

local config = {}

if wezterm.config_builder then config = wezterm.config_builder() end

-- Settings --
config.color_scheme = "Catppuccin Mocha"
config.font = wezterm.font_with_fallback({
  { family = "Fira Code", scale = 1.1 },
})
config.window_background_opacity = 0.9
config.window_decorations = "RESIZE"
config.window_close_confirmation = "AlwaysPrompt"
config.scrollback_lines = 3000
config.default_workspace = "home"
config.enable_tab_bar = false

return config
