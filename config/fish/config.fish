set -x JAVA_TOOL_OPTIONS "-Djdk.xml.totalEntitySizeLimit=2000000 --enable-native-access=ALL-UNNAMED"

# Environment Omarchy's bash defaults would otherwise set
set -q EDITOR; or set -gx EDITOR nvim
set -gx SUDO_EDITOR $EDITOR
set -q BROWSER; or set -gx BROWSER omarchy-launch-browser
set -gx BAT_THEME ansi
set -gx MANROFFOPT -c
set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"

if status is-interactive
    set fish_greeting

    mise activate fish | source
    starship init fish | source
    # cd jumps to known directories via zoxide, like Omarchy's zd
    zoxide init fish --cmd cd | source
    fzf --fish | source

    alias pamcan pacman
    alias print lp
    alias clear "printf '\033[2J\033[3J\033[1;1H'"

    # Directories
    alias .. 'cd ..'
    alias ... 'cd ../..'
    alias .... 'cd ../../..'

    # Git
    alias g git
    alias gp 'git pull'
    alias gc 'git clone'
    alias ga 'git add'
    alias gm 'git commit -m'
    alias gcm 'git commit -m'
    alias gcam 'git commit -a -m'
    alias gcad 'git commit -a --amend'

    # Omarchy shortcuts
    alias lsa 'ls -a'
    alias lt 'eza --tree --level=2 --long --icons --git'
    alias lta 'lt -a'
    alias a 'omarchy-agent --inline'
    alias c 'opencode --auto'
    alias cx 'printf "\033[2J\033[3J\033[H" && claude --permission-mode auto'
    alias cy 'codex --approve-for-me'
    alias d docker
    alias h herdr
    alias t 'tmux attach || tmux new -s Work'
    alias mup 'MISE_MINIMUM_RELEASE_AGE=0 mise up'
    if test "$TERM" = xterm-kitty
        alias ff "fzf --preview 'case \$(file --mime-type -b {}) in image/*) kitty icat --clear --transfer-mode=memory --stdin=no --place=\$FZF_PREVIEW_COLUMNS\x\$FZF_PREVIEW_LINES@0x0 {} ;; *) bat --style=numbers --color=always {} ;; esac'"
    else
        alias ff "fzf --preview 'bat --style=numbers --color=always {}'"
    end
    alias eff '$EDITOR (ff)'
    alias ic 'tdl c'
    alias ix 'tdl cx'
    alias icx 'tdl c cx'

    # Omarchy's helper functions (tdl, tds, hdl, compress, iso2sd, ssh, ...)
    # are bash-only, so wrap each one to run under bash with all of them
    # loaded. New upstream functions get picked up automatically. Names
    # already defined above (e.g. my ga alias) win. If the function changed
    # directory (ga/gd worktrees), follow it.
    set -q OMARCHY_PATH; or set -gx OMARCHY_PATH /usr/share/omarchy
    function __omarchy_bash_fn
        set -l pwd_file (mktemp)
        PWD_FILE=$pwd_file bash -c 'for f in "$OMARCHY_PATH"/default/bash/fns/*; do source "$f"; done
            "$@"; rc=$?; pwd >"$PWD_FILE"; exit $rc' bash $argv
        set -l rc $status
        set -l new_pwd (cat $pwd_file 2>/dev/null)
        rm -f $pwd_file
        test -n "$new_pwd" -a "$new_pwd" != "$PWD"; and builtin cd $new_pwd
        return $rc
    end
    for name in (cat $OMARCHY_PATH/default/bash/fns/* | string replace -rf '^([A-Za-z][A-Za-z0-9-]*)\(\)\s*\{.*' '$1')
        functions -q $name; and continue
        set -l wraps
        command -q $name; and set wraps --wraps $name
        eval "function $name $wraps --description 'Omarchy bash function'; __omarchy_bash_fn $name \$argv; end"
    end
end

function n --description 'nvim, defaulting to the current directory'
    if test (count $argv) -eq 0
        command nvim .
    else
        command nvim $argv
    end
end

function open --description 'Open with the default app, detached'
    xdg-open $argv >/dev/null 2>&1 &
    disown
end

# Random Pokémon sprite in the top-right corner of new kitty terminals. The
# sprite is handed to ~/.config/kitty/pokemon_watcher.py, which pins it to the
# window as a logo, so it stays put while output or scrollback moves, and hides
# it while full-screen programs (nvim, tmux, less) are open.
set -g __pokemon_dir (set -q XDG_RUNTIME_DIR; and echo $XDG_RUNTIME_DIR; or echo /tmp)/kitty-pokemon

# Set a kitty user variable (value is base64 encoded per the OSC 1337 spec)
function __pokemon_var
    printf '\e]1337;SetUserVar=%s=%s\a' $argv[1] (printf '%s' $argv[2] | base64 -w0)
end

function pokemon
    test "$TERM" = xterm-kitty; or return 0
    type -q curl; and type -q magick; or return 0
    mkdir -p $__pokemon_dir
    set -l img $__pokemon_dir/$fish_pid.png
    if timeout 1 curl -fsS "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/"(random 1 898)".png" -o $img 2>/dev/null
        # Trim the transparent padding and upscale 3x with crisp pixel edges
        magick $img -trim +repage -filter point -resize 300% $img 2>/dev/null; and __pokemon_var pokemon $img
    end
end

if status is-interactive; and not set -q POKEMON_SHOWN
    set -gx POKEMON_SHOWN 1
    pokemon
    # Tell the watcher when a command starts and when the prompt is back, so
    # it only watches for full-screen programs then.
    function __pokemon_busy --on-event fish_preexec
        __pokemon_var pokemon_busy 1
    end
    function __pokemon_idle --on-event fish_prompt
        __pokemon_var pokemon_busy 0
    end
    function __pokemon_cleanup --on-event fish_exit
        rm -f $__pokemon_dir/$fish_pid.png
    end
end

# Function below spawns a pokemon after each command, gets a bit glitchy when swapping windows.
# function pokemon_after_each_command --on-event fish_postexec
#     if test $status -ne 0
#         return
#     end
#     if not status is-interactive
#         return
#     end
#     if type -q curl; and type -q timeout; and type -q kitty
#         set id (random 1 898)
#         set url "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/$id.png"
#         set img "/tmp/pokemon_$fish_pid.png"
#         timeout 1 curl -fsS "$url" -o "$img" >/dev/null 2>&1
#         if test $status -eq 0
#             kitty +kitten icat "$img" 2>/dev/null
#             echo
#         end
#     end
# end

# function make_python_venv
#     set -l version $argv[1]
#
#     if test -z "$version"
#         set version (pyenv latest -k 3)
#     end
#
#     pyenv install -s $version
#     pyenv local $version
#
#     set -l venv_dir ".venv"
#     set -l req_file "requirements.txt"
#     set -l gitignore ".gitignore"
#     set -l envrc ".envrc"
#
#     rm -rf $venv_dir
#     pyenv exec python -m venv $venv_dir
#
#     if not test -f $req_file
#         touch $req_file
#     end
#
#     if not test -f $gitignore
#         printf "%s\n" "$venv_dir/" >$gitignore
#     else if not grep -qxF "$venv_dir/" $gitignore
#         printf "\n%s\n" "$venv_dir/" >>$gitignore
#     end
#
#     printf "source .venv/bin/activate.fish\n" >$envrc
#     direnv allow >/dev/null
# end

functions -e make_python_venv

function make_python_venv
    set -l pyver $argv[1]

    if test -z "$pyver"
        set pyver (pyenv install --list | string trim | string match -r '^\d+\.\d+\.\d+$' | tail -n 1)
    end

    pyenv install -s $pyver
    pyenv local $pyver

    rm -rf .venv
    pyenv exec python -m venv .venv

    test -f requirements.txt; or touch requirements.txt

    if not test -f .gitignore
        printf ".venv/\n" >.gitignore
    else if not grep -qxF ".venv/" .gitignore
        printf "\n.venv/\n" >>.gitignore
    end

    printf 'export VIRTUAL_ENV="$PWD/.venv"\nPATH_add "$VIRTUAL_ENV/bin"\n' >.envrc
    direnv allow >/dev/null
end
function install_requirments
    set -l venv_python ".venv/bin/python"
    set -l req_file "requirements.txt"

    if not test -x $venv_python
        echo "Missing .venv. Run: make_python_venv"
        return 1
    end

    if not test -f $req_file
        echo "Missing requirements.txt. Run: make_python_venv"
        return 1
    end

    $venv_python -m pip install -r $req_file
end

direnv hook fish | source
