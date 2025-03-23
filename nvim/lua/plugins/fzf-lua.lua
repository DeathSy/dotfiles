return {
  "ibhagwan/fzf-lua",
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
