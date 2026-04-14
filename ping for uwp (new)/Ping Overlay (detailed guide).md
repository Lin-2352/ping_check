# Ping Overlay — Technical Documentation

> **Version:** 2.2  
> **File:** `PingOverlay.bat`  
> **Audience:** Developers and AI agents working on modifications or extensions.

A transparent, always-on-top, real-time latency overlay for any game or UWP application on Windows. Displays a color-coded ping counter (e.g. `PING: 45 ms`) directly over the game window. Written as a single **polyglot `.bat` file** — no installation required.

> **Purpose of this document:** Complete handoff reference. Any developer or AI agent reading this should be able to fully understand the architecture, modify the code, fix bugs, or add features without additional context.

---

## Table of Contents

1. [Overview & Feature Matrix](#1-overview--feature-matrix)
2. [How It Works (High-Level Flow)](#2-how-it-works-high-level-flow)
3. [Prerequisites & Installation](#3-prerequisites--installation)
4. [File Structure](#4-file-structure)
5. [Configuration — `config.json`](#5-configuration--configjson)
6. [Overlay Position — `overlay_position.txt`](#6-overlay-position--overlay_positiontxt)
7. [Logging — `overlay.log`](#7-logging--overlaylog)
8. [Architecture Deep Dive](#8-architecture-deep-dive)
9. [Complete Function Reference](#9-complete-function-reference)
10. [Complete Variable Reference](#10-complete-variable-reference)
11. [All User Interactions](#11-all-user-interactions)
12. [Startup Flow — Step by Step](#12-startup-flow--step-by-step)
13. [Runtime Flow — Per Timer Tick](#13-runtime-flow--per-timer-tick)
14. [Shutdown Flow](#14-shutdown-flow)
15. [Known Edge Cases & How They're Handled](#15-known-edge-cases--how-theyre-handled)
16. [Change History](#16-change-history)
17. [Roadmap](#17-roadmap)
18. [Developer Notes & Gotchas](#18-developer-notes--gotchas)

---

## 1. Overview & Feature Matrix

| Feature | Description |
|---|---|
| **Overlay text** | `PING: <ms> ms` with thick black outline, rendered via GDI+ `GraphicsPath` (vector, not raster) |
| **Color coding** | Smooth gradient: Green (0–100 ms) → Yellow (100–150 ms) → Red (150–250+ ms) |
| **Position tracking** | Overlay follows game window in real time; user can drag to reposition; offset persists in `overlay_position.txt` |
| **Opacity control** | Scroll wheel on overlay (20%–100%) or via Settings dialog |
| **Dark / Light mode** | Full UI theme system; persisted in `config.json`; toggle from tray menu |
| **System tray** | Color-dot icon reflecting ping status; right-click menu with Show/Hide, Settings, Capture, Dark Mode toggle, Auto-Start, Reset Stats, Exit |
| **Startup dialog** | Professional dark/light-themed settings dialog with section headers, placeholder hints, and font preview dropdown |
| **Capture Window** | Live countdown with real-time foreground tracking; works for both UWP and Win32; shows detected target during countdown |
| **Font selection** | Dropdown with preview rendering (owner-draw); filtered to only show installed fonts |
| **Console window** | Immediately minimized on launch; titled "Ping Overlay"; kills process on X click |
| **Auto-start** | Creates/removes `.lnk` shortcut in `shell:Startup` |
| **Statistics** | Rolling 60-sample window: min/avg/max ping + packet loss %; shown in tray tooltip |
| **Foreground mode** | Overlay only shows when target app is active foreground window |
| **Grace period** | N-second buffer after game exits before returning to idle (prevents flicker) |
| **UWP + Win32** | UWP: `ApplicationFrameWindow` child enumeration to find real process; Win32: top-level window PID matching |
| **Single-file** | Entire app in one `.bat` file — batch header, PowerShell, and inline C# compiled at runtime |
| **Zero install** | Copy folder, double-click. No admin rights needed. |

---


## 2. How It Works (High-Level Flow)

```
User double-clicks PingOverlay.bat
    │
    ├─ [BATCH] Sets env vars PING_DIR and PING_BAT
    ├─ [BATCH] Launches: pwsh.exe -STA -NoProfile -ExecutionPolicy Bypass
    ├─ [BATCH] exit /b — batch portion ends
    │
    ├─ [PWSH] Kills any previous PingOverlay pwsh instances (duplicate prevention)
    │
    ├─ [PWSH] Loads .NET assemblies: System.Windows.Forms, System.Drawing
    │
    ├─ [PWSH → C#] Compiles inline C# at runtime via Add-Type:
    │   ├─ Win32 static class — P/Invoke for window management, console close handler
    │   └─ OutlinedLabel class — Custom WinForms control with GDI+ text outline rendering
    │
    ├─ [PWSH] Loads config.json (or creates defaults on first run)
    │
    ├─ [PWSH] Creates system tray icon (grey dot) + dark-themed context menu
    │
    ├─ [PWSH] Creates overlay form (borderless, transparent, topmost, Opacity=0, hidden)
    │
    ├─ [PWSH] Sets console window title = "Ping Overlay"
    │
    ├─ [PWSH → C#] Registers CTRL_CLOSE_EVENT handler for instant kill on console close
    │
    ├─ [PWSH] Shows startup settings dialog (modal WinForms dialog)
    │   ├─ User clicks "Start Overlay" → saves config, proceeds
    │   └─ User closes via X → exits cleanly
    │
    ├─ [PWSH] Re-applies config to label font and timer interval
    │
    ├─ [PWSH] Starts WinForms Timer (fires every PingIntervalMs on UI thread)
    │   └─ Each tick:
    │       ├─ Check if game process is running (Get-Process by name)
    │       ├─ If running: find game window rect → reposition overlay → ping server → update label
    │       └─ If not: hide overlay immediately → wait grace period → reset to idle
    │
    └─ [PWSH] Application.Run($form) — enters WinForms message loop
        └─ Blocks until form is closed (by Exit menu, right-click, or console close)
```

---

## 3. Prerequisites & Installation

| Requirement | Details |
|---|---|
| **OS** | Windows 10 or Windows 11 |
| **PowerShell** | **PowerShell 7+** (`pwsh.exe`). The batch header calls `pwsh`, NOT `powershell.exe` (Windows PowerShell 5.1). |
| **Installation** | None. Copy the folder anywhere and double-click `PingOverlay.bat`. |
| **Admin rights** | Not required. Exception: Auto-Start writes a `.lnk` to `shell:Startup` (user-level, no elevation needed). |
| **.NET** | Ships bundled with pwsh 7+ (`System.Windows.Forms` and `System.Drawing` assemblies). |

### Installing PowerShell 7

```powershell
winget install Microsoft.PowerShell
```

Or download from: https://aka.ms/PSWindows

### Verifying Installation

```powershell
pwsh --version
# Should output: PowerShell 7.x.x
```

---

## 4. File Structure

```
ping for uwp (new)/
├── PingOverlay.bat          ← The entire application (polyglot batch/PowerShell/inline C#)
├── config.json              ← User configuration (auto-generated on first run)
├── overlay_position.txt     ← Persisted overlay X,Y offset from game window corner
├── overlay.log              ← Timestamped append-only log file
├── README.md                ← GitHub-style project README
└── ping(readme).md          ← This file (technical documentation)
```

### About `PingOverlay.bat`

This is a **polyglot file** — simultaneously valid as:
1. A **Windows Batch script** (lines 1–7: sets env vars, launches `pwsh.exe`, exits)
2. A **PowerShell script** (lines 8+: the entire application logic)
3. Contains **inline C# code** (compiled at runtime via `Add-Type`): the `Win32` class (P/Invoke) and the `OutlinedLabel` control

The trick: `<# :` on line 1 is a valid batch label AND the start of a PowerShell block comment. Batch processes lines 2–6 and exits; PowerShell sees lines 1–7 as a comment block.

---

## 5. Configuration — `config.json`

Auto-generated on first run with blank defaults. Edit manually (JSON) or through the Settings dialog (at startup or from the tray menu).

```json
{
  "ServerIP": "",
  "PingIntervalMs": 1000,
  "GameProcessName": "",
  "ShowOnlyWhenForeground": true,
  "GameExitGraceSeconds": 15,
  "FontSize": 14,
  "FontFamily": "Consolas",
  "OverlayOpacity": 1.0,
  "AutoStart": false,
  "DarkMode": true
}
```

### Config Key Reference

| Key | Type | Default | Range / Constraints | Description |
|---|---|---|---|---|
| `ServerIP` | string | `""` | Any valid IP or hostname | The target to ping. Typically the game server IP. |
| `PingIntervalMs` | int | `1000` | 200 – 10000 (step 100) | Milliseconds between pings. |
| `GameProcessName` | string | `""` | Process name without `.exe` | Auto-filled by the Capture Window function; or enter manually. |
| `ShowOnlyWhenForeground` | bool | `true` | true / false | Overlay only shows when game is active foreground window. |
| `GameExitGraceSeconds` | int | `15` | 0 – 300 (step 1) | Delay before resetting to idle state after game closes. |
| `FontSize` | int | `14` | 8 – 48 (step 1) | Overlay text font size in points. |
| `FontFamily` | string | `"Consolas"` | Any installed font name | Overlay text font family. |
| `OverlayOpacity` | float | `1.0` | 0.20 – 1.00 (step 0.05) | Overlay transparency. Also adjustable via scroll wheel. |
| `AutoStart` | bool | `false` | true / false | Creates/removes `.lnk` in `shell:Startup`. |
| `DarkMode` | bool | `true` | true / false | Settings dialog and tray menu color theme. |

### How Config is Loaded

1. `Load-Config` defines a `$defaults` hashtable with all keys and default values.
2. If `config.json` exists: reads it, parses JSON, merges matching keys. Missing keys retain defaults (forward-compatible).
3. If `config.json` doesn't exist: writes defaults to disk on first run.
4. Returns the merged hashtable as `$script:Config`.

### How Config is Saved

`Save-Config` serializes the hashtable with `ConvertTo-Json -Depth 2` and overwrites `config.json`.

---

## 6. Overlay Position — `overlay_position.txt`

Stores the overlay's X,Y pixel offset relative to the game window's top-left corner.

| Property | Value |
|---|---|
| **Format** | `<x>,<y>` — single line, no trailing newline, ASCII encoding |
| **Example** | `10,248` = 10px right, 248px down from game window top-left |
| **Default** | `10,248` if file is missing, empty, or unparseable |
| **Updated** | On mouse-up after the user drags the overlay to a new position |
| **Validation** | Regex: `^\s*(-?\d+)\s*,\s*(-?\d+)\s*$` — negative values are allowed (overlay can be above/left of game window) |

---

## 7. Logging — `overlay.log`

Append-only timestamped log file. Never automatically truncated or rotated.

| Property | Value |
|---|---|
| **Format** | `yyyy-MM-dd HH:mm:ss  <message>` |
| **Encoding** | ASCII |
| **Location** | Same directory as the script |

### Events That Are Logged

- `"Ping Overlay started"` — successful startup after settings dialog
- `"Startup cancelled by user"` — user closed the startup dialog via X
- `"Created default config.json"` — first run, defaults written
- `"Failed to read config: ..."` — config.json parse error
- `"Failed to save config: ..."` — config.json write error
- `"Failed to read settings: ..."` — overlay_position.txt read error
- `"Failed to save settings: ..."` — overlay_position.txt write error
- `"Failed to load Windows Forms assemblies: ..."` — .NET assembly load failure
- `"Failed to load Win32 interop: ..."` — C# compilation failure for Win32 class
- `"Failed to load OutlinedLabel: ..."` — C# compilation failure for OutlinedLabel
- `"Init error: ..."` — WinForms initialization error
- `"Tick error: ..."` — any exception in the timer tick handler
- `"Fatal error: ..."` — unhandled exception in `Application.Run()`
- `"Failed to create startup shortcut: ..."` — auto-start shortcut creation failure

---

## 8. Architecture Deep Dive (Line-by-Line)

### 8.1 Polyglot Batch/PowerShell Header (Lines 1–7)

```bat
<# :
@echo off
set "PING_DIR=%~dp0"
set "PING_BAT=%~f0"
start "Ping Overlay" /min pwsh -NoProfile -STA -ExecutionPolicy Bypass -Command "iex (Get-Content -Raw -LiteralPath $env:PING_BAT)"
exit /b
#>
```

**Line-by-line:**

| Line | What Batch Sees | What PowerShell Sees |
|---|---|---|
| `<# :` | A label named `:` (valid, no-op) | Start of block comment `<#` |
| `@echo off` | Suppress command echo | Inside block comment |
| `set "PING_DIR=%~dp0"` | Set env var to script directory | Inside block comment |
| `set "PING_BAT=%~f0"` | Set env var to script full path | Inside block comment |
| `start ...` | Launch pwsh minimized | Inside block comment |
| `exit /b` | End batch script | Inside block comment |
| `#>` | Would be an error, but batch already exited | End of block comment |

**Key flags on the `pwsh` command:**

| Flag | Purpose |
|---|---|
| `-NoProfile` | Don't load user's PowerShell profile (avoids interference) |
| `-STA` | **Single-Threaded Apartment** — required for WinForms. Without this, forms crash. |
| `-ExecutionPolicy Bypass` | Allow running unsigned scripts |
| `-Command "iex (...)"` | Read the entire file and execute it as PowerShell code |

**Environment variables:**
- `PING_DIR` = `C:\path\to\folder\` (with trailing backslash)
- `PING_BAT` = `C:\path\to\folder\PingOverlay.bat` (full path)

These are consumed by line 30: `$ScriptDir = $env:PING_DIR.TrimEnd('\')`

---

### 8.2 Bootstrap & Duplicate Prevention (Lines 32–40)

```powershell
$myPid = $PID
Get-WmiObject Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue |
Where-Object { $_.ProcessId -ne $myPid -and $_.CommandLine -match 'PingOverlay' } |
ForEach-Object {
    try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
}
```

**Why WMI instead of `Get-Process`?** `Get-Process` returns process objects without `CommandLine`. We need `CommandLine` to distinguish our script from other PowerShell instances. WMI's `Win32_Process` provides this.

**Pattern match:** `'PingOverlay'` in the command line. This matches both the old `MC5PingOverlay` and new `PingOverlay` filenames.

**Self-exclusion:** `$_.ProcessId -ne $myPid` ensures the current instance doesn't kill itself.

---

### 8.3 Logging Subsystem (Lines 42–53)

```powershell
$LogFile = Join-Path $ScriptDir "overlay.log"

function Write-Log {
    param([string]$Message)
    try {
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        "$timestamp  $Message" | Out-File -FilePath $LogFile -Encoding ASCII -Append
    }
    catch {}
}
```

**Design:** Fire-and-forget. The outer `try/catch` with empty `catch` ensures logging failures never crash the app. Two-space separator between timestamp and message for readability.

---

### 8.4 .NET Assembly Loading (Lines 55–64)

```powershell
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
```

Loads the WinForms and GDI+ assemblies. These ship with PowerShell 7. If they fail to load (e.g., headless server), the script logs the error and throws (cannot continue without a GUI framework).

---

### 8.5 Win32 Interop — C# P/Invoke (Lines 66–153)

Compiled at runtime via `Add-Type @"..."@`. Creates a `public static class Win32` with:

| Declaration | Purpose |
|---|---|
| `EnumWindows` / `EnumChildWindows` | Iterate all top-level and child windows (for UWP frame detection) |
| `GetForegroundWindow` | Get the currently active window handle (for foreground-only mode) |
| `GetWindowThreadProcessId` | Map HWND → PID (to match windows to game processes) |
| `GetWindowRect` | Get screen coordinates of a window (for overlay positioning) |
| `GetClassName` | Get Win32 class name (to identify `ApplicationFrameWindow`) |
| `ShowWindow` | Show/hide overlay (`SW_HIDE=0`, `SW_SHOWNOACTIVATE=4`) |
| `GetWindowLong` / `SetWindowLong` | Read/modify extended window styles (for `WS_EX_TOOLWINDOW`) |
| `GetConsoleWindow` | Get the PowerShell console HWND |
| `DestroyIcon` | Release native icon handles (GDI leak prevention) |
| `SetConsoleCtrlHandler` | Register console close event callback |

**`RegisterCloseHandler()` method (Lines 127–136):**

```csharp
public static void RegisterCloseHandler() {
    _handler = new ConsoleCtrlDelegate(ctrlType => {
        if (ctrlType == 2) {  // CTRL_CLOSE_EVENT
            Process.GetCurrentProcess().Kill();
        }
        return false;
    });
    SetConsoleCtrlHandler(_handler, true);
}
```

**Why `Process.Kill()` instead of `Environment.Exit()`?** When the user closes the PowerShell console from the taskbar, Windows sends `CTRL_CLOSE_EVENT`. If we use `Environment.Exit()`, it tries to run WinForms cleanup (dispose forms, flush pending messages) which can hang for 5–10 seconds. `Process.Kill()` terminates instantly.

**The `_handler` static field** prevents the delegate from being garbage-collected. Without it, the GC could collect the delegate while the OS still holds a reference to it, causing an access violation crash.

**Guard pattern:** `if (-not ([PSTypeName]'Win32').Type)` prevents recompilation if the type is already loaded in the AppDomain. This is necessary because `Add-Type` types persist for the lifetime of the process and cannot be unloaded or redefined.

---

### 8.6 OutlinedLabel — Custom C# WinForms Control (Lines 155–254)

A custom `Control` subclass that renders text with a thick colored outline, similar to MSI Afterburner's OSD style.

**Public properties:**
- `OutlineColor` — `Color`, default `Color.Black`
- `OutlineWidth` — `int`, default `1` (script sets it to `2`)

**Constructor sets these control styles:**
- `UserPaint` — control paints itself (not the OS)
- `AllPaintingInWmPaint` — all painting in `WM_PAINT` (reduces flicker)
- `OptimizedDoubleBuffer` — render to back buffer first
- `ResizeRedraw` — repaint on resize
- `SupportsTransparentBackColor` — allows `BackColor = Color.Transparent`

**Rendering pipeline (`OnPaint`):**

1. Set graphics quality: `SmoothingMode.HighQuality`, `AntiAliasGridFit`, `PixelOffsetMode.HighQuality`, `CompositingQuality.HighQuality`
2. Create a `GraphicsPath` and add the text as vector outlines using `path.AddString()`
3. Draw the path with a thick `Pen` (outline color, width = `ow * 2 + 1`) using `LineJoin.Round`
4. Fill the path with a `SolidBrush` (text foreground color)

**Auto-sizing:** Overrides `GetPreferredSize()` to calculate the exact bounding box: `TextRenderer.MeasureText()` + padding + outline width on all sides. `OnTextChanged`, `OnFontChanged`, and `OnPaddingChanged` all call `UpdateSize()` → `GetPreferredSize()` → `Invalidate()`.

**PS7 assembly workaround (Lines 163–173):** PowerShell 7 splits .NET types across many assemblies (e.g., `System.Drawing.Primitives.dll`, `System.Drawing.Common.dll`). The code:
1. Finds the pwsh.exe directory
2. Loads ALL DLLs matching `System.(Drawing|Windows.Forms|ComponentModel)*`
3. Collects all loaded assembly locations
4. Passes them as `ReferencedAssemblies` to `Add-Type`

Without this, `Add-Type` fails with "type not found" errors because it can't resolve `Color`, `Font`, `Control`, etc. across fragmented assemblies.

---

### 8.7 Configuration System (Lines 256–299)

**`Load-Config` (Lines 261–291):**

```
1. Define $defaults hashtable with all 9 config keys and their default values
2. If config.json exists:
   a. Read and parse JSON → PSCustomObject
   b. For each key in $defaults:
      - If JSON has this key → copy its value into $defaults
      - If JSON doesn't have this key → keep default (forward-compatible)
3. If config.json doesn't exist:
   a. Serialize $defaults to JSON
   b. Write to config.json
   c. Log "Created default config.json"
4. Return $defaults hashtable
```

**`Save-Config` (Lines 293–297):** `$cfg | ConvertTo-Json -Depth 2 | Out-File`. Depth 2 handles nested objects (currently none, but future-proof).

**Design choice:** Hashtable (not PSCustomObject) for the in-memory config, because hashtables support easy key enumeration, modification, and JSON serialization. The merge loop handles the PSCustomObject→hashtable conversion from `ConvertFrom-Json`.

---

### 8.8 Ping Statistics Engine (Lines 301–329)

**Data structures:**
| Variable | Type | Description |
|---|---|---|
| `$script:PingHistory` | `List<int>` | Rolling window of last 60 successful ping results (ms) |
| `$script:PingTimeouts` | `int` | Running count of failed/timed-out pings |
| `$script:PingTotal` | `int` | Running count of all ping attempts (successes + timeouts) |
| `$MaxHistory` | `int` | Constant: `60` — max entries in history |

**`Add-PingResult($ms)`:**
- Increments `PingTotal`
- If `$ms` is `$null` → increments `PingTimeouts`
- If `$ms` is a number → adds to `PingHistory` (FIFO: removes oldest if at capacity)

**`Get-PingStats`:**
- Returns `"No data yet"` if history is empty
- Otherwise: `"Ping: Min X / Avg Y / Max Z ms\nLoss: P% (T/N)\nSamples: C"`
- Used in the tray icon tooltip

---

### 8.9 Window Management Helpers (Lines 331–353)

**Constants:**
- `$SW_HIDE = 0` — Hide a window completely
- `$SW_SHOWNOACTIVATE = 4` — Show a window without stealing focus (**critical** for overlay — must never take focus from the game)

**`Load-OverlayOffsets`:** Reads `overlay_position.txt`, validates with regex `^\s*(-?\d+)\s*,\s*(-?\d+)\s*$`, returns `@(x, y)` or default `@(10, 248)`.

**`Save-OverlayOffsets($x, $y)`:** Writes `"$x,$y"` to file with `-NoNewline`.

---

### 8.10 Network Ping Function (Lines 355–368)

```powershell
function Get-PingMs {
    param([string]$Target)
    try { $ping = Test-Connection -ComputerName $Target -Count 1 -ErrorAction SilentlyContinue }
    catch { return $null }
    if (-not $ping) { return $null }
    $reply = if ($ping -is [array]) { $ping[0] } else { $ping }
    if ($reply.PSObject.Properties['ResponseTime'])  { return [int]$reply.ResponseTime }
    if ($reply.PSObject.Properties['Latency'])        { return [int]$reply.Latency }
    if ($reply.PSObject.Properties['RoundtripTime'])  { return [int]$reply.RoundtripTime }
    return $null
}
```

**Cross-version compatibility:**
| PowerShell Version | Property Name |
|---|---|
| PS 5.1 | `ResponseTime` |
| PS 7.0–7.2 | `Latency` |
| PS 7.3+ | `RoundtripTime` (sometimes) |

The function checks all three in order and returns the first one found.

**Error handling:** Both `try/catch` and null-check. Any exception or missing reply returns `$null` (counted as a timeout by the statistics engine).

**Known limitation:** `Test-Connection -Count 1` is **synchronous** and blocks for the ICMP timeout (~4 seconds) if the target is unreachable. During this time, the overlay is unresponsive because the timer tick runs on the UI thread.

---

### 8.11 Game Process Detection (Lines 370–480)

This is the **most complex subsystem**. UWP (Universal Windows Platform) apps have a unique windowing model:

```
ApplicationFrameHost.exe (system process)
└── ApplicationFrameWindow (Win32 window class)
    ├── [other framework UI elements]
    └── GameProcess.exe (child window, different PID)
```

The game process owns a **child window** inside an `ApplicationFrameWindow`, but the `ApplicationFrameWindow` itself is owned by `ApplicationFrameHost.exe`. So you can't just do `GetWindowThreadProcessId(foregroundWindow)` — you'll get the wrong PID.

**Function chain:**

| Function | Lines | Purpose |
|---|---|---|
| `Is-GameRunning` | 374–376 | Simple `Get-Process -Name` check. Returns bool. |
| `Get-GameProcessIds` | 378–382 | Returns `int[]` of all PIDs for the game process name. |
| `Get-WindowClassName` | 384–389 | P/Invoke wrapper: `GetClassName(hWnd)` → string. |
| `Get-UwpFrameWindowByProcessId` | 391–414 | **UWP detection:** `EnumWindows` → for each `ApplicationFrameWindow` → `EnumChildWindows` → if any child's PID matches game → return the frame HWND. |
| `Get-TopLevelGameWindow` | 416–434 | **Fallback for non-UWP:** `EnumWindows` → find window with matching PID and size ≥ 100×100. |
| `Get-ForegroundHostWindow` | 436–455 | **Foreground check:** Is the current foreground window the game? Checks both direct PID match and `ApplicationFrameWindow` child match. |
| `Get-GameWindowRect` | 457–480 | **Main entry point.** Returns `Win32+RECT` or `$null`. |

**`Get-GameWindowRect` logic:**

```
if ShowOnlyWhenForeground:
    fg = GetForegroundWindow()
    if fg == overlay's own HWND:
        return lastRect  // Don't hide when user clicks the overlay
    frame = Get-ForegroundHostWindow(gameIds)
    if frame is null: return null  // Game not foreground → hide overlay
else:
    frame = Get-UwpFrameWindowByProcessId(gameIds)
    if null: frame = Get-TopLevelGameWindow(gameIds)  // Fallback
    if null: return null

rect = GetWindowRect(frame)
if rect is valid (w > 0, h > 0): return rect
else: return null
```

**Size filter in `Get-TopLevelGameWindow`:** Windows smaller than 100×100 pixels are rejected. This filters out splash screens, notification windows, tray helper windows, etc.

---

### 8.12 Color Interpolation (Lines 482–497)

**`Get-PingColor($ms)`** maps latency to a smooth RGB gradient:

| Range | R | G | B | Visual |
|---|---|---|---|---|
| 0 ms | 0 | 255 | 0 | Pure Green |
| 50 ms | 128 | 255 | 0 | Yellow-Green |
| 100 ms | 255 | 255 | 0 | Yellow |
| 175 ms | 255 | 128 | 0 | Orange |
| 250 ms | 255 | 0 | 0 | Pure Red |
| 250+ ms | 255 | 0 | 0 | Pure Red (clamped) |

**Formula:**
- 0–100 ms: `R = ms/100 * 255`, `G = 255`, `B = 0` (green → yellow)
- 100–250 ms: `R = 255`, `G = (1 - (ms-100)/150) * 255`, `B = 0` (yellow → red)
- 250+ ms: `R = 255`, `G = 0`, `B = 0` (pure red)

Used for both the overlay text `ForeColor` and the tray icon color.

---

### 8.13 Auto-Start with Windows (Lines 499–528)

**`Get-StartupShortcutPath`:** Returns `C:\Users\<user>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\PingOverlay.lnk`

**`Set-AutoStart($Enable)`:**
- **Enable:** Creates a `.lnk` shortcut via `WScript.Shell` COM object. Target = `PingOverlay.bat`, WindowStyle = 7 (`SW_SHOWMINNOACTIVE` — minimized, no activation).
- **Disable:** Deletes the `.lnk` file.
- Both update `$script:Config.AutoStart` and save to `config.json`.

---

### 8.14 Settings Window — WinForms Dialog (Lines 530–665)

A modal dark-themed (background `RGB(30,30,30)`) WinForms dialog. Has two modes:

| Mode | When | Title | Button |
|---|---|---|---|
| **Startup** | `-IsStartup` flag, called at launch | "Ping Overlay - Configure & Start" | "Start Overlay" |
| **Runtime** | Tray menu → Settings | "Ping Overlay - Settings" | "Save & Apply" |

**Fields (all pre-populated from current config):**

| Field | Control Type | Config Key | Constraints |
|---|---|---|---|
| Server IP | TextBox | `ServerIP` | Free text, `.Trim()`'d on save |
| Ping Interval (ms) | NumericUpDown | `PingIntervalMs` | 200–10000, step 100, 0 decimals |
| Game Process Name | TextBox | `GameProcessName` | Free text, `.Trim()`'d on save |
| Exit Grace (sec) | NumericUpDown | `GameExitGraceSeconds` | 0–300, step 1, 0 decimals |
| Font Size | NumericUpDown | `FontSize` | 8–48, step 1, 0 decimals |
| Font Family | TextBox | `FontFamily` | Free text, `.Trim()`'d on save |
| Overlay Opacity | NumericUpDown | `OverlayOpacity` | 0.20–1.00, step 0.05, 2 decimals |
| Show only when foreground | CheckBox | `ShowOnlyWhenForeground` | Boolean |

**Helper functions:**
- `Add-TextField($form, [ref]$y, $label, $value)` — Creates a label + textbox pair, advances Y position by 36px.
- `Add-NumericField($form, [ref]$y, $label, $value, $min, $max, $step)` — Creates a label + NumericUpDown pair. Clamps the initial value to the valid range with `Math.Max/Min` before assignment (prevents `ArgumentOutOfRangeException`).

**On save (button click):**
1. Copies all field values into `$script:Config`
2. Calls `Save-Config` → writes `config.json`
3. Applies live changes if overlay is already running:
   - `$script:timer.Interval = PingIntervalMs`
   - `$script:label.Font = new Font(FontFamily, FontSize, Bold)`
   - `$script:form.Opacity = OverlayOpacity`
4. Sets `$script:settingsDialogResult = 'OK'`
5. Closes the dialog

**Startup mode cancellation:** The `FormClosing` event handler checks if `settingsDialogResult` is still `$null` (user didn't click Save) and sets it to `'Cancel'`. The entry point checks this and exits cleanly.

**`AcceptButton`** is set to the save button, so pressing Enter triggers save.

---

### 8.15 UI Initialization (Lines 668–674)

```powershell
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
```

- `EnableVisualStyles()` — Enables Windows visual theme rendering (rounded buttons, etc.).
- `SetCompatibleTextRenderingDefault($false)` — Uses GDI+ text rendering instead of GDI. Smoother text.

---

### 8.16 System Tray Icon & Context Menu (Lines 676–755)

**Tray icon:** A programmatically generated 16×16 bitmap of a filled circle with a dark grey outline. Color reflects ping status.

**`Create-TrayIcon($r, $g, $b)`:**
1. `new Bitmap(16, 16)`
2. `Graphics.FromImage()` with `AntiAlias`
3. `FillEllipse` with specified color at `(1,1,13,13)`
4. `DrawEllipse` with grey outline `RGB(60,60,60)`
5. `GetHicon()` → `Icon.FromHandle()` → `.Clone()` → `DestroyIcon()`
6. Dispose bitmap and graphics

**`Update-TrayIcon($r, $g, $b)`:** **Only recreates the icon if the color has actually changed.** Caches current color in `$script:trayIconR/G/B`. This prevents GDI handle leaks — without this cache, a new icon would be created every tick (every 1 second), eventually exhausting the GDI handle limit and crashing.

**Context menu items:**
1. **Show/Hide Overlay** — `ShowWindow(SW_HIDE)` / `ShowWindow(SW_SHOWNOACTIVATE)`
2. **Settings** — `Show-SettingsWindow` (runtime mode, no `-IsStartup`)
3. **Auto-Start with Windows** — `CheckOnClick` checkbox, calls `Set-AutoStart`
4. *(separator)*
5. **Reset Stats** — Clears `PingHistory`, resets `PingTimeouts` and `PingTotal` to 0
6. *(separator)*
7. **Exit** — Disposes tray icon, closes form

**Double-click on tray icon:** Toggles overlay visibility (same as Show/Hide menu).

---

### 8.17 Overlay Form & Label (Lines 757–829)

**Form properties:**

| Property | Value | Why |
|---|---|---|
| `FormBorderStyle` | `None` | No title bar, no borders |
| `BackColor` | `RGB(1, 1, 1)` | Near-black; used as transparency key |
| `TransparencyKey` | `RGB(1, 1, 1)` | Any pixel matching this color becomes fully transparent and click-through |
| `TopMost` | `true` | Always on top |
| `ShowInTaskbar` | `false` | Not visible in taskbar (console window is) |
| `StartPosition` | `Manual` | Position set programmatically |
| `Location` | `(10, 248)` | Initial position (overridden by timer) |
| `Size` | `(10, 10)` | Tiny; auto-resized by label |
| `Opacity` | `0` | **Starts fully invisible** to prevent flash |

**Shown event (Lines 778–788):**
1. Cache form HWND in `$script:overlayHandle`
2. Apply `WS_EX_TOOLWINDOW` (hides from Alt-Tab task switcher)
3. Remove `WS_EX_APPWINDOW` (removes from taskbar)
4. `ShowWindow(SW_HIDE)` — start hidden; the timer will show it when game is detected

**Label (`OutlinedLabel`) properties:**
- Text: `"PING: --- ms"` (initial placeholder)
- ForeColor: `Lime` (bright green)
- OutlineColor: `Black`, OutlineWidth: `2`
- Font: from config (default: `Consolas 14pt Bold`)
- Padding: `(6, 2, 6, 2)` — left, top, right, bottom
- AutoSize: `true` → form auto-resizes via `SizeChanged` event

**Mouse interactions on the label:**

| Event | Handler | Behavior |
|---|---|---|
| `MouseDown` | Sets `dragging=true`, records cursor position and form location | Start drag |
| `MouseMove` | If dragging: move form by cursor delta | Drag |
| `MouseUp` | Sets `dragging=false`, calculates new offset from `lastRect`, saves to `overlay_position.txt` | End drag, persist |
| `MouseClick` (right) | Closes the form (exits app) | Quick exit |
| `MouseWheel` | ±0.05 opacity, clamped to 0.2–1.0, stores in `Config.OverlayOpacity` (in-memory only) | Adjust transparency |

**Note on scroll wheel opacity:** The changed opacity is stored in `$script:Config.OverlayOpacity` in memory but NOT auto-saved to `config.json`. It resets on restart unless the user also saves via the Settings dialog.

---

### 8.18 Main Timer Loop (Lines 831–914)

A `System.Windows.Forms.Timer` that fires on the UI thread every `PingIntervalMs` milliseconds.

**Why WinForms Timer?** Because it fires on the UI thread, avoiding cross-thread exceptions when updating form controls. A `System.Timers.Timer` would fire on a thread pool thread and require `Invoke()` calls.

**State variables:**
- `$script:lastGameSeenAt` — `DateTime` of the last tick where game was detected
- `$script:gameWasRunning` — `bool`, whether game was running on previous tick

**Complete tick logic:**

```
TRY:
    ids = Get-GameProcessIds()
    gameRunning = (ids.Count > 0)

    IF gameRunning:
        lastGameSeenAt = now
        IF NOT gameWasRunning:  // Game just started
            gameWasRunning = true
            trayText = "Ping Overlay - Running"

        rect = Get-GameWindowRect(ids)
        IF rect is null:  // Game window not found or not foreground
            IF overlayVisible: hide overlay
        ELSE:
            lastRect = rect
            IF NOT overlayVisible:
                form.Opacity = config.OverlayOpacity  // Restore opacity
                ShowWindow(SW_SHOWNOACTIVATE)
                overlayVisible = true
            form.TopMost = true  // Re-assert (games can steal topmost)
            IF NOT dragging:
                form.Location = (rect.Left + offsetX, rect.Top + offsetY)

        ms = Get-PingMs(config.ServerIP)
        Add-PingResult(ms)

        IF ms is not null:
            label.Text = "PING: {ms} ms"
            color = Get-PingColor(ms)
            label.ForeColor = color
            Update-TrayIcon(color.R, color.G, color.B)
        ELSE:
            label.Text = "PING: TIMEOUT"
            label.ForeColor = Red
            Update-TrayIcon(255, 0, 0)

        stats = Get-PingStats()
        tip = "Ping Overlay\n{stats}"
        IF tip.Length > 63: tip = tip[0..62]  // NotifyIcon API limit
        trayIcon.Text = tip

    ELSE (game not running):
        IF gameWasRunning:  // Game just exited
            IF overlayVisible:
                ShowWindow(SW_HIDE)  // IMMEDIATELY hide
                overlayVisible = false
            IF lastGameSeenAt is null: lastGameSeenAt = now
            elapsed = now - lastGameSeenAt
            IF elapsed >= GameExitGraceSeconds:
                gameWasRunning = false  // Fully reset
                trayText = "Ping Overlay - Waiting..."
                trayIcon = grey
            RETURN  // Skip ping while in grace period
        ELSE:
            RETURN  // Idle — just waiting for game

CATCH:
    label.Text = "PING: ERROR"
    label.ForeColor = Red
    Write-Log("Tick error: ...")
```

---

### 8.19 Entry Point (Lines 916–951)

```
1. $Host.UI.RawUI.WindowTitle = "Ping Overlay"
2. [Win32]::RegisterCloseHandler()          // Instant kill on console close
3. Show-SettingsWindow -IsStartup           // Modal dialog
4. IF settingsDialogResult != 'OK':
       dispose tray icon, log, exit
5. Re-apply font and timer interval from config
6. Write-Log "Ping Overlay started"
7. $script:timer.Start()
8. [Application]::Run($script:form)         // Enter WinForms message loop
9. ON CATCH: log, dispose tray, re-throw
```

---

## 9. Complete Function Reference

| # | Function | Parameters | Returns | Line | Description |
|---|---|---|---|---|---|
| 1 | `Write-Log` | `[string]$Message` | void | 46 | Appends timestamped message to overlay.log |
| 2 | `Load-Config` | none | hashtable | 261 | Loads config.json or creates defaults; returns merged config |
| 3 | `Save-Config` | `[hashtable]$cfg` | void | 293 | Serializes config to config.json |
| 4 | `Add-PingResult` | `[object]$ms` | void | 309 | Adds ping result to rolling history; null = timeout |
| 5 | `Get-PingStats` | none | string | 319 | Returns formatted min/avg/max/loss stats string |
| 6 | `Load-OverlayOffsets` | none | int[2] | 336 | Reads overlay_position.txt; returns [x, y] |
| 7 | `Save-OverlayOffsets` | `[int]$x, [int]$y` | void | 349 | Writes x,y to overlay_position.txt |
| 8 | `Get-PingMs` | `[string]$Target` | int or null | 358 | Sends one ICMP ping; returns ms or null on failure |
| 9 | `Is-GameRunning` | none | bool | 374 | Checks if game process exists |
| 10 | `Get-GameProcessIds` | none | int[] | 378 | Returns all PIDs for the game process name |
| 11 | `Get-WindowClassName` | `[IntPtr]$hWnd` | string | 384 | P/Invoke: GetClassName wrapper |
| 12 | `Get-UwpFrameWindowByProcessId` | `[int[]]$GameProcessIds` | IntPtr or null | 391 | Finds ApplicationFrameWindow hosting the game |
| 13 | `Get-TopLevelGameWindow` | `[int[]]$GameProcessIds` | IntPtr or null | 416 | Finds top-level window by PID (non-UWP fallback) |
| 14 | `Get-ForegroundHostWindow` | `[int[]]$GameProcessIds` | IntPtr or null | 436 | Checks if foreground window belongs to game |
| 15 | `Get-GameWindowRect` | `[int[]]$GameProcessIds` | Win32+RECT or null | 457 | Returns game window rect or null |
| 16 | `Get-PingColor` | `[int]$ms` | Color | 485 | Maps latency to green→yellow→red Color |
| 17 | `Get-StartupShortcutPath` | none | string | 502 | Returns shell:Startup\PingOverlay.lnk path |
| 18 | `Set-AutoStart` | `[bool]$Enable` | void | 506 | Creates/removes startup shortcut |
| 19 | `Show-SettingsWindow` | `[switch]$IsStartup` | void | 532 | Shows modal settings dialog |
| 20 | `Create-TrayIcon` | `[int]$r, $g, $b` | Icon | 679 | Creates a 16×16 colored circle icon |
| 21 | `Update-TrayIcon` | `[int]$r, $g, $b` | void | 704 | Updates tray icon only if color changed |

---

## 10. Complete Variable Reference

### Script-Scope Variables (`$script:`)

| Variable | Type | Initial Value | Description |
|---|---|---|---|
| `Config` | hashtable | from `Load-Config` | Current configuration |
| `PingHistory` | `List<int>` | empty | Rolling 60-sample ping history |
| `PingTimeouts` | int | 0 | Timeout counter |
| `PingTotal` | int | 0 | Total ping attempts |
| `form` | Form | (created) | The overlay window |
| `label` | OutlinedLabel | (created) | The ping text label |
| `timer` | Timer | (created) | WinForms timer for main loop |
| `trayIcon` | NotifyIcon | (created) | System tray icon |
| `trayIconR/G/B` | int | 128 each | Cached tray icon color |
| `overlayHandle` | IntPtr | Zero | HWND of overlay form |
| `overlayVisible` | bool | false | Current visibility state |
| `offsetX` | int | from file or 10 | X offset from game window |
| `offsetY` | int | from file or 248 | Y offset from game window |
| `lastRect` | Win32+RECT | null | Last known game window rect |
| `dragging` | bool | false | Whether user is dragging |
| `start` | Point | — | Cursor position at drag start |
| `loc` | Point | — | Form position at drag start |
| `lastGameSeenAt` | DateTime | null | Last time game process was seen |
| `gameWasRunning` | bool | false | Was game running last tick |
| `settingsDialogResult` | string | null | 'OK' or 'Cancel' |
| `uwpFrame` | IntPtr | — | Temp: during UWP frame search |
| `foundCore` | IntPtr | — | Temp: UWP child match |
| `gameWindow` | IntPtr | — | Temp: top-level window search |
| `foundChild` | bool | — | Temp: foreground child match |

### File-Scope Variables

| Variable | Type | Value | Description |
|---|---|---|---|
| `$ScriptDir` | string | from env var | Script directory (no trailing `\`) |
| `$LogFile` | string | `$ScriptDir\overlay.log` | Log file path |
| `$ConfigFile` | string | `$ScriptDir\config.json` | Config file path |
| `$SettingsFile` | string | `$ScriptDir\overlay_position.txt` | Position file path |
| `$MaxHistory` | int | `60` | Max ping samples in history |
| `$SW_HIDE` | int | `0` | ShowWindow constant |
| `$SW_SHOWNOACTIVATE` | int | `4` | ShowWindow constant |
| `$myPid` | int | `$PID` | Current process ID |

---

## 11. All User Interactions

| Interaction | Where | Effect |
|---|---|---|
| Double-click `PingOverlay.bat` | File Explorer | Launches overlay (startup dialog appears) |
| Click "Start Overlay" | Startup dialog | Saves config, starts overlay |
| Close startup dialog (X) | Startup dialog | Cancels, exits cleanly |
| Press Enter | Startup dialog | Same as clicking the button (AcceptButton) |
| Left-click drag on overlay text | Overlay | Repositions; saves offset on mouse-up |
| Right-click on overlay text | Overlay | Closes overlay (exits app) |
| Scroll wheel on overlay text | Overlay | Adjusts opacity ±5% (range 20–100%) |
| Right-click tray icon | System tray | Opens context menu |
| Double-click tray icon | System tray | Toggles overlay visibility |
| Hover tray icon | System tray | Shows tooltip: stats (min/avg/max/loss) |
| Tray → Show/Hide Overlay | Context menu | Toggles overlay visibility |
| Tray → Settings | Context menu | Opens settings dialog (runtime, live changes) |
| Tray → Auto-Start with Windows | Context menu | Toggles startup shortcut (checkbox) |
| Tray → Reset Stats | Context menu | Clears ping history and counters |
| Tray → Exit | Context menu | Exits app |
| Close PowerShell window (X) | Taskbar | **Instant kill** via RegisterCloseHandler |

---

## 12. Startup Flow — Step by Step

1. User double-clicks `PingOverlay.bat`
2. **Batch header** sets `PING_DIR` and `PING_BAT` environment variables
3. Batch launches `pwsh.exe -STA -NoProfile` minimized via `start /min`
4. Batch exits (`exit /b`)
5. PowerShell reads the entire file; lines 1–7 are a block comment
6. **Line 30:** `$ScriptDir = $env:PING_DIR.TrimEnd('\')`
7. **Lines 35–40:** Kills any prior PingOverlay pwsh instances
8. **Lines 57–64:** Loads `System.Windows.Forms` and `System.Drawing`
9. **Lines 70–153:** Compiles `Win32` C# class (P/Invoke) if not already loaded
10. **Lines 162–254:** Pre-loads PS7 DLLs, compiles `OutlinedLabel` C# control
11. **Lines 258–299:** Loads `config.json` (or creates defaults)
12. **Lines 304–307:** Initializes empty ping statistics
13. **Lines 670–674:** `EnableVisualStyles()`, `SetCompatibleTextRenderingDefault(false)`
14. **Lines 697–711:** Creates grey tray icon, sets text "Ping Overlay - Waiting..."
15. **Lines 714–755:** Creates dark-themed context menu, attaches to tray
16. **Lines 761–804:** Creates overlay form (borderless, transparent, Opacity=0, hidden)
17. **Lines 807–829:** Registers mouse handlers (drag, right-click, scroll wheel)
18. **Lines 834–914:** Creates WinForms timer, registers tick handler (NOT started yet)
19. **Line 920:** Sets console window title to "Ping Overlay"
20. **Line 923:** Registers `CTRL_CLOSE_EVENT` handler for instant kill
21. **Line 926:** Shows startup settings dialog (modal, blocks here)
22. If user clicks "Start Overlay": `settingsDialogResult = 'OK'`
23. If user closes via X: `settingsDialogResult = 'Cancel'` → dispose tray → exit
24. **Lines 935–937:** Re-apply font and timer interval from (possibly changed) config
25. **Line 939:** Log "Ping Overlay started"
26. **Line 940:** `$script:timer.Start()` — main loop begins
27. **Line 943:** `[Application]::Run($script:form)` — enters WinForms message loop, blocks until form closes

---

## 13. Runtime Flow — Per Timer Tick

```
┌─ Get-GameProcessIds()
│
├─ Game RUNNING? (ids.Count > 0)
│  │
│  ├─ YES:
│  │  ├─ lastGameSeenAt = now
│  │  ├─ If first detection → gameWasRunning = true, tray = "Running"
│  │  │
│  │  ├─ Get-GameWindowRect(ids)
│  │  │  ├─ NULL → hide overlay if visible
│  │  │  └─ FOUND:
│  │  │     ├─ lastRect = rect
│  │  │     ├─ If hidden → restore opacity, show (SW_SHOWNOACTIVATE)
│  │  │     ├─ Re-assert TopMost = true
│  │  │     └─ If not dragging → move to (rect.Left+offsetX, rect.Top+offsetY)
│  │  │
│  │  ├─ ms = Get-PingMs(ServerIP)
│  │  ├─ Add-PingResult(ms)
│  │  │
│  │  ├─ If ms ≠ null:
│  │  │  ├─ label = "PING: {ms} ms"
│  │  │  ├─ label.ForeColor = Get-PingColor(ms)
│  │  │  └─ Update-TrayIcon(color)
│  │  │
│  │  ├─ If ms = null:
│  │  │  ├─ label = "PING: TIMEOUT" (red)
│  │  │  └─ Update-TrayIcon(red)
│  │  │
│  │  └─ Update tray tooltip (stats, capped at 63 chars)
│  │
│  └─ NO:
│     ├─ Was gameWasRunning?
│     │  ├─ YES:
│     │  │  ├─ IMMEDIATELY hide overlay
│     │  │  ├─ elapsed = now - lastGameSeenAt
│     │  │  ├─ If elapsed ≥ GameExitGraceSeconds:
│     │  │  │  ├─ gameWasRunning = false
│     │  │  │  ├─ tray = "Waiting..." (grey)
│     │  │  └─ return (skip ping)
│     │  │
│     │  └─ NO:
│     │     └─ return (idle, waiting for game)
│
└─ CATCH any exception:
   ├─ label = "PING: ERROR" (red)
   └─ Write-Log("Tick error: ...")
```

---

## 14. Shutdown Flow

### Clean Exit (Tray → Exit or Right-Click Overlay)

1. `$script:trayIcon.Visible = $false`
2. `$script:trayIcon.Dispose()`
3. `$script:form.Close()`
4. `FormClosing` event fires → disposes tray (safety net for double-dispose, no-ops if already disposed)
5. `Application.Run()` returns
6. Script ends naturally

### Console Close (Taskbar X Button)

1. `CTRL_CLOSE_EVENT` (type 2) fires
2. `RegisterCloseHandler` callback runs: `Process.GetCurrentProcess().Kill()`
3. Process terminates **immediately** — no cleanup, no WinForms finalization
4. Tray icon may briefly linger as a ghost until user hovers over it

### Startup Cancellation

1. User closes startup dialog via X button
2. `FormClosing` → `settingsDialogResult = 'Cancel'`
3. Entry point checks: `if ($script:settingsDialogResult -ne 'OK')`
4. Disposes tray icon, logs "Startup cancelled by user", calls `exit`

---

## 15. Known Edge Cases & How They're Handled

| # | Edge Case | Handling |
|---|---|---|
| 1 | **Game not yet started** | Timer ticks return early. Overlay stays hidden (Opacity=0, SW_HIDE). Tray shows grey "Waiting..." |
| 2 | **Game minimized** | If `ShowOnlyWhenForeground=true`: overlay hides when game loses focus |
| 3 | **Game exits** | Overlay hidden **immediately** (not after grace period). Grace period only delays state reset. |
| 4 | **Game briefly restarts** | Grace period keeps `gameWasRunning=true`, so overlay quickly reappears without "Waiting" flicker |
| 5 | **User clicks the overlay** | `GetForegroundWindow()` returns overlay HWND → detected via `$script:overlayHandle` → returns `$script:lastRect` instead of null (prevents hide/show flicker) |
| 6 | **User drags the overlay** | `$script:dragging=true` prevents timer from repositioning during drag |
| 7 | **Multiple game instances** | All PIDs collected; first matching window used |
| 8 | **Network unreachable** | `Test-Connection` returns null → counted as timeout → "PING: TIMEOUT" displayed |
| 9 | **Server IP invalid** | Same as unreachable — timeout after ~4 seconds |
| 10 | **config.json corrupt/invalid JSON** | `try/catch` falls back to defaults for all keys |
| 11 | **config.json missing** | Created with defaults on first run |
| 12 | **config.json has extra keys** | Ignored (only known keys are read) |
| 13 | **config.json missing some keys** | Missing keys get default values (forward-compatible) |
| 14 | **overlay_position.txt corrupt** | Regex validation fails → falls back to `10,248` |
| 15 | **overlay_position.txt missing** | Falls back to `10,248` |
| 16 | **GDI handle leak (long runtime)** | `Update-TrayIcon` caches color — only recreates icon on change |
| 17 | **Console close hangs** | `Process.Kill()` via `SetConsoleCtrlHandler` for instant termination |
| 18 | **Overlay flash on startup** | Form starts at `Opacity=0` + `SW_HIDE`; opacity restored only when game detected |
| 19 | **C# type already loaded** | `if (-not ([PSTypeName]...).Type)` guards prevent recompilation errors |
| 20 | **PS7 assembly fragmentation** | All DLLs pre-loaded from pwsh dir before `Add-Type` |
| 21 | **Tooltip > 63 chars** | Truncated to 63 chars (Windows `NotifyIcon.Text` API limit) |
| 22 | **NumericUpDown out-of-range** | Values clamped with `Math.Max/Min` before assignment |
| 23 | **Duplicate overlay instances** | Bootstrap kills all other pwsh processes with 'PingOverlay' in CommandLine |
| 24 | **Game uses exclusive fullscreen** | WinForms overlay cannot appear over exclusive fullscreen. Game must use borderless windowed. |
| 25 | **Non-UWP game** | `Get-UwpFrameWindowByProcessId` returns null → falls back to `Get-TopLevelGameWindow` |
| 26 | **Overlay dragged off-screen** | Allowed (negative offsets supported). User can reset via overlay_position.txt deletion. |

---

## 16. Past Bugs That Were Fixed (History)

| # | Bug | Root Cause | Fix |
|---|---|---|---|
| 1 | **Blue-bordered window appeared when switching tabs before game started** | Overlay form was visible with default WinForms border before game was detected | Set `Opacity=0` at creation + `SW_HIDE` in Shown event. Only show when game detected. |
| 2 | **Brief overlay flash on startup** | Even with `SW_HIDE`, the form rendered one frame before hide took effect | Added `Opacity=0` at form creation time (line 770). Opacity restored to config value only on first game detection. |
| 3 | **GDI handle leak after hours of running** | `Create-TrayIcon` was called every tick (1/sec), allocating a new Bitmap+Icon each time without disposing the old one promptly | Added `Update-TrayIcon` with cached `R/G/B` comparison. Icon only recreated when color changes. Old icon explicitly disposed. |
| 4 | **Console window took 5–10 seconds to close from taskbar** | `Environment.Exit(0)` triggered WinForms finalization which hung on pending message loop work | Changed to `Process.GetCurrentProcess().Kill()` in the `CTRL_CLOSE_EVENT` handler for instant termination. |
| 5 | **Overlay stayed visible after game exited** | Overlay was only hidden after the full grace period elapsed | Changed: overlay hides **immediately** when game process disappears. Grace period only delays internal state reset. |
| 6 | **Text showed "MC5 PING:" or inconsistent naming** | Leftover references from original MC5-specific version mixed with renamed "UWP Apps Ping Overlay" | Standardized all user-visible strings to "Ping Overlay" (app name) and "PING:" (label prefix). Zero MC5/UWP references remain. |
| 7 | **Stale "MC5" text appeared from cached old pwsh process** | `Add-Type` compiled types persist in the AppDomain and cannot be reloaded | Documented that all old pwsh instances must be killed after code changes. Bootstrap auto-kills old instances on new launch. |

---

## 17. Potential Future Enhancements (Roadmap)

### Easy (< 1 hour)

- **Save opacity on scroll wheel** — Call `Save-Config` after scroll-wheel opacity change (currently in-memory only)
- **Log file rotation** — Check `overlay.log` size on startup; rename to `.log.bak` if > 1 MB
- **Configurable color thresholds** — Add `GreenMaxMs`, `YellowMaxMs` to config for custom color breakpoints
- **Sound alert on high ping** — `[System.Media.SystemSounds]::Beep.Play()` when ms > threshold
- **Custom overlay text prefix** — Config key like `OverlayPrefix = "PING:"` so users can change it

### Medium (1–4 hours)

- **Multi-server ping** — Comma-separated IPs, show lowest/average
- **Ping history sparkline** — Small graphical bar chart rendered in the overlay
- **Global hotkey toggle** — Register a system-wide hotkey (e.g., Ctrl+Shift+P) to show/hide
- **Multiple overlay labels** — Additional lines showing packet loss %, jitter, etc.
- **Configurable text format** — Template string like `"{ping} ms | {loss}%"`
- **Import/export config** — Copy/paste JSON from settings dialog
- **Minimize to tray on startup** — Console window starts minimized (already mostly done)

### Hard (4+ hours)

- **Async ping** — Use `System.Net.NetworkInformation.Ping.SendPingAsync()` to avoid blocking the UI thread
- **RTSS integration** — Send data to RivaTuner Statistics Server OSD (works with exclusive fullscreen)
- **DirectX overlay** — Inject overlay into game's rendering pipeline
- **Per-game profiles** — Different config for different `GameProcessName` values
- **Auto-detect server IP** — `Get-NetTCPConnection` to find game server connections
- **Tray icon with ping number** — Render actual ms value as tiny text on 16×16 icon
- **Multi-monitor support** — Correctly position overlay when game is on secondary monitor
- **Portable mode** — Detect if running from USB drive; adjust paths accordingly

---

## 18. Developer Notes & Gotchas

### ⚠️ C# Types Are Cached Per-Process

Once `Add-Type` compiles `Win32` and `OutlinedLabel`, they're loaded into the .NET AppDomain and **cannot be unloaded, changed, or recompiled** without killing the `pwsh.exe` process. The `if (-not ([PSTypeName]...).Type)` guards prevent "type already exists" errors but also prevent picking up code changes.

**Workflow:** After modifying any C# code in the `Add-Type @"..."@` blocks, you MUST:
1. Kill all `pwsh.exe` processes
2. Re-launch `PingOverlay.bat`

### ⚠️ WinForms Requires -STA

The `-STA` flag on the `pwsh` command line is **mandatory**. WinForms controls require Single-Threaded Apartment mode. Without it, forms may crash with COM threading exceptions, especially `ShowDialog()`, `NotifyIcon`, and clipboard operations.

### ⚠️ Test-Connection Is Synchronous

`Test-Connection -Count 1` blocks for the ICMP timeout (~4 seconds) if the target is unreachable. During this time, the timer tick handler is running on the UI thread, so the overlay is unresponsive (no drag, no repaint, no other ticks).

**Mitigation for future:** Use `System.Net.NetworkInformation.Ping` with `.SendPingAsync()` and a PowerShell job or runspace.

### ⚠️ ShowWindow Constants Matter

- `SW_SHOW (5)` — Shows a window AND **steals focus**. This would cause the game to lose focus, potentially minimizing or deactivating.
- `SW_SHOWNOACTIVATE (4)` — Shows without stealing focus. **Always use this for the overlay.**

### ⚠️ TransparencyKey Color Choice

`RGB(1, 1, 1)` is used as both `BackColor` and `TransparencyKey`. Any pixel exactly matching this color becomes transparent and click-through. This is near-black. If a future design change introduces very dark UI elements close to `(1,1,1)`, they'll become invisible. Use a more unusual color like `RGB(255, 0, 255)` (magenta) if conflicts arise.

### ⚠️ NotifyIcon.Text 63-Char Limit

The Windows `NOTIFYICONDATA` structure limits tooltip text to 63 characters (127 for Unicode, but WinForms uses the 63-char path). The script truncates with `$tip.Substring(0, 63)`.

### ⚠️ Hashtable JSON Serialization

`ConvertTo-Json` on a PowerShell hashtable does NOT guarantee key order. The key order in `config.json` may change between saves. This is cosmetic only — functionality is not affected.

### ⚠️ ApplicationFrameWindow Detection

UWP apps use a two-layer window model:
- Parent: `ApplicationFrameWindow` (owned by `ApplicationFrameHost.exe`)
- Child: The actual game window (owned by the game process)

`GetWindowThreadProcessId()` on the parent returns the `ApplicationFrameHost` PID, NOT the game PID. You must enumerate child windows and check each child's PID to find the game.

### ⚠️ Grace Period Semantics

The grace period does NOT delay hiding the overlay. The overlay hides **immediately** when the game process disappears. The grace period only delays resetting `gameWasRunning` to `false` and changing the tray icon back to grey. This allows the overlay to quickly reappear if the game restarts within the grace period.

---

## 19. How to Adapt for a Different Game

### Step 1: Find the Process Name

1. Open the game
2. Open Task Manager → **Details** tab (not Processes)
3. Find the game's executable (e.g., `FortniteClient-Win64-Shipping.exe`)
4. The process name for config is everything before `.exe`: `FortniteClient-Win64-Shipping`

### Step 2: Find the Server IP

While the game is running, in PowerShell:

```powershell
Get-NetTCPConnection -OwningProcess (Get-Process -Name "YOUR_PROCESS_NAME").Id |
Where-Object { $_.State -eq 'Established' -and $_.RemoteAddress -notmatch '^(10\.|172\.(1[6-9]|2|3[01])\.|192\.168\.|127\.)' } |
Select-Object RemoteAddress, RemotePort
```

Or: Resource Monitor → Network → TCP Connections → filter by process.

### Step 3: Update Configuration

Either:
- Edit `config.json` directly
- Use the startup settings dialog to change "Server IP" and "Game Process Name"

### Non-UWP (Regular Win32) Games

Works out of the box. `Get-UwpFrameWindowByProcessId` returns null for non-UWP apps, and the fallback `Get-TopLevelGameWindow` finds regular windows by PID.

### Exclusive Fullscreen Games

The WinForms overlay **cannot** appear over exclusive fullscreen. The game must be in **borderless windowed** or **windowed** mode. This is a fundamental Windows limitation — only DirectX/Vulkan hook overlays (like MSI Afterburner / RivaTuner) can render over exclusive fullscreen.

---

## 20. Naming Convention Notes

All user-visible strings follow this convention:

| Context | Text |
|---|---|
| App name (window titles, tray, dialogs) | `"Ping Overlay"` |
| Overlay label (in-game text) | `"PING: <value> ms"` / `"PING: TIMEOUT"` / `"PING: ERROR"` / `"PING: --- ms"` |
| Tray status | `"Ping Overlay - Waiting..."` / `"Ping Overlay - Running"` |
| Console window title | `"Ping Overlay"` |
| Settings dialog titles | `"Ping Overlay - Configure & Start"` / `"Ping Overlay - Settings"` |
| Startup shortcut | `PingOverlay.lnk`, description `"Ping Overlay"` |
| Log messages | `"Ping Overlay started"` |

**There are zero references to "MC5", "UWP Apps", or any game-specific name in any user-visible text.** The only remaining "UWP" reference is in a code comment on line 371 explaining the Windows architecture.

---

*Last updated: February 27, 2026*
*Source file: `PingOverlay.bat` — 951 lines, ~40 KB, single-file polyglot (Batch + PowerShell + inline C#)*

