#!/usr/bin/env python3
"""Apply the user's launchpad.json workspace rules to currently running windows.

For each entry that has a `workspace`, attempt to focus a running window whose
class or title matches `match` and move it to the assigned workspace. Because
Hyprland's Lua API only moves the *focused* window, we use `omarchy launch or
focus` to bring the target to front first.

Returns a JSON object on stdout:
  {"moved": N, "skipped": N, "failed": N}

- moved: windows successfully relocated.
- skipped: already on the correct workspace.
- failed: no matching window found, or move failed after focus.
"""
import json
import os
import re
import subprocess
import sys


def _hyprctl_json(cmd: str):
    p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
    if p.returncode != 0:
        return []
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:
        return []


def _match_window(window, pattern: str) -> bool:
    cls = (window.get("class") or "").lower()
    title = (window.get("title") or "").lower()
    try:
        return bool(re.search(pattern, cls, re.IGNORECASE)) or bool(
            re.search(pattern, title, re.IGNORECASE)
        )
    except re.error:
        return pattern.lower() in cls or pattern.lower() in title


def _focus_window(command: str) -> bool:
    """Focus a window by launching or focusing the app via omarchy."""
    if not command:
        return False
    p = subprocess.run(
        ["omarchy", "launch", "or", "focus", command],
        capture_output=True,
        text=True,
        timeout=8,
    )
    return p.returncode == 0


def _move_active(workspace: int) -> bool:
    cmd = (
        'eval \'return hl.dsp.window.move({workspace='
        + str(workspace)
        + '})\''
    )
    p = subprocess.run(["hyprctl"] + cmd.split(), capture_output=True, text=True, timeout=5)
    return p.returncode == 0 and "error" not in p.stdout.lower()


def main() -> int:
    home = os.environ.get("HOME", os.path.expanduser("~"))
    config_path = os.path.join(home, ".config", "omarchy", "launchpad.json")

    try:
        with open(config_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        entries = data.get("entries", []) if isinstance(data, dict) else []
    except (OSError, json.JSONDecodeError):
        entries = []

    windows = _hyprctl_json("hyprctl clients -j")
    moved = 0
    skipped = 0
    failed = 0

    for entry in entries:
        if not isinstance(entry, dict):
            continue
        ws = entry.get("workspace")
        match = str(entry.get("match", "")).strip()
        cmd = str(entry.get("command", "")).strip()
        if not ws or not match or not cmd:
            continue
        try:
            ws_int = int(ws)
        except (TypeError, ValueError):
            continue

        # find a matching running window
        target = None
        for w in windows:
            if _match_window(w, match):
                target = w
                break

        if target is None:
            failed += 1
            continue

        current_ws = target.get("workspace", {}).get("id")
        if current_ws == ws_int:
            skipped += 1
            continue

        # focus then move
        if _focus_window(cmd):
            import time
            time.sleep(0.3)
            if _move_active(ws_int):
                moved += 1
            else:
                failed += 1
        else:
            failed += 1

    print(json.dumps({"moved": moved, "skipped": skipped, "failed": failed}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
