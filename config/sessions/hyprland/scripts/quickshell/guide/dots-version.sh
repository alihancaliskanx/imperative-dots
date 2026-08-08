#!/usr/bin/env bash

# dots-version.sh — where this install stands, answered from the git checkout.
#
# The panel used to read its version out of ~/.local/state/imperative-dots-version
# and compare it against DOTS_VERSION in the upstream install.sh. Neither applies
# to a fork that is linked from a checkout: the state file is written by that
# installer and was never run here, so the chip read "vUnknown", while the remote
# number always differed and kept an "Update Available" banner lit. Clicking it
# piped the upstream installer into a shell, which would have written a stranger's
# configs over this machine's.
#
# The checkout is the truth for all three questions, so ask git.
#
#   local   short revision of the checkout, "-dirty" when edited
#   behind  commits the checkout is behind its own origin (0 if unknown)
#   pull    fast-forward the checkout, then say what still needs doing

set -o pipefail

# hyprland.conf is linked from the rice, so following it lands inside the
# checkout wherever the user keeps it -- no path baked in here.
repo_root() {
    local target
    target=$(readlink -f "$HOME/.config/hypr/hyprland.conf" 2>/dev/null) || return 1
    [ -n "$target" ] || return 1
    git -C "$(dirname "$target")" rev-parse --show-toplevel 2>/dev/null
}

root=$(repo_root)
[ -n "$root" ] || { case "$1" in behind) echo 0 ;; *) echo Unknown ;; esac; exit 0; }

case "${1:-local}" in
    local)
        git -C "$root" describe --tags --always --dirty 2>/dev/null || echo Unknown
        ;;
    behind)
        # Sourced for the proxy verdict: quickshell gets no login-shell
        # environment, so on the phone hotspot an unproxied fetch just hangs
        # until it times out and the count silently reads 0.
        source "$(dirname "${BASH_SOURCE[0]}")/../../net-env.sh"
        git -C "$root" fetch -q origin 2>/dev/null
        count=$(git -C "$root" rev-list --count HEAD..@{u} 2>/dev/null)
        echo "${count:-0}"
        ;;
    pull)
        printf 'Updating %s\n\n' "$root"
        git -C "$root" pull --ff-only || {
            printf '\nPull refused. The checkout has local commits or changes;\n'
            printf 'resolve them there and run this again.\n'
            exit 1
        }
        printf '\nPulled. Symlinks only need redoing if files were added or renamed:\n'
        printf '  ./link.sh rice imperative-dots   (from the dotfiles repo)\n'
        printf '\nThen Mod+R to reload the shell.\n'
        ;;
    *)
        echo "usage: dots-version.sh [local|behind|pull]" >&2
        exit 2
        ;;
esac
