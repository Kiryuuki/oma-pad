#!/usr/bin/env python3
"""
OmaPad Engine for Omarchy Desktop.
Polls live Hyprland workspaces/windows, indexes installed applications,
manages pinned rules, and writes state atomically to ~/.local/state/omarchy/launchpad-state.json.
"""

import argparse
import configparser
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

CONFIG_PATH = Path.home() / ".config" / "omarchy" / "launchpad.json"
STATE_PATH = Path.home() / ".local" / "state" / "omarchy" / "launchpad-state.json"
GENERATOR_PATH = Path(__file__).parent / "generate.py"
APPLY_NOW_PATH = Path(__file__).parent / "apply_now.py"


def load_config():
    if not CONFIG_PATH.exists():
        return {"version": 1, "entries": []}
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
            if not isinstance(data.get("entries"), list):
                data["entries"] = []
            return data
    except Exception:
        return {"version": 1, "entries": []}


def write_config(cfg):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    handle, temp_name = tempfile.mkstemp(dir=str(CONFIG_PATH.parent), suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(cfg, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, CONFIG_PATH)
    except BaseException:
        Path(temp_name).unlink(missing_ok=True)
        raise


def write_state(data):
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    handle, temp_name = tempfile.mkstemp(dir=str(STATE_PATH.parent), suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, STATE_PATH)
    except BaseException:
        Path(temp_name).unlink(missing_ok=True)
        raise


def get_live_hyprland_state(pinned_entries):
    pinned_map = {}
    for e in pinned_entries:
        m = str(e.get("match", "")).strip().lower()
        if m:
            pinned_map[m] = e

    clients = []
    try:
        p = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=3)
        if p.returncode == 0:
            clients = json.loads(p.stdout)
    except Exception:
        pass

    workspaces_data = []
    occupied_ws = set()

    for c in clients:
        ws_info = c.get("workspace", {})
        ws_id = ws_info.get("id", 1)
        if ws_id > 0:
            occupied_ws.add(ws_id)

    max_ws = max(max(occupied_ws, default=1), 5)

    for w_id in range(1, max_ws + 1):
        ws_windows = []
        for c in clients:
            c_ws = c.get("workspace", {}).get("id", 1)
            if c_ws == w_id:
                cls = c.get("class", "").strip()
                title = c.get("title", "").strip()
                pid = c.get("pid", 0)

                is_pinned = False
                matched_rule = None
                cls_lower = cls.lower()
                for p_match, p_rule in pinned_map.items():
                    if p_match in cls_lower or cls_lower in p_match:
                        is_pinned = True
                        matched_rule = p_rule
                        break

                ws_windows.append({
                    "class": cls,
                    "title": title,
                    "pid": pid,
                    "isPinned": is_pinned,
                    "pinnedRule": matched_rule,
                    "workspace": w_id
                })

        workspaces_data.append({
            "id": w_id,
            "windows": ws_windows,
            "windowCount": len(ws_windows),
            "isOccupied": len(ws_windows) > 0
        })

    return workspaces_data, clients


def get_installed_apps():
    home = os.environ.get("HOME", os.path.expanduser("~"))
    dirs = [
        "/usr/share/applications",
        os.path.join(home, ".local", "share", "applications"),
    ]
    seen = {}

    for directory in dirs:
        if not os.path.isdir(directory):
            continue
        try:
            entries = os.listdir(directory)
        except OSError:
            continue

        for entry in entries:
            if not entry.endswith(".desktop"):
                continue
            path = os.path.join(directory, entry)
            cp = configparser.ConfigParser(interpolation=None)
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    cp.read_file(fh)
            except Exception:
                continue

            sec = None
            for s in ["Desktop Entry", "Desktop Action"]:
                if s in cp:
                    sec = cp[s]
                    break
            if sec is None and cp.sections():
                sec = cp[cp.sections()[0]]
            if sec is None:
                continue

            name = sec.get("Name", "").strip()
            no_display = sec.get("NoDisplay", "false").strip().lower()
            if not name or no_display == "true":
                continue

            exec_val = sec.get("Exec", "").strip()
            if "%" in exec_val:
                exec_val = exec_val.split("%")[0].strip()

            base_id = entry[:-8]
            wm_class = sec.get("StartupWMClass", "").strip()
            match_class = wm_class or base_id
            icon = sec.get("Icon", "").strip()

            key = name.lower()
            if key not in seen:
                seen[key] = {
                    "id": base_id,
                    "name": name,
                    "match": match_class,
                    "command": exec_val or base_id,
                    "icon": icon,
                }

    return sorted(seen.values(), key=lambda x: x["name"].lower())


