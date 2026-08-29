import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null

  // Apply the user's launchpad.json rules when the shell (and Hyprland) start.
  Process {
    id: applyOnBoot
    command: ["/usr/bin/python3", (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-pad/scripts/generate.py"]
    running: true
  }

  function reload() {
    applyOnBoot.running = false
    applyOnBoot.running = true
    return "ok"
  }
}
