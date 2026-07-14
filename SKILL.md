---
name: claude-ipcheck-toolkit
description: 一键检测 Windows 网络环境是否适合稳定、低风控地使用 Claude AI。自动用结构化 JSON IP API（ip-api.com）做交叉验证（国家/地区、ISP、ASN、是否为机房/数据中心 IP），并运行 stormzhang/ipcheck 给出低/中/高风险综合结论与评分；可选网络性能检测（网速/DNS 解析器/服务可达性，参考 MyIP）；支持单次检测与持续监测出口 IP。适用于「我的网络能不能用 Claude」「IP 检测」「ipcheck」「Claude 风控」「网速测试」等场景。
version: 1.1.0
agent_created: true
tags: [network, claude, ipcheck, vpn, diagnostic, windows, deployment]
---

# Claude-IPCheck Toolkit

一键在 **Windows** 上部署并运行 Claude 网络环境检测，把检测结果交付给用户。

## 何时使用

- 用户询问「我的网络/IP 能不能用 Claude」「检测 IP」「跑 ipcheck」「看 Claude 风控」「部署 Claude 网络检测工具」。
- 用户希望把检测能力打包、复用到自己或其他 Windows 机器。

## 本 skill 自带的资源

| 文件 | 作用 |
| --- | --- |
| `ClaudeIpCheck.ps1` | 主脚本（结构化交叉验证 + stormzhang/ipcheck，无默认浏览器修改、无注册表写入） |
| `Start-ClaudeIpCheck.bat` | 双击 = 单次检测 |
| `Start-ClaudeIpCheck-Monitor.bat` | 双击 = 持续监测出口 IP 变化 |
| `Start-ClaudeIpCheck-NetPerf.bat` | 双击 = 单次检测 + 网络性能检测（-NetPerf：网速/DNS/可达性） |
| `screenshots/ipcheck-output-example.png` | 输出示例，供 README 与解释时引用 |

## 部署流程（在用户 Windows 机器上执行）

1. **定位本 skill 目录**：通过 `Glob`/`Read` 找到 `SKILL.md` 所在目录（典型为 `~/.workbuddy/skills/claude-ipcheck-toolkit/`）。
2. **复制三个文件**到用户指定的 Windows 目录（默认建议 `桌面\Claude-IPCheck-Toolkit\`）：用文件工具把 `ClaudeIpCheck.ps1`、两个 `.bat` 复制到目标目录。
3. **确认 Python 3.10+**：运行 `python --version`（或 `py --version`）。若未安装或版本过低，提示用户从 https://www.python.org/downloads/ 安装，并**务必勾选 Add to PATH**；不要替用户静默安装 Python。
4. **运行检测**（询问用户偏好后二选一）：
   - 单次：`pwsh -NoProfile -ExecutionPolicy Bypass -File ClaudeIpCheck.ps1 -Once`
   - 监测：追加 `-Monitor`（可选 `-OpenIpInfoCv` 在浏览器打开 ipinfo.cv 供人工核对）。
   - 网络性能检测：追加 `-NetPerf`（= `-SpeedTest -DnsCheck -Reach`），额外测网速 / DNS 解析器 / 服务可达性（参考 MyIP）。
5. **解释结果**：
   - 低/中/高风险 + 评分来自 ipcheck（核心结论）。
   - 结构化交叉验证独立给出出口 IP 属地与「是否机房/数据中心 IP」。
   - 高风险 → 建议换家庭/住宅 IP 或合规代理；中风险 → 建议开全局 TUN、关 WebRTC 本地 IP 泄漏、用清洁 DNS（如 1.1.1.1）、避免多人共用同一 IP。
   - 网络性能检测（若开启 `-NetPerf`）：网速看下载/上传 Mbps 与延迟/抖动；DNS 检测看出口 DNS 是否与本地一致（不一致可能经代理/DNS 转发）；服务可达性看各站点 RTT。

## 重要约束

- 本工具**不修改默认浏览器、不写注册表、不需要管理员权限**（仅 `-TimeSync` 时钟同步可能需要）。
- `ipinfo.cv/claude-ai-check` 是纯前端 JS 渲染页面，脚本无法解析其结论；仅作为 `-OpenIpInfoCv` 的人工核对入口，绝不作为自动判定依据。
- 首次运行自动 `python -m pip install -U ai-ipcheck`，需联网；失败则提示用户手动安装或换源（`-i https://pypi.tuna.tsinghua.edu.cn/simple`）。
- 仅支持 **Windows + PowerShell 7 (pwsh)**；非 Windows 环境直接告知用户本工具不适用。如果用户只有 Windows PowerShell 5.1，请先引导安装 PowerShell 7（`winget install Microsoft.PowerShell`）。
- 所有脚本统一为 **UTF-8 无 BOM**；中英文在 Windows Terminal / PowerShell 7 中均可正确显示。

## 故障排查

- 找不到 Python → 引导安装并勾选 PATH，或重启终端/电脑让 PATH 生效。
- pip 安装慢/失败 → 换清华源：`python -m pip install -U ai-ipcheck -i https://pypi.tuna.tsinghua.edu.cn/simple`。
- 中文乱码 → 已统一 UTF-8 无 BOM（`.bat` 内 `chcp 65001`）；若仍乱码，请使用 Windows Terminal 或 PowerShell 7，并把字体改为 Consolas / Microsoft YaHei Mono。确保 `pwsh` 在 PATH 中。
