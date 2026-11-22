return {
  {
    "GCBallesteros/jupytext.nvim",
    lazy = false,
    config = true,
    opts = {
      style = "hydrogen",
      output_extension = "py",
      force_ft = "python",
    },
  },
  {
    "benlubas/molten-nvim",
    build = ":UpdateRemotePlugins",
    init = function()
      vim.g.python3_host_prog = vim.fn.expand("~/.venvs/nvim-molten/bin/python")
      vim.g.molten_image_provider = "image.nvim"
      vim.g.molten_auto_open_output = true
    end,
    keys = {
      { "<localleader>mi", "<cmd>MoltenInit<cr>" },
      { "<localleader>rr", "<cmd>MoltenReevaluateCell<cr>" },
      { "<localleader>rl", "<cmd>MoltenEvaluateLine<cr>" },
      { "<localleader>rd", "<cmd>MoltenDelete<cr>" },
      { "<localleader>os", "<cmd>noautocmd MoltenEnterOutput<cr>" },
    },
  },
  -- image.nvim (used by molten for inline output) is configured in plugins/pdf.lua
  {
    "GCBallesteros/NotebookNavigator.nvim",
    event = "VeryLazy",
    dependencies = {
      "nvim-mini/mini.comment",
      "benlubas/molten-nvim",
    },
    keys = {
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
    },
    config = function()
      require("notebook-navigator").setup({
        repl_provider = "molten",
        activate_hydra_keys = nil,
      })
    end,
  },
}
