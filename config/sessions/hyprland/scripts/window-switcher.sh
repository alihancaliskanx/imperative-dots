#!/usr/bin/env bash
#
# window-switcher.sh — Mod+Q. Pick any window, on any workspace, with icons.
#
# The dotfiles repo has window-switch, which does the same job through fuzzel
# and draws a plain text list. This is the rofi version: it puts the actual
# application icon next to each entry and inherits the matugen theme, so it
# matches the rest of the desktop instead of looking like a terminal prompt.
#
# rofi's own `-show window` mode is X11-only and comes back empty on Wayland,
# so the list is built from hyprctl and handed to rofi in dmenu mode. The icon
# comes from the entry's "\0icon\x1f<name>" suffix, which is why the class is
# appended to every row.

set -uo pipefail

command -v rofi    >/dev/null || { notify-send "window-switcher" "rofi is not installed"; exit 1; }
command -v hyprctl >/dev/null || { notify-send "window-switcher" "hyprctl not found"; exit 1; }

# rofi resolves an icon name through the icon theme only. Several apps ship
# their icon into /usr/share/pixmaps instead — alacritty is one — and those
# never resolve, so the row comes out iconless. An absolute path is accepted
# by the same protocol, so look there first and fall back to the bare name.
icon_for() {
    local class="$1" p
    for p in "/usr/share/pixmaps/$class.svg" "/usr/share/pixmaps/$class.png" \
             "/usr/share/pixmaps/${class,,}.svg" "/usr/share/pixmaps/${class,,}.png"; do
        [ -f "$p" ] && { printf '%s' "$p"; return; }
    done
    printf '%s' "$class"
}

# One query, two uses: the address to focus with and the label to show. Asking
# hyprctl twice would race against a window closing between the two calls.
mapfile -t rows < <(hyprctl clients -j | jq -r '
    [ .[] | select(.mapped and (.hidden | not) and .title != "") ]
    | sort_by(.workspace.id, .class)
    | .[]
    | "\(.address)\t\(.workspace.name)\t\(.class)\t\(.title)"')

[ "${#rows[@]}" -gt 0 ] || { notify-send -t 2000 "window-switcher" "No windows open"; exit 0; }

# Piped straight out of the loop rather than built up in a variable: the icon
# protocol separates label from icon with a NUL, and bash cannot hold a NUL in
# a variable — it vanishes, and rofi draws the marker as literal text.
idx=$(
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r _addr ws class title <<< "$row"
        printf '%s  %s\0icon\x1f%s\n' "$ws" "$title" "$(icon_for "$class")"
    done | rofi -dmenu -i -show-icons -p "Window" -format i \
        -theme-str 'window { width: 820px; } listview { lines: 12; }') || exit 0
[ -n "$idx" ] || exit 0

IFS=$'\t' read -r addr _ _ _ <<< "${rows[$idx]}"
[ -n "$addr" ] || exit 0

# Raising as well as focusing matters for floating windows, which otherwise
# come forward behind whatever was on top.
hyprctl --batch "dispatch focuswindow address:$addr ; dispatch bringactivetotop" >/dev/null
