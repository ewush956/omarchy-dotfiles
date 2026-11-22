#!/bin/bash
# Pull this machine's current config back into the repo, then review with
# `git diff` before committing. Only paths the repo already tracks are synced;
# hardware-specific and private bits are filtered out.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="$HOME/.config"
EX=(--exclude .git --exclude '*.bak' --exclude '*.bak.*' --exclude '*backup*')

# Whole directories (new files in them are picked up too).
for d in kitty ghostty alacritty foot tmux lazygit imv mise nvim latex \
         fish/functions omarchy/branding omarchy/backgrounds \
         omarchy/plugins/io.github.jcarcinogen.rice-bar omarchy/plugins/ewse.workspaces \
         omarchy/plugins/ewse.indicators omarchy/plugins/ewse.background \
         omarchy/plugins/ewse.wallpapers omarchy/plugins/ewse.notifications \
         omarchy/plugins/ewse.weather; do
  [[ -d $C/$d ]] && rsync -a --delete "${EX[@]}" --exclude examples --exclude 'tip-with-x-money.*' \
    --exclude 'br.fish' "$C/$d/" "$REPO/config/$d/"
done

# Single files.
for f in hypr/hyprland.lua hypr/bindings.lua hypr/looknfeel.lua hypr/autostart.lua \
         hypr/input.lua hypr/workspace-links.lua hypr/workspace-links.md hypr/xdph.conf \
         hypr/scripts/cursor-pulse.py hypr/scripts/launch-browser-single \
         hypr/scripts/zen-trim-session \
         fish/config.fish btop/btop.conf voxtype/config.toml \
         herdr/config.toml omarchy/extensions/omarchy-menu.jsonc starship.toml mimeapps.list \
         xdg-terminals.list \
         wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf; do
  [[ -f $C/$f ]] && install -D -m "$(stat -c %a "$C/$f")" "$C/$f" "$REPO/config/$f"
done

# Bar layout without the private server widgets (the server repo adds them back).
jq '.bar.layout.right |= map(select(.id != "ewse.vpn" and .id != "ewse.jellyfin"))' \
  "$C/omarchy/shell.json" > "$REPO/config/omarchy/shell.json"

# Git config without name/email.
awk '/^\[user\]/{skip=1; next} /^\[/{skip=0} !skip' "$C/git/config" > "$REPO/config/git/config"
cp "$C/git/ignore" "$REPO/config/git/ignore" 2>/dev/null || true

cat "$HOME/.local/state/omarchy/current/theme.name" > "$REPO/theme" 2>/dev/null || true

# monitors.lua, workspace-links-config.lua and hypr/local.lua are per machine
# and never synced.
cd "$REPO" && git status --short
