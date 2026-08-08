#!/usr/bin/env bash
#
# switcher.sh — the Hyprland half of the Super+Tab window switcher.
#
# Two things have to happen together and Hyprland cannot bind both to one key:
# the shell has to show or advance the strip, and the compositor has to enter a
# submap so that further Tab presses go to the switcher instead of doing
# whatever Tab normally does.
#
# The submap is also what makes "release Super to pick" cheap. Binding
# `bindr = SUPER, Super_L` globally would fire an IPC call every single time
# Super is released — and every shortcut on this desktop uses Super. Inside the
# submap it only exists while the switcher is open.
#
#   switcher.sh open     first Super+Tab: show the strip, enter the submap
#   switcher.sh next     Tab while open
#   switcher.sh prev     Shift+Tab while open
#   switcher.sh select   Super released: focus the highlighted window, leave
#   switcher.sh cancel   Escape: leave without switching

set -uo pipefail

QS_CONFIG="$HOME/.config/hypr/scripts/quickshell/Shell.qml"

ipc() { qs -p "$QS_CONFIG" ipc call switcher "$1" >/dev/null 2>&1; }

case "${1:-}" in
    open)
        ipc open
        hyprctl dispatch submap switcher >/dev/null
        ;;
    next)   ipc next ;;
    prev)   ipc prev ;;
    select)
        ipc select
        hyprctl dispatch submap reset >/dev/null
        ;;
    cancel)
        ipc cancel
        hyprctl dispatch submap reset >/dev/null
        ;;
    *)
        printf 'usage: switcher.sh open|next|prev|select|cancel\n' >&2
        exit 1
        ;;
esac
