vim.scriptedcoding = "utf-8"
vim.opt.encoding = "utf-8"
vim.opt.fileencodings = "utf-8"

vim.opt.number = true

vim.opt.title = true
vim.opt.autoindent = true
vim.smartindent = true
vim.opt.hlsearch = true
vim.opt.backup = false
vim.opt.showcmd = true
vim.opt.laststatus = 0
vim.opt.expandtab = true
vim.opt.scroll = 10
vim.opt.inccommand = "split"
vim.opt.ignorecase = true
vim.opt.smarttab = true
vim.opt.breakindent = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.wrap = true
vim.opt.backspace = { "start", "eol", "indent" }
vim.opt.path:append({ "**" })
vim.opt.wildignore:append("*/node_modules/*")
