<# :
@echo off
set "PING_DIR=%~dp0"
set "PING_BAT=%~f0"
start "Ping Overlay" pwsh -NoProfile -STA -ExecutionPolicy Bypass -Command "iex (Get-Content -Raw -LiteralPath $env:PING_BAT)"
exit /b
#>

#.SYNOPSIS
#   Ping Overlay v2.2
#
#.DESCRIPTION
#   Transparent, always-on-top latency overlay for any app/game.
#   Displays real-time ping with color-coded status, system tray integration,
#   user-configurable settings, and session statistics.
#
#   This is a polyglot file: the batch header (lines 1-6) bootstraps pwsh;
#   PowerShell sees those lines as a block comment.
#
#.NOTES
#   Runtime:      PowerShell 7+ (pwsh)
#   Dependencies: System.Windows.Forms, System.Drawing (.NET)
#   Config:       config.json  (auto-generated on first run)
#   Persistence:  overlay_position.txt
#   Log:          overlay.log
#
#.LINK
#   https://github.com/user/ping-overlay

if ($env:PING_DIR) {
    $ScriptDir = $env:PING_DIR.TrimEnd('\')
} else {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
}

# ── Bootstrap ────────────────────────────────────────────────────
# Kill any prior instance so we never run duplicates.

$myPid = $PID
Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue |
Where-Object { $_.ProcessId -ne $myPid -and $_.CommandLine -match 'PingOverlay' } |
ForEach-Object {
    try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
}

# ── Logging ──────────────────────────────────────────────────────

$LogFile = Join-Path $ScriptDir "overlay.log"
$LogMaxSize = 512KB  # Rotate log when it exceeds 512 KB

function Write-Log {
    param([string]$Message)
    try {
        # Rotate log if it grows too large
        if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt $LogMaxSize) {
            $oldLog = "$LogFile.old"
            if (Test-Path $oldLog) { Remove-Item $oldLog -Force }
            Rename-Item $LogFile $oldLog -Force
        }
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        "$timestamp  $Message" | Out-File -FilePath $LogFile -Encoding ASCII -Append
    }
    catch {}
}

# ── .NET Assemblies ──────────────────────────────────────────────

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}
catch {
    Write-Log "Failed to load Windows Forms assemblies: $($_.Exception.Message)"
    throw
}

# ── Win32 Interop ────────────────────────────────────────────────
# P/Invoke declarations for window enumeration, positioning,
# visibility control, and console close handling.

if (-not ([System.Management.Automation.PSTypeName]'Win32').Type) {
    try {
        Add-Type @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class Win32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hWndParent, EnumChildProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr hIcon);

    public delegate bool ConsoleCtrlDelegate(int ctrlType);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetConsoleCtrlHandler(ConsoleCtrlDelegate handler, bool add);

    // Static field prevents the delegate from being garbage-collected.
    private static ConsoleCtrlDelegate _handler;

    /// <summary>
    /// Intercepts CTRL_CLOSE_EVENT (type 2) so the process exits
    /// immediately when the user closes the console from the taskbar.
    /// </summary>
    public static void RegisterCloseHandler() {
        _handler = new ConsoleCtrlDelegate(ctrlType => {
            if (ctrlType == 2) {
                // Force-kill immediately — WinForms cleanup hangs otherwise.
                System.Diagnostics.Process.GetCurrentProcess().Kill();
            }
            return false;
        });
        SetConsoleCtrlHandler(_handler, true);
    }

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    public const int GWL_EXSTYLE    = -20;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const int WS_EX_APPWINDOW  = 0x00040000;

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left, Top, Right, Bottom;
    }
}
"@
    }
    catch {
        Write-Log "Failed to load Win32 interop: $($_.Exception.Message)"
        throw
    }
}

# ── OutlinedLabel Control ────────────────────────────────────────
# Custom WinForms control that renders text with a configurable
# outline via GDI+ GraphicsPath, matching the MSI Afterburner style.
#
# PS7 splits types across many assemblies (e.g. System.Drawing.Primitives),
# so we load all matching DLLs from the pwsh directory before compiling.

