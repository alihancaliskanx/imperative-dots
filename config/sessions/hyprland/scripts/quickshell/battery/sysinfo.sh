#!/usr/bin/env bash

# sysinfo.sh — the six values BatteryPopup reads, one per line, always six.
#
# The popup indexes this output by position and skips its entire parse unless it
# receives six lines, so a field that cannot be read still has to print its
# fallback. The obvious `cmd 2>/dev/null | head -n1 || echo fallback` does not
# do that: a pipeline's exit status is the last command's, and `head` succeeds
# on empty input, so the `||` never fires and the line vanishes instead.
#
# On a machine with no battery -- /sys/class/power_supply holding only AC --
# that dropped the first two lines, left four, and failed the six-line check.
# Everything below the battery went with it: the power profile buttons ran
# powerprofilesctl but the highlight never moved, and volume, brightness and
# uptime sat frozen at their defaults.
#
# Command substitution plus ${x:-default} is what actually guarantees a line.
#
# Order is a contract with BatteryPopup.qml:
#   0 capacity  1 status  2 profile  3 uptime  4 volume  5 brightness

cap=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1)
printf '%s\n' "${cap:-0}"

status=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1)
printf '%s\n' "${status:-Unknown}"

profile=$(powerprofilesctl get 2>/dev/null | head -n1)
printf '%s\n' "${profile:-balanced}"

uptime_str=$(awk '{print int($1/3600)"h "int(($1%3600)/60)"m"}' /proc/uptime 2>/dev/null)
printf '%s\n' "${uptime_str:-0h 0m}"

volume=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null \
    | awk '{print int($2*100), ($3=="[MUTED]"?"off":"on")}')
printf '%s\n' "${volume:-0 on}"

brightness=$(brightnessctl -m 2>/dev/null | awk -F, '{print substr($4, 1, length($4)-1)}')
printf '%s\n' "${brightness:-0}"
