-- Vim Motion --
vim.keymap.set("n", "H", ":bnext<CR>")
vim.keymap.set("n", "L", ":bprev<CR>")

vim.keymap.set("i", "jj", "<ESC>")
vim.keymap.set("i", "jk", "<ESC>")

-- ChatGPT --
vim.keymap.set("n", "<leader>ac", ":ChatGPT<CR>")
vim.keymap.set("n", "<leader>af", ":ChatGPTRun complete_code<CR>")
vim.keymap.set("n", "<leader>at", ":ChatGPTRun add_tests<CR>")
vim.keymap.set("n", "<leader>ao", ":ChatGPTRun optimize_code<CR>")
vim.keymap.set("n", "<leader>ad", ":ChatGPTRun docstring<CR>")
