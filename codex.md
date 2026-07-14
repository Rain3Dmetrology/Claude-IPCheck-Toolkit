# Claude-IPCheck Toolkit (Codex)

This file mirrors `AGENTS.md` so OpenAI Codex picks up the instructions regardless of which filename it prefers.

Detect whether the current Windows network environment can use Claude AI stably and with low risk-control friction.

## When to use
The user asks whether their network/IP can use Claude, wants an "IP check" / "ipcheck" / "Claude risk-control check", or wants to deploy a Claude network-environment detector on Windows.

## What it does
1. **Structured cross-validation** via the free ip-api.com JSON API: country/region, ISP, ASN, org, and a heuristic判断 of datacenter/cloud IP (high risk for Claude).
2. **Claude-specific check** via `stormzhang/ipcheck` (`ai-ipcheck` pip package): IP geolocation, DNS leak, proxy, timezone consistency, Claude endpoint reachability, datacenter risk → final **Low / Medium / High** verdict + score.
3. **Optional network-performance check** (inspired by [MyIP](https://github.com/jason5ng32/MyIP)): speed test via Cloudflare endpoints (download/upload Mbps + latency/jitter), DNS resolver detection (edns.ip-api.com, no key), and service reachability (Claude/ChatGPT/Google/GitHub/YouTube/WeChat RTT). Enabled with `-SpeedTest`/`-DnsCheck`/`-Reach`, or all at once via `-NetPerf`. Off by default.

## How to deploy (Windows only)
1. Locate `ClaudeIpCheck.ps1` and the two `.bat` launchers.
2. Ensure Python 3.10+ on PATH (`python --version`). If missing, ask the user to install from https://www.python.org/downloads/ with "Add to PATH" ticked. Do not silently install Python.
3. Run:
   - One-shot: `pwsh -NoProfile -ExecutionPolicy Bypass -File ClaudeIpCheck.ps1 -Once`
   - Monitor: append `-Monitor` (optionally `-OpenIpInfoCv` to open ipinfo.cv manually).
   - Network performance: append `-NetPerf` to also run speed test, DNS resolver, and service reachability checks.
4. Interpret:
   - **Low (green)**: clean, safe to use Claude.
   - **Medium (yellow)**: enable global TUN, disable WebRTC local-IP leak, use clean DNS (1.1.1.1), avoid shared IPs.
   - **High (red)**: not recommended — switch to residential/home IP or compliant proxy.

## Constraints
- Does NOT change default browser, write registry, or require admin (only `-TimeSync` may need admin).
- `ipinfo.cv/claude-ai-check` is client-side JS; only use as manual `-OpenIpInfoCv` cross-check, never an automated gate.
- First run auto-installs `ai-ipcheck` via pip. On failure: `python -m pip install -U ai-ipcheck -i https://pypi.tuna.tsinghua.edu.cn/simple`.
- Windows + PowerShell 7 (pwsh) only. If the user only has Windows PowerShell 5.1, guide them to install PowerShell 7 (`winget install Microsoft.PowerShell`).
- All script files are saved as UTF-8 without BOM; Chinese and English display correctly in Windows Terminal / PowerShell 7.
