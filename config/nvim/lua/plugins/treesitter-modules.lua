return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      opts.highlight = opts.highlight or { enable = true }
    end,
  },
  {
    "MeanderingProgrammer/treesitter-modules.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      incremental_selection = {
        enable = true,
        keymaps = {
          init_selection = "<A-o>",
          node_incremental = "<A-o>",
          scope_incremental = "<A-O>",
          node_decremental = "<A-i>",
        },
      },
    },
  },
}
