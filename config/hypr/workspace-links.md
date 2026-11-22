# Workspace links

Fixed workspaces per monitor, with optional **linked cycling** across monitors,
for Omarchy (Hyprland Lua config + Omarchy shell). Built 2026-11-21 against
Omarchy 4.5 / Hyprland 0.56.

It replaces Omarchy 4.5's per-monitor workspaces (every monitor gets its own
1–10, numbered internally in blocks of ten) with the classic model: each
monitor owns a few fixed workspace numbers, and Super+N always means the same
workspace.

## What it does

| | |
|---|---|
| **Fixed layout** | Each managed monitor owns fixed workspaces, e.g. main 1–3, second 4–6, third 7–9. They always exist and always live on their monitor. |
| **One monitor alone** | When only one managed monitor is connected it can own more, e.g. 1–5 (`solo` in the config). The bar shows 1–5, plus any higher workspace that has windows. |
| **Other monitors** | Any monitor not in the config is left alone by the module. Optionally a catch-all rule in `monitors.lua` mirrors such monitors (TVs, projectors) onto the main one. |
| **Super + N** | Plain Hyprland: go to workspace N, on whichever monitor owns it. Affects one monitor only. |
| **Super + Tab / Shift + Tab** | Next / previous workspace on the focused monitor, **and on every monitor linked to it**. Each monitor steps from its own current workspace and wraps around its own set, empty workspaces included. An unlinked monitor cycles alone. |
| **Super + Ctrl + Tab / Ctrl + Shift + Tab** | Next / previous workspace on the **focused monitor only**: the same wrap-around loop as Super+Tab, blanks included, but linked monitors stay put. |
| **Super + Shift + L** | Link / unlink the focused monitor (the one under the mouse). Shows an on-screen message. |
| **Bar** | Each monitor's bar shows its own workspaces, then the link state: a chain when linked, a dimmed broken chain when not. Clicking it toggles. Hover for who's linked. With only one monitor connected, neither is shown. |
| **Undock** | Occupied workspaces of monitors that went away fill **empty** slots on the remaining monitors (lowest first, in config priority order). If there aren't enough empty slots, the rest count up after the first monitor's slots (6, 7, …) and show on its bar. |
| **Re-dock** | Windows go back to the workspace they came from. This is matched by **app class**, not window, so a browser closed and reopened while undocked still goes home. Only windows on the workspace they were compacted onto count, up to the number that moved. Windows you opened elsewhere stay put. |
| **Disabled** | Super + scroll wheel (workspace scrolling), and Super + Shift + Alt + arrows (move a whole workspace to another monitor). |

"Focused monitor" means the one Hyprland considers focused, which follows the
mouse.

### Link settings

Links are remembered **per monitor setup**: the set of connected managed
monitors, e.g. `main+second+third` or `main+second`. A setup seen for the first
time has everything linked. With only one monitor there is nothing to link and
no chain is shown.

### Examples

With the three-monitor config below, all linked, on 1/4/7: Super+Tab → 2/5/8. Super+2 → only main moves.

Main + second linked, third not, on 1/4/7:
- Super+Tab on main → 2/5/7
- then Super+3 → 3/5/7
- then Super+Tab on main → 1/6/7 (each steps from where it is)
- Super+Tab on third → only third moves

Undock with windows on 1, 3, 4, 6, 7, 8 (2 and 5 empty): 6→2, 7→5, 8→6, and 4
stays 4 (main owns 1–5 alone). The bar shows 1–6. Re-dock: everything
goes back to 6, 7, 8.

## Files

