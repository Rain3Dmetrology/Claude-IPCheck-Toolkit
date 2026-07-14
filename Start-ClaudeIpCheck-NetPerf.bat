@echo off
chcp 65001 >nul
setlocal
set "SCRIPT=%~dp0ClaudeIpCheck.ps1"

echo ===============================================
echo   Claude-IPCheck Toolkit —— 网络性能检测
echo   单次检测 + 网速/DNS/可达性（参考 MyIP 思路）
echo ===============================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Once -NetPerf
echo.
echo 检测完成。按任意键退出...
pause >nul
