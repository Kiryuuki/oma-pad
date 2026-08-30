#!/usr/bin/env python3
"""
Descriptor-Safe Bounded State Reader for OmaPad.
Validates file descriptor properties (regular file, ownership, no-follow symlink,
non-blocking FIFO protection) and enforces strict byte ceilings before materialization.
"""

import os
import stat
import sys
from pathlib import Path

MAX_STATE_BYTES = 512 * 1024  # 512 KB ceiling
STATE_PATH = Path.home() / ".local" / "state" / "omarchy" / "launchpad-state.json"


def safe_read_state():
    if not STATE_PATH.exists():
        sys.stdout.write("{}\n")
        return

    try:
        # Open with O_RDONLY, O_NONBLOCK (prevents FIFO hangs), and O_NOFOLLOW (prevents symlink hijacking)
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
        fd = os.open(str(STATE_PATH), flags)
        with os.fdopen(fd, "rb") as stream:
            st = os.fstat(fd)
            # Ensure it is a regular file owned by the current user
            if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
                sys.stdout.write("{}\n")
                return
            # Check size ceiling
            if st.st_size > MAX_STATE_BYTES:
                print(f"Error: State file size {st.st_size} exceeds {MAX_STATE_BYTES} ceiling", file=sys.stderr)
                sys.stdout.write("{}\n")
                return
            content = stream.read(MAX_STATE_BYTES + 1)
            if len(content) > MAX_STATE_BYTES:
                sys.stdout.write("{}\n")
                return
            sys.stdout.buffer.write(content)
    except Exception as e:
        print(f"Safe state read error: {e}", file=sys.stderr)
        sys.stdout.write("{}\n")


if __name__ == "__main__":
    safe_read_state()
