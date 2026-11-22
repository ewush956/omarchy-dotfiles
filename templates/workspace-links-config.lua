-- Workspace links: this machine's monitors. See ~/.config/hypr/workspace-links.md.
--
-- Generic single-monitor setup. install.sh writes this file once, with MAIN_OUTPUT
-- replaced by the connector name Hyprland reports for the first monitor (e.g. eDP-1).
-- To add more monitors, see the Configuration section of workspace-links.md.
-- `solo` is used when this is the only managed monitor connected.

return {
  monitors = {
    {
      key = "main",
      label = "Main",
      output = "MAIN_OUTPUT",
      slots = { 1, 2, 3, 4, 5 },
      solo = { 1, 2, 3, 4, 5 },
    },
  },
}