if (-not ([System.Management.Automation.PSTypeName]'OutlinedLabel').Type) {
    try {
        # Resolve the PowerShell runtime directory for DLL loading.
        # When running as .exe (ps2exe), MainModule points to the exe itself,
        # so we fall back to the runtime assembly directory.
        $psDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
        $psExeTest = Join-Path $psDir 'System.Drawing.dll'
        if (-not (Test-Path $psExeTest)) {
            # Fallback: use the directory of the System.Drawing assembly already loaded
            $drawingAsm = [System.AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object { -not $_.IsDynamic -and $_.Location -and $_.GetName().Name -eq 'System.Drawing' } |
                Select-Object -First 1
            if ($drawingAsm) {
                $psDir = [System.IO.Path]::GetDirectoryName($drawingAsm.Location)
            } else {
                # Last resort: use the runtime directory
                $psDir = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
            }
        }
        Get-ChildItem -Path $psDir -Filter '*.dll' | Where-Object {
            $_.Name -match 'System\.(Drawing|Windows\.Forms|ComponentModel)'
        } | ForEach-Object {
            try { [System.Reflection.Assembly]::LoadFrom($_.FullName) | Out-Null } catch {}
        }

        $refAssemblies = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { -not $_.IsDynamic -and $_.Location -and $_.Location -match '\.(dll|exe)$' -and $_.Location -notmatch 'PingOverlay' } |
        ForEach-Object { $_.Location }

        Add-Type -ReferencedAssemblies $refAssemblies -TypeDefinition @"
using System;
using System.Drawing;
using System.Windows.Forms;

public class OutlinedLabel : Control {
    public Color OutlineColor { get; set; }
    public int OutlineWidth { get; set; }

    public OutlinedLabel() {
        this.SetStyle(ControlStyles.UserPaint |
                      ControlStyles.AllPaintingInWmPaint |
                      ControlStyles.OptimizedDoubleBuffer |
                      ControlStyles.ResizeRedraw |
                      ControlStyles.SupportsTransparentBackColor, true);
        this.DoubleBuffered = true;
        this.OutlineColor = Color.Black;
        this.OutlineWidth = 1;
        this.BackColor = Color.Transparent;
        this.AutoSize = true;
    }

    protected override void OnTextChanged(EventArgs e)   { base.OnTextChanged(e);   UpdateSize(); }
    protected override void OnFontChanged(EventArgs e)    { base.OnFontChanged(e);    UpdateSize(); }
    protected override void OnPaddingChanged(EventArgs e) { base.OnPaddingChanged(e); UpdateSize(); }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode      = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
        e.Graphics.TextRenderingHint  = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
        e.Graphics.PixelOffsetMode    = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
        e.Graphics.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;

        string text = this.Text ?? "";
        if (text.Length == 0) return;

        Font font = this.Font ?? Control.DefaultFont;
        int ow = Math.Max(1, this.OutlineWidth);
        Padding pad = this.Padding;

        using (var path = new System.Drawing.Drawing2D.GraphicsPath()) {
            float emSize = e.Graphics.DpiY * font.Size / 72f;
            using (var sf = new StringFormat(StringFormat.GenericTypographic)) {
                sf.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;
                path.AddString(text, font.FontFamily, (int)font.Style, emSize,
                               new PointF(pad.Left + ow, pad.Top + ow), sf);
            }

            using (var pen = new Pen(this.OutlineColor, ow * 2 + 1)) {
                pen.LineJoin = System.Drawing.Drawing2D.LineJoin.Round;
                pen.MiterLimit = 2;
                e.Graphics.DrawPath(pen, path);
            }
            using (var brush = new SolidBrush(this.ForeColor)) {
                e.Graphics.FillPath(brush, path);
            }
        }
    }

    private void UpdateSize() {
        if (this.AutoSize) this.Size = GetPreferredSize(Size.Empty);
        this.Invalidate();
    }

    public override Size GetPreferredSize(Size proposedSize) {
        string text = this.Text ?? "";
        Font font = this.Font ?? Control.DefaultFont;
        Size size = TextRenderer.MeasureText(text, font,
                        new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
        int ow = Math.Max(1, this.OutlineWidth);
        Padding pad = this.Padding;
        return new Size(size.Width  + pad.Left + pad.Right  + ow * 2,
                        size.Height + pad.Top  + pad.Bottom + ow * 2);
    }
}
"@
    }
    catch {
        Write-Log "Failed to load OutlinedLabel: $($_.Exception.Message)"
        throw
    }
}

# ── Configuration ────────────────────────────────────────────────

$ConfigFile   = Join-Path $ScriptDir "config.json"
$SettingsFile = Join-Path $ScriptDir "overlay_position.txt"

function Load-Config {
    $defaults = @{
        ServerIP               = ""
        PingIntervalMs         = 1000
        GameProcessName        = ""
        ShowOnlyWhenForeground = $true
        GameExitGraceSeconds   = 15
        FontSize               = 14
        FontFamily             = "Consolas"
        OverlayOpacity         = 1.0
        AutoStart              = $false
        DarkMode               = $true
    }
    if (Test-Path $ConfigFile) {
        try {
            $json = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
            $keyList = [string[]]($defaults.Keys)
            foreach ($key in $keyList) {
                if ($json.PSObject.Properties[$key]) { $defaults[$key] = $json.$key }
            }
        }
        catch { Write-Log "Failed to read config: $($_.Exception.Message)" }
    }
    else {
        # First launch — persist defaults so the user can edit them.
        try {
            $defaults | ConvertTo-Json -Depth 2 | Out-File -FilePath $ConfigFile -Encoding UTF8
            Write-Log "Created default config.json"
        }
        catch { Write-Log "Failed to create default config: $($_.Exception.Message)" }
    }
    return $defaults
}

function Save-Config {
    param([hashtable]$cfg)
    try { $cfg | ConvertTo-Json -Depth 2 | Out-File -FilePath $ConfigFile -Encoding UTF8 }
    catch { Write-Log "Failed to save config: $($_.Exception.Message)" }
}

$script:Config = Load-Config

# ── Ping Statistics ──────────────────────────────────────────────
# Rolling window of the last N samples, plus timeout tracking.

$script:PingHistory  = [System.Collections.Generic.List[int]]::new()
$script:PingTimeouts = 0
$script:PingTotal    = 0
$MaxHistory          = 60

function Add-PingResult {
    param([object]$ms)
    $script:PingTotal++
    if ($null -eq $ms) { $script:PingTimeouts++ }
    else {
        if ($script:PingHistory.Count -ge $MaxHistory) { $script:PingHistory.RemoveAt(0) }
        $script:PingHistory.Add([int]$ms)
    }
}

function Get-PingStats {
    $count = $script:PingHistory.Count
    if ($count -eq 0) { return "No data yet" }
    $min = ($script:PingHistory | Measure-Object -Minimum).Minimum
    $max = ($script:PingHistory | Measure-Object -Maximum).Maximum
    $avg = [math]::Round(($script:PingHistory | Measure-Object -Average).Average, 0)
    $loss = if ($script:PingTotal -gt 0) {
        [math]::Round(($script:PingTimeouts / $script:PingTotal) * 100, 1)
    } else { 0 }
    return "Ping: Min $min / Avg $avg / Max $max ms`nLoss: $loss% ($($script:PingTimeouts)/$($script:PingTotal))`nSamples: $count"
}

# ── Window Management ────────────────────────────────────────────
# ShowWindow constants
$SW_HIDE           = 0
$SW_SHOWNOACTIVATE = 4

function Load-OverlayOffsets {
    if (Test-Path $SettingsFile) {
        try {
            $raw = Get-Content -Path $SettingsFile -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($raw -match '^\s*(-?\d+)\s*,\s*(-?\d+)\s*$') {
                return @([int]$matches[1], [int]$matches[2])
            }
        }
        catch { Write-Log "Failed to read settings: $($_.Exception.Message)" }
    }
    return @(10, 248)
}

function Save-OverlayOffsets {
    param([int]$x, [int]$y)
    try { "$x,$y" | Out-File -FilePath $SettingsFile -Encoding ASCII -NoNewline }
    catch { Write-Log "Failed to save settings: $($_.Exception.Message)" }
}

# ── Network ──────────────────────────────────────────────────────
# Compatible with both PS 5.1 (ResponseTime) and PS 7+ (Latency).

function Get-PingMs {
    param([string]$Target)
    if ([string]::IsNullOrWhiteSpace($Target)) { return $null }
    try { $ping = Test-Connection -ComputerName $Target -Count 1 -ErrorAction SilentlyContinue }
    catch { return $null }
    if (-not $ping) { return $null }
    $reply = if ($ping -is [array]) { $ping[0] } else { $ping }
    if ($reply.PSObject.Properties['ResponseTime'])  { return [int]$reply.ResponseTime }
    if ($reply.PSObject.Properties['Latency'])        { return [int]$reply.Latency }
    if ($reply.PSObject.Properties['RoundtripTime'])  { return [int]$reply.RoundtripTime }
    return $null
}

# ── Game Process Detection ───────────────────────────────────────
# Game/UWP apps run hosted inside ApplicationFrameWindow.
# We enumerate all top-level windows and match by process ID.

function Get-GameProcessIds {
    $procs = Get-Process -Name $script:Config.GameProcessName -ErrorAction SilentlyContinue
    if (-not $procs) { return @() }
    return @($procs.Id)
}

function Get-WindowClassName {
    param([IntPtr]$hWnd)
    $sb = New-Object System.Text.StringBuilder 256
    [Win32]::GetClassName($hWnd, $sb, $sb.Capacity) | Out-Null
    return $sb.ToString()
}

function Get-UwpFrameWindowByProcessId {
    param([int[]]$GameProcessIds)
    $script:uwpFrame = [IntPtr]::Zero
    $callback = {
        param([IntPtr]$hWnd, [IntPtr]$lParam)
        $class = Get-WindowClassName -hWnd $hWnd
        if ($class -ne "ApplicationFrameWindow") { return $true }
        $childCallback = {
            param([IntPtr]$child, [IntPtr]$lParamChild)
            $procId = 0
            [Win32]::GetWindowThreadProcessId($child, [ref]$procId) | Out-Null
            if ($GameProcessIds -contains $procId) { $script:foundCore = $child; return $false }
            return $true
        }
        $script:foundCore = [IntPtr]::Zero
        [Win32]::EnumChildWindows($hWnd, $childCallback, [IntPtr]::Zero) | Out-Null
        if ($script:foundCore -eq [IntPtr]::Zero) { return $true }
        $script:uwpFrame = $hWnd
        return $false
    }
    [Win32]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
    if ($script:uwpFrame -eq [IntPtr]::Zero) { return $null }
    return $script:uwpFrame
}

function Get-TopLevelGameWindow {
    param([int[]]$GameProcessIds)
    $script:gameWindow = [IntPtr]::Zero
    $callback = {
        param([IntPtr]$hWnd, [IntPtr]$lParam)
        $procId = 0
        [Win32]::GetWindowThreadProcessId($hWnd, [ref]$procId) | Out-Null
        if ($GameProcessIds -notcontains $procId) { return $true }
        $rect = New-Object Win32+RECT
        if (-not [Win32]::GetWindowRect($hWnd, [ref]$rect)) { return $true }
        $w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
        if ($w -lt 100 -or $h -lt 100) { return $true }
        $script:gameWindow = $hWnd
        return $false
    }
    [Win32]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
    if ($script:gameWindow -eq [IntPtr]::Zero) { return $null }
    return $script:gameWindow
}

function Get-ForegroundHostWindow {
    param([int[]]$GameProcessIds)
    $fg = [Win32]::GetForegroundWindow()
    if ($fg -eq [IntPtr]::Zero) { return $null }
    $procId = 0
    [Win32]::GetWindowThreadProcessId($fg, [ref]$procId) | Out-Null
    if ($GameProcessIds -contains $procId) { return $fg }
    # Check whether the foreground ApplicationFrameWindow hosts the game.
    $script:foundChild = $false
    $childCallback = {
        param([IntPtr]$child, [IntPtr]$lParamChild)
        $childProcId = 0
        [Win32]::GetWindowThreadProcessId($child, [ref]$childProcId) | Out-Null
        if ($GameProcessIds -contains $childProcId) { $script:foundChild = $true; return $false }
        return $true
    }
    [Win32]::EnumChildWindows($fg, $childCallback, [IntPtr]::Zero) | Out-Null
    if ($script:foundChild) { return $fg }
    return $null
}

function Get-GameWindowRect {
    param([int[]]$GameProcessIds)
    if ($script:Config.ShowOnlyWhenForeground) {
        $fg = [Win32]::GetForegroundWindow()
        # Keep last position if the overlay itself has focus (avoids flicker).
        if ($script:overlayHandle -ne [IntPtr]::Zero -and $fg -eq $script:overlayHandle -and $script:lastRect) {
            return $script:lastRect
        }
        $frame = Get-ForegroundHostWindow -GameProcessIds $GameProcessIds
        if ($null -eq $frame) { return $null }
    }
    else {
        $frame = Get-UwpFrameWindowByProcessId -GameProcessIds $GameProcessIds
        if ($null -eq $frame) {
            $frame = Get-TopLevelGameWindow -GameProcessIds $GameProcessIds
            if ($null -eq $frame) { return $null }
        }
    }
    $rect = New-Object Win32+RECT
    if (-not [Win32]::GetWindowRect($frame, [ref]$rect)) { return $null }
    $w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
    if ($w -le 0 -or $h -le 0) { return $null }
    return $rect
}

# ── Window Capture ──────────────────────────────────────────────
# Allows the user to pick any visible window and overlay ping on it.

$script:capturedHwnd = [IntPtr]::Zero

function Get-WindowTitle {
    param([IntPtr]$hWnd)
    $len = [Win32]::GetWindowTextLength($hWnd)
    if ($len -le 0) { return "" }
    $sb = New-Object System.Text.StringBuilder ($len + 1)
    [Win32]::GetWindowText($hWnd, $sb, $sb.Capacity) | Out-Null
    return $sb.ToString()
}

function Show-WindowPicker {
    param([System.Windows.Forms.Form]$ParentForm = $null)

    # Countdown capture: gives the user 5 seconds to switch to the target window.
    # We track the foreground window on EVERY tick so we remember the last window
    # the user switched to, even if focus returns to us when the dialog closes.

    $parentWasVisible = $false
    if ($null -ne $ParentForm -and $ParentForm.Visible) {
        $parentWasVisible = $true
        $ParentForm.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
    }

    $countdownForm = New-Object System.Windows.Forms.Form
    $countdownForm.Text            = "Capture Window"
    $countdownForm.Size            = New-Object System.Drawing.Size(360, 200)
    $countdownForm.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $countdownForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedToolWindow
    $countdownForm.BackColor       = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $countdownForm.ForeColor       = [System.Drawing.Color]::White
    $countdownForm.Font            = New-Object System.Drawing.Font("Segoe UI", 10)
    $countdownForm.TopMost         = $true
    $countdownForm.ShowInTaskbar   = $false

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text      = "Switch to the window you want to capture..."
    $lblInfo.Location  = New-Object System.Drawing.Point(20, 18)
    $lblInfo.AutoSize  = $true
    $lblInfo.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $countdownForm.Controls.Add($lblInfo)

    $lblTarget = New-Object System.Windows.Forms.Label
    $lblTarget.Text      = ""
    $lblTarget.Location  = New-Object System.Drawing.Point(20, 42)
    $lblTarget.Size      = New-Object System.Drawing.Size(310, 18)
    $lblTarget.ForeColor = [System.Drawing.Color]::FromArgb(0, 200, 100)
    $lblTarget.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $countdownForm.Controls.Add($lblTarget)

    $lblCountdown = New-Object System.Windows.Forms.Label
    $lblCountdown.Text      = "5"
    $lblCountdown.Font      = New-Object System.Drawing.Font("Segoe UI", 36, [System.Drawing.FontStyle]::Bold)
    $lblCountdown.ForeColor = [System.Drawing.Color]::FromArgb(0, 180, 255)
    $lblCountdown.AutoSize  = $true
    $lblCountdown.Location  = New-Object System.Drawing.Point(153, 60)
    $countdownForm.Controls.Add($lblCountdown)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text      = "Cancel"
    $btnCancel.Size      = New-Object System.Drawing.Size(100, 32)
    $btnCancel.Location  = New-Object System.Drawing.Point(125, 125)
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.FlatAppearance.BorderSize = 1
    $btnCancel.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $btnCancel.Cursor    = [System.Windows.Forms.Cursors]::Hand

    $script:captureCountdown = 5
    $script:captureCancelled = $false
    $script:pickerResult     = $null
    # Track the last valid external window seen during countdown
    $script:lastSeenFg       = [IntPtr]::Zero
    $script:lastSeenProcName = ""
    $script:lastSeenTitle    = ""
    $script:lastSeenProcId   = 0

    $captureTimer = New-Object System.Windows.Forms.Timer
    $captureTimer.Interval = 1000

    $btnCancel.Add_Click({
        $script:captureCancelled = $true
        $captureTimer.Stop()
        $captureTimer.Dispose()
        $countdownForm.Close()
    })
    $countdownForm.Controls.Add($btnCancel)

    $captureTimer.Add_Tick({
        $myPid = $PID
        $consoleH = [Win32]::GetConsoleWindow()

        # On every tick, check what's in the foreground and remember it
        # (so we don't lose it when focus snaps back to us later)
        $fg = [Win32]::GetForegroundWindow()
        if ($fg -ne [IntPtr]::Zero -and $fg -ne $consoleH -and $fg -ne $countdownForm.Handle) {
            $fgProcId = [uint32]0
            [Win32]::GetWindowThreadProcessId($fg, [ref]$fgProcId) | Out-Null

            # Resolve UWP: ApplicationFrameWindow hosts the real app as a child
            $realPid = $fgProcId
            $fgClass = Get-WindowClassName -hWnd $fg
            if ($fgClass -eq 'ApplicationFrameWindow') {
                $script:uwpChildPid = 0
                $framePid = $fgProcId
                $childCb = {
                    param([IntPtr]$child, [IntPtr]$lParam)
                    $cPid = [uint32]0
                    [Win32]::GetWindowThreadProcessId($child, [ref]$cPid) | Out-Null
                    if ($cPid -ne 0 -and $cPid -ne $framePid) {
                        $script:uwpChildPid = $cPid
                        return $false
                    }
                    return $true
                }
                [Win32]::EnumChildWindows($fg, $childCb, [IntPtr]::Zero) | Out-Null
                if ($script:uwpChildPid -ne 0) { $realPid = $script:uwpChildPid }
            }

            if ([int]$realPid -ne $myPid) {
                $script:lastSeenFg = $fg
                $script:lastSeenProcId = [int]$realPid
                try {
                    $p = Get-Process -Id ([int]$realPid) -ErrorAction SilentlyContinue
                    if ($p) { $script:lastSeenProcName = $p.ProcessName }
                } catch {}
                $script:lastSeenTitle = Get-WindowTitle -hWnd $fg
                # Show what we're tracking in the countdown dialog
                $shortTitle = $script:lastSeenTitle
                if ($shortTitle.Length -gt 40) { $shortTitle = $shortTitle.Substring(0, 40) + "..." }
                $lblTarget.Text = "Target: $shortTitle"
            }
        }

        $script:captureCountdown--
        if ($script:captureCountdown -le 0) {
            $captureTimer.Stop()
            $captureTimer.Dispose()

            # Use the last external window we saw during the countdown
            if ($script:lastSeenFg -ne [IntPtr]::Zero) {
                $script:pickerResult = @{
                    Handle      = $script:lastSeenFg
                    Title       = $script:lastSeenTitle
                    ProcessName = $script:lastSeenProcName
                }
            }
            $countdownForm.Close()
        }
        else {
            $lblCountdown.Text = "$($script:captureCountdown)"
            if ($script:captureCountdown -ge 3) {
                $lblCountdown.ForeColor = [System.Drawing.Color]::FromArgb(0, 180, 255)
            } elseif ($script:captureCountdown -eq 2) {
                $lblCountdown.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 0)
            } else {
                $lblCountdown.ForeColor = [System.Drawing.Color]::FromArgb(255, 80, 80)
            }
        }
    })

    $countdownForm.Add_FormClosed({
        if ($null -ne $captureTimer) {
            try { $captureTimer.Stop(); $captureTimer.Dispose() } catch {}
        }
    })

    $captureTimer.Start()
    $countdownForm.ShowDialog() | Out-Null
    $countdownForm.Dispose()

    # Restore the parent form
    if ($parentWasVisible -and $null -ne $ParentForm) {
        $ParentForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $ParentForm.BringToFront()
    }

    if ($script:captureCancelled) { return $null }
    return $script:pickerResult
}

