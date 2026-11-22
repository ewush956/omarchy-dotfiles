#!/bin/bash
# Make a fresh Omarchy install look and behave like my main machine.
#
#   git clone https://github.com/ewush956/omarchy-dotfiles ~/omarchy-dotfiles
#   cd ~/omarchy-dotfiles && ./install.sh             # core setup
#   ./install.sh --optional                           # also the heavy app list
#   ./install.sh --config-only                        # just copy config files
#
# Run it from a terminal inside a Hyprland session (it asks for your password
# for packages and for changing your shell). Safe to run again: every file it
# replaces is first copied to ~/.config-backup/<timestamp>/.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPTIONAL=no CONFIG_ONLY=no
for arg in "$@"; do
  case $arg in
    --optional) OPTIONAL=yes ;;
    --config-only) CONFIG_ONLY=yes ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

step() { printf '\n\e[1;32m==>\e[0m \e[1m%s\e[0m\n' "$*"; }
warn() { printf '\e[33m  ! %s\e[0m\n' "$*"; }

command -v omarchy >/dev/null || { echo "Omarchy isn't installed. Install it first: https://omarchy.org" >&2; exit 1; }

# Read a package list, dropping comments and blank lines.
read_list() { grep -vE '^\s*(#|$)' "$1" | awk '{print $1}'; }

# Install a list, splitting official-repo packages from AUR ones.
install_list() {
  local repo=() aur=() p
  for p in $(read_list "$1"); do
    if pacman -Si "$p" &>/dev/null; then repo+=("$p"); else aur+=("$p"); fi
  done
  ((${#repo[@]})) && omarchy pkg add "${repo[@]}"
  ((${#aur[@]})) && { omarchy pkg aur add "${aur[@]}" || warn "some AUR packages failed: ${aur[*]}"; }
  return 0
}

if [[ $CONFIG_ONLY == no ]]; then
  step "Installing packages (packages/core.txt)"
  install_list "$REPO/packages/core.txt"

  if [[ $OPTIONAL == yes ]]; then
    step "Installing optional packages (packages/optional.txt)"
    install_list "$REPO/packages/optional.txt"
  fi

  if ! omarchy pkg present voxtype-bin 2>/dev/null; then
    step "Setting up Voxtype dictation"
    omarchy install dictation voxtype || warn "voxtype setup failed; run: omarchy install dictation voxtype"
  fi
fi

step "Copying config into ~/.config"
BACKUP="$HOME/.config-backup/$(date +%Y%m%d-%H%M%S)"
rsync -a --backup --backup-dir="$BACKUP" "$REPO/config/" "$HOME/.config/"
[[ -d $BACKUP ]] && echo "  Replaced files backed up to $BACKUP"

# Workspace links need this machine's monitors. Written once; edit it after.
WL="$HOME/.config/hypr/workspace-links-config.lua"
if [[ ! -f $WL ]]; then
  out=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name // empty' || true)
  out=${out:-eDP-1}
  sed "s/MAIN_OUTPUT/$out/" "$REPO/templates/workspace-links-config.lua" > "$WL"
  echo "  Workspace links: main monitor is $out (edit $WL to add monitors)"
fi

# Voxtype ships its settings panel as an Omarchy plugin; shell.json loads it.
VOX=/usr/share/voxtype/omarchy-plugin/io.voxtype.settings
[[ -d $VOX ]] && ln -sfn "$VOX" "$HOME/.config/omarchy/plugins/io.voxtype.settings"

# Scripts need to stay executable after the copy.
chmod +x "$HOME"/.config/hypr/scripts/* "$HOME"/.config/kitty/*.py 2>/dev/null || true

step "Installing community themes (themes.txt)"
mkdir -p "$HOME/.config/omarchy/themes"
while read -r name url; do
  [[ -z $name || $name == \#* ]] && continue
  dir="$HOME/.config/omarchy/themes/$name"
  if [[ -d $dir/.git ]]; then
    git -C "$dir" pull -q --ff-only || warn "couldn't update theme $name"
  else
    git clone -q --depth 1 "$url" "$dir" && echo "  $name" || warn "couldn't clone theme $name"
  fi
done < "$REPO/themes.txt"

if [[ -z $(git config --global user.name || true) ]]; then
  step "Git identity (stored in ~/.config/git/config, not in this repo)"
  read -rp "  Git name:  " gname
  read -rp "  Git email: " gemail
  [[ -n $gname ]] && git config --global user.name "$gname"
  [[ -n $gemail ]] && git config --global user.email "$gemail"
fi

if [[ $CONFIG_ONLY == no && $(getent passwd "$USER" | cut -d: -f7) != */fish ]]; then
  step "Making fish your login shell"
  chsh -s /usr/bin/fish || warn "chsh failed; run: chsh -s /usr/bin/fish"
fi

step "Applying"
THEME=$(cat "$REPO/theme" 2>/dev/null || echo nord)
omarchy theme set "$THEME" || warn "couldn't set theme $THEME"
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  hyprctl reload >/dev/null
  errs=$(hyprctl configerrors 2>/dev/null | grep -v '^$' || true)
  [[ -n $errs && $errs != "no errors" ]] && warn "Hyprland config errors:" && echo "$errs"
  omarchy restart shell || true
  omarchy restart terminal || true
else
  warn "Not inside Hyprland: log in and run 'omarchy restart shell' once."
fi

cat <<EOF

Done. A few things to finish by hand:
  - Log out and back in (fish shell, uwsm env).
  - Open nvim once so lazy.nvim installs plugins.
  - Weather: set your location from the weather widget in the bar.
  - Wallpapers: pick per-monitor wallpapers with Super+Ctrl+Space.
  - More monitors: set them up in ~/.config/hypr/monitors.lua, then add them to
    ~/.config/hypr/workspace-links-config.lua (see workspace-links.md).
  - Machine-only Hyprland tweaks go in ~/.config/hypr/local.lua (never synced).
  - Sign in to 1Password, Zen and GitHub (gh auth login).
EOF
