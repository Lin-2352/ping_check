# Ping Overlay

<p align="center">
  <img src="https://img.shields.io/badge/platform-Windows%2010%2F11-0078D4?style=for-the-badge&logo=windows" />
  <img src="https://img.shields.io/badge/runtime-PowerShell%207%2B-5391FE?style=for-the-badge&logo=powershell" />
  <img src="https://img.shields.io/badge/UWP%20%26%20Win32-Supported-00C896?style=for-the-badge" />
  <img src="https://img.shields.io/badge/no%20install-just%20double--click-FF6B35?style=for-the-badge" />
</p>

A transparent, always-on-top real-time **ping counter** that sits over any game or UWP application window. Color-coded from green → yellow → red. Zero installation — just a single `.bat` file.

> **Tired of playing UWP games with no way to monitor your ping?**  
> Most overlays don't work with Microsoft Store (UWP) apps — Ping Overlay does. Built specifically to bridge that gap, it works seamlessly on any UWP or Win32 game without touching your game files or requiring admin rights.

---

## What It Does

Ping Overlay draws a live latency readout (`PING: 42 ms`) directly on top of your game window, updating every second. It follows the window as you move it, auto-hides when the game isn't in focus, and disappears completely when the game closes — all without touching your game files or requiring admin rights.

---

## Screenshots

> **Look at the top right corner** to see the overlay in action!
> 
> ![In-game Screenshot](./screenshot.png)

---

## Features

| Feature | Details |
|---|---|
| 🎯 **Any App** | Works with UWP (Microsoft Store) and Win32 games |
| 🎨 **Color-coded ping** | Green → Yellow → Red gradient |
| 📌 **Window tracking** | Overlay follows the game window; drag to reposition |
| 🖱️ **Scroll wheel opacity** | Scroll on the overlay to adjust transparency |
| 🌙 **Dark / Light mode** | Toggle from the system tray menu |
| 🖥️ **System tray** | Right-click for settings, capture, stats reset |
| ⚙️ **Capture Window** | Click and switch to your game — auto-detects the process |
| 📊 **Ping statistics** | Rolling 60-sample min/avg/max + packet loss % |
| 🔁 **Auto-start** | Optional Windows startup integration |
| 📦 **Zero install** | Single `.bat` file — copy, double-click, done |

---

## Quick Start

1. **Download** `PingOverlay.bat` (and keep it in its own folder)
2. **Double-click** `PingOverlay.bat`
3. **Settings dialog opens** — fill in:
   - **Server IP** — the server you want to ping (e.g. your game's server IP)
   - **Capture Window** — click the button, then switch to your game within 5 seconds
4. Click **Start Overlay**

The overlay appears on top of your game and starts measuring latency immediately.

---

## Requirements

| Requirement | Version |
|---|---|
| Windows | 10 or 11 |
| PowerShell | 7+ (`pwsh.exe`) |
| .NET | 5+ (bundled with PowerShell 7) |

> To check: open a terminal and run `pwsh --version`. If it's not installed, download from [aka.ms/powershell](https://aka.ms/powershell).

---

## Configuration

Settings are stored in `config.json` (auto-created next to `PingOverlay.bat`):

```json
{
  "ServerIP": "8.8.8.8",
  "PingIntervalMs": 1000,
  "GameProcessName": "YourGame",
  "ShowOnlyWhenForeground": true,
  "GameExitGraceSeconds": 15,
  "FontSize": 14,
  "FontFamily": "Consolas",
  "OverlayOpacity": 1.0,
  "AutoStart": false,
  "DarkMode": true
}
```

All settings are editable via the **Settings dialog** (right-click tray icon → Settings).

---

## File Structure & Auto-Generated Files

When you run `PingOverlay.bat`, it will automatically generate a few files in the same directory to save your preferences and log information:

| File | Description |
|---|---|
| `PingOverlay.bat` | The main executable script. Double-click this to start the overlay. |
| `config.json` | **(Auto-generated)** Stores all your settings (Server IP, font size, interval, etc.). |
| `overlay_position.txt` | **(Auto-generated)** Saves the exact X and Y coordinates of where you last dragged the overlay. |
| `overlay.log` | **(Auto-generated)** A rolling log file containing background operation info and errors (auto-rotates at 512KB). |
| `README.md` | This quick overview file. |
| `Ping Overlay (detailed guide).md` | A comprehensive technical breakdown of the script for developers. |

---

## System Tray Menu

Right-click the tray icon for quick actions:

| Menu Item | Action |
|---|---|
| Show / Hide Overlay | Toggle overlay visibility |
| ⚙ Settings | Open settings dialog |
| ◎ Capture Window | Re-capture target window |
| ✕ Release Capture | Stop tracking current window |
| ☀ / 🌙 Dark / Light Mode | Toggle UI theme |
| Auto-Start with Windows | Register/remove from Startup |
| ↺ Reset Stats | Clear ping history |
| ⏻ Exit | Close the application |

---

## How the Capture Works

1. Click **Capture Window** in settings (or from the tray)
2. A 5-second countdown appears
3. **Switch to your game** at any point during the countdown
4. The overlay reads `Target: <window title>` in green as confirmation
5. When the timer hits 0, that window is locked in

Works with both **UWP apps** (Microsoft Store games) and **regular Win32 games**.

---

## Overlay Controls

| Action | Effect |
|---|---|
| **Drag** | Move overlay anywhere on screen |
| **Scroll wheel** | Adjust opacity (20%–100%) |
| **Right-click** | Exit the application |

---

## Files

```
PingOverlay.bat         ← The entire application (polyglot batch/PowerShell)
config.json             ← User settings (auto-created)
overlay_position.txt    ← Saved overlay position (auto-created)
overlay.log             ← Debug log (auto-created)
README.md               ← This file
Ping Overlay (detailed guide).md ← Technical documentation for developers
```

---

## FAQ

**Q: The overlay doesn't appear over my game.**  
A: Make sure "Show only when app is in foreground" is enabled and your game window is the active window. For fullscreen exclusive games, try windowed borderless mode.

**Q: The process name field is empty after capture.**  
A: Switch to your game *during* the countdown (before it hits 0). The green `Target:` label in the countdown dialog confirms detection.

**Q: Can I ping any server, not just my game server?**  
A: Yes — enter any IP or hostname in the Server IP field (e.g. `8.8.8.8` for Google DNS to test your general internet latency).

**Q: Does it work with fullscreen games?**  
A: Best results are with windowed or borderless windowed mode. True exclusive fullscreen may prevent the overlay from appearing on top.

---

## Technical Documentation

For architecture details, Win32 P/Invoke references, function-by-function breakdown, and developer notes, see **[Ping Overlay (detailed guide).md](Ping%20Overlay%20(detailed%20guide).md)**.

---

## License

This project is provided as-is for personal use. No warranty. Modify freely.
