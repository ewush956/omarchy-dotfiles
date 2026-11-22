-- pdfview: render PDF pages inside a neovim buffer via image.nvim
--
-- Pages are rasterized with pdftoppm (poppler) into a content-hashed cache and
-- drawn with image.nvim's kitty backend, so what you see is the real rendered
-- page -- layout, figures, hand-drawn signatures and all.
--
-- Two things about kitty graphics drive the structure here:
--
--  * Images live in the *terminal*, not the buffer. Nothing about hiding a
--    buffer, switching tmux panes or closing a window deletes them; something
--    has to emit the delete escape. image.nvim tries, but its own auto-clear
--    pass returns after the first image it clears, so a document showing five
--    pages leaves four behind. pdfview therefore owns the lifecycle of its own
--    images and clears them itself whenever the buffer stops being on screen.
--
--  * Geometry is in pixels-per-cell, which image.nvim caches and only refreshes
--    on VimResized. Moving a window between monitors of different scale changes
--    the cell size while leaving the character grid identical, so VimResized
--    never fires and every page keeps the old monitor's dimensions. pdfview
--    polls the tty's pixel geometry directly and forces a re-read on change.

local M = {}

M.opts = {
  dpi = 180, -- rasterization DPI; bump for finer detail at higher zoom
  fit = "page", -- "page" (one page per screen) or "width"
  zoom = 1.0,
  gap = 1, -- blank lines between pages (carries the page label)
  preload = 2, -- pages kept rasterized/rendered on each side of the viewport
  label = true,
  poll = 400, -- ms between tty pixel-geometry checks while a pdf is visible
}

---@type table<integer, table>
local states = {}
local group = vim.api.nvim_create_augroup("pdfview", { clear = true })

-- true while the editor is unfocused (another app, or another tmux pane/window)
local suspended = false
-- true while we are synthesising a VimResized, to keep our own handler out
local syncing = false

local function notify(msg, level)
  vim.notify("pdfview: " .. msg, level or vim.log.levels.INFO)
end

-- ── terminal pixel geometry ────────────────────────────────────────────────
-- image.nvim's cache is authoritative for the geometry maths; this is only a
-- cheap detector telling us when that cache has gone stale.

local ffi_ok, ffi = pcall(require, "ffi")
if ffi_ok then
  -- distinct type name: image.nvim already cdef'd `winsize`, and redefining a
  -- struct is an error
  pcall(
    ffi.cdef,
    "typedef struct { unsigned short row; unsigned short col; unsigned short xpixel; unsigned short ypixel; } pdfview_winsize;"
  )
  pcall(ffi.cdef, "int ioctl(int, int, ...);")
end

local TIOCGWINSZ = vim.fn.has("linux") == 1 and 0x5413 or 0x40087468

local function tty_signature()
  if not ffi_ok then return nil end
  local ok, sig = pcall(function()
    local sz = ffi.new("pdfview_winsize")
    if ffi.C.ioctl(1, TIOCGWINSZ, sz) ~= 0 then return nil end
    return ("%d:%d:%d:%d"):format(sz.col, sz.row, sz.xpixel, sz.ypixel)
  end)
  return ok and sig or nil
end

local last_sig = tty_signature()

-- image.nvim's only invalidation hook for its cell-size cache is a VimResized
-- autocmd, so fire one. `syncing` stops us reacting to our own event.
local function force_term_refresh()
  syncing = true
  pcall(vim.api.nvim_exec_autocmds, "VimResized", {})
  syncing = false
end

---@return boolean changed
local function term_changed()
  local sig = tty_signature()
  if not sig or sig == last_sig then return false end
  last_sig = sig
  force_term_refresh()
  return true
end

-- image.nvim is only usable when it is loaded *and* the terminal reported a
-- pixel cell size; otherwise we fall back to extracted text.
local function image_api()
  local ok, api = pcall(require, "image")
  if not ok then return nil end
  local ok_term, term = pcall(function()
    return require("image/utils").term.get_size()
  end)
  if not ok_term or not term or not term.cell_width or term.cell_width == 0 then return nil end
  return api, term
end

-- ── windows ───────────────────────────────────────────────────────────────

