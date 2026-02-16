# MC5 Ping Overlay - Setup Instructions

`Need claude to fix this code as it doesnt actually points to the window of the game and points to any window, i want this overlay to be only shown in my MC5 windows store app game whose process name is always gonna be WindowsEntryPoint.Windows_W10.exe`

## Quick Start

### Step 1: Test the Ping Monitor
1. Open PowerShell in `c:\Users\Harsh Raj\Desktop\ping check`
2. Run: `.\PingMonitor.ps1`
3. You should see ping values updating. Press `Ctrl+C` to stop.

### Step 2: Configure RTSS Overlay Editor

1. **Open RivaTuner Statistics Server** (RTSS)
2. Click the **"Setup"** button
3. Go to **"On-Screen Display"** tab
4. Click **"Raster 3D"** or your preferred rendering mode
5. Click **"..."** next to "On-Screen Display Layout" to open **Overlay Editor**

### Step 3: Add Ping to Overlay

In the **Overlay Editor**, you need to add a text layer that reads from the ping file:

1. Right-click → **Add** → **Text**
2. Set the text to display your ping. Use this format:
   ```
   MC5 PING: <File=c:\Users\Harsh Raj\Desktop\ping check\ping_data.txt> ms
   ```
3. Position it below your existing stats
4. Set color to match your theme (yellow/green recommended)

### Step 4: Start Monitoring Before Gaming

**Option A: Manual Start**
- Double-click `StartPingMonitor.bat` before launching your game

**Option B: Auto-Start with Game**
- Add a shortcut to `StartPingMonitor.bat` in your Windows Startup folder
- Or create a shortcut that launches both the monitor and your game

### Step 5: Stop Monitoring
- Double-click `StopPingMonitor.bat` when done gaming

---

## File Locations

| File | Purpose |
|------|---------|
| [PingMonitor.ps1](file:///c:/Users/Harsh%20Raj/Desktop/ping%20check/PingMonitor.ps1) | Main ping monitoring script |
| [StartPingMonitor.bat](file:///c:/Users/Harsh%20Raj/Desktop/ping%20check/StartPingMonitor.bat) | Start monitor (hidden window) |
| [StopPingMonitor.bat](file:///c:/Users/Harsh%20Raj/Desktop/ping%20check/StopPingMonitor.bat) | Stop monitor |
| `ping_data.txt` | Auto-generated file with current ping value |

---

## Troubleshooting

**Overlay not showing ping?**
- Make sure `StartPingMonitor.bat` is running
- Check that `ping_data.txt` exists and contains a number
- Verify RTSS overlay is enabled for your game

**Ping shows "TIMEOUT"?**
- Check your internet connection
- The MC5 server (198.136.44.61) may be temporarily unreachable

**Want to change ping interval?**
- Edit `PingMonitor.ps1` and change `$PingInterval = 1` to your preferred seconds
