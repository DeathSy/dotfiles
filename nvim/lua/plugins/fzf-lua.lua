return {
  "ibhagwan/fzf-lua",
  -- Derive fzf's colors from the active colorscheme (catppuccin) so the
  -- picker matches instead of using fzf's default green/ANSI palette.
  opts = {
    fzf_colors = true,
  },
  keys = {
    -- Remove the default mapping
    { "<leader>ff", false },
    -- Add your new mapping
    {
      "<leader>sf",
      function()
        require("fzf-lua").files()
      end,
      desc = "Find Files (fzf)",
    },
  },
}
