# Claude-IPCheck Toolkit

Detect whether the current Windows network environment can use Claude AI stably and with low risk-control friction.

## When to use
Use this toolkit when the user asks whether their network/IP can use Claude, wants an "IP check", "ipcheck", "Claude risk-control check", or wants to deploy a Claude network-environment detector on Windows.

## What it does
Two layered checks that corroborate each other:
1. **Structured cross-validation** via the free ip-api.com JSON API: country/region, ISP, ASN, organization, and a heuristic判断 of whether the exit IP is a datacenter/cloud IP (a high risk factor for Claude).
2. **Claude-specific check** via `stormzhang/ipcheck` (the `ai-ipcheck` pip package): IP geolocation, DNS leak, proxy state, timezone consistency, Claude endpoint reachability, datacenter risk → final **Low / Medium / High** risk verdict + score.
3. **Optional network-performance check** (inspired by [MyIP](https://github.com/jason5ng32/MyIP)): speed test via Cloudflare endpoints (download/upload Mbps + latency/jitter), DNS resolver detection (edns.ip-api.com, no key required), and service reachability (Claude/ChatGPT/Google/GitHub/YouTube/WeChat RTT). Enabled with `-SpeedTest`/`-DnsCheck`/`-Reach`, or all at once via `-NetPerf`. Off by default.

## How to deploy (Windows only)
1. Locate this toolkit's files: `ClaudeIpCheck.ps1` and the two `.bat` launchers (`Start-ClaudeIpCheck.bat`, `Start-ClaudeIpCheck-Monitor.bat`).
2. Ensure Python 3.10+ is on PATH (`python --version`). If missing, ask the user to install it from https://www.python.org/downloads/ and tick **"Add to PATH"**. Do not silently install Python.
3. Run a check (pick one):
   - One-shot: `pwsh -NoProfile -ExecutionPolicy Bypass -File ClaudeIpCheck.ps1 -Once`
   - Monitor (auto-detect after VPN IP stabilizes): append `-Monitor`
   - Optionally append `-OpenIpInfoCv` to open ipinfo.cv in a browser for manual cross-check.
   - Optionally append `-NetPerf` to also run the network-performance check (speed test, DNS resolver, service reachability).
4. Interpret results:
   - **Low (green)**: clean environment, safe to use Claude.
   - **Medium (yellow)**: usable but improve — enable global TUN, disable WebRTC local-IP leak, use clean DNS (e.g. 1.1.1.1), avoid shared IPs.
   - **High (red)**: not recommended for Claude (risk of control/ban) — switch to a residential/home IP or a compliant proxy.

## Constraints
- Does **NOT** change the default browser, write the registry, or require admin rights (only `-TimeSync` clock sync may need admin).
- `ipinfo.cv/claude-ai-check` is a client-side JS page; its verdict cannot be parsed by scripts. Use it only as a manual `-OpenIpInfoCv` cross-check, never as an automated gate.
- First run auto-installs `ai-ipcheck` via pip (needs network). On failure, suggest manual install or a mirror:
  `python -m pip install -U ai-ipcheck -i https://pypi.tuna.tsinghua.edu.cn/simple`
- Windows + PowerShell 7 (pwsh) only. If the user only has Windows PowerShell 5.1, guide them to install PowerShell 7 (`winget install Microsoft.PowerShell`).
- All script files are saved as UTF-8 without BOM; Chinese and English display correctly in Windows Terminal / PowerShell 7.

## Troubleshooting
- Python not found → guide install + PATH (or restart terminal to apply PATH).
- pip slow/fails → use the Tsinghua mirror above.
- Garbled Chinese → UTF-8 without BOM is enforced; use Windows Terminal or PowerShell 7 and a font like Consolas / Microsoft YaHei Mono. The `.bat` launchers also run `chcp 65001`.
