# net-env.sh — put net-auto's proxy verdict into this script's environment.
#
# Source (do not execute) this from anything here that reaches the network.
#
# quickshell is started by the compositor, not by a login shell, so none of the
# proxy variables the shells export are present in these scripts. On a network
# where the phone proxy is the only way out, curl and urllib then try to go
# direct and fail — which is what makes the weather read 0.0°C and the wallpaper
# search come back empty, with no error anywhere.
#
# net-auto (in the dotfiles repo) is what decides and writes the verdict down;
# this only reads it, so there is no probing and no timeout on the way to a
# weather refresh. With no state file, or with the verdict "off", nothing is
# exported and everything goes direct.

_ne_state="${XDG_CACHE_HOME:-$HOME/.cache}/net-auto/state"
if [ -r "$_ne_state" ] && [ "$(cat "$_ne_state" 2>/dev/null)" = "on" ]; then
    _ne_url="http://${PROXY_ADDR:-192.168.49.1:8000}"
    export http_proxy="$_ne_url" https_proxy="$_ne_url"
    export HTTP_PROXY="$_ne_url" HTTPS_PROXY="$_ne_url"
    export no_proxy="localhost,127.0.0.1,::1,.local"
    export NO_PROXY="$no_proxy"
    unset _ne_url
fi
unset _ne_state
