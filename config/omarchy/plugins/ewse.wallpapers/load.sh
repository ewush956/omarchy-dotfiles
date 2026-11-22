#!/bin/bash

# Emits the picker's state as one JSON object:
#   focused   connector the overlay should open on
#   monitors  [{name, description, label, vertical, current}] left to right
#   images    [{path, real, thumb}] from the current theme + user backgrounds

state="$HOME/.local/state/omarchy/current"
overrides="$state/monitor-backgrounds.json"
theme_name=$(cat "$state/theme.name" 2>/dev/null)
dirs=("$state/theme/backgrounds" "$HOME/.config/omarchy/backgrounds/$theme_name")

# Same thumbnail cache as the stock switcher, so thumbnails are shared.
omarchy-menu-images --cache-only "${dirs[@]}" >/dev/null 2>&1

global=$(readlink -f "$state/background" 2>/dev/null)
[[ -s $overrides ]] && override_json=$(<"$overrides") || override_json='{}'

images=$(
  bash "${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/image-picker/list.sh" "$(printf '%s\n' "${dirs[@]}")" |
    while IFS=$'\t' read -r image thumb; do
      jq -cn --arg path "$image" --arg real "$(readlink -f "$image")" --arg thumb "$thumb" '{path: $path, real: $real, thumb: $thumb}'
    done | jq -cs .
)

hyprctl monitors -j | jq -c \
  --arg global "$global" \
  --argjson overrides "$override_json" \
  --argjson images "${images:-[]}" '
  def monitor_label:
    if (.name | startswith("eDP")) then "Laptop"
    else ((.model | split(" ")[0]) // .name) | ascii_downcase | (.[0:1] | ascii_upcase) + .[1:]
    end;
  {
    focused: (map(select(.focused))[0].name // .[0].name),
    monitors: (sort_by(.x) | map({
      name,
      description,
      label: monitor_label,
      vertical: ((.transform % 2) == 1),
      current: ($overrides[.description] // $global)
    })),
    images: $images
  }'
