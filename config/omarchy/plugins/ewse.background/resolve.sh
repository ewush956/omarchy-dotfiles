#!/bin/bash

# Prints the global background on the first line, then one
# "<connector>\t<image>" line per monitor that has its own background.
# Overrides are keyed by Hyprland monitor description, so they survive
# connector renames (DP-2 vs DP-3) across dock reconnects.

state="$HOME/.local/state/omarchy/current"
overrides="$state/monitor-backgrounds.json"

readlink -f "$state/background" 2>/dev/null || echo

[[ -s $overrides ]] || exit 0

hyprctl monitors -j 2>/dev/null |
  jq -r --slurpfile o "$overrides" '.[] | select(($o[0] // {})[.description] != null) | "\(.name)\t\($o[0][.description])"' 2>/dev/null |
  while IFS=$'\t' read -r name image; do
    [[ -f $image ]] && printf '%s\t%s\n' "$name" "$image"
  done
