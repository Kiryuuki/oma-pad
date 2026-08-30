#!/usr/bin/env python3
"""
OmaPad Engine for Omarchy Desktop.
Polls live Hyprland workspaces/windows, indexes installed applications,
manages pinned rules, and writes state atomically with bounded descriptor safety.
"""

import argparse
import configparser
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

CONFIG_PATH = Path.home() / ".config" / "omarchy" / "launchpad.json"
STATE_PATH = Path.home() / ".local" / "state" / "omarchy" / "launchpad-state.json"
GENERATOR_PATH = Path(__file__).parent / "generate.py"
APPLY_NOW_PATH = Path(__file__).parent / "apply_now.py"

MAX_SUBPROCESS_BYTES = 512 * 1024  # 512 KB ceiling
MAX_STATE_BYTES = 512 * 1024       # 512 KB ceiling


def run_bounded_subprocess(cmd, timeout=3):
    """Runs a subprocess with strict byte ceiling and timeout, failing closed on overflow."""
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=False
        )
        raw_out, _ = proc.communicate(timeout=timeout)
        if len(raw_out) > MAX_SUBPROCESS_BYTES:
            print(f"Error: Subprocess output exceeded {MAX_SUBPROCESS_BYTES} bytes limit", file=sys.stderr)
            return None
        return raw_out.decode("utf-8", errors="replace")
    except Exception as e:
        print(f"Subprocess error: {e}", file=sys.stderr)
        return None


def load_config():
    if not CONFIG_PATH.exists():
        return {"version": 1, "entries": []}
    try:
        st = CONFIG_PATH.stat()
        if st.st_uid != os.getuid() or not stat.S_ISREG(st.st_mode):
            return {"version": 1, "entries": []}
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
            if not isinstance(data.get("entries"), list):
                data["entries"] = []
            return data
    except Exception:
        return {"version": 1, "entries": []}


