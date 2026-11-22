-- Keep only your personal keybinding overrides here.
-- See current bindings and descriptions:
-- omarchy menu keybindings --print

local terminal = "uwsm app -- $TERMINAL"
local browser = os.getenv("HOME") .. "/.config/hypr/scripts/launch-browser-single"

hl.unbind("SUPER + ALT + RETURN")
o.bind("SUPER + ALT + RETURN", "Tmux", 'uwsm-app -- xdg-terminal-exec --dir="$(omarchy-cmd-terminal-cwd)" tmux new')

hl.unbind("SUPER + RETURN")
o.bind("SUPER + RETURN", "Terminal", terminal .. ' --dir="$(omarchy-cmd-terminal-cwd)"')

hl.unbind("SUPER + E")
o.bind("SUPER + E", "File manager", "uwsm app -- nautilus --new-window")

hl.unbind("SUPER + B")
o.bind("SUPER + B", "Browser", browser)

hl.unbind("SUPER + SHIFT + B")
o.bind("SUPER + SHIFT + B", "Browser (private)", browser .. " --private")

hl.unbind("SUPER + N")
o.bind("SUPER + N", "Editor", "omarchy-launch-editor")

hl.unbind("SUPER + T")
o.bind("SUPER + T", "Activity", "omarchy-launch-tui btop")

hl.unbind("SUPER + D")
o.bind("SUPER + D", "GitHub Desktop", "uwsm app -- github-desktop --disable-gpu")

hl.unbind("SUPER + O")
o.bind("SUPER + O", "Obsidian", 'omarchy-launch-or-focus obsidian "uwsm-app -- obsidian"')

hl.unbind("SUPER + SLASH")
o.bind("SUPER + SLASH", "Passwords", "uwsm app -- 1password")

hl.unbind("SUPER + A")
o.bind("SUPER + A", "ChatGPT", 'omarchy-launch-webapp "https://chatgpt.com"')

hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Grok", 'omarchy-launch-webapp "https://grok.com"')

hl.unbind("SUPER + M")
o.bind("SUPER + M", "gmail", 'omarchy-launch-webapp "https://mail.google.com/mail/u/0/#inbox"')

hl.unbind("SUPER + Y")
o.bind("SUPER + Y", "YouTube", 'omarchy-launch-or-focus-webapp YouTube "https://youtube.com/"')

hl.unbind("SUPER + SHIFT + G")
o.bind("SUPER + SHIFT + G", "WhatsApp", 'omarchy-launch-or-focus-webapp WhatsApp "https://web.whatsapp.com/"')

hl.unbind("SUPER + ALT + G")
o.bind("SUPER + ALT + G", "Google Messages", 'omarchy-launch-or-focus-webapp "Google Messages" "https://messages.google.com/web/conversations"')

hl.unbind("SUPER + X")
o.bind("SUPER + X", "X", 'omarchy-launch-webapp "https://x.com/"')

hl.unbind("SUPER + SHIFT + X")
o.bind("SUPER + SHIFT + X", "X Post", 'omarchy-launch-webapp "https://x.com/compose/post"')

hl.unbind("SUPER + G")
o.bind("SUPER + G", "Github", 'omarchy-launch-webapp "https://github.com"')

hl.unbind("SUPER + Q")
hl.bind("SUPER + Q", hl.dsp.window.close())

hl.unbind("SUPER + W")
o.bind("SUPER + W", "Restart shell", "omarchy-restart-shell")

-- Swap the focused window with its neighbour in a direction, crossing monitors.
-- When the neighbouring monitor has no windows, move the window there instead.
local axis = { l = "x", r = "x", u = "y", d = "y" }
local step = { l = -1, r = 1, u = -1, d = 1 }

local function center(win, ax)
  return win.at[ax] + win.size[ax] / 2
end

local function overlaps(a, b, ax)
  local cross = ax == "x" and "y" or "x"
  return a.at[cross] < b.at[cross] + b.size[cross] and b.at[cross] < a.at[cross] + a.size[cross]
end

-- Closest tiled window on `workspace` that sits in `dir` from `win`.
local function neighbor(win, workspace, dir, aligned_only)
  local ax, sign = axis[dir], step[dir]
  local best, best_gap

  for _, other in ipairs(hl.get_windows({ workspace = workspace.id, floating = false, mapped = true })) do
    if other.address ~= win.address and (not aligned_only or overlaps(win, other, ax)) then
      local gap = (center(other, ax) - center(win, ax)) * sign
      if gap > 0 and (best_gap == nil or gap < best_gap) then
        best, best_gap = other, gap
      end
    end
  end

  return best
end

