-- Workspace links: fixed workspaces per monitor, with linked cycling.
-- Documentation: ~/.config/hypr/workspace-links.md
-- Monitors and slots: ~/.config/hypr/workspace-links-config.lua
--
-- Loaded in place of Omarchy's per-monitor workspaces module
-- (default.hypr.monitor-workspaces) through package.preload in hyprland.lua,
-- so it must provide the same o.workspaces actions Omarchy's tiling bindings
-- call: focus, move_window, move_to_monitor, move_window_to_monitor.
--
-- What it does:
--   * Every managed monitor owns fixed workspaces (e.g. main 1-3, second 4-6, ...).
--     Super+N is plain Hyprland: workspace N, on whichever monitor owns it.
--   * Super+Tab / Super+Shift+Tab step the focused monitor, and every monitor
--     linked to it, to its own next / previous workspace, wrapping around.
--     Links are kept per monitor setup and toggled with M.toggle.
--   * When monitors go away, their occupied workspaces are compacted into
--     empty slots of the ones left (overflow keeps counting up). When they
--     come back, windows of the remembered app classes go home again.
--   * The current layout is written to layout.json for the bar widget.

local M = { slots = 10 }

local HOME = os.getenv("HOME") or ""
local STATE_DIR = (os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/omarchy/workspace-links"
local LAYOUT_FILE = STATE_DIR .. "/layout.json"
local LINKS_FILE = STATE_DIR .. "/links.tsv"
local RECORDS_FILE = STATE_DIR .. "/compacted.tsv"
local SETUP_FILE = STATE_DIR .. "/setup"

local loaded, config = pcall(require, "hypr.workspace-links-config")
if not loaded or type(config) ~= "table" or type(config.monitors) ~= "table" then
  print("workspace-links: could not load hypr/workspace-links-config.lua: " .. tostring(config))
  config = { monitors = {} }
end

-- ---------------------------------------------------------------------------
-- Files

local function ensure_dir()
  os.execute("mkdir -p " .. o.shell_quote(STATE_DIR))
end

local function read_lines(path)
  local lines = {}
  local file = io.open(path, "r")
  if not file then
    return lines
  end
  for line in file:lines() do
    lines[#lines + 1] = line
  end
  file:close()
  return lines
end

local function write_file(path, content)
  local file = io.open(path, "w")
  if not file then
    ensure_dir()
    file = io.open(path, "w")
  end
  if file then
    file:write(content)
    file:close()
  end
end

local function split(text, separator)
  local parts = {}
  for part in string.gmatch(text, "([^" .. separator .. "]+)") do
    parts[#parts + 1] = part
  end
  return parts
end

local function json_string(value)
  return '"' .. tostring(value):gsub('[%c"\\]', function(c)
    return string.format("\\u%04x", c:byte())
  end) .. '"'
end

-- Nerd Font glyphs; the OSD draws any icon name it doesn't know as the text
-- itself, and shows a mute icon when given none.
local ICON_LINKED = utf8.char(0xf0c1) -- chain, as on the bar
local ICON_UNLINKED = utf8.char(0xf127) -- broken chain

local function notify(message, icon)
  hl.exec_cmd("omarchy-osd -i " .. o.shell_quote(icon or ICON_LINKED) .. " -m " .. o.shell_quote(message) .. " -d 1200")
end

-- ---------------------------------------------------------------------------
-- Links: setup signature -> set of linked monitor keys. A setup never seen
-- before has every monitor linked.

local links = {}

local function load_links()
  links = {}
  for _, line in ipairs(read_lines(LINKS_FILE)) do
    local setup, keys = line:match("^([^\t]+)\t?(.*)$")
    if setup then
      local set = {}
      for _, key in ipairs(split(keys or "", ",")) do
        set[key] = true
      end
      links[setup] = set
    end
  end
end

local function save_links()
  local setups = {}
  for setup in pairs(links) do
    setups[#setups + 1] = setup
  end
  table.sort(setups)

  local lines = {}
  for _, setup in ipairs(setups) do
    local keys = {}
    for key in pairs(links[setup]) do
      keys[#keys + 1] = key
    end
    table.sort(keys)
    lines[#lines + 1] = setup .. "\t" .. table.concat(keys, ",")
  end
  write_file(LINKS_FILE, table.concat(lines, "\n") .. "\n")
end

-- ---------------------------------------------------------------------------
-- Compaction records: a workspace of a missing monitor whose windows moved
-- into another slot. On its monitor's return, windows of these classes on
-- `to` go back to `from`, up to the counts remembered.

local records = {}

local function load_records()
  records = {}
  for _, line in ipairs(read_lines(RECORDS_FILE)) do
    local from, to, home, classes = line:match("^(%d+)\t(%d+)\t([^\t]+)\t?(.*)$")
    if from then
      local counts = {}
      for _, pair in ipairs(split(classes or "", ",")) do
        local class, count = pair:match("^(.*)=(%d+)$")
        if class then
          counts[class] = tonumber(count)
        end
      end
      records[#records + 1] = { from = tonumber(from), to = tonumber(to), home = home, classes = counts }
    end
  end
end

local function save_records()
  local lines = {}
  for _, record in ipairs(records) do
    local pairs_list = {}
    for class, count in pairs(record.classes) do
      pairs_list[#pairs_list + 1] = class .. "=" .. count
    end
    table.sort(pairs_list)
    lines[#lines + 1] = record.from .. "\t" .. record.to .. "\t" .. record.home .. "\t" .. table.concat(pairs_list, ",")
  end
  write_file(RECORDS_FILE, table.concat(lines, "\n") .. (#lines > 0 and "\n" or ""))
end

-- ---------------------------------------------------------------------------
-- Layout

local function matches(spec, monitor)
  local output = spec.output or ""
  if output:sub(1, 5) == "desc:" then
    return (monitor.description or "") == output:sub(6)
  end
  return monitor.name == output
end

local function regular(workspace)
  return workspace and not workspace.special and workspace.id > 0
end

local function occupied(workspace)
  return workspace and (workspace.windows or 0) > 0
end

-- The managed monitor whose normal slots hold `id`, connected or not.
local function home_spec(id)
  for _, spec in ipairs(config.monitors) do
    for _, slot in ipairs(spec.slots or {}) do
      if slot == id then
        return spec
      end
    end
  end
  return nil
end

-- The managed monitors connected now, in config order, each with the
-- workspace ids it owns in this setup. `gone` is a set of connector names
-- Hyprland may still list while it reports their removal.
local function layout(gone)
  gone = gone or {}
  local entries = {}
  for _, monitor in ipairs(hl.get_monitors()) do
    if not monitor.is_mirror and not gone[monitor.name] then
      for order, spec in ipairs(config.monitors) do
        if matches(spec, monitor) then
          entries[#entries + 1] = { spec = spec, monitor = monitor, order = order }
          break
        end
      end
    end
  end
  table.sort(entries, function(left, right) return left.order < right.order end)

  local keys = {}
  local by_name = {}
  local by_key = {}
  local owner = {}
  for _, entry in ipairs(entries) do
    entry.slots = (#entries == 1 and entry.spec.solo) or entry.spec.slots or {}
    keys[#keys + 1] = entry.spec.key
    by_name[entry.monitor.name] = entry
    by_key[entry.spec.key] = entry
    for _, id in ipairs(entry.slots) do
      owner[id] = entry
    end
  end

  local setup = table.concat(keys, "+")
  local linked = {}
  if #entries >= 2 then
    local set = links[setup]
    for _, entry in ipairs(entries) do
      linked[entry.spec.key] = set == nil or set[entry.spec.key] == true
    end
  end

  return {
    entries = entries,
    setup = setup,
    by_name = by_name,
    by_key = by_key,
    owner = owner,
    linked = linked,
  }
end

local function write_layout(L)
  local monitors = {}
  for _, entry in ipairs(L.entries) do
    local slots = {}
    for _, id in ipairs(entry.slots) do
      slots[#slots + 1] = tostring(id)
    end
    monitors[#monitors + 1] = json_string(entry.monitor.name) .. ":{"
      .. '"key":' .. json_string(entry.spec.key)
      .. ',"label":' .. json_string(entry.spec.label or entry.spec.key)
      .. ',"slots":[' .. table.concat(slots, ",") .. "]"
      .. ',"linked":' .. tostring(L.linked[entry.spec.key] == true)
      .. "}"
  end
  write_file(LAYOUT_FILE, "{"
    .. '"setup":' .. json_string(L.setup)
    .. ',"linkable":' .. tostring(#L.entries >= 2)
    .. ',"monitors":{' .. table.concat(monitors, ",") .. "}"
    .. "}\n")
end

-- ---------------------------------------------------------------------------
-- Moving things

local function class_of(window)
  local class = window.class or ""
  if class == "" then
    class = window.initial_class or ""
  end
  return (class:gsub("[\t,=\n]", "_"))
end

local function windows_on(id)
  local list = {}
  for _, window in ipairs(hl.get_windows({ workspace = id })) do
    if window.mapped ~= false then
      list[#list + 1] = window
    end
  end
  return list
end

local function move_window_silently(window, id)
  hl.dispatch(hl.dsp.window.move({ workspace = tostring(id), follow = false, window = "address:" .. window.address }))
end

local function move_workspace(id, monitor_name)
  hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(id), monitor = monitor_name }))
end

-- Show workspace `id` on `monitor` without moving focus there, when it
-- exists; otherwise create it, which focuses it (callers refocus after).
local function show_on(monitor, id)
  local workspace = hl.get_workspace(id)
  if workspace then
    if workspace.monitor and workspace.monitor.name ~= monitor.name then
      move_workspace(id, monitor.name)
      workspace = hl.get_workspace(id)
    end
    hl.get_monitor(monitor.name):set_workspace({ workspace = workspace.name })
  else
    hl.dispatch(hl.dsp.focus({ monitor = monitor.name }))
    hl.dispatch(hl.dsp.focus({ workspace = tostring(id) }))
  end
end

-- ---------------------------------------------------------------------------
-- Reconciling a monitor change

-- Windows of remembered classes go back to their own workspace once its
-- monitor is connected again.
local function restore(L)
  local kept = {}
  local changed = false

  for _, record in ipairs(records) do
    if L.by_key[record.home] then
      local remaining = {}
      for class, count in pairs(record.classes) do
        remaining[class] = count
      end
      for _, window in ipairs(windows_on(record.to)) do
        local class = class_of(window)
        if (remaining[class] or 0) > 0 then
          move_window_silently(window, record.from)
          remaining[class] = remaining[class] - 1
        end
      end
      changed = true
    else
      kept[#kept + 1] = record
    end
  end

  if changed then
    records = kept
    save_records()
  end
end

-- Every workspace a connected monitor owns goes to that monitor.
local function place(L)
  for _, workspace in ipairs(hl.get_workspaces()) do
    local entry = regular(workspace) and L.owner[workspace.id]
    if entry and workspace.monitor and workspace.monitor.name ~= entry.monitor.name then
      move_workspace(workspace.id, entry.monitor.name)
    end
  end
end

-- Occupied workspaces no connected monitor owns move into empty slots, in
-- monitor priority order; the rest count up after the first monitor's slots,
-- skipping ids another monitor owns, and sit on that first monitor.
local function compact(L)
  local candidates = {}
  for _, workspace in ipairs(hl.get_workspaces()) do
    if regular(workspace) and occupied(workspace) and not L.owner[workspace.id] then
      candidates[#candidates + 1] = workspace.id
    end
  end
  if #candidates == 0 then
    return
  end
  table.sort(candidates)

  local empties = {}
  for _, entry in ipairs(L.entries) do
    for _, id in ipairs(entry.slots) do
      if not occupied(hl.get_workspace(id)) then
        empties[#empties + 1] = id
      end
    end
  end

  local receiver = L.entries[1]
  local next_id = 0
  for _, id in ipairs(receiver.slots) do
    next_id = math.max(next_id, id)
  end
  next_id = next_id + 1

  local taken = {}
  local function overflow_target(from)
    while L.owner[next_id] or taken[next_id] or (next_id ~= from and occupied(hl.get_workspace(next_id))) do
      next_id = next_id + 1
    end
    taken[next_id] = true
    return next_id
  end

  for _, from in ipairs(candidates) do
    local target = table.remove(empties, 1)
    local overflow = target == nil
    if overflow then
      target = overflow_target(from)
    end

    if target ~= from then
      local counts = {}
      for _, window in ipairs(windows_on(from)) do
        local class = class_of(window)
        counts[class] = (counts[class] or 0) + 1
        move_window_silently(window, target)
      end

      -- A workspace compacted before keeps the home it first came from.
      local merged = false
      for _, record in ipairs(records) do
        if record.to == from then
          record.to = target
          merged = true
        end
      end
      local spec = home_spec(from)
      if not merged and spec then
        records[#records + 1] = { from = from, to = target, home = spec.key, classes = counts }
      end
    end

    if overflow then
      local workspace = hl.get_workspace(target)
      if workspace and workspace.monitor and workspace.monitor.name ~= receiver.monitor.name then
        move_workspace(target, receiver.monitor.name)
      end
    end
  end

  save_records()
end

-- Each connected monitor shows a workspace of its own, or an occupied one no
-- monitor owns (overflow) that is already on it.
local function settle_views(L)
  for _, entry in ipairs(L.entries) do
    local monitor = hl.get_monitor(entry.monitor.name)
    local active = monitor and monitor.active_workspace
    local fine = regular(active)
      and (L.owner[active.id] == entry or (not L.owner[active.id] and occupied(active)))
    if monitor and not fine and entry.slots[1] then
      show_on(monitor, entry.slots[1])
    end
  end
end

function M.reconcile(gone)
  local L = layout(gone)
  if #L.entries == 0 then
    return
  end

  local focused_window = hl.get_active_window()
  local focused_monitor = hl.get_active_monitor()
  local focused_name = focused_monitor and focused_monitor.name

  local previous = read_lines(SETUP_FILE)[1]

  restore(L)
  place(L)
  if previous and previous ~= "" and previous ~= L.setup then
    compact(L)
  end
  settle_views(L)

  if previous ~= L.setup then
    write_file(SETUP_FILE, L.setup .. "\n")
  end
  write_layout(L)

  if focused_window and hl.get_window("address:" .. focused_window.address) then
    hl.dispatch(hl.dsp.focus({ window = "address:" .. focused_window.address }))
  elseif focused_name and not (gone or {})[focused_name] and hl.get_monitor(focused_name) then
    hl.dispatch(hl.dsp.focus({ monitor = focused_name }))
  end
end

-- ---------------------------------------------------------------------------
-- Actions (bound to keys; also callable with `hyprctl eval`)

local function action(fn, expression)
  o.bind_expressions[fn] = expression
  return fn
end

-- The workspaces a monitor cycles through: its own, then any occupied
-- overflow sitting on it, in order. The bar shows the same list.
local function cycle_list(L, entry)
  local ids = {}
  local seen = {}
  for _, id in ipairs(entry.slots) do
    ids[#ids + 1] = id
    seen[id] = true
  end
  for _, workspace in ipairs(hl.get_workspaces()) do
    if regular(workspace) and not seen[workspace.id] and not L.owner[workspace.id] and occupied(workspace)
      and workspace.monitor and workspace.monitor.name == entry.monitor.name then
      ids[#ids + 1] = workspace.id
      seen[workspace.id] = true
    end
  end
  table.sort(ids)
  return ids
end

-- Step the focused monitor, and every monitor linked to it, `step` places
-- through its own workspaces, each from where it is now. `alone` steps only
-- the focused monitor, whatever its links.
function M.cycle_now(step, alone)
  local L = layout()
  local focused = hl.get_active_monitor()
  local main = focused and L.by_name[focused.name]
  if not main then
    hl.dispatch(hl.dsp.focus({ workspace = step > 0 and "m+1" or "m-1" }))
    return
  end

  local group = { main }
  if not alone and L.linked[main.spec.key] then
    for _, entry in ipairs(L.entries) do
      if entry ~= main and L.linked[entry.spec.key] then
        group[#group + 1] = entry
      end
    end
  end

  local targets = {}
  for _, entry in ipairs(group) do
    local list = cycle_list(L, entry)
    if #list > 0 then
      local current = entry.monitor.active_workspace and entry.monitor.active_workspace.id
      local index = nil
      for i, id in ipairs(list) do
        if id == current then
          index = i
        end
      end
      local target = index and list[((index - 1 + step) % #list) + 1] or list[1]
      targets[#targets + 1] = { entry = entry, id = target }
    end
  end

  -- The others first, without focus; the focused monitor last, so focus
  -- ends where it started.
  for i = 2, #targets do
    show_on(targets[i].entry.monitor, targets[i].id)
  end
  if targets[1] then
    hl.dispatch(hl.dsp.focus({ workspace = tostring(targets[1].id) }))
  end
end

function M.cycle(step)
  return action(function()
    M.cycle_now(step)
  end, "o.workspaces.cycle(" .. step .. ")")
end

-- The same, for the focused monitor only.
function M.cycle_alone(step)
  return action(function()
    M.cycle_now(step, true)
  end, "o.workspaces.cycle_alone(" .. step .. ")")
end

-- Toggle a monitor (connector name, or the focused one) in or out of the
-- cycle group for the current setup. The bar's chain calls this through
-- `hyprctl eval 'o.workspaces.toggle("DP-2")'`.
function M.toggle(name)
  local L = layout()
  if #L.entries < 2 then
    notify("Nothing to link with one monitor", ICON_UNLINKED)
    return
  end

  local focused = hl.get_active_monitor()
  local entry = L.by_name[name or (focused and focused.name) or ""]
  if not entry then
    return
  end

  local set = {}
  for _, other in ipairs(L.entries) do
    set[other.spec.key] = L.linked[other.spec.key] == true
  end
  local key = entry.spec.key
  set[key] = not set[key]

  links[L.setup] = {}
  for k, on in pairs(set) do
    if on then
      links[L.setup][k] = true
    end
  end
  save_links()

  local label = entry.spec.label or key
  notify(label .. (set[key] and " linked" or " unlinked"), set[key] and ICON_LINKED or ICON_UNLINKED)
  write_layout(layout())
end

function M.toggle_link()
  return action(function()
    M.toggle()
  end, "o.workspaces.toggle_link()")
end

-- Omarchy's tiling bindings call these four.

function M.focus(slot)
  return action(function()
    hl.dispatch(hl.dsp.focus({ workspace = tostring(slot) }))
  end, "o.workspaces.focus(" .. slot .. ")")
end

function M.move_window(slot, follow)
  return action(function()
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(slot), follow = follow ~= false }))
  end, "o.workspaces.move_window(" .. slot .. (follow == false and ", false" or "") .. ")")
end

-- Whole workspaces don't change monitors here; bindings.lua unbinds the keys,
-- and this keeps Omarchy's binding code working.
function M.move_to_monitor(direction)
  return action(function() end, "o.workspaces.move_to_monitor(" .. string.format("%q", direction) .. ")")
end

function M.move_window_to_monitor(direction)
  return action(function()
    local target = hl.get_monitor(direction)
    if target then
      hl.dispatch(hl.dsp.window.move({ monitor = target.name }))
    end
  end, "o.workspaces.move_window_to_monitor(" .. string.format("%q", direction) .. ")")
end

-- ---------------------------------------------------------------------------
-- Workspace rules: each slot lives on its monitor and always exists, so the
-- bar and Super+Tab can rely on it. Ids only in a `solo` list belong to that
-- monitor.

local function apply_rules()
  local rule_of = {}
  local order = {}
  for _, spec in ipairs(config.monitors) do
    for index, id in ipairs(spec.slots or {}) do
      if not rule_of[id] then
        rule_of[id] = { spec = spec, default = index == 1 }
        order[#order + 1] = id
      end
    end
  end
  for _, spec in ipairs(config.monitors) do
    for _, id in ipairs(spec.solo or {}) do
      if not rule_of[id] then
        rule_of[id] = { spec = spec, default = false }
        order[#order + 1] = id
      end
    end
  end
  table.sort(order)

  for _, id in ipairs(order) do
    local rule = rule_of[id]
    hl.workspace_rule({ workspace = tostring(id), monitor = rule.spec.output, persistent = true, default = rule.default })
  end
end

load_links()
load_records()
apply_rules()

hl.on("hyprland.start", function()
  -- Windows don't outlive a session, so neither do compaction records.
  records = {}
  save_records()
  M.reconcile()
end)

hl.on("config.reloaded", function()
  M.reconcile()
end)

-- A dock plugs or unplugs several monitors within moments of each other, one
-- event each. Reconciling after every event would compact for each
-- in-between setup (main+third, then main), so wait for the events to stop
-- and reconcile once against the final setup. This also runs well after
-- Hyprland's monitor teardown, where moving workspaces can crash it.
local SETTLE_MS = 600
local pending = 0
local gone_names = {}

local function schedule()
  pending = pending + 1
  local mine = pending
  hl.timer(function()
    if mine ~= pending then
      return
    end
    -- A monitor still listed after its removal event is skipped by name.
    local gone = gone_names
    gone_names = {}
    M.reconcile(gone)
  end, { type = "oneshot", timeout = SETTLE_MS })
end

hl.on("monitor.added", function(monitor)
  if monitor and monitor.name then
    gone_names[monitor.name] = nil
  end
  schedule()
end)

hl.on("monitor.removed", function(monitor)
  if monitor and monitor.name then
    gone_names[monitor.name] = true
  end
  schedule()
end)

o.workspaces = M

return M
