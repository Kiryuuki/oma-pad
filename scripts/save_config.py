#!/usr/bin/env python3
"""Write the user's launchpad.json config from a JSON payload passed via
an environment variable or an explicit path.

Usage (called from QML Panel):
  LAUNCHPAD_PAYLOAD='{"entries":[...]}' python3 save_config.py

Or explicit path:
  python3 save_config.py --path /tmp/launchpad_payload.json

The payload must be a JSON object with an "entries" array. Each entry
has the shape:
  {
    "match": "zen-browser",
    "command": "zen-browser",
    "workspace": 1,
    "launchAtBoot": true
  }

Fields "workspace" and "launchAtBoot" are optional.
"""
import argparse
import json
import os
import sys
import tempfile


def main() -> int:
    home = os.environ.get("HOME", os.path.expanduser("~"))
    config_path = os.path.join(home, ".config", "omarchy", "launchpad.json")

    parser = argparse.ArgumentParser()
    parser.add_argument("--path", help="read payload from this file instead of env")
    args = parser.parse_args()

    if args.path:
        with open(args.path, "r", encoding="utf-8") as fh:
            payload = json.load(fh)
    else:
        raw = os.environ.get("LAUNCHPAD_PAYLOAD", "")
        if not raw:
            print("save_config.py: LAUNCHPAD_PAYLOAD is empty", file=sys.stderr)
            return 1
        payload = json.loads(raw)

    entries = payload.get("entries", []) if isinstance(payload, dict) else []
    # Sanitize: ensure each entry has at least "match" and "command".
    clean = []
    for e in entries:
        if not isinstance(e, dict):
            continue
        match = str(e.get("match", "")).strip()
        cmd = str(e.get("command", "")).strip()
        if not match or not cmd:
            continue
        entry = {"match": match, "command": cmd}
        if "workspace" in e and e["workspace"] is not None:
            try:
                entry["workspace"] = int(e["workspace"])
            except (TypeError, ValueError):
                pass
        if "launchAtBoot" in e:
            entry["launchAtBoot"] = bool(e["launchAtBoot"])
        if "silent" in e:
            entry["silent"] = bool(e["silent"])
        clean.append(entry)

    payload_out = {"entries": clean}

    # Atomic write: write to a temp file in the same directory, then rename.
    directory = os.path.dirname(config_path)
    os.makedirs(directory, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=directory, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload_out, fh, indent=2)
            fh.write("\n")
        os.replace(tmp_path, config_path)
    except BaseException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

    print(f"wrote {len(clean)} entries to {config_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
