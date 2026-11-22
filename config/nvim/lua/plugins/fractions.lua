return {
  {
    "nvim-lua/plenary.nvim",
    ft = "tex",
    config = function()
      local function FractionConvert()
        local input = vim.fn.input("\\Frac(numerator; denominator): ")
        if input == "" then
          return
        end

        local inside = input:match("%b()")
        inside = inside and inside:sub(2, -2) or input

        local parts = {}
        for part in inside:gmatch("[^;]+") do
          table.insert(parts, vim.trim(part))
        end

        local numerator = parts[1] or "1"
        local denominator = parts[2] or "2"

        local tex = "\\frac{" .. numerator .. "}{" .. denominator .. "}"
        tex = tex:gsub("%z", "")

        local bufnr = vim.api.nvim_get_current_buf()
        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        vim.api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, { tex })
      end

      vim.keymap.set("n", "<leader>mF", FractionConvert, {
        noremap = true,
        silent = true,
        desc = "Insert fraction (format: a; b)",
      })
    end,
  },
}
