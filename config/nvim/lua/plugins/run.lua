return {
  {
    "CRAG666/code_runner.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "akinsho/toggleterm.nvim" },
    config = function()
      require("code_runner").setup({
        mode = "toggleterm", -- <- use mode, not term={"toggleterm"}
        focus = true,
        startinsert = true,
        term = {
          position = "bot", -- "bot" | "top" | "left" | "right"
          size = 12, -- MUST be a number
        },
        filetype = {
          python = "python3 -u $file",
          javascript = "node $file",
          typescript = "tsx $file",
          lua = "lua $file",
          sh = "bash $file",
          ruby = "ruby $file",
          go = "go run $file",
          c = { "cd $dir &&", "gcc $fileName -O2 -o $fileNameWithoutExt &&", "$dir/$fileNameWithoutExt" },
          cpp = { "cd $dir &&", "g++ $fileName -std=c++17 -O2 -o $fileNameWithoutExt &&", "$dir/$fileNameWithoutExt" },
          java = { "cd $dir &&", "javac $fileName &&", "java $fileNameWithoutExt" },
        },
      })
      vim.keymap.set("n", "<leader>rr", ":RunFile<CR>", { desc = "Run current file" })
      vim.keymap.set("n", "<leader>rl", ":CRLast<CR>", { desc = "Re-run last" })
      vim.keymap.set("n", "<leader>rt", ":ToggleTerm<CR>", { desc = "Toggle terminal" })
    end,
  },
}