-- Only windows in the *current* tabpage count as showing the buffer: an image
-- whose window lives on another tab is off screen and must be cleared.
local function visible_win(buf)
  local cur = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(cur) and vim.api.nvim_win_get_buf(cur) == buf then return cur end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then return win end
  end
  return nil
end

local win_style = {
  wrap = false,
  number = false,
  relativenumber = false,
  signcolumn = "no",
  cursorline = false,
  colorcolumn = "",
  list = false,
  foldenable = false,
  scrolloff = 0,
  sidescrolloff = 0,
  fillchars = "eob: ",
}

-- Any gutter shifts the image, so every window the pdf lands in gets styled,
-- not just the one it was first opened in.
local function style_win(win)
  for opt, value in pairs(win_style) do
    pcall(function()
      vim.wo[win][opt] = value
    end)
  end
end

-- ── debounce ──────────────────────────────────────────────────────────────

local timers = {}

local function debounce(key, ms, fn)
  local existing = timers[key]
  if existing then pcall(function()
    existing:stop()
  end) end
  timers[key] = vim.defer_fn(function()
    timers[key] = nil
    fn()
  end, ms)
end

-- ── rasterization ─────────────────────────────────────────────────────────

local function probe(path)
  if vim.fn.executable("pdfinfo") == 0 then return nil, "pdfinfo not found (install poppler)" end
  local res = vim.system({ "pdfinfo", path }, { text = true }):wait()
  if res.code ~= 0 then return nil, vim.trim(res.stderr or "") ~= "" and vim.trim(res.stderr) or "pdfinfo failed" end
  local out = res.stdout or ""
  local pages = tonumber(out:match("Pages:%s*(%d+)")) or 0
  if pages < 1 then return nil, "could not determine page count" end
  local w = tonumber(out:match("Page size:%s*([%d%.]+)")) or 612
  local h = tonumber(out:match("Page size:%s*[%d%.]+%s*x%s*([%d%.]+)")) or 792
  local rot = tonumber(out:match("Page rot:%s*(%-?%d+)")) or 0
  if rot % 180 == 90 then
    w, h = h, w
  end
  return { pages = pages, w = w, h = h }
end

-- Cache keyed on path + mtime + size + dpi, so an edited PDF re-rasterizes but
-- reopening an unchanged one is instant.
local function cache_dir(path, dpi)
  local stat = vim.uv.fs_stat(path)
  local key = vim.fn.sha256(
    table.concat({ path, tostring(stat and stat.mtime.sec or 0), tostring(stat and stat.size or 0), tostring(dpi) }, ":")
  )
  local dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "pdfview", key:sub(1, 16))
  vim.fn.mkdir(dir, "p")
  return dir
end

local function page_png(st, n)
  return vim.fs.joinpath(st.dir, ("page-%d.png"):format(n))
end