# ── Color Interpolation ─────────────────────────────────────────
# Maps latency to a smooth green → yellow → red gradient.

function Get-PingColor {
    param([int]$ms)
    if ($ms -le 100) {
        $t = [math]::Min(1.0, $ms / 100.0)
        $r = [int]($t * 255); $g = 255; $b = 0
    }
    elseif ($ms -le 250) {
        $t = [math]::Min(1.0, ($ms - 100) / 150.0)
        $r = 255; $g = [int]((1 - $t) * 255); $b = 0
    }
    else { $r = 255; $g = 0; $b = 0 }
    return [System.Drawing.Color]::FromArgb($r, $g, $b)
}

# ── Auto-Start ───────────────────────────────────────────────────
# Creates/removes a shortcut in shell:Startup.

function Get-StartupShortcutPath {
    return Join-Path ([System.Environment]::GetFolderPath('Startup')) "PingOverlay.lnk"
}

function Set-AutoStart {
    param([bool]$Enable)
    $shortcutPath = Get-StartupShortcutPath
    if ($Enable) {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath       = Join-Path $ScriptDir "PingOverlay.bat"
            $shortcut.WorkingDirectory = $ScriptDir
            $shortcut.Description      = "Ping Overlay"
            $shortcut.WindowStyle      = 7  # SW_SHOWMINNOACTIVE
            $shortcut.Save()
            $script:Config.AutoStart = $true
            Save-Config -cfg $script:Config
        }
        catch { Write-Log "Failed to create startup shortcut: $($_.Exception.Message)" }
    }
    else {
        if (Test-Path $shortcutPath) { Remove-Item -Path $shortcutPath -Force -ErrorAction SilentlyContinue }
        $script:Config.AutoStart = $false
        Save-Config -cfg $script:Config
    }
}

# ── Theme System ─────────────────────────────────────────────────
# Returns a hashtable of colors based on current dark/light mode.

