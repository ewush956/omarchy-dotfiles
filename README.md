# omarchy-dotfiles

My [Omarchy](https://omarchy.org) desktop: install stock Omarchy, clone this
repo, run one script, and the machine looks and behaves like my main one.

```bash
git clone https://github.com/ewush956/omarchy-dotfiles ~/omarchy-dotfiles
cd ~/omarchy-dotfiles
./install.sh               # packages, config, themes, fish shell
./install.sh --optional    # also the heavy apps in packages/optional.txt
./install.sh --config-only # only copy config (e.g. after pulling changes)
```

Run it from a terminal inside Hyprland. Every file it replaces in `~/.config`
is backed up to `~/.config-backup/<timestamp>/` first.

## What's in it

| Area | Files |
|---|---|
| Hyprland | `config/hypr/`: keybindings (`bindings.lua`, incl. swap/focus across monitors with wrap-around), look and feel (`looknfeel.lua`: 2px gaps, rounding 4, dim inactive, opaque windows, blur for the bar), autostart, input |
| Workspace links | `config/hypr/workspace-links.lua` + `workspace-links.md`: fixed workspaces per monitor with linked Super+Tab cycling, instead of Omarchy's per-monitor blocks |
| Bar + shell | `config/omarchy/shell.json` and plugins: Rice Bar (Liquid preset, patched for Omarchy 4.x, MIT, by jcarcinogen), `ewse.workspaces`, `ewse.indicators`, `ewse.weather`, `ewse.background` + `ewse.wallpapers` (per-monitor wallpapers, Super+Ctrl+Space), `ewse.notifications` (reminders stay on screen) |
| Menu | `config/omarchy/extensions/omarchy-menu.jsonc` |
| Terminals | kitty (default, with the Pokémon sprite watcher), ghostty, alacritty, foot, tmux, starship |
| Shell | fish (`config/fish/`): Omarchy's bash aliases and functions ported, Pokémon sprite, Python venv helpers |
| Editor | Neovim (LazyVim) with LaTeX, Jupyter/molten, PDF view; follows the Omarchy theme |
| Other | btop, lazygit, git aliases, imv, mise, voxtype dictation, browser flags, mimeapps, wireplumber tweaks |
| Themes | `themes.txt`: community themes cloned by the installer; active theme in `theme` |
| Packages | `packages/core.txt` (installed), `packages/optional.txt` (`--optional`) |

Nothing hardware-specific is included, so it works with any monitors. Omarchy's
own `monitors.lua` auto-detects displays, and the installer writes a one-monitor
`workspace-links-config.lua` for whatever screen it finds (add more monitors
later, see `config/hypr/workspace-links.md`). Machine-only Hyprland tweaks go in
`~/.config/hypr/local.lua`, which `hyprland.lua` loads if it exists and the repo
never touches.

Server/VPN/media setup lives in a separate private repo.

## Updating this repo from a machine

```bash
./sync.sh        # copy the tracked files back from ~/.config, then review git diff
```
