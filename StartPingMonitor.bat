@echo off
:: Start Ping Monitor (hidden window)
:: This runs the PowerShell script in the background without showing a window

powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0PingMonitor.ps1"
