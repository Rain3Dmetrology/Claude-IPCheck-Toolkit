@echo off
chcp 65001 >nul
setlocal

REM Self-elevate to administrator on double-click (UAC prompt)
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrator privileges...
    pwsh -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "SCRIPT=%~dp0ClaudeIpCheck.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"

echo.
echo Done. Press any key to exit...
pause >nul
