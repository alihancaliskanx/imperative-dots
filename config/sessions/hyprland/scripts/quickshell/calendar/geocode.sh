#!/usr/bin/env bash

# geocode.sh — turn a typed place name into coordinates.
#
# Open-Meteo's geocoder, the same keyless service the forecast comes from, so
# adding a city costs no account and no API key. Prints one match per line as
# "label<TAB>lat<TAB>lon"; the settings panel splits on the tab and never has to
# parse JSON in QML.
#
# net-env.sh is sourced for the same reason weather.sh sources it: quickshell is
# started by the compositor, so the shells' proxy variables are not in scope and
# a search on the phone hotspot would otherwise come back empty with no error.

source "$(dirname "${BASH_SOURCE[0]}")/../../net-env.sh"

query="$*"
[ -z "${query// /}" ] && exit 0

curl -sf --max-time 8 --get "https://geocoding-api.open-meteo.com/v1/search" \
    --data-urlencode "name=$query" \
    --data-urlencode "count=8" \
    --data-urlencode "language=tr" \
    --data-urlencode "format=json" 2>/dev/null \
| jq -r '
    (.results // [])[]
    | . as $r
    | [ $r.name,
        (if ($r.admin1 // "") == "" or $r.admin1 == $r.name then empty else $r.admin1 end),
        ($r.country // empty) ]
      as $parts
    | [ ($parts | join(", ")),
        (($r.latitude  * 10000 | round) / 10000 | tostring),
        (($r.longitude * 10000 | round) / 10000 | tostring) ]
    | @tsv
' 2>/dev/null
