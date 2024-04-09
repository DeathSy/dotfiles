-- Vim Motion --
vim.keymap.set("n", "H", ":bprev<CR>")
vim.keymap.set("n", "L", ":bnext<CR>")

vim.keymap.set("i", "jj", "<ESC>")
vim.keymap.set("i", "jk", "<ESC>")

-- Vim Motion --
lvim.keys.normal_mode["<leader>|"] = ":vsplit<CR>"
lvim.keys.normal_mode["<leader>-"] = ":split<CR>"

-- Change telescope default config --
