@echo off
echo Starting MC5 Ping Monitor...
echo.
echo This window will show ping values.
echo Keep it running while gaming.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0PingWriter.ps1"
pause
