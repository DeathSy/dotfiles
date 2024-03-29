-- Vim Motion --
vim.keymap.set("n", "H", ":bnext<CR>")
vim.keymap.set("n", "L", ":bprev<CR>")

vim.keymap.set("i", "jj", "<ESC>")
vim.keymap.set("i", "jk", "<ESC>")

-- Vim Motion --
lvim.keys.normal_mode["<leader>|"] = ":vsplit<CR>"
lvim.keys.normal_mode["<leader>-"] = ":split<CR>"

-- Telescope --
lvim.keys.normal_mode["<leader>t/"] = ":Telescope live_grep<CR>"
