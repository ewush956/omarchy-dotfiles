return {
  {
    "nvim-lua/plenary.nvim",
    ft = "tex",
    config = function()
      -- MATRIX FUNCTION
      local function MatrixConvert()
        local input = vim.fn.input("\\Matrix(...) input: ")
        if input == "" then
          return
        end

        local inside = input:match("%b()")
        inside = inside and inside:sub(2, -2) or input

        local rows = {}
        for row in inside:gmatch("[^;]+") do
          row = row:gsub("^%s+", ""):gsub("%s+$", "")
          local cols = {}
          for cell in row:gmatch("[^,%s]+") do
            table.insert(cols, cell)
          end
          table.insert(rows, table.concat(cols, " & "))
        end

        local tex = "\\begin{pmatrix}\n" .. table.concat(rows, " \\\\\n") .. "\n\\end{pmatrix}"
        tex = tex:gsub("%z", "")

        local bufnr = vim.api.nvim_get_current_buf()
        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        local lines = {}
        for s in tex:gmatch("([^\n]*)\n?") do
          if s ~= "" or #lines == 0 then
            table.insert(lines, s)
          end
        end
        vim.api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, lines)
      end

      vim.keymap.set("n", "<leader>mM", MatrixConvert, {
        noremap = true,
        silent = true,
        desc = "Insert matrix (rows separated by ';')",
      })

      -- FRACTION FUNCTION
      local function FractionConvert()
        local input = vim.fn.input("\\Frac(...) input (num ; den): ")
        if input == "" then
          return
        end

        local inside = input:match("%b()")
        inside = inside and inside:sub(2, -2) or input

        local parts = {}
        for part in inside:gmatch("[^;]+") do
          part = part:gsub("^%s+", ""):gsub("%s+$", "")
          table.insert(parts, part)
        end

        local num = parts[1] or "1"
        local den = parts[2] or "1"
        local tex = string.format("\\frac{%s}{%s}", num, den)

        local bufnr = vim.api.nvim_get_current_buf()
        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        vim.api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, { tex })
      end

      vim.keymap.set("n", "<leader>mF", FractionConvert, {
        noremap = true,
        silent = true,
        desc = "Fraction (num;den)",
      })
    end,
  },
}
