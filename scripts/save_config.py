#!/usr/bin/env python3
"""
Save and modify OmaPad rules in ~/.config/omarchy/launchpad.json.
Supports both individual rule operations (--add, --delete, --toggle-boot)
and full JSON file writes.
"""

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path

CONFIG_PATH = Path.home() / ".config" / "omarchy" / "launchpad.json"


def load_config():
    if not CONFIG_PATH.exists():
        return {"version": 1, "entries": []}
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"version": 1, "entries": []}


def write_config(data):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    handle, temp_name = tempfile.mkstemp(dir=str(CONFIG_PATH.parent), suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, CONFIG_PATH)
    except BaseException:
        Path(temp_name).unlink(missing_ok=True)
        raise


def main():
    parser = argparse.ArgumentParser(description="OmaPad Config Manager")
    parser.add_argument("--id", default="", help="App Display Name")
    parser.add_argument("--match", default="", help="Window Class Match")
    parser.add_argument("--command", default="", help="Launch Command")
    parser.add_argument("--workspace", type=int, default=1, help="Workspace Number")
    parser.add_argument("--launch-at-boot", action="store_true", help="Launch at boot")
    parser.add_argument("--silent", action="store_true", help="Silent pinning")
    parser.add_argument("--delete", default="", help="Delete entry matching id or match")
    parser.add_argument("--path", help="Read payload from JSON file")

    args = parser.parse_args()

    cfg = load_config()
    entries = cfg.get("entries", [])
    if not isinstance(entries, list):
        entries = []

    if args.path:
        with open(args.path, "r", encoding="utf-8") as f:
            payload = json.load(f)
            cfg = payload if isinstance(payload, dict) else {"version": 1, "entries": payload}
            write_config(cfg)
            print(f"Loaded config from {args.path}")
            return

    if args.delete:
        del_target = args.delete.strip()
        entries = [e for e in entries if e.get("match") != del_target and e.get("id") != del_target]
        cfg["entries"] = entries
        write_config(cfg)
        print(f"Deleted rule: {del_target}")
        return

    if args.match.strip() or args.id.strip():
        match_str = args.match.strip() or args.id.strip()
        app_id = args.id.strip() or match_str
        cmd_str = args.command.strip() or match_str

        # Remove existing entry with same match if present
        entries = [e for e in entries if e.get("match") != match_str]

        new_entry = {
            "id": app_id,
            "match": match_str,
            "command": cmd_str,
            "workspace": args.workspace,
            "launchAtBoot": args.launch_at_boot,
            "silent": args.silent,
        }
        entries.append(new_entry)
        cfg["entries"] = entries
        write_config(cfg)
        print(f"Saved rule for {app_id} -> Workspace {args.workspace}")


if __name__ == "__main__":
    main()