function Get-Theme {
    if ($script:Config.DarkMode) {
        return @{
            FormBg       = [System.Drawing.Color]::FromArgb(18, 18, 24)      # near-black
            PanelBg      = [System.Drawing.Color]::FromArgb(28, 28, 36)      # card bg
            InputBg      = [System.Drawing.Color]::FromArgb(40, 40, 52)      # input bg
            BorderColor  = [System.Drawing.Color]::FromArgb(60, 60, 80)      # subtle border
            AccentColor  = [System.Drawing.Color]::FromArgb(0, 150, 255)     # blue accent
            AccentHover  = [System.Drawing.Color]::FromArgb(30, 170, 255)
            BtnBg        = [System.Drawing.Color]::FromArgb(45, 45, 60)      # secondary btn
            TextPrimary  = [System.Drawing.Color]::FromArgb(240, 240, 245)
            TextSecond   = [System.Drawing.Color]::FromArgb(160, 160, 180)
            TextHint     = [System.Drawing.Color]::FromArgb(90, 90, 110)
            SepColor     = [System.Drawing.Color]::FromArgb(50, 50, 65)
            SuccessColor = [System.Drawing.Color]::FromArgb(0, 200, 100)
            DangerColor  = [System.Drawing.Color]::FromArgb(255, 80, 80)
            LabelSection = [System.Drawing.Color]::FromArgb(100, 100, 130)
        }
    } else {
        return @{
            FormBg       = [System.Drawing.Color]::FromArgb(245, 245, 250)
            PanelBg      = [System.Drawing.Color]::FromArgb(255, 255, 255)
            InputBg      = [System.Drawing.Color]::FromArgb(255, 255, 255)
            BorderColor  = [System.Drawing.Color]::FromArgb(200, 200, 215)
            AccentColor  = [System.Drawing.Color]::FromArgb(0, 120, 215)
            AccentHover  = [System.Drawing.Color]::FromArgb(0, 100, 190)
            BtnBg        = [System.Drawing.Color]::FromArgb(230, 230, 240)
            TextPrimary  = [System.Drawing.Color]::FromArgb(20, 20, 30)
            TextSecond   = [System.Drawing.Color]::FromArgb(60, 60, 80)
            TextHint     = [System.Drawing.Color]::FromArgb(140, 140, 160)
            SepColor     = [System.Drawing.Color]::FromArgb(210, 210, 225)
            SuccessColor = [System.Drawing.Color]::FromArgb(0, 150, 70)
            DangerColor  = [System.Drawing.Color]::FromArgb(200, 40, 40)
            LabelSection = [System.Drawing.Color]::FromArgb(100, 100, 130)
        }
    }
}

# ── Settings Window ──────────────────────────────────────────────

function Apply-Theme {
    param($theme, $controls)
    # Called after theme switch to recolor all registered controls.
    # $controls is a hashtable: { 'form' => form, 'inputs' => @(...), 'labels' => @(...), etc. }
    try {
        if ($null -ne $controls.form) {
            $controls.form.BackColor = $theme.FormBg
            $controls.form.ForeColor = $theme.TextPrimary
        }
        foreach ($c in $controls.inputs)  { $c.BackColor = $theme.InputBg;  $c.ForeColor = $theme.TextPrimary }
        foreach ($c in $controls.labels)  { $c.ForeColor = $theme.TextSecond }
        foreach ($c in $controls.secHdrs) { $c.ForeColor = $theme.LabelSection }
        foreach ($c in $controls.btns)    { $c.BackColor = $theme.BtnBg; $c.ForeColor = $theme.TextPrimary; if ($c.FlatAppearance) { $c.FlatAppearance.BorderColor = $theme.BorderColor } }
        foreach ($c in $controls.seps)    { $c.BackColor = $theme.SepColor }
        foreach ($c in $controls.chks)    { $c.ForeColor = $theme.TextSecond }

        # specific primary buttons
        if ($null -ne $controls.btnSave) {
            $controls.btnSave.BackColor = $theme.AccentColor
            $controls.btnSave.ForeColor = [System.Drawing.Color]::White
        }
    } catch {}
}

