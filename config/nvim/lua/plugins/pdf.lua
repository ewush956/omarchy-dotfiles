-- In-buffer PDF viewing.
--
-- image.nvim owns the kitty graphics plumbing (shared with molten); the local
-- `pdfview` module rasterizes pages with pdftoppm and draws them over a blank
-- buffer canvas. This is the single source of truth for the image.nvim spec.
return {
  {
    "3rd/image.nvim",
    lazy = false, -- BufReadCmd for `nvim foo.pdf` fires before VeryLazy
    priority = 100,
    opts = {
      backend = "kitty",
      processor = "magick_cli",
      -- don't leak images into other tmux windows
      tmux_show_only_in_active_window = true,
      window_overlap_clear_enabled = true,
    },
    init = function()
      -- Neovim >= 0.11 wraps redraws in synchronized-output frames; image.nvim
      -- writes graphics escapes straight to the tty, and those writes get
      -- swallowed by the frame. Turning termsync off lets them through.
      vim.o.termsync = false
    end,
    config = function(_, opts)
      require("image").setup(opts)
      require("pdfview").setup({
        dpi = 180, -- raise for finer detail (signatures, thin rules)
        fit = "page", -- "page" = one page per screen, "width" = fill width
      })
    end,
  },
}
