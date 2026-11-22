return {
  {
    "benlubas/molten-nvim",
    build = ":UpdateRemotePlugins",
    keys = {
      { "<leader>o", "<cmd>noautocmd MoltenEnterOutput<cr>" }, -- jump into output (same window)
      { "<leader>O", "<cmd>b#<cr>" }, -- go back to the notebook buffer
      {
        "<leader>R",
        function()
          vim.cmd("normal! ggVG")
          vim.cmd("MoltenEvaluateVisual")
        end,
      },
    },
  },
}
