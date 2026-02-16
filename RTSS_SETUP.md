# How to Add MC5 Ping to MSI Afterburner Overlay

## Step 1: Run the Ping Writer
1. Double-click `StartPingWriter.bat`
2. Keep the window running in background while gaming
3. It writes ping values to `C:\ProgramData\ping_value.txt`

---

## Step 2: Configure RTSS to Display Ping

### Option A: Using RTSS Overlay Editor (Recommended)

1. Open **RivaTuner Statistics Server**
2. Click the **"..." button** next to "On-Screen Display preset" 
3. This opens the **Overlay Editor**
4. Add a new text item with this content:
   ```
   MC5 PING: %File(C:\ProgramData\ping_value.txt)% ms
   ```
5. Position it where you want
6. Save the preset

### Option B: Edit RTSS Overlay Layout File Directly

1. Navigate to RTSS installation folder (usually `C:\Program Files (x86)\RivaTuner Statistics Server`)
2. Open `Profiles` folder
3. Find or create a profile for your game
4. Edit the `.ovl` file and add:
   ```
   MC5 PING: %File(C:\ProgramData\ping_value.txt)% ms
   ```

---

## Files Created

| File | Purpose |
|------|---------|
| `PingWriter.ps1` | Pings server, writes to file |
| `StartPingWriter.bat` | Easy launcher |
| `C:\ProgramData\ping_value.txt` | Ping value file (read by RTSS) |

---

## Troubleshooting

**Ping not showing in overlay?**
- Make sure `StartPingWriter.bat` is running
- Check that `C:\ProgramData\ping_value.txt` exists and has a number
- Verify RTSS is enabled for your game

**Want to auto-start?**
- Add shortcut to `StartPingWriter.bat` in Windows Startup folder
