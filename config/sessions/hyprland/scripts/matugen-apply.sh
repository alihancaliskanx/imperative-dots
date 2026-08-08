#!/usr/bin/env bash

# matugen-apply.sh — regenerate every theme file from a wallpaper.
#
# The pickers used to call `matugen image "$x" || true` inline. Three problems
# came with that:
#
#   matugen refuses an image it cannot reduce to one source colour unless it is
#   told which to prefer, and with no terminal attached it cannot ask. The `||
#   true` then swallowed the refusal, so a busy wallpaper simply left the whole
#   desktop on the previous palette with nothing logged anywhere.
#
#   matugen has nine scheme types and a light mode, and none of them were
#   reachable: every call took the defaults.
#
#   The flags lived in three copies of an inlined shell string.
#
# With no argument the wallpaper is read back from awww, which is what makes
# re-theming on a scheme change possible without storing the path anywhere.
#
#   matugen-apply.sh [image]

set -uo pipefail

SETTINGS="$HOME/.config/hypr/settings.json"

img="${1:-}"
if [ -z "$img" ]; then
    img=$(awww query 2>/dev/null | sed -n 's/.*currently displaying: image: //p' | head -n1)
fi

if [ -z "$img" ] || [ ! -f "$img" ]; then
    notify-send "Theme" "No wallpaper to read colours from." 2>/dev/null
    exit 1
fi

read_setting() {
    [ -r "$SETTINGS" ] || return 1
    jq -r --arg k "$1" '.[$k] // empty' "$SETTINGS" 2>/dev/null
}

scheme=$(read_setting matugenScheme)
mode=$(read_setting matugenMode)

# The same defaults matugen itself documents, so an unset setting behaves
# exactly as the old inline call did.
scheme="${scheme:-scheme-tonal-spot}"
mode="${mode:-dark}"

# --prefer is what keeps a multi-coloured wallpaper from stopping the run. It
# only decides between candidates matugen already found; a single-colour image
# is unaffected.
if err=$(matugen image "$img" --type "$scheme" --mode "$mode" --prefer saturation 2>&1); then
    exit 0
fi

printf '%s\n' "$err" >&2
notify-send "Theme" "matugen failed for $(basename "$img")" 2>/dev/null
exit 1
