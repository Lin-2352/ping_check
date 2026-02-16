@echo off
:: Start Ping Overlay (always-on-top window)
start "" powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0PingOverlay.ps1"
