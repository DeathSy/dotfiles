-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

-- Brighter window split separators. catppuccin links WinSeparator -> VertSplit
-- (near-black crust), and its custom_highlights merge keeps the link, so set it
-- explicitly to match the tmux pane border color.
local function brighten_separator()
  vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#a6adc8" })
end

-- Re-apply whenever the colorscheme changes.
vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = brighten_separator })

-- Apply now too: this file is loaded on VeryLazy, which fires *after* the
-- initial colorscheme is set, so the autocmd above would otherwise miss it.
brighten_separator()
