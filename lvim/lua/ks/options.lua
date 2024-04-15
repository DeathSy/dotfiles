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

lvim.builtin.telescope.defaults.file_ignore_patterns = {
  "vendor/*",
  "%.lock",
  "__pycache__/*",
  "%.sqlite3",
  "%.ipynb",
  "node_modules/*",
  "%.jpg",
  "%.jpeg",
  "%.png",
  "%.svg",
  "%.otf",
  "%.ttf",
  ".git/",
  "%.webp",
  ".dart_tool/",
  ".github/",
  ".gradle/",
  ".idea/",
  ".vscode/",
  "__pycache__/",
  "build/",
  "env/",
  "gradle/",
  "node_modules/",
  "target/",
  "%.pdb",
  "%.dll",
  "%.class",
  "%.exe",
  "%.cache",
  "%.ico",
  "%.pdf",
  "%.dylib",
  "%.jar",
  "%.docx",
  "%.met",
  "smalljre_*/*",
  ".vale/",
}

lvim.builtin.telescope.pickers.find_files = {
  layout_config = { height = 0.80, width = 0.80, preview_cutoff = 120, preview_width = 0.6, prompt_position = "top" },
  layout_strategy = "horizontal",
  hidden = true,
}

lvim.builtin.telescope.pickers.live_grep = {
  layout_config = { height = 0.80, width = 0.80, preview_cutoff = 120, preview_width = 0.6, prompt_position = "top" },
  layout_strategy = "horizontal"
}

lvim.builtin.telescope.pickers.git_commits = {
  layout_strategy = "horizontal",
  layout_config = { height = 0.88, width = 0.88, preview_cutoff = 20, preview_width = 0.70, prompt_position = "bottom" }
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