| File | Role |
|---|---|
| `~/.config/hypr/workspace-links-config.lua` | **The only file to edit per machine:** monitors, their workspaces, `solo` set. |
| `~/.config/hypr/workspace-links.lua` | The module: layout, cycling, links, compaction and restore, workspace rules. Generic, so copy it unchanged. |
| `~/.config/hypr/hyprland.lua` | `package.preload` hook that loads the module in place of Omarchy's `default.hypr.monitor-workspaces`. |
| `~/.config/hypr/bindings.lua` | Super+Tab / Shift+Tab / Shift+L, and the two unbinds. |
| `~/.config/hypr/monitors.lua` | Monitor modes/positions and the mirror catch-all. No workspace rules here any more. |
| `~/.config/omarchy/plugins/ewse.workspaces/` | Bar widget (numbers + chain or broken chain). Clone of `omarchy.workspaces`, in the bar center. |
| `~/.local/state/omarchy/workspace-links/layout.json` | Written by the module, read by the bar: setup, each connector's slots and link state. |
| `…/links.tsv` | Saved links: `setup<TAB>key,key`. An empty list means nothing linked. |
| `…/compacted.tsv` | Pending restores: `from<TAB>to<TAB>home<TAB>class=count,…`. Cleared at each Hyprland start (windows don't outlive a session). |
| `…/setup` | Last seen setup, so compaction only runs when the setup changes. |

## Configuration

```lua
-- ~/.config/hypr/workspace-links-config.lua
return {
  monitors = {
    { key = "main", label = "Main", output = "eDP-1",
      slots = { 1, 2, 3 }, solo = { 1, 2, 3, 4, 5 } },
    { key = "second", label = "Second", output = "desc:<make> <model> <serial>",
      slots = { 4, 5, 6 } },
    { key = "third", label = "Third", output = "desc:<make> <model> <serial>",
      slots = { 7, 8, 9 } },
  },
}
```

- **`key`**: a stable id used in saved links and records. Don't rename it casually.
- **`label`**: shown in the on-screen message and the chain's tooltip.
- **`output`**: a connector (`eDP-1`), or `desc:` plus the description from
  `hyprctl monitors` (make, model, serial). Use `desc:` for externals, since dock
  ports get renamed between plugs.
- **`slots`**: the workspaces this monitor owns. The first one is where it starts.
- **`solo`** (optional): used instead of `slots` when this is the only managed
  monitor connected.
- **Order matters:** when monitors go away, their windows fill empty slots on
  the remaining monitors in this order, and overflow lands on the first one
  present.

The module generates the matching Hyprland workspace rules (persistent, bound
to each monitor), so don't add your own `workspace_rule`s for these numbers.

## Installing on another Omarchy machine

1. Copy `workspace-links.lua` into `~/.config/hypr/`.
2. Create `~/.config/hypr/workspace-links-config.lua` for that machine. Get each
   monitor's description with
   `hyprctl monitors -j | jq -r '.[] | "\(.name)  desc:\(.description)"'`.
3. In `~/.config/hypr/hyprland.lua`, **above** `require("default.hypr.omarchy")`:
   ```lua
   package.preload["default.hypr.monitor-workspaces"] = function()
     return require("hypr.workspace-links")
   end
   ```
4. In `~/.config/hypr/bindings.lua`:
   ```lua
   o.rebind("SUPER + TAB", "Next workspace (linked monitors too)", o.workspaces.cycle(1))
   o.rebind("SUPER + SHIFT + TAB", "Previous workspace (linked monitors too)", o.workspaces.cycle(-1))
   o.rebind("SUPER + CTRL + TAB", "Next workspace (this monitor only)", o.workspaces.cycle_alone(1))
   o.rebind("SUPER + CTRL + SHIFT + TAB", "Previous workspace (this monitor only)", o.workspaces.cycle_alone(-1))
   o.bind("SUPER + SHIFT + L", "Link or unlink this monitor's workspace cycling", o.workspaces.toggle_link())
   hl.unbind("SUPER + mouse_down")
   hl.unbind("SUPER + mouse_up")
   for _, key in ipairs({ "LEFT", "RIGHT", "UP", "DOWN" }) do
     hl.unbind("SUPER + SHIFT + ALT + " .. key)
   end
   ```
5. Remove any old `workspace_rule` lines for these numbers from `monitors.lua`.
   Optionally add a mirror catch-all after the main monitor's `hl.monitor` line:
   `hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1, mirror = "<main connector>" })`
6. Bar: copy `~/.config/omarchy/plugins/ewse.workspaces/` (rename the id in
   `manifest.json` and `moduleName` if you like), and put it in the bar's center
   in place of `omarchy.workspaces` in `~/.config/omarchy/shell.json`.
7. `hyprctl reload && hyprctl configerrors`, then `omarchy restart shell`.

## Checking it works

```bash
cat ~/.local/state/omarchy/workspace-links/layout.json     # current layout
hyprctl repl 'return type(o.workspaces.cycle)'             # "function" = module loaded
hyprctl repl 'o.workspaces.cycle_now(1) return 1'          # same as Super+Tab
hyprctl eval 'o.workspaces.toggle("DP-3")'                 # same as the chain / Super+Shift+L
# Simulate an undock (screens go dark); `hyprctl reload` brings them back:
hyprctl eval 'hl.monitor({ output = "desc:<description>", disabled = true })'
```

## Notes and gotchas

- **Bar widget edits need `omarchy restart shell`.** The shell says it's
  reloading a changed local bar widget, but keeps the old code. State changes
  (links, layout) show up live.
- **Hyprland side:** edits to the `.lua` files take effect on save or reload.
  Always check `hyprctl configerrors`.
- **The bar draws each docked monitor's numbers from `layout.json`, not from
  Quickshell's workspace list.** Quickshell credits every workspace switch to
  the *focused* monitor, so Super+Tab switching linked monitors in the
  background made it think workspaces had moved. The widget also calls
  `Hyprland.refreshMonitors()` / `refreshWorkspaces()` after every switch, for
  the active highlight. If the layout file goes missing, it retries every 2 s.
- **Monitor changes are debounced** (about 0.6 s), so a dock that drops several
  monitors at once is handled as one change, not one per monitor.
- **To turn it off:** delete the `package.preload` lines in `hyprland.lua` and
  the bindings block, then reload. Omarchy's per-monitor workspaces come back.
- **After Omarchy updates**, check that `default/hypr/omarchy.lua` still
  `require`s `default.hypr.monitor-workspaces` and that
  `default/hypr/bindings/tiling.lua` still calls `o.workspaces.focus`,
  `move_window`, `move_to_monitor` and `move_window_to_monitor`. If they rename
  any of these, the preload or the stand-in actions need updating to match.
- **On a laptop, closing the lid with the panel disabled (clamshell) counts as
  that monitor leaving.** Its workspaces compact onto the others and return when
  it comes back. A mirror-only TV with the panel disabled has nothing to mirror.
- If a monitor without `solo` ends up alone, it just uses its normal `slots`.
