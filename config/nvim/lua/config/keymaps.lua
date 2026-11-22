-- ~/.config/nvim/lua/config/keymaps.lua
-- Runner: reuse single terminal tab/buffer, safe save, clean autoclose

require("keymaps.latex")

local api = vim.api
local fn = vim.fn

local function is_term_buf(buf)
  return buf and api.nvim_buf_is_valid(buf) and api.nvim_buf_get_option(buf, "buftype") == "terminal"
end

local function term_tab_and_buf()
  for _, tp in ipairs(api.nvim_list_tabpages()) do
    for _, win in ipairs(api.nvim_tabpage_list_wins(tp)) do
      local buf = api.nvim_win_get_buf(win)
      if is_term_buf(buf) then
        return tp, win, buf
      end
    end
  end
  return nil, nil, nil
end

local function tab_valid(tp)
  return tp and pcall(api.nvim_tabpage_list_wins, tp)
end

local function make_term_autoclose(buf, tab)
  if not is_term_buf(buf) then
    return
  end
  local group_name = ("RunnerTermClose_%d"):format(buf)
  pcall(api.nvim_create_augroup, group_name, { clear = true })
  api.nvim_create_autocmd({ "BufWipeout", "BufDelete", "BufUnload" }, {
    group = group_name,
    buffer = buf,
    once = true,
    callback = function()
      if vim.g.__runner_term_buf == buf then
        vim.g.__runner_term_buf = nil
      end
      if vim.g.__runner_term_tab == tab then
        if tab_valid(tab) then
          pcall(api.nvim_set_current_tabpage, tab)
          pcall(vim.cmd, "tabclose")
        end
        vim.g.__runner_term_tab = nil
      end
      pcall(api.nvim_del_augroup_by_name, group_name)
    end,
  })
end

local function ensure_term_in_tab()
  local stored_tab = vim.g.__runner_term_tab
  local stored_buf = vim.g.__runner_term_buf

  if is_term_buf(stored_buf) then
    local tp, win = term_tab_and_buf()
    if tp and win and api.nvim_win_get_buf(win) == stored_buf then
      return tp, win, stored_buf
    end
    -- buffer exists but not visible — open in new tab reusing buffer
    pcall(vim.cmd, "tabnew")
    pcall(api.nvim_set_current_buf, stored_buf)
    local cur_tp = api.nvim_get_current_tabpage()
    vim.g.__runner_term_tab = cur_tp
    make_term_autoclose(stored_buf, cur_tp)
    return cur_tp, api.nvim_get_current_win(), stored_buf
  end

  if tab_valid(stored_tab) then
    for _, w in ipairs(api.nvim_tabpage_list_wins(stored_tab)) do
      local b = api.nvim_win_get_buf(w)
      if is_term_buf(b) then
        vim.g.__runner_term_buf = b
        make_term_autoclose(b, stored_tab)
        return stored_tab, w, b
      end
    end
    -- stored tab exists but no terminal inside it: create one
    pcall(api.nvim_set_current_tabpage, stored_tab)
    pcall(vim.cmd, "split")
    pcall(vim.cmd, "terminal")
    local b = api.nvim_get_current_buf()
    vim.g.__runner_term_buf = b
    make_term_autoclose(b, stored_tab)
    return stored_tab, api.nvim_get_current_win(), b
  end

  -- create a new tab + terminal
  pcall(vim.cmd, "tabnew")
  pcall(vim.cmd, "terminal")
  local b = api.nvim_get_current_buf()
  local t = api.nvim_get_current_tabpage()
  vim.g.__runner_term_buf = b
  vim.g.__runner_term_tab = t
  make_term_autoclose(b, t)
  return t, api.nvim_get_current_win(), b
end

local function send_cmd_to_term(cmd)
  local tp, win, buf = ensure_term_in_tab()

  if not api.nvim_buf_is_valid(buf) then
    pcall(vim.cmd, "tabnew")
    pcall(vim.cmd, "terminal")
    tp = api.nvim_get_current_tabpage()
    win = api.nvim_get_current_win()
    buf = api.nvim_get_current_buf()
    vim.g.__runner_term_buf = buf
    vim.g.__runner_term_tab = tp
    make_term_autoclose(buf, tp)
  end

  local job = vim.b[buf].terminal_job_id
  if job and fn.jobwait({ job }, 0)[1] == -1 then
    fn.chansend(job, cmd .. "\n")
  else
    pcall(vim.cmd, "startinsert")
    vim.defer_fn(function()
      local j = vim.b[buf].terminal_job_id
      if j then
        fn.chansend(j, cmd .. "\n")
      end
    end, 50)
  end

  if api.nvim_get_current_tabpage() ~= tp then
    pcall(api.nvim_set_current_tabpage, tp)
  end
  if api.nvim_get_current_win() ~= win then
    pcall(api.nvim_set_current_win, win)
  end
  pcall(vim.cmd, "startinsert")
end

