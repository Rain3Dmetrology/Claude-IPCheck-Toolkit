@echo off
chcp 65001 >nul
setlocal
set "SCRIPT=%~dp0ClaudeIpCheck.ps1"

pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Monitor

echo.
echo Stopped. Press any key to exit...
pause >nul
