#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# CACHING & MIGRATION
# -----------------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/../../caching.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../net-env.sh"
qs_ensure_cache "weather"

# Force standard C locale for number formatting and date parsing (fixes printf and date command issues on varying OS locales)
export LC_ALL=C

# Paths
cache_dir="$QS_CACHE_WEATHER"
json_file="${cache_dir}/weather.json"
view_file="${cache_dir}/view_id"
daily_cache_file="${cache_dir}/daily_weather_cache.json"
next_day_cache_file="${cache_dir}/next_day_precache.json"
ENV_FILE="$(dirname "$0")/.env"

# Settings written by the settings panel. Sourced rather than fed through
# `export $(... | xargs)`: place names carry spaces and commas ("Kadıköy,
# İstanbul") and xargs splits those into bogus operands, so the name arrived
# truncated and export complained on stderr for every remaining word.
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# Open-Meteo needs no API key, only a coordinate. WEATHER_LAT/WEATHER_LON come
# from .env; the defaults are Istanbul so a missing .env still shows real
# weather rather than zeroes.
LAT="${WEATHER_LAT:-41.0138}"
LON="${WEATHER_LON:-28.9497}"
UNIT="${WEATHER_UNIT:-${OPENWEATHER_UNIT:-metric}}"

# Determine temperature symbol based on unit
case "$UNIT" in
    "imperial") UNIT_SYM="°F" ;;
    "standard") UNIT_SYM="K" ;;
    *) UNIT_SYM="°C" ;;
esac

mkdir -p "${cache_dir}"

write_dummy_data() {
    final_json="["
    for i in {0..4}; do
        future_date=$(date -d "+$i days")
        f_day=$(date -d "$future_date" "+%a")
        f_full_day=$(date -d "$future_date" "+%A")
        f_date_num=$(date -d "$future_date" "+%d %b")
        
        final_json="${final_json} {
            \"id\": \"${i}\",
            \"day\": \"${f_day}\",
            \"day_full\": \"${f_full_day}\",
            \"date\": \"${f_date_num}\",
            \"max\": \"0.0\",
            \"min\": \"0.0\",
            \"feels_like\": \"0.0\",
            \"wind\": \"0\",
            \"humidity\": \"0\",
            \"pop\": \"0\",
            \"icon\": \"\",
            \"hex\": \"#cdd6f4\",
            \"desc\": \"Offline\",
            \"hourly\": [{\"time\": \"00:00\", \"temp\": \"0.0\", \"icon\": \"\", \"hex\": \"#cdd6f4\"}]
        },"
    done
    final_json="${final_json%,}]"
    echo "{ \"current_temp\": \"0.0\", \"current_icon\": \"\", \"current_hex\": \"#cdd6f4\", \"forecast\": ${final_json} }" > "${json_file}"
}

get_data() {
    # Open-Meteo: no key, no account, no rate limit to speak of. The endpoint
    # returns daily aggregates directly, so none of the 3-hour bucketing and
    # day-rollover caching the OpenWeather version needed is required here.
    local unit_param=""
    case "$UNIT" in
        imperial) unit_param="&temperature_unit=fahrenheit&wind_speed_unit=mph" ;;
    esac

    local url="https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}"
    url+="&current=temperature_2m,weather_code,is_day"
    url+="&daily=weather_code,temperature_2m_max,temperature_2m_min,apparent_temperature_max,precipitation_probability_max,wind_speed_10m_max"
    url+="&hourly=temperature_2m,weather_code,is_day,relative_humidity_2m"
    url+="&timezone=auto&forecast_days=5${unit_param}"

    local raw
    raw=$(curl -sf --max-time 20 "$url")

    # A failed fetch must never destroy a working cache — same rule the previous
    # version had. With no cache at all, write the zeroes so the bar has
    # something valid to parse.
    if [ -z "$raw" ] || [ "$(printf '%s' "$raw" | jq -r 'has("current")' 2>/dev/null)" != "true" ]; then
        [ -f "$json_file" ] || write_dummy_data
        return
    fi

    # Written to a temp file first: quickshell watches this path, and a
    # half-written file is a parse error on the other side.
    if printf '%s' "$raw" | jq 'def f1: (. * 10 | round) / 10 | tostring | if test("\\.") then . else . + ".0" end;
def icon($c; $day):
    if $c == 0 then (if $day == 1 then "" else "" end)
    elif $c <= 3 then ""
    elif $c == 45 or $c == 48 then "󰖑"
    elif ($c >= 71 and $c <= 77) or $c == 85 or $c == 86 then ""
    elif $c >= 95 then ""
    else "󰖗" end;
def hex($c; $day):
    if $c == 0 then (if $day == 1 then "#f9e2af" else "#cba6f7" end)
    elif $c <= 3 then "#bac2de"
    elif $c == 45 or $c == 48 then "#84afdb"
    elif ($c >= 71 and $c <= 77) or $c == 85 or $c == 86 then "#cdd6f4"
    elif $c >= 95 then "#f9e2af"
    else "#74c7ec" end;
def desc($c):
    if $c == 0 then "Clear" elif $c == 1 then "Mainly Clear"
    elif $c == 2 then "Partly Cloudy" elif $c == 3 then "Overcast"
    elif $c == 45 or $c == 48 then "Fog"
    elif $c >= 51 and $c <= 57 then "Drizzle"
    elif $c >= 61 and $c <= 67 then "Rain"
    elif $c >= 71 and $c <= 77 then "Snow"
    elif $c >= 80 and $c <= 82 then "Showers"
    elif $c == 85 or $c == 86 then "Snow Showers"
    elif $c == 95 then "Thunderstorm"
    elif $c >= 96 then "Thunderstorm, Hail"
    else "Unknown" end;
