---
name: claude-ipcheck-toolkit
description: >-
  一键检测 Windows 当前网络环境是否适合稳定、低风控地使用 Claude AI。自动用结构化
  JSON IP API（ip-api.com）做交叉验证（国家/地区、ISP、ASN、是否为机房/数据中心 IP），
  并运行 stormzhang/ipcheck（ai-ipcheck）给出「低/中/高」风险综合结论与评分；支持单次
  检测与持续监测出口 IP 变化。当用户询问「我的网络能不能用 Claude」「IP 检测」「Claude
  风控」「ipcheck」「检测 Claude 网络环境」或希望在 Windows 上部署 Claude 网络环境检测时使用。
version: 1.0.0
agent_created: true
tags: [network, claude, ipcheck, vpn, diagnostic, windows, deployment]
---

# Claude-IPCheck Toolkit

帮助用户一键在 **Windows** 上部署并运行 Claude 网络环境检测。

## 何时使用
- 用户想知道当前网络/IP 是否适合用 Claude。
- 用户要求「检测 IP」「跑 ipcheck」「看 Claude 风控」「部署 Claude 网络检测工具」。
- 用户希望把检测能力打包、复用到自己的或其他 Windows 机器。

## 交付物（本 skill 已自带）
- `ClaudeIpCheck.ps1`：主脚本（结构化交叉验证 + ipcheck，无默认浏览器修改、无注册表写入）。
- `Start-ClaudeIpCheck.bat`：双击 = 单次检测。
- `Start-ClaudeIpCheck-Monitor.bat`：双击 = 持续监测出口 IP。

## 部署流程（在用户机器上执行）
1. **定位本 skill 目录**，把三个文件复制到用户指定的 Windows 目录（默认建议
   `桌面\Claude-IPCheck-Toolkit\`）。可用如下思路：
   - 用 `Read`/`Glob` 找到本 SKILL.md 所在目录（`~/.workbuddy/skills/claude-ipcheck-toolkit/`）。
   - 用 `Bash` 或文件工具把 `ClaudeIpCheck.ps1` 与两个 `.bat` 复制到目标目录。
2. **确认 Python 3.10+**：
   - 运行 `python --version`（或 `py --version`）。
   - 若未安装或版本过低，提示用户从 https://www.python.org/downloads/ 安装，
     并**务必勾选 Add to PATH**。不要替用户静默安装 Python。
3. **运行检测**（二选一，优先询问用户偏好）：
   - 单次：在该目录执行
     `powershell -NoProfile -ExecutionPolicy Bypass -File ClaudeIpCheck.ps1 -Once`
   - 监测：加 `-Monitor`（可选 `-OpenIpInfoCv` 在浏览器打开 ipinfo.cv 人工核对）。
4. **解释结果**：
   - 低/中/高风险 + 评分来自 ipcheck（核心结论）。
   - 结构化交叉验证给出出口 IP 属地与「是否机房 IP」。
   - 高风险 → 建议换家庭/住宅 IP 或合规代理；中风险 → 建议开全局 TUN、关 WebRTC 泄漏、用清洁 DNS。

## 重要约束
- 本工具**不修改默认浏览器、不写注册表、不需要管理员权限**（时间同步 `-TimeSync` 才可能需要）。
- `ipinfo.cv/claude-ai-check` 是纯前端 JS 渲染页面，脚本无法解析其结论；仅作为
  `-OpenIpInfoCv` 的人工核对入口，绝不作为自动判定依据。
- 首次运行会自动 `python -m pip install -U ai-ipcheck`，需联网；如失败提示用户手动安装。
- 仅支持 Windows + PowerShell 5.1+。非 Windows 环境请直接告知用户本工具不适用。

## 故障排查
- 找不到 Python → 引导安装并勾选 PATH。
- pip 安装慢/失败 → 建议换源：
  `python -m pip install -U ai-ipcheck -i https://pypi.tuna.tsinghua.edu.cn/simple`
- 中文乱码 → 已强制 UTF-8；若仍乱码，确认终端为 UTF-8（bat 内已 `chcp 65001`）。
