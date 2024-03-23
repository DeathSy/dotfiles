reload("ks.options")
reload("ks.treesitter")
reload("ks.keymaps")
reload("ks.mason")

lvim.plugins = {
  -- vim motion plugins --
  { "tpope/vim-surround" },
  { "mg979/vim-visual-multi" },
  {
    "ggandor/leap.nvim",
    name = "leap",
    config = function()
      require("leap").add_default_mappings()
    end,
  },
  {
    "tpope/vim-repeat"
  },

  -- Editor --
  {
    "f-person/git-blame.nvim",
    event = "BufRead",
    config = function()
      vim.cmd "highlight default link gitblame SpecialComment"
      require("gitblame").setup { enabled = false }
    end,

  },
  {
    "mrjones2014/nvim-ts-rainbow",
  },

  -- Productivity --

  -- Themes --
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {},
  }
}

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
