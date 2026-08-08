#!/usr/bin/env bash
#
# reload.sh — Mod+R. Reloads the shell, and refreshes the shortcut list the
# settings panel shows while it is at it: that list lives in settings.json, so
# it goes stale the moment keybindings.conf is edited.

"$(dirname "${BASH_SOURCE[0]}")/sync-keybinds.py" >/dev/null 2>&1

qs -p ~/.config/hypr/scripts/quickshell/Shell.qml ipc call main forceReload
