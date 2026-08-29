# OmaPad — App-to-Workspace & Auto-Launch Manager for Omarchy

Declaratively pin apps to Hyprland workspaces and optionally auto-launch them at boot, driven entirely by a single config file and a searchable in-panel application picker.

---

## 🌟 Features

- **🎯 Searchable App Dropdown**: Discovers all installed `.desktop` applications and running windows automatically so you don't have to guess window class matches or execution commands.
- **📌 Workspace Pinning**: Assign apps to workspaces 1 through 10.
- **🚀 Boot Launching**: Toggle `Auto-launch at boot` on any app rule.
- **🔇 Silent Pinning**: Open apps in designated workspaces without pulling focus away from your current workspace.
- **⚡ Instant Repositioning (`󰵱` / `M`)**: 1-click button to move all currently open windows to their assigned workspaces.
- **🔄 Zero Hand-Editing**: Generates `~/.config/hypr/launchpad.lua` and reloads Hyprland (`hyprctl reload`) cleanly.

---

## ⌨️ Keyboard Shortcuts

| Key | Action |
|---|---|
| `a` / `A` | Open **Add App Rule** picker |
| `r` / `R` | Re-generate rules & reload Hyprland |
| `m` / `M` | Reposition currently open windows now |
| `Esc` | Close flyout |

---

## 📄 License

MIT License © 2026 Kiryuuki
