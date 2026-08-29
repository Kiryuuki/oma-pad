#!/usr/bin/env python3
"""Emit the user's launchpad.json entries as a JSON array on stdout.

Used by the Launchpad bar widget to render its menu. Reads only
~/.config/omarchy/launchpad.json (user data). Prints "[]" if absent or invalid
so the widget safely shows an empty state.
"""
import json
import os
import sys

HOME = os.environ.get("HOME", os.path.expanduser("~"))
CONFIG = os.path.join(HOME, ".config", "omarchy", "launchpad.json")

try:
    with open(CONFIG, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    entries = data.get("entries", []) if isinstance(data, dict) else []
except (OSError, json.JSONDecodeError):
    entries = []

print(json.dumps(entries))
