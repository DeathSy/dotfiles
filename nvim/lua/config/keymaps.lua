local keymap = vim.keymap
local opts = { noremap = true, silent = true }

-- Editor
keymap.set("i", "jj", "<Esc>", opts)
keymap.set("i", "jk", "<Esc>", opts)

-- Toggle Terminal
keymap.set("n", "<leader>ot", ":ToggleTerm<CR>", opts)