function Show-SettingsWindow {
    param([switch]$IsStartup)

    $theme = Get-Theme
    $W = 480; $H = 640

    $settingsForm = New-Object System.Windows.Forms.Form
    $settingsForm.Text            = if ($IsStartup) { "Ping Overlay" } else { "Ping Overlay — Settings" }
    $settingsForm.Size            = New-Object System.Drawing.Size($W, $H)
    $settingsForm.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $settingsForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
    $settingsForm.MaximizeBox     = $false
    $settingsForm.MinimizeBox     = $true
    $settingsForm.BackColor       = $theme.FormBg
    $settingsForm.ForeColor       = $theme.TextPrimary
    $settingsForm.Font            = New-Object System.Drawing.Font("Segoe UI", 10)
    $settingsForm.TopMost         = $true

    # Pop up on top initially, then drop TopMost so it goes behind
    # other windows when the user clicks away from it.
    $script:settingsTopMostTimer = $null
    $script:settingsFormRef = $settingsForm
    $settingsForm.Add_Shown({
        # Restore from minimized if needed (e.g. if parent process started minimized)
        if ($script:settingsFormRef.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            $script:settingsFormRef.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }
        # Force the window to the absolute front on startup
        $script:settingsFormRef.Activate()
        $script:settingsFormRef.BringToFront()
        [Win32]::SetForegroundWindow($script:settingsFormRef.Handle) | Out-Null

        # After a short delay, drop TopMost so the dialog behaves normally:
        # it stays on screen but goes behind other windows when user clicks away.
        $script:settingsTopMostTimer = New-Object System.Windows.Forms.Timer
        $script:settingsTopMostTimer.Interval = 500
        $script:settingsTopMostTimer.Add_Tick({
            try {
                if ($null -ne $script:settingsFormRef -and -not $script:settingsFormRef.IsDisposed) {
                    $script:settingsFormRef.TopMost = $false
                }
            } catch {}
            $script:settingsTopMostTimer.Stop()
            $script:settingsTopMostTimer.Dispose()
            $script:settingsTopMostTimer = $null
        })
        $script:settingsTopMostTimer.Start()
    })
    $settingsForm.Add_FormClosed({
        if ($null -ne $script:settingsTopMostTimer) {
            $script:settingsTopMostTimer.Stop()
            $script:settingsTopMostTimer.Dispose()
            $script:settingsTopMostTimer = $null
        }
    })

    # Track whether user confirmed or cancelled (X button).
    $script:settingsDialogResult = $null
    if ($IsStartup) {
        $settingsForm.Add_FormClosing({
            param($s, $e)
            if ($null -eq $script:settingsDialogResult) {
                $script:settingsDialogResult = 'Cancel'
            }
        })
    }

    # Theme controls registry for live theme switching
    $script:themeControls = @{
        form   = $settingsForm
        inputs = @()
        labels = @()
        btns   = @()
        seps   = @()
        secHdrs = @()
        chks = @()
        btnSave = $null
    }

    # ── Layout constants ──────────────────────────────────────────
    $PAD   = 24          # outer padding
    $ROW_H = 44          # height per field row
    $LBL_W = 170         # label column width
    $INP_W = 210         # input column width
    $INP_X = $PAD + $LBL_W + 8   # input X position
    $FULL_W = $W - $PAD * 2 - 2  # full-width control width
    $y = $PAD

    $hintColor   = $theme.TextHint
    $textColor   = $theme.TextPrimary

    # Helper: horizontal separator line
    function Add-Separator($yRef) {
        $sep = New-Object System.Windows.Forms.Panel
        $sep.Location = New-Object System.Drawing.Point($PAD, $yRef.Value)
        $sep.Size     = New-Object System.Drawing.Size($FULL_W, 1)
        $sep.BackColor = $theme.SepColor
        $settingsForm.Controls.Add($sep)
        $yRef.Value += 12
        $script:themeControls.seps += $sep
        return $sep
    }

    # Helper: section header label
    function Add-SectionHeader($text, $yRef) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text     = $text.ToUpper()
        $lbl.Location = New-Object System.Drawing.Point($PAD, $yRef.Value)
        $lbl.AutoSize = $true
        $lbl.Font     = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
        $lbl.ForeColor = $theme.LabelSection
        $settingsForm.Controls.Add($lbl)
        $yRef.Value += 22
        $script:themeControls.secHdrs += $lbl
        return $lbl
    }

    # Helper: row with label + TextBox
    function Add-Row-Text($labelText, $value, $placeholder, $yRef) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text      = $labelText
        $lbl.Location  = New-Object System.Drawing.Point($PAD, ($yRef.Value + 5))
        $lbl.Size      = New-Object System.Drawing.Size($LBL_W, 22)
        $lbl.ForeColor = $theme.TextSecond
        $settingsForm.Controls.Add($lbl)

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Location    = New-Object System.Drawing.Point($INP_X, ($yRef.Value + 2))
        $txt.Size        = New-Object System.Drawing.Size($INP_W, 28)
        $txt.BackColor   = $theme.InputBg
        $txt.ForeColor   = if ([string]::IsNullOrWhiteSpace($value)) { $hintColor } else { $textColor }
        $txt.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $txt.Text        = if ([string]::IsNullOrWhiteSpace($value)) { $placeholder } else { $value }
        $settingsForm.Controls.Add($txt)

        # Placeholder clear/restore
        if (-not [string]::IsNullOrWhiteSpace($placeholder)) {
            $txt.Add_GotFocus({
                if ($txt.Text -eq $placeholder) { $txt.Text = ""; $txt.ForeColor = $textColor }
            })
            $txt.Add_LostFocus({
                if ([string]::IsNullOrWhiteSpace($txt.Text)) { $txt.Text = $placeholder; $txt.ForeColor = $hintColor }
            })
        }
        $yRef.Value += $ROW_H
        $script:themeControls.inputs += $txt
        $script:themeControls.labels += $lbl
        return @{ lbl = $lbl; txt = $txt }
    }

    # Helper: row with label + NumericUpDown
    function Add-Row-Numeric($labelText, $value, $min, $max, $step, $yRef) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text      = $labelText
        $lbl.Location  = New-Object System.Drawing.Point($PAD, ($yRef.Value + 5))
        $lbl.Size      = New-Object System.Drawing.Size($LBL_W, 22)
        $lbl.ForeColor = $theme.TextSecond
        $settingsForm.Controls.Add($lbl)

        $num = New-Object System.Windows.Forms.NumericUpDown
        $num.Minimum       = $min; $num.Maximum = $max; $num.Increment = $step
        $num.DecimalPlaces = if ($step -lt 1) { 2 } else { 0 }
        $num.Value         = [math]::Max($min, [math]::Min($max, $value))
        $num.Location      = New-Object System.Drawing.Point($INP_X, ($yRef.Value + 2))
        $num.Size          = New-Object System.Drawing.Size($INP_W, 28)
        $num.BackColor     = $theme.InputBg
        $num.ForeColor     = $textColor
        $settingsForm.Controls.Add($num)
        $yRef.Value += $ROW_H
        $script:themeControls.inputs += $num
        $script:themeControls.labels += $lbl
        return @{ lbl = $lbl; num = $num }
    }

    # ─────────────────────────────────────────────────────────────
    # HEADER BANNER
    # ─────────────────────────────────────────────────────────────
    $banner = New-Object System.Windows.Forms.Panel
    $banner.Location  = New-Object System.Drawing.Point(0, 0)
    $banner.Size      = New-Object System.Drawing.Size($W, 64)
    $banner.BackColor = $theme.AccentColor
    $settingsForm.Controls.Add($banner)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text      = "Ping Overlay"
    $lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.AutoSize  = $true
    $lblTitle.Location  = New-Object System.Drawing.Point(20, 10)
    $banner.Controls.Add($lblTitle)

    $lblSubtitle = New-Object System.Windows.Forms.Label
    $lblSubtitle.Text      = if ($IsStartup) { "Configure your ping overlay before starting" } else { "Adjust settings below" }
    $lblSubtitle.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(210, 230, 255)
    $lblSubtitle.AutoSize  = $true
    $lblSubtitle.Location  = New-Object System.Drawing.Point(22, 38)
    $banner.Controls.Add($lblSubtitle)

    $y = 76   # content starts below banner
    $y += 10  # top padding

    # ─────────────────────────────────────────────────────────────
    # SECTION: Network
    # ─────────────────────────────────────────────────────────────
    $secNet = Add-SectionHeader "Network" ([ref]$y)
    $rowServer   = Add-Row-Text   "Server IP"         $script:Config.ServerIP      "e.g. 8.8.8.8"     ([ref]$y)
    $txtServer   = $rowServer.txt
    $rowInterval = Add-Row-Numeric "Ping Interval (ms)" $script:Config.PingIntervalMs 200 10000 100 ([ref]$y)
    $numInterval = $rowInterval.num

    $sepNet = Add-Separator ([ref]$y)

    # ─────────────────────────────────────────────────────────────
    # SECTION: Target Application
    # ─────────────────────────────────────────────────────────────
    $secApp = Add-SectionHeader "Target Application" ([ref]$y)
    $rowProcess  = Add-Row-Text   "Process Name"      $script:Config.GameProcessName "(auto-filled by capture)" ([ref]$y)
    $txtProcess  = $rowProcess.txt

    # Capture row: button + status on a single line
    $btnCapture = New-Object System.Windows.Forms.Button
    $btnCapture.Text      = "●  Capture Window"
    $btnCapture.Size      = New-Object System.Drawing.Size(140, 30)
    $btnCapture.Location  = New-Object System.Drawing.Point($INP_X, ($y + 2))
    $btnCapture.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCapture.BackColor = $theme.BtnBg
    $btnCapture.ForeColor = $theme.TextPrimary
    $btnCapture.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnCapture.FlatAppearance.BorderSize  = 1
    $btnCapture.FlatAppearance.BorderColor = $theme.BorderColor
    $btnCapture.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $settingsForm.Controls.Add($btnCapture)

    $script:themeControls.btns += $btnCapture

    $lblCaptureStatus = New-Object System.Windows.Forms.Label
    $lblCaptureStatus.Location  = New-Object System.Drawing.Point($PAD, ($y + 8))
    $lblCaptureStatus.Size      = New-Object System.Drawing.Size($LBL_W, 20)
    $lblCaptureStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
    if ($script:capturedHwnd -ne [IntPtr]::Zero -and [Win32]::IsWindow($script:capturedHwnd)) {
        $captTitle = Get-WindowTitle -hWnd $script:capturedHwnd
        if ($captTitle.Length -gt 20) { $captTitle = $captTitle.Substring(0, 20) + "…" }
        $lblCaptureStatus.Text     = "✓ $captTitle"
        $lblCaptureStatus.ForeColor = $theme.SuccessColor
    } else {
        $lblCaptureStatus.Text      = "No window captured"
        $lblCaptureStatus.ForeColor = $theme.TextHint
    }
    $settingsForm.Controls.Add($lblCaptureStatus)

    $btnCapture.Add_Click({
        $result = Show-WindowPicker -ParentForm $settingsForm
        if ($null -ne $result) {
            $script:capturedHwnd = $result.Handle
            $txtProcess.Text     = $result.ProcessName
            $txtProcess.ForeColor = $textColor
            $captTitle = $result.Title
            if ($captTitle.Length -gt 20) { $captTitle = $captTitle.Substring(0, 20) + "…" }
            $lblCaptureStatus.Text      = "✓ $captTitle"
            $lblCaptureStatus.ForeColor = $theme.SuccessColor
            Write-Log "Captured window: '$($result.Title)' (Process: $($result.ProcessName), HWND $($result.Handle))"
        }
    })
    $y += $ROW_H

    $rowGrace = Add-Row-Numeric "Exit Grace (sec)" $script:Config.GameExitGraceSeconds 0 300 1 ([ref]$y)
    $numGrace = $rowGrace.num

    $chkForeground = New-Object System.Windows.Forms.CheckBox
    $chkForeground.Text      = "Show only when app is in foreground"
    $chkForeground.Checked   = $script:Config.ShowOnlyWhenForeground
    $chkForeground.Location  = New-Object System.Drawing.Point($PAD, ($y + 4))
    $chkForeground.AutoSize  = $true
    $chkForeground.ForeColor = $theme.TextSecond
    $chkForeground.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $settingsForm.Controls.Add($chkForeground)
    $y += $ROW_H

    $script:themeControls.chks += $chkForeground

    $sepApp = Add-Separator ([ref]$y)

    # ─────────────────────────────────────────────────────────────
    # SECTION: Overlay Appearance
    # ─────────────────────────────────────────────────────────────
    $secAppearance = Add-SectionHeader "Overlay Appearance" ([ref]$y)
    $script:themeControls.secHdrs += $secAppearance

    $rowFontSize   = Add-Row-Numeric  "Font Size"       $script:Config.FontSize       8    48   1    ([ref]$y)
    $numFont       = $rowFontSize.num
    $script:themeControls.inputs += $numFont
    $script:themeControls.labels += $rowFontSize.lbl

    $rowOpacity    = Add-Row-Numeric  "Opacity"         $script:Config.OverlayOpacity 0.20 1.00 0.05 ([ref]$y)
    $numOpacity    = $rowOpacity.num
    $script:themeControls.inputs += $numOpacity
    $script:themeControls.labels += $rowOpacity.lbl

    # Font Family row (ComboBox with preview)
    $lblFontFam = New-Object System.Windows.Forms.Label
    $lblFontFam.Text      = "Font Family"
    $lblFontFam.Location  = New-Object System.Drawing.Point($PAD, ($y + 5))
    $lblFontFam.Size      = New-Object System.Drawing.Size($LBL_W, 22)
    $lblFontFam.ForeColor = $theme.TextSecond
    $settingsForm.Controls.Add($lblFontFam)

    $txtFontFamily = New-Object System.Windows.Forms.ComboBox
    $txtFontFamily.DropDownStyle    = [System.Windows.Forms.ComboBoxStyle]::DropDown
    $txtFontFamily.Location         = New-Object System.Drawing.Point($INP_X, ($y + 2))
    $txtFontFamily.Size             = New-Object System.Drawing.Size($INP_W, 28)
    $txtFontFamily.BackColor        = $theme.InputBg
    $txtFontFamily.ForeColor        = $textColor
    $txtFontFamily.FlatStyle        = [System.Windows.Forms.FlatStyle]::Flat
    $txtFontFamily.DrawMode         = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $txtFontFamily.ItemHeight       = 22
    $txtFontFamily.MaxDropDownItems = 12
    $settingsForm.Controls.Add($txtFontFamily)
    $y += $ROW_H

    $script:themeControls.inputs += $txtFontFamily
    $script:themeControls.labels += $lblFontFam

    $overlayFonts = @("Consolas","Cascadia Mono","Courier New","Lucida Console","JetBrains Mono","Fira Code","Source Code Pro","Segoe UI","Verdana","Tahoma","Arial","Calibri")
    $installedFamilies = [System.Drawing.FontFamily]::Families | ForEach-Object { $_.Name }
    foreach ($fn in $overlayFonts) {
        if ($installedFamilies -contains $fn) { $txtFontFamily.Items.Add($fn) | Out-Null }
    }
    $txtFontFamily.Text = $script:Config.FontFamily

    $txtFontFamily.Add_DrawItem({
        param($sender, $e)
        if ($e.Index -lt 0) { return }

        # Use simple fallback if Get-Theme fails
        $isDark = $script:Config.DarkMode
        $bBg = if ($isDark) { [System.Drawing.Color]::FromArgb(40, 40, 52) } else { [System.Drawing.Color]::FromArgb(255, 255, 255) }
        $bFg = if ($isDark) { [System.Drawing.Color]::FromArgb(240, 240, 245) } else { [System.Drawing.Color]::FromArgb(20, 20, 30) }

        $isSelected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
        if ($isSelected) {
            $bBg = if ($isDark) { [System.Drawing.Color]::FromArgb(0, 150, 255) } else { [System.Drawing.Color]::FromArgb(0, 120, 215) }
            $bFg = [System.Drawing.Color]::White
        }

        $bgBrush = New-Object System.Drawing.SolidBrush($bBg)
        $e.Graphics.FillRectangle($bgBrush, $e.Bounds)
        $bgBrush.Dispose()

        $itemText = $sender.Items[$e.Index]
        $pf = $null
        try { $pf = New-Object System.Drawing.Font($itemText, 10) } catch { $pf = $e.Font }

        $fgBrush = New-Object System.Drawing.SolidBrush($bFg)
        $e.Graphics.DrawString($itemText, $pf, $fgBrush, ($e.Bounds.X + 4), ($e.Bounds.Y + 3))
        $fgBrush.Dispose()

        if ($pf -ne $e.Font) { $pf.Dispose() }
        $e.DrawFocusRectangle()
    })

    $btnToggleTheme = New-Object System.Windows.Forms.Button
    $btnToggleTheme.Text      = if ($script:Config.DarkMode) { "☀  Switch to Light Mode" } else { "🌙  Switch to Dark Mode" }
    $btnToggleTheme.Location  = New-Object System.Drawing.Point($PAD, ($y + 2))
    $btnToggleTheme.Size      = New-Object System.Drawing.Size(200, 30)
    $btnToggleTheme.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnToggleTheme.BackColor = $theme.BtnBg
    $btnToggleTheme.ForeColor = $theme.TextPrimary
    $btnToggleTheme.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnToggleTheme.FlatAppearance.BorderSize  = 1
    $btnToggleTheme.FlatAppearance.BorderColor = $theme.BorderColor
    $btnToggleTheme.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $settingsForm.Controls.Add($btnToggleTheme)
    $y += $ROW_H

    $script:themeControls.btns += $btnToggleTheme

    $btnToggleTheme.Add_Click({
        $script:Config.DarkMode = -not $script:Config.DarkMode
        Save-Config -cfg $script:Config

        $btnToggleTheme.Text = if ($script:Config.DarkMode) { "☀  Switch to Light Mode" } else { "🌙  Switch to Dark Mode" }

        # update context menu
        if ($null -ne $menuDarkMode) {
            $menuDarkMode.Text = $btnToggleTheme.Text
            Update-TrayMenuTheme
        }

        # apply to current window
        $newTheme = Get-Theme
        Apply-Theme -theme $newTheme -controls $script:themeControls
    })

    $sepApp2 = Add-Separator ([ref]$y)

    # ─────────────────────────────────────────────────────────────
    # SAVE BUTTON
    # ─────────────────────────────────────────────────────────────
    $btnText = if ($IsStartup) { "Start Overlay" } else { "Save & Apply" }
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text      = $btnText
    $btnSave.Size      = New-Object System.Drawing.Size($FULL_W, 44)
    $btnSave.Location  = New-Object System.Drawing.Point($PAD, ($y + 4))
    $btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSave.BackColor = $theme.AccentColor
    $btnSave.ForeColor = [System.Drawing.Color]::White
    $btnSave.Font      = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnSave.FlatAppearance.BorderSize = 0
    $btnSave.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $settingsForm.Controls.Add($btnSave)
    $settingsForm.AcceptButton = $btnSave
    $y += 56

    $script:themeControls.btnSave = $btnSave

    # Resize form to content
    $settingsForm.ClientSize = New-Object System.Drawing.Size($W, ($y + $PAD))

    $btnSave.Add_Click({
        $newProcessName = $txtProcess.Text.Trim()
        if ($newProcessName -eq "(auto-filled by capture)") { $newProcessName = "" }
        $serverIP = $txtServer.Text.Trim()
        if ($serverIP -eq "e.g. 8.8.8.8") { $serverIP = "" }
        if ($newProcessName -ne $script:Config.GameProcessName) {
            $script:gameWasRunning = $false
            $script:lastGameSeenAt = $null
        }
        $script:Config.ServerIP               = $serverIP
        $script:Config.PingIntervalMs          = [int]$numInterval.Value
        $script:Config.GameProcessName         = $newProcessName
        $script:Config.GameExitGraceSeconds    = [int]$numGrace.Value
        $script:Config.FontSize                = [int]$numFont.Value
        $script:Config.FontFamily              = $txtFontFamily.Text.Trim()
        $script:Config.OverlayOpacity          = [math]::Round([double]$numOpacity.Value, 2)
        $script:Config.ShowOnlyWhenForeground  = $chkForeground.Checked
        Save-Config -cfg $script:Config

        if ($null -ne $script:timer)  { $script:timer.Interval = $script:Config.PingIntervalMs }
        if ($null -ne $script:label) {
            try {
                $script:label.Font = New-Object System.Drawing.Font(
                    $script:Config.FontFamily, $script:Config.FontSize, [System.Drawing.FontStyle]::Bold)
            } catch {
                Write-Log "Invalid font '$($script:Config.FontFamily)', falling back to Consolas"
                $script:Config.FontFamily = "Consolas"
                $script:label.Font = New-Object System.Drawing.Font("Consolas", $script:Config.FontSize, [System.Drawing.FontStyle]::Bold)
            }
        }
        if ($null -ne $script:form -and $script:overlayVisible) { $script:form.Opacity = $script:Config.OverlayOpacity }

        $script:settingsDialogResult = 'OK'
        $settingsForm.Close()
    })

    $settingsForm.ShowDialog() | Out-Null
    $settingsForm.Dispose()
}


