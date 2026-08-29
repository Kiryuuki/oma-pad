#!/usr/bin/env python3
import os
import subprocess
import sys
import time
from pathlib import Path

APPLY_NOW_PATH = Path(__file__).parent / "apply_now.py"


def launch(cmd_or_id, target_ws=None):
    if not cmd_or_id:
        return

    cmd = cmd_or_id.strip()

    # Check if a .desktop file exists with this name or base id
    dirs = [
        Path("/usr/share/applications"),
        Path.home() / ".local" / "share" / "applications",
    ]
    is_desktop = False
    desktop_name = cmd
    for d in dirs:
        if (d / f"{cmd}.desktop").exists():
            is_desktop = True
            desktop_name = cmd
            break
        elif (d / f"{cmd.lower()}.desktop").exists():
            is_desktop = True
            desktop_name = cmd.lower()
            break

    try:
        if is_desktop:
            subprocess.Popen(["gtk-launch", desktop_name], start_new_session=True)
        else:
            subprocess.Popen(cmd, shell=True, start_new_session=True)
    except Exception as e:
        print(f"Error launching {cmd}: {e}", file=sys.stderr)

    if target_ws:
        time.sleep(1.0)
        try:
            subprocess.run(["/usr/bin/python3", str(APPLY_NOW_PATH)], capture_output=True, timeout=5)
        except Exception:
            pass


if __name__ == "__main__":
    if len(sys.argv) > 1:
        target = sys.argv[2] if len(sys.argv) > 2 else None
        launch(sys.argv[1], target)
