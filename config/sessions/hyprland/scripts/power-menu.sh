#!/usr/bin/env bash
#
# power-menu.sh — lock / suspend / log out / reboot / shut down, through rofi.
#
# Added by this fork. Upstream keeps its power actions inside the shell's
# battery panel, which on a machine with no battery draws "0% UNKNOWN" and a
# single logout icon — so there is effectively no way to shut down from the
# desktop. This takes over Super+B, which opened that panel.
#
# rofi rather than a quickshell popup on purpose: it is one file, it works
# whether or not the shell is healthy, and rofi is already a dependency here.

set -uo pipefail

command -v rofi >/dev/null || { notify-send "power-menu" "rofi is not installed"; exit 1; }

choice=$(printf '%s\n' "Lock" "Suspend" "Log out" "Reboot" "Shut down" \
    | rofi -dmenu -i -p "Power" -lines 5) || exit 0

case "$choice" in
    "Lock")      exec bash "$HOME/.config/hypr/scripts/lock.sh" ;;
    "Suspend")   exec systemctl suspend ;;
    "Log out")   exec bash "$HOME/.config/hypr/scripts/exit.sh" ;;
    "Reboot")    exec systemctl reboot ;;
    "Shut down") exec systemctl poweroff ;;
    *)           exit 0 ;;
esac