def reload_hyprland_rules():
    try:
        subprocess.run(["/usr/bin/python3", str(GENERATOR_PATH)], capture_output=True, timeout=5)
    except Exception as e:
        print(f"Error regenerating rules: {e}", file=sys.stderr)


def sync():
    cfg = load_config()
    entries = cfg.get("entries", [])
    workspaces, clients = get_live_hyprland_state(entries)
    apps = get_installed_apps()

    state = {
        "version": 1,
        "entries": entries,
        "workspaces": workspaces,
        "installedApps": apps,
        "totalPinned": len(entries),
        "totalRunningWindows": len(clients),
    }

    write_state(state)
    print(f"OmaPad synced: {len(workspaces)} workspaces, {len(entries)} pinned rules, {len(apps)} installed apps")


def main():
    parser = argparse.ArgumentParser(description="OmaPad Engine")
    parser.add_argument("--sync", action="store_true", help="Sync full state")
    parser.add_argument("--pin-current-windows", action="store_true", help="Pin all currently open windows to their current workspaces")
    parser.add_argument("--pin-window", action="store_true", help="Pin a specific window to a workspace")
    parser.add_argument("--class-name", default="", help="Window class name")
    parser.add_argument("--app-title", default="", help="App title")
    parser.add_argument("--workspace", type=int, default=1, help="Workspace number")
    parser.add_argument("--command", default="", help="Launch command")
    parser.add_argument("--launch-at-boot", action="store_true", help="Auto launch at boot")
    parser.add_argument("--silent", action="store_true", help="Silent pinning")
    parser.add_argument("--toggle-boot", default="", help="Toggle launchAtBoot for a rule by match or id")
    parser.add_argument("--set-workspace", default="", help="Update workspace for a rule by match or id")
    parser.add_argument("--delete-rule", default="", help="Delete rule by match or id")
    parser.add_argument("--apply-now", action="store_true", help="Reposition open windows")

    args = parser.parse_args()

    if args.pin_current_windows:
        cfg = load_config()
        entries = cfg.get("entries", [])
        _, clients = get_live_hyprland_state(entries)
        existing_matches = {e.get("match") for e in entries}

        for c in clients:
            cls = c.get("class", "").strip()
            ws = c.get("workspace", {}).get("id", 1)
            title = c.get("title", "").strip()
            if not cls or cls in existing_matches:
                continue
            entries.append({
                "id": cls,
                "match": cls,
                "command": cls.lower(),
                "workspace": ws,
                "launchAtBoot": False,
                "silent": False
            })
            existing_matches.add(cls)

        cfg["entries"] = entries
        write_config(cfg)
        reload_hyprland_rules()
        sync()
    elif args.toggle_boot:
        target = args.toggle_boot.strip()
        cfg = load_config()
        entries = cfg.get("entries", [])
        for e in entries:
            if e.get("match") == target or e.get("id") == target:
                e["launchAtBoot"] = not bool(e.get("launchAtBoot", False))
                break
        cfg["entries"] = entries
        write_config(cfg)
        reload_hyprland_rules()
        sync()
    elif args.set_workspace:
        target = args.set_workspace.strip()
        cfg = load_config()
        entries = cfg.get("entries", [])
        for e in entries:
            if e.get("match") == target or e.get("id") == target:
                e["workspace"] = args.workspace
                break
        cfg["entries"] = entries
        write_config(cfg)
        reload_hyprland_rules()
        sync()
    elif args.pin_window or (args.class_name.strip() and not args.delete_rule):
        cfg = load_config()
        entries = cfg.get("entries", [])
        match_str = args.class_name.strip()
        app_name = args.app_title.strip() or match_str
        cmd_str = args.command.strip() or match_str

        entries = [e for e in entries if e.get("match") != match_str]
        entries.append({
            "id": app_name,
            "match": match_str,
            "command": cmd_str,
            "workspace": args.workspace,
            "launchAtBoot": args.launch_at_boot,
            "silent": args.silent
        })
        cfg["entries"] = entries
        write_config(cfg)
        reload_hyprland_rules()
        sync()
    elif args.delete_rule:
        target = args.delete_rule.strip()
        cfg = load_config()
        entries = [e for e in cfg.get("entries", []) if e.get("match") != target and e.get("id") != target]
        cfg["entries"] = entries
        write_config(cfg)
        reload_hyprland_rules()
        sync()
    elif args.apply_now:
        try:
            subprocess.run(["/usr/bin/python3", str(APPLY_NOW_PATH)], capture_output=True, timeout=5)
        except Exception:
            pass
        sync()
    else:
        sync()


if __name__ == "__main__":
    main()
