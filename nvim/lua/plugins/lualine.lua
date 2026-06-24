return {
  "nvim-lualine/lualine.nvim",
  -- LazyVim defaults to the "auto" theme, which derives muted/washed colors
  -- from the (transparent) catppuccin highlights. Pin catppuccin's own lualine
  -- theme so the powerline gets the proper vibrant mode accents.
  opts = {
    options = {
      theme = "catppuccin",
    },
  },
}
