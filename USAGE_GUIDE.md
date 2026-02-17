# How to Use MC5 Ping Monitor Scripts

This repository provides **two different methods** to monitor your Modern Combat 5 ping while gaming. Choose the one that works best for you!

---

## 🎯 Method 1: Direct Overlay (NEW - Recommended)

**Best for:** Users who want a simple, standalone overlay that only appears when the MC5 game is running.

### Features
- ✅ Automatically appears when MC5 game window is active
- ✅ Automatically hides when game is minimized
- ✅ No additional software (RTSS/MSI Afterburner) required
- ✅ Draggable overlay - position it anywhere
- ✅ Color-coded ping (Cyan = good, Yellow = fair, Red = poor)

### Quick Start

1. **Navigate to the `new` folder** in your ping check directory
2. **Double-click `StartPingOverlay.bat`**
3. **Launch MC5** - The overlay will appear automatically when the game window is visible
4. **Done!** The ping overlay will show in the top-left corner

### How It Works

- The script waits for `WindowsEntryPoint.Windows_W10.exe` (MC5 Windows Store) to start
- When the game window is visible, the overlay appears
- When you minimize the game, the overlay automatically hides
- When you close the game, the overlay closes too

### Customization

**Move the overlay:**
- Simply click and drag it to your preferred position

**Close the overlay:**
- Right-click on the overlay and it will close

**Change ping update interval:**
- Edit `new/PingOverlay.ps1`
- Find the line: `$PingInterval = 1000`
- Change `1000` to your preferred milliseconds (1000 = 1 second)

---

## 🎯 Method 2: RTSS/MSI Afterburner Integration

**Best for:** Users who already use MSI Afterburner/RTSS for monitoring FPS, CPU, GPU, etc.

### Prerequisites
- Install **RivaTuner Statistics Server (RTSS)** or **MSI Afterburner** (includes RTSS)

### Quick Start

#### Step 1: Start the Ping Monitor

Double-click `StartPingMonitor.bat` in the main folder

**Alternative:** You can also use `new/StartPingWriter.bat` for a slightly different implementation

#### Step 2: Configure RTSS Overlay

1. Open **RivaTuner Statistics Server**
2. Click the **"Setup"** button or **"..."** button next to "On-Screen Display preset"
3. This opens the **Overlay Editor**
4. Right-click → **Add** → **Text**
5. Add this text:
   ```
   MC5 PING: <File=C:\Users\Harsh Raj\Desktop\ping check\ping_data.txt> ms
   ```
   **Or if using PingWriter:**
   ```
   MC5 PING: %File(C:\ProgramData\ping_value.txt)% ms
   ```
6. Position it where you want on the overlay
7. Save the preset

#### Step 3: Game!

- The ping will now appear in your RTSS overlay along with your other stats
- When done gaming, double-click `StopPingMonitor.bat` to stop the monitor

### Auto-Start Option

To automatically start the ping monitor when Windows starts:
1. Press `Win + R`
2. Type: `shell:startup` and press Enter
3. Create a shortcut to `StartPingMonitor.bat` in this folder

---

## 📁 File Reference

### Main Folder Files

| File | Purpose |
|------|---------|
| `StartPingMonitor.bat` | Start RTSS-compatible ping monitor |
| `StopPingMonitor.bat` | Stop the ping monitor |
| `PingMonitor.ps1` | Core monitoring script (RTSS version) |
| `ping_data.txt` | Auto-generated ping data file |

### New Folder Files (`new/`)

| File | Purpose |
|------|---------|
| `StartPingOverlay.bat` | **Start the direct overlay (Method 1)** |
| `PingOverlay.ps1` | Direct overlay script with window detection |
| `StartPingWriter.bat` | Alternative RTSS ping writer |
| `PingWriter.ps1` | Alternative RTSS monitoring script |

---

## 🎨 Understanding Ping Colors (Method 1 - Direct Overlay)

The overlay changes color based on your ping:

- **🔵 Cyan (Blue):** Less than 100ms - Excellent connection
- **🟡 Yellow:** 100-200ms - Fair connection, playable
- **🔴 Red:** Over 200ms or TIMEOUT - Poor connection

---

## ⚙️ Configuration

### Change MC5 Server IP

If you need to ping a different server:

1. Edit `PingMonitor.ps1` or `new/PingOverlay.ps1`
2. Find the line: `$ServerIP = "198.136.44.61"`
3. Change to your preferred server IP
4. Save the file

### Change Ping Interval

**For Direct Overlay (Method 1):**
- Edit `new/PingOverlay.ps1`
- Find: `$PingInterval = 1000` (in milliseconds)
- Change to desired interval (e.g., 2000 = 2 seconds)

**For RTSS Method (Method 2):**
- Edit `PingMonitor.ps1`
- Find: `$PingInterval = 1` (in seconds)
- Change to desired interval (e.g., 2 = 2 seconds)

---

## 🔧 Troubleshooting

### Direct Overlay (Method 1)

**Overlay doesn't appear:**
- Make sure MC5 game (`WindowsEntryPoint.Windows_W10.exe`) is running
- Check that the game window is not minimized
- Verify the script is running (check Task Manager for PowerShell)

**Overlay appears but shows "---" or "TIMEOUT":**
- Check your internet connection
- The MC5 server (198.136.44.61) may be temporarily down
- Try pinging manually: `ping 198.136.44.61` in Command Prompt

### RTSS Method (Method 2)

**Ping not showing in RTSS overlay:**
- Make sure `StartPingMonitor.bat` is running
- Check that `ping_data.txt` exists and contains a number
- Verify RTSS overlay is enabled for your game
- Check the file path in your RTSS configuration matches the actual file location

**Ping shows "ERROR":**
- The ping monitor may not be running
- Check internet connection
- Restart `StartPingMonitor.bat`

---

## 🚀 Quick Comparison

| Feature | Method 1: Direct Overlay | Method 2: RTSS |
|---------|-------------------------|----------------|
| **Setup Complexity** | Very Easy | Moderate |
| **Additional Software** | None | Requires RTSS |
| **Auto-hide when minimized** | ✅ Yes | ❌ No |
| **Integrates with other stats** | ❌ No | ✅ Yes |
| **Customization** | Limited | Extensive |
| **Best for** | Simple ping monitoring | Full system monitoring |

---

## 💡 Tips

1. **For best results with Method 1:** Start the overlay before launching the game, or just double-click the bat file and it will wait for the game to start
2. **Performance:** Both methods are lightweight and won't impact game performance
3. **Multiple monitors:** The overlay can be positioned on any monitor
4. **Testing:** Run the scripts before gaming to ensure everything works

---

## 📝 Need More Help?

- Check `README.md` for the original RTSS setup instructions
- Check `RTSS_SETUP.md` for detailed RTSS configuration
- Check `VERIFICATION.md` for technical details about the overlay fix

---

**Recommended:** Try **Method 1 (Direct Overlay)** first - it's simpler and specifically designed for MC5!
