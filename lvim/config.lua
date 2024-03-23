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
  {
    "jackMort/ChatGPT.nvim",
    event = "VeryLazy",
    config = function()
      require("chatgpt").setup({
        api_key_cmd = "echo $OPENAI_API_KEY",
        openai_params = {
          model = "gpt-4-turbo-preview",
        },
        openai_edit_params = {
          model = "gpt-4-turbo-preview",
        },
      })
    end,
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "folke/trouble.nvim",
      "nvim-telescope/telescope.nvim"
    },
  },

  -- Themes --
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {},
  }
}

require("ks.options")
require("ks.treesitter")
require("ks.keymaps")
