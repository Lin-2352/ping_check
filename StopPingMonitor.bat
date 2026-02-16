@echo off
:: Stop all running Ping Monitor processes
echo Stopping Ping Monitor...
taskkill /F /IM powershell.exe /FI "WINDOWTITLE eq *PingMonitor*" 2>nul
:: Also try to kill by script name pattern
powershell -Command "Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*PingMonitor*' } | Stop-Process -Force" 2>nul
echo Done!
pause
