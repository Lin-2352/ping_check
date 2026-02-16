# Ping Writer for RTSS - Writes ping to file that RTSS can read
# Run this in background while gaming

$ServerIP = "198.136.44.61"
$OutputFile = "C:\ProgramData\ping_value.txt"
$PingInterval = 1  # seconds

Write-Host "================================"
Write-Host "  MC5 Ping Monitor for RTSS"
Write-Host "================================"
Write-Host ""
Write-Host "Server: $ServerIP"
Write-Host "Output: $OutputFile"
Write-Host ""
Write-Host "Press Ctrl+C to stop"
Write-Host ""

while ($true) {
    try {
        $ping = Test-Connection -ComputerName $ServerIP -Count 1 -ErrorAction SilentlyContinue
        if ($ping) {
            $ms = $ping.ResponseTime
            # Write just the number - RTSS will read this
            "$ms" | Out-File -FilePath $OutputFile -Encoding ASCII -NoNewline
            Write-Host "Ping: $ms ms"
        }
        else {
            "---" | Out-File -FilePath $OutputFile -Encoding ASCII -NoNewline
            Write-Host "Ping: TIMEOUT"
        }
    }
    catch {
        "ERR" | Out-File -FilePath $OutputFile -Encoding ASCII -NoNewline
        Write-Host "Ping: ERROR"
    }
    Start-Sleep -Seconds $PingInterval
}
