return {
  {
    "lervag/vimtex",
    config = function()
      vim.g.vimtex_view_method = "zathura"
      vim.g.vimtex_compiler_method = "latexmk"
      vim.g.vimtex_compiler_latexmk = {
        build_dir = "",
        continuous = true,
        options = { "-pdf", "-interaction=nonstopmode", "-synctex=1" },
      }
      vim.cmd([[
        autocmd FileType tex nnoremap <buffer> <leader>ll :VimtexCompile<CR>
        autocmd FileType tex nnoremap <buffer> <leader>lv :VimtexView<CR>
      ]])
    end,
  },
}
