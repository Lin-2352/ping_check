# Ping Monitor for RTSS/MSI Afterburner Overlay
# Monitors ping to Modern Combat 5 server and writes to file for RTSS to display

$ServerIP = "198.136.44.61"
$OutputFile = Join-Path $PSScriptRoot "ping_data.txt"
$PingInterval = 1  # seconds between pings

Write-Host "Starting Ping Monitor for $ServerIP"
Write-Host "Output file: $OutputFile"
Write-Host "Press Ctrl+C to stop"

# Create initial file
"---" | Out-File -FilePath $OutputFile -Encoding ASCII

while ($true) {
    try {
        # Ping the server
        $ping = Test-Connection -ComputerName $ServerIP -Count 1 -ErrorAction SilentlyContinue
        
        if ($ping) {
            $latency = $ping.ResponseTime
            # Write just the number for RTSS to read
            "$latency" | Out-File -FilePath $OutputFile -Encoding ASCII -NoNewline
        } else {
            "TIMEOUT" | Out-File -FilePath $OutputFile -Encoding ASCII -NoNewline
        }
    }
    catch {
        "ERROR" | Out-File -FilePath $OutputFile -Encoding ASCII -NoNewline
    }
    
    Start-Sleep -Seconds $PingInterval
}