. as $r
| { current_temp: ($r.current.temperature_2m | f1),
    current_icon: icon($r.current.weather_code; $r.current.is_day),
    current_hex:  hex($r.current.weather_code; $r.current.is_day),
    forecast: [ range(0; ($r.daily.time | length)) as $i
      | ($r.daily.time[$i]) as $d
      | ($d | strptime("%Y-%m-%d") | mktime) as $ep
      | { id: ($i | tostring),
          day: ($ep | strftime("%a")),
          day_full: ($ep | strftime("%A")),
          date: ($ep | strftime("%d %b")),
          max: ($r.daily.temperature_2m_max[$i] | f1),
          min: ($r.daily.temperature_2m_min[$i] | f1),
          feels_like: ($r.daily.apparent_temperature_max[$i] | f1),
          wind: ($r.daily.wind_speed_10m_max[$i] | round | tostring),
          humidity: ([ range(0; ($r.hourly.time | length)) as $j
                       | select($r.hourly.time[$j] | startswith($d))
                       | $r.hourly.relative_humidity_2m[$j] ] | (add / length) | round | tostring),
          pop: (($r.daily.precipitation_probability_max[$i] // 0) | round | tostring),
          icon: icon($r.daily.weather_code[$i]; 1),
          hex:  hex($r.daily.weather_code[$i]; 1),
          desc: desc($r.daily.weather_code[$i]),
          hourly: [ range(0; ($r.hourly.time | length)) as $j
                    | select($r.hourly.time[$j] | startswith($d))
                    | { time: ($r.hourly.time[$j] | split("T")[1]),
                        temp: ($r.hourly.temperature_2m[$j] | f1),
                        icon: icon($r.hourly.weather_code[$j]; $r.hourly.is_day[$j]),
                        hex:  hex($r.hourly.weather_code[$j]; $r.hourly.is_day[$j]) } ] } ] }' > "${json_file}.tmp" 2>/dev/null; then
        mv "${json_file}.tmp" "${json_file}"
    else
        rm -f "${json_file}.tmp"
        [ -f "$json_file" ] || write_dummy_data
    fi
}

# --- MODE HANDLING ---
if [[ "$1" == "--getdata" ]]; then
    get_data

elif [[ "$1" == "--json" ]]; then
    CACHE_LIMIT=900         # 15 minutes for valid working data
    PENDING_RETRY_LIMIT=3600 # 1 hour for invalid/activating keys

    if [ -f "$json_file" ]; then
        file_time=$(stat -c %Y "$json_file")
        current_time=$(date +%s)
        diff=$((current_time - file_time))
        
        if grep -q '"desc": "Offline"' "$json_file"; then
            # Key is pending/invalid. Check once an hour.
            if [ $diff -gt $PENDING_RETRY_LIMIT ]; then
                touch "$json_file" # Bump file timestamp slightly to avoid spamming processes
                get_data &
            fi
        else
            # Normal working API key. Check every 15 mins.
            if [ $diff -gt $CACHE_LIMIT ]; then
                touch "$json_file"
                get_data &
            fi
        fi
        cat "$json_file"
    else
        get_data
        cat "$json_file"
    fi

elif [[ "$1" == "--view-listener" ]]; then
    if [ ! -f "$view_file" ]; then echo "0" > "$view_file"; fi
    tail -F "$view_file"

elif [[ "$1" == "--nav" ]]; then
    if [ ! -f "$view_file" ]; then echo "0" > "$view_file"; fi
    current=$(cat "$view_file")
    direction=$2
    max_idx=4
    if [[ "$direction" == "next" ]]; then
        if [ "$current" -lt "$max_idx" ]; then
            new=$((current + 1))
            echo "$new" > "$view_file"
        fi
    elif [[ "$direction" == "prev" ]]; then
        if [ "$current" -gt 0 ]; then
            new=$((current - 1))
            echo "$new" > "$view_file"
        fi
    fi

elif [[ "$1" == "--icon" ]]; then
    cat "$json_file" | jq -r '.forecast[0].icon'

elif [[ "$1" == "--temp" ]]; then 
    t=$(cat "$json_file" | jq -r '.forecast[0].max')
    echo "${t}${UNIT_SYM}"

elif [[ "$1" == "--hex" ]]; then 
    cat "$json_file" | jq -r '.forecast[0].hex'

elif [[ "$1" == "--current-icon" ]]; then
    # A missing cache is the normal first read after the location changes --
    # the panel wipes the cache so the old city cannot linger -- so the probe
    # stays quiet and get_data below is what actually reports trouble.
    icon=$(cat "$json_file" 2>/dev/null | jq -r '.current_icon // empty')
    if [[ -z "$icon" || "$icon" == "null" ]]; then 
        get_data
        icon=$(cat "$json_file" | jq -r '.current_icon')
    fi
    echo "$icon"

elif [[ "$1" == "--current-temp" ]]; then 
    t=$(cat "$json_file" 2>/dev/null | jq -r '.current_temp // empty')
    if [[ -z "$t" || "$t" == "null" ]]; then 
        get_data
        t=$(cat "$json_file" | jq -r '.current_temp')
    fi
    echo "${t}${UNIT_SYM}"

elif [[ "$1" == "--current-hex" ]]; then
    hex=$(cat "$json_file" 2>/dev/null | jq -r '.current_hex // empty')
    if [[ -z "$hex" || "$hex" == "null" ]]; then 
        get_data
        hex=$(cat "$json_file" | jq -r '.current_hex')
    fi
    echo "$hex"
fi
