lvim.colorscheme = "catppuccin-mocha"
lvim.transparent_window = true
lvim.format_on_save = true
lvim.builtin.alpha.dashboard.section.header.val = {
  "██╗  ██╗███████╗██████╗ ",
  "██║ ██╔╝██╔════╝██╔══██╗",
  "█████╔╝ ███████╗██║  ██║",
  "██╔═██╗ ╚════██║██║  ██║",
  "██║  ██╗███████║██████╔╝",
  "╚═╝  ╚═╝╚══════╝╚═════╝ ",
}

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.wrap = true

-- Telescope Setup --
lvim.builtin.telescope = {
  defaults = {
    layout_strategy = "horizontal",
    layout_config = {
      width = 0.75,
      preview_cutoff = 120,
      horizontal = { mirror = false },
      vertical = { mirror = false },
    },
  },
}

-- Copilot Setup --
local ok, copilot = pcall(require, "copilot")
if not ok then
  return
end

copilot.setup {
  suggestion = {
    keymap = {
      accept = "<c-l>",
      next = "<c-j>",
      prev = "<c-k>",
      dismiss = "<c-h>",
    },
  },
}

local opts = { noremap = true, silent = true }
vim.api.nvim_set_keymap("n", "<c-s>", "<cmd>lua require('copilot.suggestion').toggle_auto_trigger()<CR>", opts)
