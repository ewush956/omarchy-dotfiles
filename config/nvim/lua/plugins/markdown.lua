return {
  "MeanderingProgrammer/render-markdown.nvim",
  name = "render-markdown", -- optional, but ensures the name is correct
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  ft = "markdown", -- Automatically load for markdown files
  config = function()
    require("render-markdown").setup({
      -- Optional configuration options (defaults are often fine)
      -- For example, to enable LaTeX rendering:
      -- latex = { enabled = true },
    })
  end,
}
