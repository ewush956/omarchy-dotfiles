# Pins the shell's Pokémon sprite to the top-right corner of its kitty window as
# a window logo. A logo belongs to the window, not the text, so it stays put
# while output or scrollback moves underneath it.
#
# The shell (pokemon() in ~/.bashrc) talks to this watcher through kitty user
# variables:
#   pokemon=<path>     show the PNG at <path> (must live in the sprite dir)
#   pokemon_busy=1|0   a command started / the prompt is back
# While a command runs, the alternate screen is polled so the sprite hides
# while full-screen programs (nvim, tmux, less) are open.

import hashlib
import os
from typing import Any

from kitty.boss import Boss
from kitty.fast_data_types import add_timer, remove_timer
from kitty.window import Window

SPRITE_DIR = os.path.realpath(os.path.join(os.environ.get('XDG_RUNTIME_DIR', '/tmp'), 'kitty-pokemon'))
POLL_INTERVAL = 0.05

# window id -> {'key': logo cache key, 'data': png bytes, 'shown': bool, 'timer': timer id | None}
sprites: dict[int, dict[str, Any]] = {}


def _show(window: Window, state: dict[str, Any], visible: bool) -> None:
    if state['shown'] == visible:
        return
    if visible:
        window.set_logo(state['key'], 'top-right', 1.0, state['data'])
    else:
        window.set_logo('', 'top-right', 1.0, b'')
    state['shown'] = visible


def _stop_polling(state: dict[str, Any]) -> None:
    if state.get('timer') is not None:
        remove_timer(state['timer'])
        state['timer'] = None


def _load(path: str) -> bytes | None:
    # Any program in the terminal can set user vars, so only read PNGs from the
    # sprite directory.
    real = os.path.realpath(path)
    if os.path.dirname(real) != SPRITE_DIR or not real.endswith('.png'):
        return None
    try:
        with open(real, 'rb') as f:
            return f.read(4 * 1024 * 1024)
    except OSError:
        return None


def on_set_user_var(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    key, value = data.get('key'), data.get('value')

    if key == 'pokemon' and value:
        png = _load(value)
        if png is None:
            return
        state = sprites.setdefault(window.id, {'shown': False, 'timer': None})
        state['key'] = '/pokemon/' + hashlib.sha1(png).hexdigest()
        state['data'] = png
        state['shown'] = False
        _show(window, state, window.screen.is_main_linebuf())

    elif key == 'pokemon_busy' and window.id in sprites:
        state = sprites[window.id]
        _stop_polling(state)
        if value == '1':
            window_id = window.id

            def poll(timer_id: int | None) -> None:
                w = boss.window_id_map.get(window_id)
                if w is None or window_id not in sprites:
                    remove_timer(timer_id)
                    return
                _show(w, sprites[window_id], w.screen.is_main_linebuf())

            state['timer'] = add_timer(poll, POLL_INTERVAL, True)
        else:
            _show(window, state, window.screen.is_main_linebuf())


def on_close(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    state = sprites.pop(window.id, None)
    if state:
        _stop_polling(state)
