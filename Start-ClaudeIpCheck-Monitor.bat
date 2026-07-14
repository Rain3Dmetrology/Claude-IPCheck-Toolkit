@echo off
chcp 65001 >nul
setlocal
set "SCRIPT=%~dp0ClaudeIpCheck.ps1"

echo ===============================================
echo   Claude-IPCheck Toolkit —— 监测模式
echo   持续检测出口 IP，稳定后自动跑检测（Ctrl+C 退出）
echo ===============================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Monitor
echo.
echo 已停止。按任意键退出...
pause >nul
