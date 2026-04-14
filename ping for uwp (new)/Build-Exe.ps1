#Requires -Version 7.0
<#
.SYNOPSIS
    Builds PingOverlay.bat into a standalone PingOverlay.exe using ps2exe.

.DESCRIPTION
    1. Installs ps2exe module if not present
    2. Extracts the PowerShell portion from PingOverlay.bat (strips the batch header)
    3. Compiles it into PingOverlay.exe (GUI mode, no console window)

.NOTES
    Run from the same directory as PingOverlay.bat:
        pwsh -File Build-Exe.ps1
#>

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$batFile  = Join-Path $scriptDir "PingOverlay.bat"
$ps1File  = Join-Path $scriptDir "PingOverlay_temp.ps1"
$exeFile  = Join-Path $scriptDir "PingOverlay.exe"
$iconFile = Join-Path $scriptDir "PingOverlay.ico"

# ── Step 1: Install ps2exe if needed ─────────────────────────────
if (-not (Get-Module -ListAvailable ps2exe)) {
    Write-Host "Installing ps2exe module..." -ForegroundColor Yellow
    Install-Module ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe -Force

# ── Step 2: Extract PowerShell from the polyglot .bat ────────────
Write-Host "Extracting PowerShell code from PingOverlay.bat..." -ForegroundColor Cyan
$lines = Get-Content -Path $batFile -Encoding UTF8
# Find the end of the batch header (the #> closing tag)
$startLine = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*#>') {
        $startLine = $i + 1
        break
    }
}
# Replace the $env:PING_DIR bootstrap with exe-compatible path detection
$psCode = @"
# Auto-detect script directory (exe-compatible)
`$ScriptDir = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
if (-not `$ScriptDir) { `$ScriptDir = (Get-Location).Path }
"@
# Skip lines until we get past the PING_DIR block
$skipTo = $startLine
for ($i = $startLine; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*#\s*──\s*Bootstrap') {
        $skipTo = $i
        break
    }
    # Also skip if/else block for PING_DIR
    if ($lines[$i] -match '^\s*if\s*\(\s*\$env:PING_DIR') {
        # Find the closing brace of this if/else block
        $braceCount = 0
        for ($j = $i; $j -lt $lines.Count; $j++) {
            if ($lines[$j] -match '\{') { $braceCount++ }
            if ($lines[$j] -match '\}') { $braceCount-- }
            if ($braceCount -le 0 -and $j -gt $i) { $skipTo = $j + 1; break }
        }
        break
    }
}
$psCode += "`n" + ($lines[$skipTo..($lines.Count - 1)] -join "`n")

$psCode | Out-File -FilePath $ps1File -Encoding UTF8
Write-Host "  Wrote $ps1File ($($lines.Count - $startLine) lines)" -ForegroundColor Green

# ── Step 3: Compile to .exe ──────────────────────────────────────
Write-Host "Compiling to exe..." -ForegroundColor Cyan
$params = @{
    inputFile  = $ps1File
    outputFile = $exeFile
    noConsole  = $true
    STA        = $true
    title      = "Ping Overlay"
    description = "Real-time ping overlay for games and apps"
    version    = "2.2.0.0"
}
# Add icon if available
if (Test-Path $iconFile) { $params.iconFile = $iconFile }

Invoke-ps2exe @params

# ── Cleanup ──────────────────────────────────────────────────────
Remove-Item -Path $ps1File -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "Build complete: $exeFile" -ForegroundColor Green
Write-Host "You can now run PingOverlay.exe directly (no PowerShell window needed)." -ForegroundColor Gray