def write_config(cfg):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    raw_bytes = (json.dumps(cfg, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if len(raw_bytes) > MAX_STATE_BYTES:
        print(f"Error: Config size {len(raw_bytes)} exceeds ceiling {MAX_STATE_BYTES}", file=sys.stderr)
        return

    handle, temp_name = tempfile.mkstemp(dir=str(CONFIG_PATH.parent), suffix=".tmp")
    try:
        os.fchmod(handle, 0o600)
        with os.fdopen(handle, "wb") as stream:
            stream.write(raw_bytes)
            stream.flush()
            os.fsync(stream.fileno())
        if CONFIG_PATH.exists():
            st = CONFIG_PATH.lstat()
            if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
                CONFIG_PATH.unlink(missing_ok=True)
        os.replace(temp_name, CONFIG_PATH)
    except BaseException:
        Path(temp_name).unlink(missing_ok=True)
        raise


def write_state(data):
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    raw_bytes = (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if len(raw_bytes) > MAX_STATE_BYTES:
        print(f"Error: State size {len(raw_bytes)} exceeds ceiling {MAX_STATE_BYTES}", file=sys.stderr)
        return

    handle, temp_name = tempfile.mkstemp(dir=str(STATE_PATH.parent), suffix=".tmp")
    try:
        os.fchmod(handle, 0o600)
        with os.fdopen(handle, "wb") as stream:
            stream.write(raw_bytes)
            stream.flush()
            os.fsync(stream.fileno())
        if STATE_PATH.exists():
            st = STATE_PATH.lstat()
            if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
                STATE_PATH.unlink(missing_ok=True)
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
    out = run_bounded_subprocess(["hyprctl", "clients", "-j"], timeout=3)
    if out:
        try:
            parsed = json.loads(out)
            if isinstance(parsed, list):
                clients = parsed
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
                cls = str(c.get("class", "")).strip()
                title = str(c.get("title", "")).strip()
                pid = int(c.get("pid", 0))

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


def get_installed_applications():
    search_paths = [
        Path("/usr/share/applications"),
        Path.home() / ".local" / "share" / "applications",
    ]

    apps = {}
    for sp in search_paths:
        if not sp.exists():
            continue
        for desktop_file in sp.glob("*.desktop"):
            try:
                cp = configparser.RawConfigParser(interpolation=None)
                cp.read(desktop_file, encoding="utf-8", errors="ignore")
                if not cp.has_section("Desktop Entry"):
                    continue

                entry = cp["Desktop Entry"]
                if entry.get("NoDisplay", "false").lower() == "true":
                    continue
                if entry.get("Type", "Application") != "Application":
                    continue

                name = entry.get("Name", desktop_file.stem).strip()
                exec_cmd = entry.get("Exec", "").strip()
                icon = entry.get("Icon", "").strip()
                comment = entry.get("Comment", "").strip()
                wm_class = entry.get("StartupWMClass", "").strip()

                if not exec_cmd or not name:
                    continue

                clean_exec = exec_cmd.split("%")[0].strip()
                app_id = desktop_file.stem

                if app_id not in apps:
                    apps[app_id] = {
                        "id": app_id,
                        "name": name,
                        "exec": clean_exec,
                        "icon": icon or "application-x-executable",
                        "comment": comment,
                        "wmClass": wm_class or app_id,
                        "desktopFile": str(desktop_file)
                    }
            except Exception:
                continue

    sorted_apps = sorted(apps.values(), key=lambda x: x["name"].lower())
    return sorted_apps[:250]


def sync_state():
    cfg = load_config()
    pinned_entries = cfg.get("entries", [])
    workspaces, clients = get_live_hyprland_state(pinned_entries)
    apps = get_installed_applications()

    state = {
        "version": 1,
        "entries": pinned_entries,
        "workspaces": workspaces,
        "installedApps": apps,
        "totalPinned": len(pinned_entries),
        "totalRunningWindows": len(clients),
    }
    write_state(state)
    print(f"OmaPad state synced: {len(pinned_entries)} pinned, {len(workspaces)} workspaces, {len(apps)} apps")
    return state


def add_pin(name, match, workspace, launch_at_boot=False, silent=False):
    cfg = load_config()
    entries = cfg.get("entries", [])

    match_clean = str(match).strip()
    entries = [e for e in entries if str(e.get("match", "")).strip().lower() != match_clean.lower()]

    entries.append({
        "name": str(name).strip() or match_clean,
        "match": match_clean,
        "workspace": int(workspace),
        "launchAtBoot": bool(launch_at_boot),
        "silent": bool(silent)
    })

    cfg["entries"] = entries
    write_config(cfg)

    if GENERATOR_PATH.exists():
        run_bounded_subprocess(["python3", str(GENERATOR_PATH)], timeout=3)
    if APPLY_NOW_PATH.exists():
        run_bounded_subprocess(["python3", str(APPLY_NOW_PATH)], timeout=3)

    sync_state()
    return {"ok": True, "entries": entries}


def remove_pin(match):
    cfg = load_config()
    entries = cfg.get("entries", [])
    match_clean = str(match).strip().lower()
    entries = [e for e in entries if str(e.get("match", "")).strip().lower() != match_clean]

    cfg["entries"] = entries
    write_config(cfg)

    if GENERATOR_PATH.exists():
        run_bounded_subprocess(["python3", str(GENERATOR_PATH)], timeout=3)

    sync_state()
    return {"ok": True, "entries": entries}


def update_pin(match, workspace=None, launch_at_boot=None, silent=None):
    cfg = load_config()
    entries = cfg.get("entries", [])
    match_clean = str(match).strip().lower()

    found = False
    for e in entries:
        if str(e.get("match", "")).strip().lower() == match_clean:
            if workspace is not None:
                e["workspace"] = int(workspace)
            if launch_at_boot is not None:
                e["launchAtBoot"] = bool(launch_at_boot)
            if silent is not None:
                e["silent"] = bool(silent)
            found = True
            break

    if not found:
        return {"ok": False, "error": f"Rule matching '{match}' not found"}

    cfg["entries"] = entries
    write_config(cfg)

    if GENERATOR_PATH.exists():
        run_bounded_subprocess(["python3", str(GENERATOR_PATH)], timeout=3)
    if APPLY_NOW_PATH.exists():
        run_bounded_subprocess(["python3", str(APPLY_NOW_PATH)], timeout=3)

    sync_state()
    return {"ok": True, "entries": entries}


def main():
    parser = argparse.ArgumentParser(description="OmaPad Engine")
    parser.add_argument("--sync", action="store_true", help="Sync state and live Hyprland windows")
    parser.add_argument("--add", action="store_true", help="Add or update a pinned rule")
    parser.add_argument("--remove", action="store_true", help="Remove a pinned rule")
    parser.add_argument("--update", action="store_true", help="Update existing pinned rule properties")
    parser.add_argument("--apply-now", action="store_true", help="Dispatch running windows to workspaces")
    parser.add_argument("--name", default="")
    parser.add_argument("--match", default="")
    parser.add_argument("--workspace", type=int, default=1)
    parser.add_argument("--launch-at-boot", action="store_true")
    parser.add_argument("--silent", action="store_true")
    parser.add_argument("--boot-toggle", default="")
    args = parser.parse_args()

    if args.add:
        res = add_pin(args.name, args.match, args.workspace, args.launch_at_boot, args.silent)
        print(json.dumps(res))
    elif args.remove:
        res = remove_pin(args.match)
        print(json.dumps(res))
    elif args.update:
        b_val = None
        if args.boot_toggle:
            b_val = args.boot_toggle.lower() in ("true", "1", "yes")
        res = update_pin(args.match, args.workspace if args.workspace else None, b_val, None)
        print(json.dumps(res))
    elif args.apply_now:
        if APPLY_NOW_PATH.exists():
            run_bounded_subprocess(["python3", str(APPLY_NOW_PATH)], timeout=5)
        sync_state()
    else:
        sync_state()


if __name__ == "__main__":
    main()
