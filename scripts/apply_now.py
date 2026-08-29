#!/usr/bin/env python3
"""
Apply OmaPad workspace rules to all currently running windows in Hyprland.
Uses Hyprland address dispatching with specific-rule priority so terminal apps
(like btop) are not hijacked by generic terminal rules (like Ghostty).
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

CONFIG_PATH = Path.home() / ".config" / "omarchy" / "launchpad.json"
GENERIC_TERMINALS = {"com.mitchellh.ghostty", "kitty", "foot", "alacritty", "ghostty"}


def get_hyprland_clients():
    try:
        p = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=5)
        if p.returncode == 0:
            return json.loads(p.stdout)
    except Exception:
        pass
    return []


def match_window(win, pattern: str) -> bool:
    cls = (win.get("class") or "").lower()
    title = (win.get("title") or "").lower()
    pat = pattern.lower().strip()
    return pat in cls or pat in title or bool(re.search(re.escape(pat), cls, re.IGNORECASE)) or bool(re.search(re.escape(pat), title, re.IGNORECASE))


def move_window_to_workspace(address: str, workspace_id: int, silent: bool = True):
    follow_val = "false" if silent else "true"
    lua_cmd = f'hl.dispatch(hl.dsp.focus({{ window = "address:{address}" }})); hl.dispatch(hl.dsp.window.move({{ workspace = "{workspace_id}", follow = {follow_val} }}))'
    try:
        subprocess.run(["hyprctl", "eval", lua_cmd], capture_output=True, text=True, timeout=3)
    except Exception as e:
        print(f"Error moving window {address}: {e}", file=sys.stderr)


def main():
    if not CONFIG_PATH.exists():
        return 0

    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception:
        return 1

    entries = cfg.get("entries", [])
    if not isinstance(entries, list):
        return 0

    clients = get_hyprland_clients()
    moved = 0
    skipped = 0
    claimed_addresses = set()

    # Sort entries: Specific rules (title/app match) first, generic terminal rules last!
    specific_entries = []
    generic_entries = []

    for e in entries:
        m = str(e.get("match", "")).strip()
        if m.lower() in GENERIC_TERMINALS:
            generic_entries.append(e)
        else:
            specific_entries.append(e)

    sorted_entries = specific_entries + generic_entries

    for e in sorted_entries:
        ws = e.get("workspace")
        match = str(e.get("match", "")).strip()
        if not ws or not match:
            continue
        try:
            ws_int = int(ws)
        except (ValueError, TypeError):
            continue

        silent = bool(e.get("silent", True))

        for c in clients:
            addr = c.get("address")
            if addr in claimed_addresses:
                continue

            if match_window(c, match):
                claimed_addresses.add(addr)
                c_ws = c.get("workspace", {}).get("id")
                if c_ws != ws_int and addr:
                    move_window_to_workspace(addr, ws_int, silent=silent)
                    moved += 1
                else:
                    skipped += 1

    print(json.dumps({"moved": moved, "skipped": skipped}))
    return 0


if __name__ == "__main__":
    main()