-- pdftoppm -singlefile gives a deterministic filename, which lets us rasterize
-- one page at a time and stay lazy on large documents. Callbacks queue per page
-- so a second request while a job is in flight still gets answered.
local function ensure_page(st, n, cb)
  local png = page_png(st, n)
  if vim.uv.fs_stat(png) then return cb(png) end

  local queued = st.jobs[n]
  if queued then
    queued[#queued + 1] = cb
    return
  end
  st.jobs[n] = { cb }

  local prefix = png:gsub("%.png$", "")
  vim.system({
    "pdftoppm",
    "-png",
    "-r",
    tostring(st.dpi),
    "-f",
    tostring(n),
    "-l",
    tostring(n),
    "-singlefile",
    st.path,
    prefix,
  }, { text = true }, function(res)
    vim.schedule(function()
      local callbacks = st.jobs[n] or {}
      st.jobs[n] = nil
      if not vim.api.nvim_buf_is_valid(st.buf) then return end
      if res.code == 0 and vim.uv.fs_stat(png) then
        for _, fn in ipairs(callbacks) do
          fn(png)
        end
      else
        notify(("failed to rasterize page %d: %s"):format(n, vim.trim(res.stderr or "")), vim.log.levels.ERROR)
      end
    end)
  end)
end

-- ── image lifecycle ───────────────────────────────────────────────────────

local function clear_images(st, keep_lo, keep_hi)
  for n, img in pairs(st.images) do
    if not keep_lo or n < keep_lo or n > keep_hi then
      pcall(function()
        img:clear()
      end)
      st.images[n] = nil
    end
  end
end

local function clear_all()
  for _, st in pairs(states) do
    clear_images(st)
  end
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

-- ── geometry poll ─────────────────────────────────────────────────────────

local poll_timer = nil

local function any_visible()
  for buf in pairs(states) do
    if vim.api.nvim_buf_is_valid(buf) and visible_win(buf) then return true end
  end
  return false
end

-- WinResized fires for any window change in the tab; only a pdf whose own
-- window actually changed shape needs its pages thrown away and redrawn.
local function geometry_stale()
  for buf, st in pairs(states) do
    if vim.api.nvim_buf_is_valid(buf) then
      local win = visible_win(buf)
      if win and (st.ww ~= vim.api.nvim_win_get_width(win) or st.wh ~= vim.api.nvim_win_get_height(win)) then
        return true
      end
    end
  end
  return false
end

local function relayout_visible()
  for buf in pairs(states) do
    if vim.api.nvim_buf_is_valid(buf) and visible_win(buf) then M.layout(buf) end
  end
end

local function poll_stop()
  if not poll_timer then return end
  pcall(function()
    poll_timer:stop()
    poll_timer:close()
  end)
  poll_timer = nil
end

-- Moving the terminal window to a monitor with a different scale keeps focus
-- and keeps the character grid, so no autocmd fires -- only the tty's pixel
-- dimensions change. Poll for that, but only while a pdf is actually on screen.
local function poll_start()
  if poll_timer or not M.opts.poll or M.opts.poll <= 0 then return end
  poll_timer = vim.uv.new_timer()
  if not poll_timer then return end
  poll_timer:start(
    M.opts.poll,
    M.opts.poll,
    vim.schedule_wrap(function()
      if not any_visible() then return poll_stop() end
      if term_changed() then
        clear_all()
        relayout_visible()
      end
    end)
  )
end

-- ── layout & drawing ──────────────────────────────────────────────────────

local function current_page(st, win)
  local view = vim.api.nvim_win_call(win, function()
    return vim.fn.winsaveview()
  end)
  return math.max(1, math.min(st.info.pages, math.floor((view.topline - 1) / st.stride) + 1))
end

-- Recompute page geometry for the current window size and refill the buffer
-- with the blank canvas the images are drawn over. Bumping `gen` invalidates
-- any rasterization callback still in flight for the previous geometry.
function M.layout(buf)
  local st = states[buf]
  if not st or not st.info then return end
  local win = visible_win(buf)
  if not win then return end
  local _, term = image_api()
  if not term then return end

  st.win = win
  style_win(win)

  local wh = vim.api.nvim_win_get_height(win)
  local ww = vim.api.nvim_win_get_width(win)
  local ar = st.info.w / st.info.h
  local cols, rows

  if st.fit == "width" then
    cols = math.max(1, math.floor((ww - 2) * st.zoom))
    rows = math.max(1, math.floor(cols * term.cell_width / ar / term.cell_height))
  else
    rows = math.max(1, math.floor((wh - st.gap) * st.zoom))
    cols = math.max(1, math.floor(rows * term.cell_height * ar / term.cell_width))
    if cols > ww - 2 then
      cols = math.max(1, ww - 2)
      rows = math.max(1, math.floor(cols * term.cell_width / ar / term.cell_height))
    end
  end

  st.ww, st.wh = ww, wh
  st.rows, st.cols = rows, cols
  st.x = math.max(0, math.floor((ww - cols) / 2))
  st.stride = rows + st.gap
  st.gen = (st.gen or 0) + 1

  local lines = {}
  for n = 1, st.info.pages do
    for _ = 1, rows do
      lines[#lines + 1] = ""
    end
    for g = 1, st.gap do
      if g == 1 and st.label then
        local text = ("── page %d / %d ──"):format(n, st.info.pages)
        local pad = math.max(0, math.floor((ww - vim.fn.strdisplaywidth(text)) / 2))
        lines[#lines + 1] = string.rep(" ", pad) .. text
      else
        lines[#lines + 1] = ""
      end
    end
  end
  -- trailing slack so the final page can still be scrolled to the top
  for _ = 1, math.max(0, wh - st.stride) do
    lines[#lines + 1] = ""
  end
  set_lines(buf, lines)

  clear_images(st)

  -- hold the reader's place across the relayout
  local page = math.max(1, math.min(st.info.pages, st.page or 1))
  local line = math.min((page - 1) * st.stride + 1, vim.api.nvim_buf_line_count(buf))
  pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
  pcall(vim.api.nvim_win_call, win, function()
    vim.cmd("normal! zt")
  end)

  M.refresh(buf)
end

local function draw(buf, n, png, gen)
  local st = states[buf]
  if not st or st.gen ~= gen or suspended then return end
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local api, term = image_api()
  if not api then return end
  local win = visible_win(buf)
  if not win then return end

  local id = ("pdfview-%d-%d"):format(buf, n)
  local existing = st.images[n]
  if existing then
    pcall(function()
      existing:clear()
    end)
    st.images[n] = nil
  end
  -- from_file hands back the live instance for a known id, stale geometry and
  -- all, so make sure image.nvim has forgotten this one first
  pcall(api.clear, id)

  local ok, img = pcall(api.from_file, png, {
    id = id,
    window = win,
    buffer = buf,
    x = st.x,
    y = (n - 1) * st.stride,
    width = st.cols,
    height = st.rows,
    max_width_window_percentage = 100,
    max_height_window_percentage = 100,
  })
  if not ok or not img then return end

  img.geometry.y = (n - 1) * st.stride
  img.geometry.width = st.cols
  img.geometry.height = st.rows

  -- The backend fits the page to its own cell rounding, which can differ from
  -- our estimate by a column or two. Predict that with the same maths it uses
  -- and centre on the result, so the page is drawn once in the right place
  -- instead of being drawn and then moved.
  local fit_ok, drawn = pcall(function()
    local mathu = require("image/utils/math")
    local w = mathu.adjust_to_aspect_ratio(term, img.image_width, img.image_height, st.cols, st.rows)
    return w
  end)
  if fit_ok and type(drawn) == "number" and drawn > 0 then
    img.geometry.x = math.max(0, math.floor((vim.api.nvim_win_get_width(win) - drawn) / 2))
  else
    img.geometry.x = st.x
  end

  st.images[n] = img
  pcall(function()
    img:render()
  end)
end

-- Rasterize + draw the pages around the viewport, drop the rest.
function M.refresh(buf)
  local st = states[buf]
  if not st or not st.info or not st.stride then return end
  if suspended then return end
  local win = visible_win(buf)
  if not win then return end
  if not image_api() then return end

  st.win = win
  local cur = current_page(st, win)
  st.page = cur
  local lo = math.max(1, cur - st.preload)
  local hi = math.min(st.info.pages, cur + st.preload)
  clear_images(st, lo, hi)

  local gen = st.gen
  for n = lo, hi do
    -- already drawn for this geometry: image.nvim re-renders it on scroll
    if not st.images[n] then
      ensure_page(st, n, function(png)
        draw(buf, n, png, gen)
      end)
    end
  end
end

-- Reconcile every pdf buffer against what is actually on screen. This is the
-- one place that decides whether images should exist, so hiding a buffer,
-- moving between splits, switching tabs and closing windows all take the same
-- path.
local function reconcile()
  for buf, st in pairs(states) do
    if not vim.api.nvim_buf_is_valid(buf) then
      clear_images(st)
      states[buf] = nil
    else
      local win = visible_win(buf)
      if not win or suspended then
        if next(st.images) then clear_images(st) end
        st.win = nil
      elseif st.win ~= win then
        -- a different window means different dimensions
        M.layout(buf)
      else
        M.refresh(buf)
      end
    end
  end
  if any_visible() then
    poll_start()
  else
    poll_stop()
  end
end

-- ── commands ──────────────────────────────────────────────────────────────

function M.goto_page(buf, n)
  local st = states[buf]
  if not st or not st.info or not st.stride then return end
  local win = visible_win(buf)
  if not win then return end
  n = math.max(1, math.min(st.info.pages, n))
  local line = math.min((n - 1) * st.stride + 1, vim.api.nvim_buf_line_count(buf))
  vim.api.nvim_win_set_cursor(win, { line, 0 })
  vim.api.nvim_win_call(win, function()
    vim.cmd("normal! zt")
  end)
  M.refresh(buf)
end

function M.set(buf, changes)
  local st = states[buf]
  if not st then return end
  for k, v in pairs(changes) do
    st[k] = v
  end
  if changes.dpi then
    st.dir = cache_dir(st.path, st.dpi)
    st.jobs = {}
  end
  M.layout(buf)
end

function M.reload(buf)
  local st = states[buf]
  if not st then return end
  clear_images(st)
  vim.fn.delete(st.dir, "rf")
  st.dir = cache_dir(st.path, st.dpi)
  st.jobs = {}
  local info, err = probe(st.path)
  if not info then return notify(err, vim.log.levels.ERROR) end
  st.info = info
  M.layout(buf)
end

-- Escape hatch for leftover graphics: re-read the terminal, drop every page we
-- own (or, with `all`, every image on the terminal) and draw again from scratch.
function M.redraw(all)
  local api = image_api()
  clear_all()
  if all and api then pcall(api.clear) end
  force_term_refresh()
  last_sig = tty_signature()
  vim.cmd("redraw!")
  relayout_visible()
end

-- Snapshot of what pdfview thinks is going on, for `:checkhealth`-style triage.
function M.debug()
  local api, term = image_api()
  local info = {
    suspended = suspended,
    tty = tty_signature(),
    term = term and { cols = term.screen_cols, rows = term.screen_rows, cw = term.cell_width, ch = term.cell_height }
      or nil,
    image_api = api ~= nil,
    polling = poll_timer ~= nil,
    buffers = {},
  }
  for buf, st in pairs(states) do
    local drawn = {}
    for n, img in pairs(st.images) do
      drawn[#drawn + 1] = ("%d(x=%s,y=%s,rendered=%s)"):format(
        n,
        tostring(img.geometry and img.geometry.x),
        tostring(img.geometry and img.geometry.y),
        tostring(img.is_rendered)
      )
    end
    table.sort(drawn)
    info.buffers[tostring(buf)] = {
      path = st.path,
      pages = st.info and st.info.pages,
      page = st.page,
      gen = st.gen,
      win = st.win,
      visible_win = visible_win(buf),
      rows = st.rows,
      cols = st.cols,
      stride = st.stride,
      x = st.x,
      dir = st.dir,
      jobs = vim.tbl_keys(st.jobs),
      images = drawn,
    }
  end
  return info
end

-- Text-only fallback for terminals without graphics support.
local function text_fallback(buf, path, reason)
  local lines = { "" }
  if vim.fn.executable("pdftotext") == 1 then
    local res = vim.system({ "pdftotext", "-layout", path, "-" }, { text = true }):wait()
    if res.code == 0 then lines = vim.split(res.stdout or "", "\n", { plain = true }) end
  end
  table.insert(lines, 1, ("── pdfview: %s — showing extracted text ──"):format(reason))
  set_lines(buf, lines)
  vim.bo[buf].filetype = "text"
end

local function setup_keymaps(buf)
  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, nowait = true, desc = "pdfview: " .. desc })
  end
  local st = function()
    return states[buf]
  end

  map("]p", function()
    M.goto_page(buf, (st().page or 1) + 1)
  end, "next page")
  map("[p", function()
    M.goto_page(buf, (st().page or 1) - 1)
  end, "previous page")
  map("<PageDown>", function()
    M.goto_page(buf, (st().page or 1) + 1)
  end, "next page")
  map("<PageUp>", function()
    M.goto_page(buf, (st().page or 1) - 1)
  end, "previous page")
  map("gg", function()
    M.goto_page(buf, 1)
  end, "first page")
  map("G", function()
    M.goto_page(buf, st().info and st().info.pages or 1)
  end, "last page")
  map("gp", function()
    vim.ui.input({ prompt = "Go to page: " }, function(input)
      local n = tonumber(input)
      if n then M.goto_page(buf, n) end
    end)
  end, "go to page")

  -- scroll the window rather than the cursor, so movement always moves the view
  map("j", "<C-e>", "scroll down")
  map("k", "<C-y>", "scroll up")
  map("<Down>", "<C-e>", "scroll down")
  map("<Up>", "<C-y>", "scroll up")

  map("+", function()
    M.set(buf, { zoom = math.min(6, (st().zoom or 1) * 1.25) })
  end, "zoom in")
  map("-", function()
    M.set(buf, { zoom = math.max(0.2, (st().zoom or 1) / 1.25) })
  end, "zoom out")
  map("=", function()
    M.set(buf, { zoom = 1.0 })
  end, "reset zoom")
  map("f", function()
    M.set(buf, { fit = "page", zoom = 1.0 })
  end, "fit page")
  map("w", function()
    M.set(buf, { fit = "width", zoom = 1.0 })
  end, "fit width")
  map("<", function()
    M.set(buf, { dpi = math.max(72, st().dpi - 60) })
  end, "lower render DPI")
  map(">", function()
    M.set(buf, { dpi = math.min(600, st().dpi + 60) })
  end, "raise render DPI")

  map("<C-l>", function()
    M.redraw(false)
  end, "force redraw")
  map("r", function()
    M.reload(buf)
  end, "reload from disk")
  map("o", function()
    vim.system({ "zathura", states[buf].path }, { detach = true })
  end, "open in zathura")
  map("q", "<cmd>bdelete<cr>", "close")
end

function M.open(buf, path)
  -- re-entrant: `:e` on an already-open pdf must not stack autocmds or leak images
  local prev = states[buf]
  if prev then
    clear_images(prev)
    states[buf] = nil
  end

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = true
  vim.bo[buf].undolevels = -1
  vim.bo[buf].filetype = "pdf"

  local win = visible_win(buf)
  if win then style_win(win) end

  if vim.fn.executable("pdftoppm") == 0 then
    return text_fallback(buf, path, "pdftoppm not found (install poppler)")
  end
  if not image_api() then return text_fallback(buf, path, "no terminal graphics available") end

  local info, err = probe(path)
  if not info then return text_fallback(buf, path, err) end

  local st = vim.tbl_extend("force", vim.deepcopy(M.opts), {
    buf = buf,
    path = path,
    info = info,
    images = {},
    jobs = {},
    page = 1,
    gen = 0,
    win = nil,
  })
  st.dir = cache_dir(path, st.dpi)
  states[buf] = st

  set_lines(
    buf,
    { ("rendering %s (%d page%s)…"):format(vim.fn.fnamemodify(path, ":t"), info.pages, info.pages == 1 and "" or "s") }
  )
  setup_keymaps(buf)
  poll_start()

  -- image.nvim cannot draw before the UI is up; defer the first layout past
  -- VimEnter when the pdf was opened from the command line.
  local function initial_layout()
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      term_changed()
      M.layout(buf)
    end)
  end
  if vim.v.vim_did_enter == 1 then
    initial_layout()
  else
    vim.api.nvim_create_autocmd("VimEnter", { group = group, once = true, callback = initial_layout })
  end
end

function M.setup(opts)
  M.opts = vim.tbl_extend("force", M.opts, opts or {})
  -- re-runnable: a config reload must not stack a second copy of every handler
  vim.api.nvim_clear_autocmds({ group = group })

  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = { "*.pdf", "*.PDF" },
    callback = function(ev)
      local path = vim.fn.fnamemodify(ev.match ~= "" and ev.match or ev.file, ":p")
      M.open(ev.buf, path)
    end,
  })

  -- Visibility. The *Leave events fire before the switch completes, so the pass
  -- is deferred a tick and then sees the settled layout.
  vim.api.nvim_create_autocmd({
    "BufEnter",
    "BufLeave",
    "BufWinEnter",
    "BufWinLeave",
    "WinEnter",
    "WinLeave",
    "WinNew",
    "WinClosed",
    "TabEnter",
    "TabLeave",
    "TabClosed",
    "TabNewEntered",
  }, {
    group = group,
    callback = function()
      if not next(states) then return end
      debounce("reconcile", 10, reconcile)
    end,
  })

  -- Resize. Clear first so no page sits at the old dimensions while the drag is
  -- in progress, then relayout once things settle.
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = group,
    callback = function()
      if syncing or not next(states) then return end
      local sig = tty_signature()
      local pixels_changed = sig ~= nil and sig ~= last_sig
      last_sig = sig or last_sig
      if not pixels_changed and not geometry_stale() then return end
      clear_all()
      debounce("layout", 80, relayout_visible)
    end,
  })

  -- Focus. Covers switching apps and, with tmux focus-events on, switching tmux
  -- panes and windows -- the cases that used to leave pages drawn over whatever
  -- replaced them.
  vim.api.nvim_create_autocmd("FocusLost", {
    group = group,
    callback = function()
      suspended = true
      clear_all()
    end,
  })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      suspended = false
      if not next(states) then return end
      -- the window may have been moved to another monitor while unfocused
      debounce("focus", 20, function()
        if term_changed() then
          relayout_visible()
        else
          reconcile()
        end
      end)
    end,
  })

  -- If a FocusGained is ever dropped, editor activity is proof we have focus;
  -- without this the pages would stay blank until the next focus change.
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorHold", "ModeChanged", "WinScrolled", "BufEnter" }, {
    group = group,
    callback = function()
      if not suspended or not next(states) then return end
      suspended = false
      debounce("unsuspend", 20, reconcile)
    end,
  })

  vim.api.nvim_create_autocmd("WinScrolled", {
    group = group,
    callback = function()
      if not next(states) or suspended then return end
      debounce("scroll", 30, function()
        for buf in pairs(states) do
          if vim.api.nvim_buf_is_valid(buf) and visible_win(buf) then M.refresh(buf) end
        end
      end)
    end,
  })

  -- Leaving nvim (or backgrounding it) must not strand graphics on the terminal.
  vim.api.nvim_create_autocmd({ "VimSuspend", "VimLeavePre" }, {
    group = group,
    callback = function()
      suspended = true
      clear_all()
    end,
  })
  vim.api.nvim_create_autocmd("VimResume", {
    group = group,
    callback = function()
      suspended = false
      debounce("resume", 50, function()
        term_changed()
        relayout_visible()
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    callback = function(ev)
      local st = states[ev.buf]
      if st then
        clear_images(st)
        states[ev.buf] = nil
      end
      if not any_visible() then poll_stop() end
    end,
  })

  vim.api.nvim_create_user_command("PdfPage", function(a)
    M.goto_page(vim.api.nvim_get_current_buf(), tonumber(a.args) or 1)
  end, { nargs = 1, desc = "pdfview: go to page" })
  vim.api.nvim_create_user_command("PdfFit", function(a)
    M.set(vim.api.nvim_get_current_buf(), { fit = a.args, zoom = 1.0 })
  end, {
    nargs = 1,
    complete = function()
      return { "page", "width" }
    end,
    desc = "pdfview: fit mode",
  })
  vim.api.nvim_create_user_command("PdfDpi", function(a)
    M.set(vim.api.nvim_get_current_buf(), { dpi = tonumber(a.args) or M.opts.dpi })
  end, { nargs = 1, desc = "pdfview: set render DPI" })
  vim.api.nvim_create_user_command("PdfReload", function()
    M.reload(vim.api.nvim_get_current_buf())
  end, { desc = "pdfview: re-rasterize from disk" })
  vim.api.nvim_create_user_command("PdfRedraw", function(a)
    M.redraw(a.bang)
  end, { bang = true, desc = "pdfview: force redraw (! clears every image on the terminal)" })
  vim.api.nvim_create_user_command("PdfDebug", function()
    vim.print(M.debug())
  end, { desc = "pdfview: dump renderer state" })
  vim.api.nvim_create_user_command("PdfText", function()
    local st = states[vim.api.nvim_get_current_buf()]
    if not st then return notify("not a pdf buffer", vim.log.levels.WARN) end
    local res = vim.system({ "pdftotext", "-layout", st.path, "-" }, { text = true }):wait()
    vim.cmd("vsplit")
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, b)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.split(res.stdout or "", "\n", { plain = true }))
    vim.bo[b].modifiable = false
  end, { desc = "pdfview: extracted text in a split" })
end

return M
