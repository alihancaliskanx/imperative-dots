#!/usr/bin/env bash
#
# switcher.sh — the Hyprland half of the Super+Tab window switcher.
#
# Hyprland only opens it. The switcher then takes an exclusive keyboard grab and
# handles Tab, the arrows, Escape and the Super release on its own, so there is
# no submap to enter and no per-keystroke IPC call.
#
# The other verbs stay reachable for scripting and for testing without a
# keyboard, which is how this was developed.
#
#   switcher.sh open | next | prev | select | cancel

set -uo pipefail

QS_CONFIG="$HOME/.config/hypr/scripts/quickshell/Shell.qml"

ipc() { qs -p "$QS_CONFIG" ipc call switcher "$1" >/dev/null 2>&1; }

case "${1:-}" in
    open)   ipc open ;;
    next)   ipc next ;;
    prev)   ipc prev ;;
    select) ipc select ;;
    cancel) ipc cancel ;;
    *)
        printf 'usage: switcher.sh open|next|prev|select|cancel\n' >&2
        exit 1
        ;;
esac
