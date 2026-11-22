-- return {
--   {
--     "nyoom-engineering/oxocarbon.nvim",
--     name = "oxocarbon",
--     lazy = false,
--     priority = 1000,
--     config = function()
--       vim.opt.termguicolors = true
--       vim.opt.background = "dark"
--       vim.cmd.colorscheme("oxocarbon")
--     end,
--   },
-- }
return {
  {
    "sainnhe/everforest",
    lazy = false,
    priority = 1000,
    config = function()
      vim.cmd.colorscheme("everforest")
    end,
  },
}
