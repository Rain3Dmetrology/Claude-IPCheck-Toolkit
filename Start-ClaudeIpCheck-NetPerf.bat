@echo off
chcp 65001 >nul
setlocal
set "SCRIPT=%~dp0ClaudeIpCheck.ps1"

pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Once -NetPerf

echo.
echo Done. Press any key to exit...
pause >nul