-- Left/right wrap around the monitors: past the rightmost monitor comes the
-- leftmost, and the other way round (mirrors don't count). Up/down don't wrap.
local function wrap_monitor(dir, from)
  if dir ~= "l" and dir ~= "r" then
    return nil
  end

  local best
  for _, monitor in ipairs(hl.get_monitors()) do
    if not monitor.is_mirror and monitor.name ~= from.name then
      local x = monitor.x
      if not best or (dir == "r" and x < best.x) or (dir == "l" and x > best.x) then
        best = monitor
      end
    end
  end

  return best
end

-- The tiled window nearest the edge you arrive at when entering a workspace
-- going `dir`: its left edge going right, its right edge going left.
local function entry_window(workspace, dir, skip)
  local ax, sign = axis[dir], step[dir]
  local best, best_pos

  for _, other in ipairs(hl.get_windows({ workspace = workspace.id, floating = false, mapped = true })) do
    if not skip or other.address ~= skip.address then
      local pos = center(other, ax) * sign
      if best_pos == nil or pos < best_pos then
        best, best_pos = other, pos
      end
    end
  end

  return best
end

local function swap_across_monitors(dir)
  return function()
    local win = hl.get_active_window()
    if not win or not win.workspace then
      return
    end

    -- Floating windows have no tiling neighbours, so just nudge them along.
    if win.floating then
      return hl.dispatch(hl.dsp.window.move({ direction = dir }))
    end

    local target = neighbor(win, win.workspace, dir, true)

    if not target then
      local monitor = hl.get_monitor(dir)
      local wrapped = false
      if not monitor then
        local here = hl.get_active_monitor()
        monitor = here and wrap_monitor(dir, here)
        wrapped = true
      end
      local workspace = monitor and monitor.active_workspace
      if not workspace then
        return
      end

      -- Everything over there is in `dir`, so take whatever sits nearest the
      -- edge; after wrapping, nearest the edge we come in from.
      if wrapped then
        target = entry_window(workspace, dir)
      else
        target = neighbor(win, workspace, dir, false)
      end
      if not target then
        return hl.dispatch(hl.dsp.window.move({ workspace = workspace.id }))
      end
    end

    hl.dispatch(hl.dsp.window.swap({ target = target }))
  end
end

-- Super+Left/Right: Hyprland's focus, but past the outermost monitor it
-- wraps to the window nearest the far monitor's edge (or that monitor, if
-- its workspace is empty).
local function focus_wrapping(dir)
  return function()
    local win = hl.get_active_window()
    local here = hl.get_active_monitor()
    local at_edge = here and not hl.get_monitor(dir)
      and not (win and win.workspace and not win.floating and neighbor(win, win.workspace, dir, false))

    if not at_edge then
      return hl.dispatch(hl.dsp.focus({ direction = dir }))
    end

    local monitor = wrap_monitor(dir, here)
    if not monitor then
      return
    end

    local target = monitor.active_workspace and entry_window(monitor.active_workspace, dir)
    if target then
      hl.dispatch(hl.dsp.focus({ window = "address:" .. target.address }))
    else
      hl.dispatch(hl.dsp.focus({ monitor = monitor.name }))
    end
  end
end

for _, dir in ipairs({ "l", "r" }) do
  local key = ({ l = "LEFT", r = "RIGHT" })[dir]
  local label = ({ l = "left", r = "right" })[dir]
  o.rebind("SUPER + " .. key, "Focus on " .. label .. " window (wraps around monitors)", focus_wrapping(dir))
end

for _, dir in ipairs({ "l", "r", "u", "d" }) do
  local key = ({ l = "LEFT", r = "RIGHT", u = "UP", d = "DOWN" })[dir]
  local label = ({ l = "left", r = "right", u = "up", d = "down" })[dir]

  hl.unbind("SUPER + SHIFT + " .. key)
  o.bind("SUPER + SHIFT + " .. key, "Swap window " .. label .. " (across monitors)", swap_across_monitors(dir))
end

-- Workspace links (see ~/.config/hypr/workspace-links.md). Super+Tab steps the
-- focused monitor and every monitor linked to it; Super+Ctrl+Tab steps only the
-- focused monitor. Super+N and bar clicks stay per workspace.
o.rebind("SUPER + TAB", "Next workspace (linked monitors too)", o.workspaces.cycle(1))
o.rebind("SUPER + SHIFT + TAB", "Previous workspace (linked monitors too)", o.workspaces.cycle(-1))
o.rebind("SUPER + CTRL + TAB", "Next workspace (this monitor only)", o.workspaces.cycle_alone(1))
o.rebind("SUPER + CTRL + SHIFT + TAB", "Previous workspace (this monitor only)", o.workspaces.cycle_alone(-1))
o.bind("SUPER + SHIFT + L", "Link or unlink this monitor's workspace cycling", o.workspaces.toggle_link())
-- Off: scrolling through workspaces, and moving whole workspaces to another
-- monitor (workspaces stay on the monitor that owns them).
hl.unbind("SUPER + mouse_down")
hl.unbind("SUPER + mouse_up")
for _, key in ipairs({ "LEFT", "RIGHT", "UP", "DOWN" }) do
  hl.unbind("SUPER + SHIFT + ALT + " .. key)
end

-- Per-monitor wallpaper picker (ewse.wallpapers plugin) replaces the stock background switcher
hl.unbind("SUPER + CTRL + SPACE")
o.bind("SUPER + CTRL + SPACE", "Background switcher", "omarchy-shell shell toggle ewse.wallpapers '{}'")

o.bind("SUPER + R", "Set reminder", "omarchy-menu toggle reminder-set")

-- Dictation keys from before Alt + Space and Right Alt became the defaults.
-- Remove these lines to give the keys back to applications.
if o.dictation_installed and o.dictation_installed() then
  o.bind("SUPER + CTRL + X", "Toggle dictation", "omarchy-dictation toggle")
  o.bind_hold("F9", "Start dictation (push-to-talk)", "omarchy-dictation start", "Stop dictation (push-to-talk)", "omarchy-dictation stop")
end

-- Lets `hyprctl repl` run the wrapping actions, e.g.
-- hyprctl repl 'o.wrap_actions.focus("r")() return 1'
o.wrap_actions = { focus = focus_wrapping, swap = swap_across_monitors }
