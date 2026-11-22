-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Workspace links (~/.config/hypr/workspace-links.md): fixed workspaces per
-- monitor with linked Super+Tab cycling, in place of Omarchy's per-monitor
-- workspaces. Must come before Omarchy's defaults load. Delete these lines to
-- go back to Omarchy's own behaviour.
package.preload["default.hypr.monitor-workspaces"] = function()
  return require("hypr.workspace-links")
end

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Machine-specific extras that don't belong in shared dotfiles (lid handling,
-- one-off hardware tweaks). Optional: loaded only if hypr/local.lua exists.
local local_config = io.open(os.getenv("HOME") .. "/.config/hypr/local.lua", "r")
if local_config then
  local_config:close()
  require("hypr.local")
end

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- hyprmon: managed monitor profile include
-- require("hyprmon")
