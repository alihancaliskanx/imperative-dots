#!/usr/bin/env python3
"""sync-keybinds — put the real keybindings into settings.json.

The settings panel reads its shortcut list out of settings.json, not out of
keybindings.conf, so it shipped showing upstream's defaults: 67 entries that
had nothing to do with what the keys on this machine actually do. This reads
keybindings.conf and rewrites that list from it.

Run it after editing keybindings.conf:

    ~/.config/hypr/scripts/sync-keybinds.py

Note that the panel is a *view* here. Upstream applies edits made in it through
settings_watcher.sh, which regenerates the .conf files — that script is part of
the Arch repo and does not exist in this tree, so editing a shortcut in the
panel changes nothing. keybindings.conf is the source of truth; this script
only makes the panel tell the truth about it.
"""

import json
import os
import re
import sys

HOME = os.path.expanduser("~")
CONF = os.path.join(HOME, ".config/hypr/config/keybindings.conf")
SETTINGS = os.path.join(HOME, ".config/hypr/settings.json")

# bind / binde / bindl / bindel / bindm = MODS, KEY, DISPATCHER[, ARGS]
LINE = re.compile(r"^(bind[elm]*)\s*=\s*(.*)$")


def strip_comment(s: str) -> str:
    """Drop a trailing ` # comment`, but not a '#' inside quotes."""
    out, quote = [], None
    for i, c in enumerate(s):
        if quote:
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "#" and (i == 0 or s[i - 1].isspace()):
            break
        out.append(c)
    return "".join(out).rstrip()


def parse(path: str) -> list[dict]:
    binds = []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw or raw.startswith("#"):
                continue
            m = LINE.match(raw)
            if not m:
                continue
            kind, rest = m.group(1), strip_comment(m.group(2))

            # Only the first three commas separate fields; whatever follows is
            # the argument, which may itself contain commas.
            parts = [p.strip() for p in rest.split(",", 3)]
            if len(parts) < 3:
                continue
            mods, key, dispatcher = parts[0], parts[1], parts[2]
            command = parts[3].strip() if len(parts) > 3 else ""

            binds.append({
                "type": kind,
                "mods": mods,
                "key": key,
                "dispatcher": dispatcher,
                "command": command,
                "isEditing": False,
            })
    return binds


def main() -> int:
    if not os.path.exists(CONF):
        print(f"no keybindings.conf at {CONF}", file=sys.stderr)
        return 1

    binds = parse(CONF)
    if not binds:
        print("parsed no bindings — refusing to write an empty list", file=sys.stderr)
        return 1

    try:
        with open(SETTINGS, encoding="utf-8") as fh:
            settings = json.load(fh)
    except (OSError, json.JSONDecodeError):
        settings = {}

    was = len(settings.get("keybinds", []))
    settings["keybinds"] = binds

    # Written through a temp file: quickshell watches this path and a
    # half-written file is a parse error on the other side.
    tmp = SETTINGS + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(settings, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, SETTINGS)

    print(f"keybinds: {was} -> {len(binds)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