local function run_current_file()
  -- Don't run if current buffer is a terminal
  if vim.bo.buftype == "terminal" then
    vim.notify(
      "Can't run: you're inside a terminal buffer. Switch to a file buffer and try <leader>rr.",
      vim.log.levels.WARN
    )
    return
  end

  local ft = vim.bo.filetype
  local file = fn.expand("%:p")
  if file == "" then
    vim.notify("No file to run (empty buffer).", vim.log.levels.WARN)
    return
  end

  local runners = {
    python = "python3 -u " .. file,
    javascript = "node " .. file,
    typescript = "tsx " .. file,
    sh = "bash " .. file,
    lua = "lua " .. file,
    ruby = "ruby " .. file,
    go = "go run " .. file,
    c = "sh -lc 'gcc % -O2 -o %:r && %:r'",
    cpp = "sh -lc 'g++ % -std=c++17 -O2 -o %:r && %:r'",
    java = "sh -lc 'javac %:t && java -cp %:p:h %:t:r'",
  }

  local cmd = runners[ft]
  if not cmd then
    vim.notify("No runner for filetype: " .. (ft or "unknown"), vim.log.levels.WARN)
    return
  end

  -- safe save (only when not terminal and buffer is writable)
  if vim.bo.modifiable and not vim.bo.readonly and vim.bo.buftype == "" then
    pcall(vim.cmd, "write")
  end

  cmd = cmd
    :gsub("%%:r", fn.expand("%:r"))
    :gsub("%%:t", fn.expand("%:t"))
    :gsub("%%:p:h", fn.expand("%:p:h"))
    :gsub("%%", fn.expand("%"))

  local file_dir = fn.expand("%:p:h")
  cmd = ("sh -lc 'cd %s && %s'"):format(fn.shellescape(file_dir), cmd)

  send_cmd_to_term(cmd)
end

-- keymaps
vim.keymap.set("n", "<leader>rr", run_current_file, { desc = "Run current file (terminal tab)" })
vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], { desc = "Terminal: exit to Normal" })

vim.keymap.set({ "n", "t" }, "<leader>rp", function()
  local tp, win, _ = term_tab_and_buf()
  if win then
    if api.nvim_get_current_tabpage() ~= tp then
      api.nvim_set_current_tabpage(tp)
    end
    if api.nvim_get_current_win() ~= win then
      api.nvim_set_current_win(win)
    end
  else
    pcall(vim.cmd, "wincmd p")
  end
end, { desc = "Prev window/tab (code/term)" })

vim.keymap.set({ "n", "t" }, "<leader>rt", function()
  local tp, win, buf = term_tab_and_buf()
  if tp and win and buf then
    if api.nvim_get_current_tabpage() ~= tp then
      api.nvim_set_current_tabpage(tp)
    end
    if api.nvim_get_current_win() ~= win then
      api.nvim_set_current_win(win)
    end
    pcall(vim.cmd, "startinsert")
  else
    ensure_term_in_tab()
    pcall(vim.cmd, "startinsert")
  end
end, { desc = "Focus terminal tab" })

-- Open Codex CLI in a terminal split
vim.keymap.set("n", "<leader>cx", function()
  vim.cmd("tabnew | terminal codex")
end, { desc = "Open Codex CLI" })

vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-w>h]], { desc = "Terminal: left window" })
vim.keymap.set("t", "<C-j>", [[<C-\><C-n><C-w>j]], { desc = "Terminal: down window" })
vim.keymap.set("t", "<C-k>", [[<C-\><C-n><C-w>k]], { desc = "Terminal: up window" })
vim.keymap.set("t", "<C-l>", [[<C-\><C-n><C-w>l]], { desc = "Terminal: right window" })

vim.keymap.set("n", "<A-j>", ":m .+1<CR>==", { desc = "Move line down" })
vim.keymap.set("n", "<A-k>", ":m .-2<CR>==", { desc = "Move line up" })
vim.keymap.set("v", "<A-j>", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
vim.keymap.set("v", "<A-k>", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })
vim.keymap.set("i", "<A-j>", "<Esc>:m .+1<CR>==gi", { desc = "Move line down (insert)" })
vim.keymap.set("i", "<A-k>", "<Esc>:m .-2<CR>==gi", { desc = "Move line up (insert)" })

vim.keymap.set("n", "<leader>ls", function()
  local dir = vim.fn.expand("%:p:h")
  vim.g._live_server_job = vim.fn.jobstart({
    "live-server",
    dir,
    "--port=5500",
    "--host=127.0.0.1",
  }, { detach = true })

  vim.defer_fn(function()
    vim.fn.jobstart({ "xdg-open", "http://127.0.0.1:5500" }, { detach = true })
  end, 200)
end, { desc = "Start live-server (current file dir)" })

vim.keymap.set("n", "<leader>lS", function()
  local job = vim.g._live_server_job
  if job and job > 0 then
    pcall(vim.fn.jobstop, job)
    vim.g._live_server_job = nil
  end
end, { desc = "Stop live-server" })

vim.keymap.set("n", "<leader>ss", function()
  require("telescope.builtin").spell_suggest()
end, { desc = "Spell suggestions" })
