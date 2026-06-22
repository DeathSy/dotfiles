-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

-- Brighter window split separators. catppuccin links WinSeparator -> VertSplit
-- (near-black crust), and its custom_highlights merge keeps the link, so set it
-- explicitly after the colorscheme loads (matches the tmux pane border color).
vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "*",
  callback = function()
    vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#a6adc8" })
  end,
})
