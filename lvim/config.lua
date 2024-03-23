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

  -- Themes --
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {},
  }
}