# ── UI Initialization ────────────────────────────────────────────

try {
    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
}
catch { Write-Log "Init error: $($_.Exception.Message)" }

# ── System Tray ──────────────────────────────────────────────────
# 16×16 filled circle icon; colour reflects current ping status.

function Create-TrayIcon {
    param([int]$r, [int]$g, [int]$b)
    $bmp = $null; $gfx = $null; $brush = $null; $pen = $null; $hIcon = [IntPtr]::Zero
    try {
        $bmp = New-Object System.Drawing.Bitmap(16, 16, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gfx = [System.Drawing.Graphics]::FromImage($bmp)
        $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $gfx.Clear([System.Drawing.Color]::Transparent)
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($r, $g, $b))
        $gfx.FillEllipse($brush, 1, 1, 13, 13)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60, 60, 60), 1)
        $gfx.DrawEllipse($pen, 1, 1, 13, 13)
        $pen.Dispose(); $pen = $null
        $brush.Dispose(); $brush = $null
        $gfx.Dispose(); $gfx = $null
        $hIcon = $bmp.GetHicon()
        $tempIcon = [System.Drawing.Icon]::FromHandle($hIcon)
        $icon = $tempIcon.Clone()
        $tempIcon.Dispose()
        [Win32]::DestroyIcon($hIcon) | Out-Null
        $hIcon = [IntPtr]::Zero
        $bmp.Dispose(); $bmp = $null
        return $icon
    }
    catch {
        if ($hIcon -ne [IntPtr]::Zero) { try { [Win32]::DestroyIcon($hIcon) | Out-Null } catch {} }
        if ($pen)   { try { $pen.Dispose()   } catch {} }
        if ($brush) { try { $brush.Dispose() } catch {} }
        if ($gfx)   { try { $gfx.Dispose()   } catch {} }
        if ($bmp)   { try { $bmp.Dispose()   } catch {} }
        return $null
    }
}

