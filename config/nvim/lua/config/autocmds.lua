-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

do
  local ns = vim.api.nvim_create_namespace("ctrlr_paste_guard")
  local ctrl_r = vim.api.nvim_replace_termcodes("<C-r>", true, false, true)

  local armed = false
  local augroup = vim.api.nvim_create_augroup("CtrlRPasteGuard", { clear = false })

  vim.on_key(function(k)
    if vim.fn.mode() ~= "i" then
      return
    end

    if not armed and k == ctrl_r then
      armed = true
      vim.o.paste = true

      vim.api.nvim_clear_autocmds({ group = augroup, buffer = 0 })
      vim.api.nvim_create_autocmd("TextChangedI", {
        group = augroup,
        buffer = 0,
        once = true,
        callback = function()
          vim.o.paste = false
          armed = false
        end,
      })
    end
  end, ns)
end

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.g.python3_host_prog = vim.fn.expand("~/.venvs/nvim/bin/python")
  end,
})

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.txt",
  callback = function()
    vim.opt_local.spell = true
    vim.opt_local.spelllang = "en_us"
    vim.opt_local.spellsuggest = { "best", 9 }
  end,
})
