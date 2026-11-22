return {
  {
    "GCBallesteros/NotebookNavigator.nvim",
    dependencies = { "benlubas/molten-nvim", "nvim-mini/mini.comment" },
    keys = {
      {
        "<leader>X",
        function()
          require("notebook-navigator").run_cell()
        end,
      },
      {
        "<leader>x",
        function()
          require("notebook-navigator").run_and_move()
        end,
      },
      {
        "]h",
        function()
          require("notebook-navigator").move_cell("d")
        end,
      },
      {
        "[h",
        function()
          require("notebook-navigator").move_cell("u")
        end,
      },
    },
    config = function()
      require("notebook-navigator").setup({
        repl_provider = "molten",
        activate_hydra_keys = nil,
      })
    end,
  },
}
