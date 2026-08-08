#!/usr/bin/env bash
export QS_CACHE_DIR="$HOME/.cache/quickshell"
export QS_STATE_DIR="$HOME/.local/state/quickshell"
export QS_RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/quickshell"
export QS_LOG_DIR="$QS_RUN_DIR/logs"

mkdir -p "$QS_CACHE_DIR" "$QS_STATE_DIR" "$QS_RUN_DIR" "$QS_LOG_DIR"
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
QS_DIR="$SCRIPT_DIR/quickshell"

# Function to dynamically create and export cache directories for ANY module by request
#
# The loop below calls this once per widget folder, and every script that wants
# a single cache path sources this file, so anything forked in here is paid ~18
# times over on each call. `$(echo | tr)` was one such fork; bash uppercases in
# the expansion. The mkdir is skipped once the directories exist, which after
# the first login is always.
qs_ensure_cache() {
    local WIDGET_NAME="$1"
    local WIDGET_UPPER="${WIDGET_NAME^^}"

    local WIDGET_CACHE="$QS_CACHE_DIR/$WIDGET_NAME"
    local WIDGET_STATE="$QS_STATE_DIR/$WIDGET_NAME"
    local WIDGET_RUN="$QS_RUN_DIR/$WIDGET_NAME"

    [ -d "$WIDGET_CACHE" ] && [ -d "$WIDGET_STATE" ] && [ -d "$WIDGET_RUN" ] \
        || mkdir -p "$WIDGET_CACHE" "$WIDGET_STATE" "$WIDGET_RUN"

    export "QS_CACHE_${WIDGET_UPPER}=$WIDGET_CACHE"
    export "QS_STATE_${WIDGET_UPPER}=$WIDGET_STATE"
    export "QS_RUN_${WIDGET_UPPER}=$WIDGET_RUN"
}

# Pre-initialize for all existing QML widget folders in the main directory
if [ -d "$QS_DIR" ]; then
    for dir in "$QS_DIR"/*/; do
        [ -d "$dir" ] || continue
        WIDGET_NAME="${dir%/}"
        qs_ensure_cache "${WIDGET_NAME##*/}"
    done
fi
