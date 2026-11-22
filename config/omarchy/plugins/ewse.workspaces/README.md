# ewse.workspaces

Bar widget for **workspace links**. Full documentation, including installing on
another machine: `~/.config/hypr/workspace-links.md`.

- Shows the workspaces the bar's monitor owns, read from
  `~/.local/state/omarchy/workspace-links/layout.json` (written by
  `~/.config/hypr/workspace-links.lua`), plus any occupied overflow workspace
  sitting on that monitor.
- After the numbers: a chain when the monitor is linked, a dimmed broken chain
  when it isn't (hidden with only one monitor). Clicking it runs
  `hyprctl eval 'o.workspaces.toggle("<connector>")'`.
- Without the layout file it falls back to listing workspaces 1–10 on its
  monitor.
- After editing `Workspaces.qml`, run `omarchy restart shell`. Hot reload
  doesn't pick up bar widget code.
