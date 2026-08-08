#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# CACHING & MIGRATION
# -----------------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/caching.sh"
qs_ensure_cache "workspaces"

# ============================================================================
# 1. ZOMBIE PREVENTION
# Kills any older instances of this script. When Quickshell reloads, 
# it can leave the old listener pipelines running in the background infinitely.
# ============================================================================
for pid in $(pgrep -f "workspaces.sh"); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
        kill -9 "$pid" 2>/dev/null
    fi
done

# Cleanly kill immediate children (like socat) when the script exits normally
cleanup() {
    pkill -P $$ 2>/dev/null
}
trap cleanup EXIT SIGTERM SIGINT

# --- Special Cleanup for Network/Bluetooth ---
# The network toggle starts a background bluetooth scan that must be killed
# explicitly. qs_manager.sh writes that pid to $QS_RUN_DIR, not to the
# per-widget run dir this used to look in, so the block below had never once
# found the file it was meant to clean up. The pid names a process group.
BT_PID_FILE="$QS_RUN_DIR/bt_scan_pid"

if [ -f "$BT_PID_FILE" ]; then
    read -r bt_pgid < "$BT_PID_FILE"
    [ -n "$bt_pgid" ] && kill -- -"$bt_pgid" 2>/dev/null
    rm -f "$BT_PID_FILE"
fi

# Ensure bluetooth scan is explicitly turned off (timeout prevents deadlocks on fresh installs)
(timeout 2 bluetoothctl scan off > /dev/null 2>&1) &
# ---------------------------------------------

# Configuration: Parse from settings.json dynamically, fallback to 8
SETTINGS_FILE="$HOME/.config/hypr/settings.json"
SEQ_END=$(jq -r '.workspaceCount // 8' "$SETTINGS_FILE" 2>/dev/null)
# Double check it is a valid integer to prevent jq errors later
if ! [[ "$SEQ_END" =~ ^[0-9]+$ ]]; then
    SEQ_END=8
fi

print_workspaces() {
    # One hyprctl and one jq instead of two of each. --batch returns the two
    # documents back to back and `jq -s` reads them as a two element array.
    # This runs on every switch, so those spawns were showing up as bar lag.
    raw=$(timeout 2 hyprctl -j --batch "workspaces;activeworkspace" 2>/dev/null)

    # Failsafe if hyprctl crashes to prevent jq from outputting errors
    if [ -z "$raw" ]; then return; fi

    # Generate the JSON and write it atomically to prevent UI flickering
    printf '%s' "$raw" | jq -s --arg end "$SEQ_END" -c '
        .[0] as $list | (.[1].id // -1) as $a
        |
        # Create a map of workspace ID -> workspace data for easy lookup
        (($list | map( { (.id|tostring): . } ) | add) // {}) as $s
        |
        # Iterate from 1 to SEQ_END
        [range(1; ($end|tonumber) + 1)] | map(
            . as $i |
            # Determine state: active -> occupied -> empty
            (if $i == $a then "active"
             elif ($s[$i|tostring] != null and $s[$i|tostring].windows > 0) then "occupied"
             else "empty" end) as $state |

            # Get window title for tooltip (if exists)
            (if $s[$i|tostring] != null then $s[$i|tostring].lastwindowtitle else "Empty" end) as $win |

            {
                id: $i,
                state: $state,
                tooltip: $win
            }
        )
    ' > "$QS_RUN_WORKSPACES/workspaces.tmp" || return

    mv "$QS_RUN_WORKSPACES/workspaces.tmp" "$QS_RUN_WORKSPACES/workspaces.json"
}

# Print initial state
print_workspaces

# ============================================================================
# 2. THE EVENT DEBOUNCER
# Listen to Hyprland socket wrapped in an infinite loop
# ============================================================================
while true; do
    socat -u UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | while read -r line; do
        case "$line" in
            workspace*|focusedmon*|activewindow*|createwindow*|closewindow*|movewindow*|destroyworkspace*)
                
                # Hyprland emits HUNDREDS of events a second when you move/resize windows.
                # This reads and discards subsequent events until the storm goes quiet,
                # bundling it into a single UI update instead of clogging the CPU.
                #
                # The window used to be 50ms, but `read -t` waits the whole timeout when
                # nothing more arrives -- and after a plain workspace switch nothing does.
                # So every switch paid the full 50ms before the bar was allowed to redraw,
                # which is most of a slide that finishes in under 150ms. A storm's events
                # arrive microseconds apart, so 10ms still bundles them just as tightly.
                while read -t 0.01 -r extra_line; do
                    continue
                done

                print_workspaces
                ;;
        esac
    done
    sleep 1
done
