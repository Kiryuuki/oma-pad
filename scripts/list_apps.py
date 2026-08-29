#!/usr/bin/env python3
"""
Emit installed .desktop apps and currently open Hyprland windows as a JSON array.
Used by OmaPad to provide an intelligent dropdown so users don't have to guess
window classes or launch commands.
"""

import configparser
import json
import os
import subprocess
import sys


def get_running_windows():
    try:
        p = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=3)
        if p.returncode == 0:
            clients = json.loads(p.stdout)
            running = []
            seen_classes = set()
            for c in clients:
                cls = c.get("class", "").strip()
                title = c.get("title", "").strip()
                if not cls or cls in seen_classes:
                    continue
                seen_classes.add(cls)
                running.append({
                    "id": cls,
                    "name": f"{cls} (Running: {title[:28]}...)" if len(title) > 28 else f"{cls} (Running: {title})",
                    "match": cls,
                    "command": cls.lower(),
                    "isRunning": True,
                })
            return running
    except Exception:
        pass
    return []


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

            key = name.lower()
            if key not in seen:
                seen[key] = {
                    "id": base_id,
                    "name": name,
                    "match": match_class,
                    "command": exec_val or base_id,
                    "isRunning": False,
                }

    return sorted(seen.values(), key=lambda x: x["name"].lower())


def main():
    running = get_running_windows()
    installed = get_installed_apps()

    # Prioritize currently running windows at the top, followed by all installed apps
    combined = running + [app for app in installed if app["match"] not in {r["match"] for r in running}]
    print(json.dumps(combined))


if __name__ == "__main__":
    main()
