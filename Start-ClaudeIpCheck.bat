@echo off
chcp 65001 >nul
setlocal
set "SCRIPT=%~dp0ClaudeIpCheck.ps1"

echo ===============================================
echo   Claude-IPCheck Toolkit —— 一键检测（单次）
echo ===============================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Once
echo.
echo 检测完成。按任意键退出...
pause >nul