$script:trayIcon         = New-Object System.Windows.Forms.NotifyIcon
$script:trayIcon.Icon    = Create-TrayIcon -r 128 -g 128 -b 128
$script:trayIcon.Text    = "Ping Overlay - Waiting..."
$script:trayIcon.Visible = $true
# Cache the current tray icon colour to avoid recreating icons every tick (GDI leak).
$script:trayIconR = 128; $script:trayIconG = 128; $script:trayIconB = 128

function Update-TrayIcon {
    param([int]$r, [int]$g, [int]$b)
    if ($r -eq $script:trayIconR -and $g -eq $script:trayIconG -and $b -eq $script:trayIconB) { return }
    try {
        $newIcon = Create-TrayIcon -r $r -g $g -b $b
        if ($null -eq $newIcon) { return }
        $oldIcon = $script:trayIcon.Icon
        $script:trayIcon.Icon = $newIcon
        $script:trayIconR = $r; $script:trayIconG = $g; $script:trayIconB = $b
        if ($oldIcon) { try { $oldIcon.Dispose() } catch {} }
    }
    catch {}
}

# Helper: apply theme colors to the tray menu
function Update-TrayMenuTheme {
    $t = Get-Theme
    $trayMenu.BackColor = $t.PanelBg
    $trayMenu.ForeColor = $t.TextPrimary
}

# Context menu — theme-aware
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$trayMenu.Font            = New-Object System.Drawing.Font("Segoe UI", 10)
$trayMenu.ShowImageMargin = $false
$trayMenu.RenderMode      = [System.Windows.Forms.ToolStripRenderMode]::System
Update-TrayMenuTheme

$menuShowHide = New-Object System.Windows.Forms.ToolStripMenuItem("⬛  Show / Hide Overlay")
$menuShowHide.Add_Click({
    if ($script:overlayVisible) { [Win32]::ShowWindow($script:form.Handle, $SW_HIDE) | Out-Null; $script:overlayVisible = $false }
    else { [Win32]::ShowWindow($script:form.Handle, $SW_SHOWNOACTIVATE) | Out-Null; $script:overlayVisible = $true }
})
$trayMenu.Items.Add($menuShowHide) | Out-Null

$menuSettings = New-Object System.Windows.Forms.ToolStripMenuItem("⚙  Settings")
$menuSettings.Add_Click({ Show-SettingsWindow })
$trayMenu.Items.Add($menuSettings) | Out-Null

$menuCapture = New-Object System.Windows.Forms.ToolStripMenuItem("◎  Capture Window...")
$menuCapture.Add_Click({
    $result = Show-WindowPicker
    if ($null -ne $result) {
        $script:capturedHwnd = $result.Handle
        $script:Config.GameProcessName = $result.ProcessName
        $script:gameWasRunning = $false
        Write-Log "Tray: Captured window '$($result.Title)' (HWND $($result.Handle))"
    }
})
$trayMenu.Items.Add($menuCapture) | Out-Null

$menuRelease = New-Object System.Windows.Forms.ToolStripMenuItem("✕  Release Capture")
$menuRelease.Add_Click({
    Write-Log "Release Capture clicked. Current HWND: $($script:capturedHwnd)"
    $script:capturedHwnd = [IntPtr]::Zero
    $script:gameWasRunning = $false
    $script:lastGameSeenAt = $null
    if ($script:overlayVisible) {
        [Win32]::ShowWindow($script:form.Handle, $SW_HIDE) | Out-Null
        $script:overlayVisible = $false
    }
    $script:trayIcon.Text = "Ping Overlay - Waiting..."
    Update-TrayIcon -r 128 -g 128 -b 128
})
$trayMenu.Items.Add($menuRelease) | Out-Null

$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$darkModeText = if ($script:Config.DarkMode) { "☀  Switch to Light Mode" } else { "🌙  Switch to Dark Mode" }
$menuDarkMode = New-Object System.Windows.Forms.ToolStripMenuItem($darkModeText)
$menuDarkMode.Add_Click({
    $script:Config.DarkMode = -not $script:Config.DarkMode
    Save-Config -cfg $script:Config
    $menuDarkMode.Text = if ($script:Config.DarkMode) { "☀  Switch to Light Mode" } else { "🌙  Switch to Dark Mode" }
    Update-TrayMenuTheme
})
$trayMenu.Items.Add($menuDarkMode) | Out-Null

$menuAutoStart = New-Object System.Windows.Forms.ToolStripMenuItem("⟳  Auto-Start with Windows")
$menuAutoStart.Checked      = $script:Config.AutoStart
$menuAutoStart.CheckOnClick = $true
$menuAutoStart.Add_Click({ Set-AutoStart -Enable $menuAutoStart.Checked })
$trayMenu.Items.Add($menuAutoStart) | Out-Null

$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$menuResetStats = New-Object System.Windows.Forms.ToolStripMenuItem("↺  Reset Stats")
$menuResetStats.Add_Click({ $script:PingHistory.Clear(); $script:PingTimeouts = 0; $script:PingTotal = 0 })
$trayMenu.Items.Add($menuResetStats) | Out-Null

$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$menuExit = New-Object System.Windows.Forms.ToolStripMenuItem("⏻  Exit")
$menuExit.Add_Click({ $script:form.Close() })
$trayMenu.Items.Add($menuExit) | Out-Null

$script:trayIcon.ContextMenuStrip = $trayMenu

# Double-click tray icon toggles overlay visibility.
$script:trayIcon.Add_DoubleClick({
        if ($script:overlayVisible) { [Win32]::ShowWindow($script:form.Handle, $SW_HIDE) | Out-Null; $script:overlayVisible = $false }
        else { [Win32]::ShowWindow($script:form.Handle, $SW_SHOWNOACTIVATE) | Out-Null; $script:overlayVisible = $true }
    })

# ── Overlay Form ─────────────────────────────────────────────────
# Borderless, transparent window that sits on top of the game.
# Uses WS_EX_TOOLWINDOW to hide from Alt-Tab.

$script:form = New-Object System.Windows.Forms.Form
$script:form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$script:form.BackColor       = [System.Drawing.Color]::FromArgb(1, 1, 1)
$script:form.TransparencyKey = [System.Drawing.Color]::FromArgb(1, 1, 1)
$script:form.TopMost         = $true
$script:form.ShowInTaskbar   = $false
$script:form.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
$script:form.Location        = New-Object System.Drawing.Point(10, 248)
$script:form.Size            = New-Object System.Drawing.Size(10, 10)
$script:form.Opacity         = 0          # Start fully transparent to prevent flash
$script:overlayHandle        = [IntPtr]::Zero
$script:overlayVisible       = $false
$offsets = Load-OverlayOffsets
$script:offsetX = $offsets[0]
$script:offsetY = $offsets[1]
$script:lastRect = $null

$script:form.Add_Shown({
        $script:overlayHandle = $script:form.Handle
        # Exclude from Alt-Tab by applying WS_EX_TOOLWINDOW.
        $exStyle = [Win32]::GetWindowLong($script:form.Handle, [Win32]::GWL_EXSTYLE)
        $exStyle = $exStyle -bor [Win32]::WS_EX_TOOLWINDOW
        $exStyle = $exStyle -band (-bnot [Win32]::WS_EX_APPWINDOW)
        [Win32]::SetWindowLong($script:form.Handle, [Win32]::GWL_EXSTYLE, $exStyle) | Out-Null
        # Start hidden — the timer tick will show it once the game is detected.
        [Win32]::ShowWindow($script:form.Handle, $SW_HIDE) | Out-Null
        $script:overlayVisible = $false
    })

$script:form.Add_FormClosing({
    try {
        if ($null -ne $script:timer) { $script:timer.Stop(); $script:timer.Dispose(); $script:timer = $null }
        if ($null -ne $script:trayIcon) {
            $script:trayIcon.Visible = $false
            $script:trayIcon.Dispose()
            $script:trayIcon = $null
        }
    } catch {}
})

$script:label = New-Object OutlinedLabel
$script:label.Text         = "PING: --- ms"
$script:label.ForeColor    = [System.Drawing.Color]::Lime
$script:label.BackColor    = [System.Drawing.Color]::Transparent
$script:label.OutlineColor = [System.Drawing.Color]::Black
$script:label.OutlineWidth = 2
$script:label.Font         = New-Object System.Drawing.Font($script:Config.FontFamily, $script:Config.FontSize, [System.Drawing.FontStyle]::Bold)
$script:label.AutoSize     = $true
$script:label.Padding      = New-Object System.Windows.Forms.Padding(6, 2, 6, 2)
$script:label.Location     = New-Object System.Drawing.Point(0, 0)
$script:form.Controls.Add($script:label)
$script:form.ClientSize = $script:label.PreferredSize
$script:label.Add_SizeChanged({ $script:form.ClientSize = $script:label.PreferredSize })

