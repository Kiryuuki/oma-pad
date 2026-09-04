#!/usr/bin/env python3
"""
OmaPad Launch Helper -- safely launches desktop applications.

All launches route through gtk-launch for .desktop entries to avoid
executing raw Exec= values via shell splitting.  Non-desktop commands
are validated for safe characters before argv-based Popen (never shell=True).
"""

import os
import re
import subprocess
import sys
import time
from pathlib import Path

APPLY_NOW_PATH = Path(__file__).parent / "apply_now.py"

# Only allow plain command tokens: alphanumeric, hyphens, underscores,
# dots, forward slashes, tildes and equals.  No shell metacharacters.
_SAFE_CMD_RE = re.compile(r'^[a-zA-Z0-9_./@:~=,+ -]+$')


def _find_desktop_entry(name):
    """Case-insensitive search for a matching .desktop file.
    Returns the stem (without .desktop) if found, or None."""
    dirs = [
        Path("/usr/share/applications"),
        Path.home() / ".local" / "share" / "applications",
    ]
    name_lower = name.lower()
    for d in dirs:
        if not d.exists():
            continue
        for f in d.glob("*.desktop"):
            if f.stem.lower() == name_lower:
                return f.stem
    return None


def launch(cmd_or_id, target_ws=None):
    if not cmd_or_id:
        return

    cmd = cmd_or_id.strip()

    # Always prefer gtk-launch for desktop entries.  This delegates
    # Exec= parsing entirely to the freedesktop launcher, avoiding
    # any direct execution of arbitrary Exec= strings.
    desktop_stem = _find_desktop_entry(cmd)
    if desktop_stem:
        try:
            subprocess.Popen(
                ["gtk-launch", desktop_stem],
                start_new_session=True
            )
        except Exception as e:
            print(f"Error gtk-launching {desktop_stem}: {e}", file=sys.stderr)
    else:
        # Non-desktop command: reject anything with shell metacharacters
        if not _SAFE_CMD_RE.match(cmd):
            print(
                f"Refusing to launch command with unsafe characters: {cmd!r}",
                file=sys.stderr,
            )
            return

        # Split into argv on whitespace only (no shell interpretation)
        args = cmd.split()
        if not args:
            return

        # Verify the binary exists on disk or in PATH
        binary = args[0]
        if not os.path.isabs(binary):
            from shutil import which
            resolved = which(binary)
            if not resolved:
                print(f"Binary not found in PATH: {binary}", file=sys.stderr)
                return
            args[0] = resolved

        try:
            subprocess.Popen(args, start_new_session=True)
        except Exception as e:
            print(f"Error launching {args}: {e}", file=sys.stderr)

    if target_ws:
        time.sleep(1.2)
        try:
            subprocess.run(
                ["/usr/bin/python3", str(APPLY_NOW_PATH)],
                capture_output=True, timeout=5
            )
        except Exception:
            pass


if __name__ == "__main__":
    if len(sys.argv) > 1:
        target = sys.argv[2] if len(sys.argv) > 2 else None
        launch(sys.argv[1], target)
