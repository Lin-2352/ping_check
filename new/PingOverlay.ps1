# Ping Overlay - Simple, shows when MC5 is running
# Clean text matching MSI Afterburner style

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Add Win32 API functions
Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class Win32 {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }
    }
"@

$ServerIP = "198.136.44.61"
$PingInterval = 1000
$GameProcessName = "WindowsEntryPoint.Windows_W10"

Write-Host "Ping Overlay for Modern Combat 5"
Write-Host "Waiting for game to start..."

function Get-GameProcess {
    return Get-Process -Name $GameProcessName -ErrorAction SilentlyContinue
}

function Get-GameWindow {
    $process = Get-GameProcess
    if (-not $process) { return $null }

    # Get main window handle
    if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
        return $process.MainWindowHandle
    }
    return $null
}

function Is-GameWindowActive {
    $gameWindow = Get-GameWindow
    if (-not $gameWindow) { return $false }

    # Check if window is visible and not minimized
    $isVisible = [Win32]::IsWindowVisible($gameWindow)
    $isMinimized = [Win32]::IsIconic($gameWindow)

    return ($isVisible -and -not $isMinimized)
}

# Wait for game
while (-not (Get-GameWindow)) {
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 2
}

Write-Host "`nGame detected! Starting overlay..."

# Create overlay
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.BackColor = [System.Drawing.Color]::Black
$form.TransparencyKey = [System.Drawing.Color]::Black
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.Location = New-Object System.Drawing.Point(10, 248)
$form.Size = New-Object System.Drawing.Size(180, 18)

# Label
$label = New-Object System.Windows.Forms.Label
$label.Text = "MC5 PING: --- ms"
$label.ForeColor = [System.Drawing.Color]::Cyan
$label.BackColor = [System.Drawing.Color]::Black
$label.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(0, 0)
$form.Controls.Add($label)

# Drag support
$script:dragging = $false
$form.Add_MouseDown({ $script:dragging = $true; $script:start = [System.Windows.Forms.Cursor]::Position; $script:loc = $form.Location })
$form.Add_MouseMove({ if ($script:dragging) { $c = [System.Windows.Forms.Cursor]::Position; $form.Location = New-Object System.Drawing.Point(($script:loc.X + $c.X - $script:start.X), ($script:loc.Y + $c.Y - $script:start.Y)) } })
$form.Add_MouseUp({ $script:dragging = $false })
$label.Add_MouseDown({ $script:dragging = $true; $script:start = [System.Windows.Forms.Cursor]::Position; $script:loc = $form.Location })
$label.Add_MouseMove({ if ($script:dragging) { $c = [System.Windows.Forms.Cursor]::Position; $form.Location = New-Object System.Drawing.Point(($script:loc.X + $c.X - $script:start.X), ($script:loc.Y + $c.Y - $script:start.Y)) } })
$label.Add_MouseUp({ $script:dragging = $false })

# Right-click to close
$form.Add_MouseClick({ param($s, $e); if ($e.Button -eq 'Right') { $form.Close() } })
$label.Add_MouseClick({ param($s, $e); if ($e.Button -eq 'Right') { $form.Close() } })

# Timer
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $PingInterval
$timer.Add_Tick({
        # Check if game process still exists
        $gameProcess = Get-GameProcess
        if (-not $gameProcess) {
            Write-Host "Game closed."
            $timer.Stop()
            $form.Close()
            return
        }

        # Check if game window is visible and active
        $isActive = Is-GameWindowActive

        # Show or hide overlay based on game window state
        if ($isActive -and -not $form.Visible) {
            $form.Show()
        }
        elseif (-not $isActive -and $form.Visible) {
            $form.Hide()
        }

        # Only update ping when overlay is visible
        if ($form.Visible) {
            try {
                $ping = Test-Connection -ComputerName $ServerIP -Count 1 -ErrorAction SilentlyContinue
                if ($ping) {
                    $ms = $ping.ResponseTime
                    $label.Text = "MC5 PING: $ms ms"
                    if ($ms -lt 100) { $label.ForeColor = [System.Drawing.Color]::Cyan }
                    elseif ($ms -lt 200) { $label.ForeColor = [System.Drawing.Color]::Yellow }
                    else { $label.ForeColor = [System.Drawing.Color]::Red }
                }
                else {
                    $label.Text = "MC5 PING: TIMEOUT"
                    $label.ForeColor = [System.Drawing.Color]::Red
                }
            }
            catch {
                $label.Text = "MC5 PING: ERROR"
            }
        }
    })

$timer.Start()
[System.Windows.Forms.Application]::Run($form)