# Drag to reposition
$script:dragging = $false
$script:label.Add_MouseDown({ $script:dragging = $true; $script:start = [System.Windows.Forms.Cursor]::Position; $script:loc = $script:form.Location })
$script:label.Add_MouseMove({ if ($script:dragging) { $c = [System.Windows.Forms.Cursor]::Position; $script:form.Location = New-Object System.Drawing.Point(($script:loc.X + $c.X - $script:start.X), ($script:loc.Y + $c.Y - $script:start.Y)) } })
$script:label.Add_MouseUp({
        $script:dragging = $false
        if ($script:lastRect) {
            $script:offsetX = $script:form.Location.X - $script:lastRect.Left
            $script:offsetY = $script:form.Location.Y - $script:lastRect.Top
            Save-OverlayOffsets -x $script:offsetX -y $script:offsetY
        }
    })

# Right-click overlay text to close
$script:label.Add_MouseClick({ param($s, $e); if ($e.Button -eq 'Right') { $script:form.Close() } })

# Scroll wheel adjusts opacity (range: 20% – 100%)
$script:label.Add_MouseWheel({
        param($s, $e)
        $delta = if ($e.Delta -gt 0) { 0.05 } else { -0.05 }
        $newOpacity = [math]::Max(0.2, [math]::Min(1.0, $script:form.Opacity + $delta))
        $script:form.Opacity = $newOpacity
        $script:Config.OverlayOpacity = $newOpacity
        Save-Config -cfg $script:Config
    })

# ── Main Loop ────────────────────────────────────────────────────
# WinForms Timer fires on the UI thread to avoid cross-thread issues.

$script:timer          = New-Object System.Windows.Forms.Timer
$script:timer.Interval = $script:Config.PingIntervalMs
$script:lastGameSeenAt = $null
$script:gameWasRunning = $false
$script:lastTickError  = ""
$script:tickErrorCount = 0

$script:timer.Add_Tick({
        try {
            $rect = $null
            $targetActive = $false

            # ── Captured HWND mode ────────────────────────────────
            if ($script:capturedHwnd -ne [IntPtr]::Zero) {
                if (-not [Win32]::IsWindow($script:capturedHwnd)) {
                    # Captured window was closed — release capture, hide overlay
                    Write-Log "Captured window closed (HWND $($script:capturedHwnd))"
                    $script:capturedHwnd = [IntPtr]::Zero
                    $script:gameWasRunning = $false
                    $script:lastGameSeenAt = $null
                    if ($script:overlayVisible) {
                        [Win32]::ShowWindow($script:form.Handle, $SW_HIDE) | Out-Null
                        $script:overlayVisible = $false
                    }
                    $script:trayIcon.Text = "Ping Overlay - Capture lost"
                    Update-TrayIcon -r 128 -g 128 -b 128
                    # Fall through to PID-based mode below
                }
                else {
                    $targetActive = $true
                    # ShowOnlyWhenForeground: check if captured window or overlay is foreground
                    if ($script:Config.ShowOnlyWhenForeground) {
                        $fg = [Win32]::GetForegroundWindow()
                        if ($fg -ne $script:capturedHwnd -and $fg -ne $script:overlayHandle) {
                            $rect = $null
                        }
                        else {
                            $r = New-Object Win32+RECT
                            if ([Win32]::GetWindowRect($script:capturedHwnd, [ref]$r)) {
                                $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
                                if ($w -gt 0 -and $h -gt 0) { $rect = $r }
                            }
                        }
                    }
                    else {
                        $r = New-Object Win32+RECT
                        if ([Win32]::GetWindowRect($script:capturedHwnd, [ref]$r)) {
                            $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
                            if ($w -gt 0 -and $h -gt 0) { $rect = $r }
                        }
                    }

                    if (-not $script:gameWasRunning) {
                        $script:gameWasRunning = $true
                        $script:trayIcon.Text = "Ping Overlay - Captured"
                    }
                }
            }

            # ── PID-based mode (original logic) ───────────────────
            if ($script:capturedHwnd -eq [IntPtr]::Zero) {
                $ids = Get-GameProcessIds
                $gameRunning = ($ids.Count -gt 0)

                if ($gameRunning) {
                    $script:lastGameSeenAt = Get-Date
                    if (-not $script:gameWasRunning) {
                        $script:gameWasRunning = $true
                        $script:trayIcon.Text = "Ping Overlay - Running"
                    }
                    $targetActive = $true
                }
                else {
                    if ($script:gameWasRunning) {
                        if ($script:overlayVisible) {
                            [Win32]::ShowWindow($script:form.Handle, $SW_HIDE) | Out-Null
                            $script:overlayVisible = $false
                        }
                        if (-not $script:lastGameSeenAt) { $script:lastGameSeenAt = Get-Date }
                        $elapsed = (Get-Date) - $script:lastGameSeenAt
                        if ($elapsed.TotalSeconds -ge $script:Config.GameExitGraceSeconds) {
                            $script:gameWasRunning = $false
                            $script:trayIcon.Text = "Ping Overlay - Waiting..."
                            Update-TrayIcon -r 128 -g 128 -b 128
                        }
                        return
                    } else { return }
                }

                $rect = Get-GameWindowRect -GameProcessIds $ids
            }

            # ── Position overlay ──────────────────────────────────
            if ($null -eq $rect) {
                if ($script:overlayVisible) {
                    [Win32]::ShowWindow($script:form.Handle, $SW_HIDE) | Out-Null
                    $script:overlayVisible = $false
                }
            }
            else {
                $script:lastRect = $rect
                if (-not $script:overlayVisible) {
                    $script:form.Opacity = $script:Config.OverlayOpacity
                    [Win32]::ShowWindow($script:form.Handle, $SW_SHOWNOACTIVATE) | Out-Null
                    $script:overlayVisible = $true
                }
                $script:form.TopMost = $true
                if (-not $script:dragging) {
                    $script:form.Location = New-Object System.Drawing.Point(($rect.Left + $script:offsetX), ($rect.Top + $script:offsetY))
                }
            }

            # Only ping when target is active (window exists, even if hidden)
            if (-not $targetActive) { return }

            # Measure latency and update display.
            $ms = Get-PingMs -Target $script:Config.ServerIP
            Add-PingResult -ms $ms

            if ($null -ne $ms) {
                $script:label.Text = "PING: $ms ms"
                $color = Get-PingColor -ms $ms
                $script:label.ForeColor = $color
                Update-TrayIcon -r $color.R -g $color.G -b $color.B
            }
            else {
                $script:label.Text      = "PING: TIMEOUT"
                $script:label.ForeColor = [System.Drawing.Color]::Red
                Update-TrayIcon -r 255 -g 0 -b 0
            }

            # Tooltip is capped at 63 chars by the NotifyIcon API.
            $stats = Get-PingStats
            $tip   = "Ping Overlay`n$stats"
            if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
            $script:trayIcon.Text = $tip
        }
        catch {
            $script:label.Text      = "PING: ERROR"
            $script:label.ForeColor = [System.Drawing.Color]::Red
            $errMsg = $_.Exception.Message
            if ($errMsg -ne $script:lastTickError) {
                Write-Log "Tick error: $errMsg"
                $script:lastTickError  = $errMsg
                $script:tickErrorCount = 1
            } else {
                $script:tickErrorCount++
                if ($script:tickErrorCount -le 3 -or $script:tickErrorCount % 60 -eq 0) {
                    Write-Log "Tick error (repeated x$($script:tickErrorCount)): $errMsg"
                }
            }
        }
    })

# ── Entry Point ──────────────────────────────────────────────────

# Rename the console window for clarity; keep it visible in the taskbar
# so the user can close the app quickly via the taskbar X button.
$Host.UI.RawUI.WindowTitle = "Ping Overlay"

# Minimize the console window immediately so it doesn't cover the settings dialog.
# The console stays in the taskbar for easy "X to close" access.
$consoleHwnd = [Win32]::GetConsoleWindow()
if ($consoleHwnd -ne [IntPtr]::Zero) {
    [Win32]::ShowWindow($consoleHwnd, 6) | Out-Null  # SW_MINIMIZE = 6
}

# Instant-kill when user closes the console window from the taskbar.
[Win32]::RegisterCloseHandler()

# Show startup configuration dialog before the overlay begins.
Show-SettingsWindow -IsStartup
if ($script:settingsDialogResult -ne 'OK') {
    Write-Log "Startup cancelled by user"
    $script:trayIcon.Visible = $false
    $script:trayIcon.Dispose()
    exit
}

# Re-apply config that may have been changed in the startup dialog.
$script:label.Font = New-Object System.Drawing.Font(
    $script:Config.FontFamily, $script:Config.FontSize, [System.Drawing.FontStyle]::Bold)
$script:timer.Interval = $script:Config.PingIntervalMs

Write-Log "Ping Overlay started"
$script:timer.Start()

try {
    [System.Windows.Forms.Application]::Run($script:form)
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)"
    $script:trayIcon.Visible = $false
    $script:trayIcon.Dispose()
    throw
}
