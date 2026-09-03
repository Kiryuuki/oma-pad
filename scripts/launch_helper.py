#!/usr/bin/env python3
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path

APPLY_NOW_PATH = Path(__file__).parent / "apply_now.py"


def launch(cmd_or_id, target_ws=None):
    if not cmd_or_id:
        return

    cmd = cmd_or_id.strip()

    dirs = [
        Path("/usr/share/applications"),
        Path.home() / ".local" / "share" / "applications",
    ]
    is_desktop = False
    desktop_name = cmd

    # Case-insensitive desktop search
    for d in dirs:
        if not d.exists():
            continue
        for f in d.glob("*.desktop"):
            if f.stem.lower() == cmd.lower():
                is_desktop = True
                desktop_name = f.stem
                break
        if is_desktop:
            break

    try:
        if is_desktop:
            subprocess.Popen(["gtk-launch", desktop_name], start_new_session=True)
        else:
            args = shlex.split(cmd)
            if args:
                subprocess.Popen(args, start_new_session=True)
    except Exception as e:
        print(f"Error launching {cmd}: {e}", file=sys.stderr)

    if target_ws:
        time.sleep(1.2)
        try:
            subprocess.run(["/usr/bin/python3", str(APPLY_NOW_PATH)], capture_output=True, timeout=5)
        except Exception:
            pass


if __name__ == "__main__":
    if len(sys.argv) > 1:
        target = sys.argv[2] if len(sys.argv) > 2 else None
        launch(sys.argv[1], target)
