-- LaTeX helper keymaps for Neovim (LazyVim compatible)

local opts = { noremap = true, silent = true }

local function insert_pair_at_cursor(left, right)
  local bufnr = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, { left .. right })
  vim.api.nvim_win_set_cursor(0, { row, col + #left })
end

local function wrap_visual_selection(left, right)
  local bufnr = vim.api.nvim_get_current_buf()
  local s_pos = vim.fn.getpos("'<")
  local e_pos = vim.fn.getpos("'>")
  local s_row, s_col = s_pos[2], s_pos[3] - 1
  local e_row, e_col = e_pos[2], e_pos[3]
  local lines = vim.api.nvim_buf_get_lines(bufnr, s_row - 1, e_row, false)
  if #lines == 0 then
    return
  end
  if #lines == 1 then
    lines[1] = left .. lines[1]:sub(s_col + 1, e_col) .. right
    vim.api.nvim_buf_set_text(bufnr, s_row - 1, s_col, e_row - 1, e_col, lines)
    vim.api.nvim_win_set_cursor(0, { s_row, s_col + #left })
  else
    lines[1] = left .. lines[1]:sub(s_col + 1)
    lines[#lines] = lines[#lines]:sub(1, e_col) .. right
    vim.api.nvim_buf_set_text(bufnr, s_row - 1, s_col, e_row - 1, e_col, lines)
    vim.api.nvim_win_set_cursor(0, { s_row, s_col + #left })
  end
end

-- Round brackets
vim.keymap.set("n", "<leader>m(", function()
  insert_pair_at_cursor("\\left( ", " \\right)")
  vim.cmd("startinsert")
end, { desc = "Round brackets" })
vim.keymap.set("i", "<C-Space>m(", function()
  insert_pair_at_cursor("\\left( ", " \\right)")
end, { desc = "Round brackets" })
vim.keymap.set("v", "<leader>m(", function()
  wrap_visual_selection("\\left( ", " \\right)")
end, { desc = "Round brackets" })

-- Curly braces
vim.keymap.set("n", "<leader>m{", function()
  insert_pair_at_cursor("\\left\\{ ", " \\right\\}")
  vim.cmd("startinsert")
end, { desc = "Curly braces" })
vim.keymap.set("i", "<C-Space>m{", function()
  insert_pair_at_cursor("\\left\\{ ", " \\right\\}")
end, { desc = "Curly braces" })
vim.keymap.set("v", "<leader>m{", function()
  wrap_visual_selection("\\left\\{ ", " \\right\\}")
end, { desc = "Curly braces" })

-- Angle brackets
vim.keymap.set("n", "<leader>m<", function()
  insert_pair_at_cursor("\\left\\langle ", " \\right\\rangle")
  vim.cmd("startinsert")
end, { desc = "Angle brackets" })
vim.keymap.set("i", "<C-Space>m<", function()
  insert_pair_at_cursor("\\left\\langle ", " \\right\\rangle")
end, { desc = "Angle brackets" })
vim.keymap.set("v", "<leader>m<", function()
  wrap_visual_selection("\\left\\langle ", " \\right\\rangle")
end, { desc = "Angle brackets" })

-- align* environment
vim.keymap.set("n", "<leader>ma", function()
  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = {
    "\\begin{align*}",
    "    ",
    "\\end{align*}",
  }
  vim.api.nvim_buf_set_lines(bufnr, row, row, false, lines)
  vim.api.nvim_win_set_cursor(0, { row + 2, 4 })
  vim.cmd("startinsert")
end, { desc = "Align* environment" })

-- enumerate environment
vim.keymap.set("n", "<leader>me", function()
  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = {
    "\\begin{enumerate}",
    "    ",
    "\\end{enumerate}",
  }
  vim.api.nvim_buf_set_lines(bufnr, row, row, false, lines)
  vim.api.nvim_win_set_cursor(0, { row + 2, 4 })
  vim.cmd("startinsert")
end, { desc = "Enumerate environment" })
