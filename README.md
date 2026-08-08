# imperative-dots — fork

A fork of [ilyamiro/nixos-configuration](https://github.com/ilyamiro/nixos-configuration):
a Hyprland desktop whose entire shell — bar, launcher, notifications, lock
screen, wallpaper picker, settings — is one [quickshell](https://quickshell.org)
configuration, themed from the wallpaper by [matugen](https://github.com/InioX/matugen).

This checkout is **not** installed the way upstream installs. It is linked into
`$HOME` from [my dotfiles](https://github.com/alihancaliskanx/dotfiles) as one
of two selectable desktops, so switching between this and my own waybar setup is
a single command and nothing is copied anywhere.

```bash
cd ~/Documents/Code/dotfiles
./link.sh                      # menu: 1) Own Dotfiles  2) imperative-dots
./link.sh rice imperative-dots # or straight to the point
./link.sh rice own             # and back
```

## Two upstreams, and which one this is

Upstream keeps the same desktop in two repos:

| repo | for | layout |
|---|---|---|
| `ilyamiro/nixos-configuration` | NixOS | `config/programs/*`, `config/sessions/*`, thin `.nix` files |
| `ilyamiro/imperative-dots` | Arch | flat `$HOME` overlay + a 1900-line `install.sh` |

**This fork is of the NixOS one**, despite the name — and for linking that is
the better half. Its `.nix` files do nothing but
`mkOutOfStoreSymlink`, i.e. exactly what a symlinker does, so the content under
`config/` is plain, dist-agnostic config. The Arch repo instead *copies* into
`~/.config`, `sed`s the copies afterwards, and runs a `settings_watcher.sh` that
rewrites its own `config/*.conf` at runtime — none of which survives being
managed as a git checkout.

The `.nix` files are dead weight here and are skipped by the linker.

## `.linkmap`

The one file this fork adds. Upstream's directories are named for home-manager
(`config/sessions/hyprland`), not for `$HOME` (`.config/hypr`), so the mapping
that used to live in the `default.nix` files is written out plainly:

```
config/sessions/hyprland     .config/hypr
config/programs/matugen      .config/matugen
config/programs/cava         .config/cava
config/programs/kitty        .config/kitty
config/programs/rofi         .config/rofi
```

Files only, directory by directory — anything of my own that ends up in those
directories and is not in this repo stays put. What is deliberately left out
(neovim, zsh, plymouth, fonts) and why is commented in the file itself.

## What it needs installed

`quickshell` and `matugen` are in Arch `extra`; the rest is mostly repos too:

```bash
sudo pacman -S quickshell matugen swww rofi cava cliphist jq socat pamixer \
  brightnessctl acpi iw bluez-utils libnotify lm_sensors bc imagemagick \
  wl-clipboard fd ripgrep grim slurp satty playerctl go-yq mpvpaper \
  pavucontrol qt6-multimedia qt6-5compat qt6-websockets qt6-webengine
yay -S gpu-screen-recorder wl-screenrec networkmanager-dmenu
```

Upstream's `install.sh` (in the *other* repo) is not used and should not be:
besides copying over configs, it edits `/etc/pacman.conf`, removes your display
manager with `pacman -Rns`, runs `chsh`, writes `/etc/sddm.conf.d/`, and ships
no uninstall path.

## Hyprland only

`hyprctl` is called from 15 files — monitor layout, keyboard layout, workspaces,
submaps, app launching. Under niri the bar comes up (quickshell talks
layer-shell, not Hyprland) but those paths are dead. Upstream's announced v2.0.0
is meant to make the shell compositor-agnostic and add niri; until then this
desktop is for the Hyprland profile.

## Keeping up with upstream

```bash
git remote -v
# origin    git@github.com:alihancaliskanx/imperative-dots.git
# upstream  https://github.com/ilyamiro/nixos-configuration.git

git fetch upstream && git merge upstream/main   # or whatever the branch is
```

Local changes belong in normal commits on this fork — that is the whole reason
it is a fork and not a submodule or a vendored copy. Note that upstream
restructures directories wholesale from time to time; when a merge moves things,
`.linkmap` is the one file to re-check, and `./link.sh rice imperative-dots`
relinks from scratch.

## Credit

All of the desktop is [ilyamiro](https://github.com/ilyamiro)'s work — the
quickshell configuration, the matugen templates, the Hyprland config. This fork
adds `.linkmap` and this README, nothing else.
