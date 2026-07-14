# Claude-IPCheck Toolkit

> 一键检测「当前 Windows 网络环境是否适合稳定、低风控地使用 Claude AI」。

本工具面向普通 Windows 用户，无需改注册表、不修改默认浏览器、不需要管理员权限。
它把两套核心检测合在一起，互相印证（另含一套**可选**的网络性能检测层）：

| 检测层 | 工具 | 看什么 |
| --- | --- | --- |
| **结构化交叉验证**（默认开） | [ip-api.com](http://ip-api.com/json) 免费 JSON API | 出口 IP 的国家/地区、ISP、ASN、组织，并判断是否为「机房/数据中心 IP」（Claude 风控高风险项） |
| **Claude 专项检测**（核心） | [stormzhang/ipcheck](https://github.com/stormzhang/ipcheck)（`ai-ipcheck`） | IP 属地、DNS 泄漏、代理、时区、Claude 端点可达性、数据中心风险 → 给出 **低 / 中 / 高** 风险综合结论 + 评分 |
| **网络性能检测**（可选） | 参考 [MyIP](https://github.com/jason5ng32/MyIP)，复用 Cloudflare 测速端点 + edns.ip-api.com | 网速（下载/上传 + 延迟/抖动）、DNS 解析器检测、服务可达性，需 `-SpeedTest`/`-DnsCheck`/`-Reach`/`-NetPerf` 开启 |

> 为什么不用 `ipinfo.cv/claude-ai-check` 做自动判定？
> 该页面是纯前端 JavaScript 渲染，脚本抓取不到结论（只拿到一个 5 KB 的空壳）。
> 因此脚本用**结构化 JSON API** 做自动化交叉验证，同时**可选**在浏览器里打开 ipinfo.cv 让你**人工**肉眼核对。

---

## 一、准备工作（只需一次）

1. 安装 **Python 3.10 或以上**，安装时务必勾选 **`Add python.exe to PATH`**。
   下载：<https://www.python.org/downloads/>
2. 安装 **PowerShell 7**（`.bat` 启动器需要它）。推荐方式：
   - Windows 商店搜索 "PowerShell" 安装；或
   - 命令行：`winget install Microsoft.PowerShell`；或
   - 官网 MSI：<https://github.com/PowerShell/PowerShell/releases>
3. 把本仓库整个文件夹下载 / 克隆到任意位置（例如桌面 `Claude-IPCheck-Toolkit`）。

> 首次运行会自动执行 `python -m pip install ai-ipcheck`，需联网。

---

## 二、傻瓜式使用

### 方式 A：双击运行（推荐）
直接双击 **`Start-ClaudeIpCheck.bat`**，等待结果即可。它会自动调用 PowerShell 7 (`pwsh`)。

### 方式 B：持续监测（适合挂 VPN 后自动检测）
双击 **`Start-ClaudeIpCheck-Monitor.bat`**：脚本每 15 秒看一次出口 IP，
等 IP 稳定后自动跑一次完整检测。`Ctrl+C` 退出。

---

## 三、命令行参数

在 `ClaudeIpCheck.ps1` 后追加参数即可，例如：
`pwsh -File ClaudeIpCheck.ps1 -Monitor -OpenIpInfoCv`

> 本工具要求 **PowerShell 7 (pwsh)**。`.bat` 启动器会自动调用 `pwsh`；若命令行手动运行，也请使用 `pwsh` 而非 `powershell`（后者是 Windows PowerShell 5.1）。
> 所有脚本文件统一保存为 **UTF-8 无 BOM**，在 Windows Terminal 或 PowerShell 7 控制台中英文均可正确显示。

| 参数 | 说明 | 默认 |
| --- | --- | --- |
| `-Once` | 只检测一次就退出（默认行为） | 开 |
| `-Monitor` | 持续监测出口 IP 变化，稳定后自动检测 | 关 |
| `-Region <Overseas\|China\|Any>` | 目标区域建议文案 | `Overseas` |
| `-StablePolls <int>` | Monitor 模式：IP 连续稳定几次后触发 | `2` |
| `-PollIntervalSec <int>` | Monitor 模式轮询间隔（秒） | `15` |
| `-NoCrossCheck` | 关闭结构化 JSON IP 交叉验证 | 关（即开启） |
| `-OpenIpInfoCv` | 检测后打开 ipinfo.cv 供人工核对 | 关 |
| `-SkipInstall` | 跳过自动安装 ai-ipcheck（已装好时用） | 关 |
| `-TimeSync` | 开启时钟同步（w32tm /resync，通常需管理员） | 关 |
| `-SpeedTest` | 网速测试（参考 MyIP）：下载/上传带宽(Mbps) + 延迟/抖动(ms)，并显示就近接入的 Cloudflare 节点 | 关 |
| `-DnsCheck` | DNS 解析器检测：查询出口 DNS 是否与你本地网卡配置一致（泄漏/被接管迹象） | 关 |
| `-Reach` | 服务可达性：测 Claude / ChatGPT / Google / GitHub / YouTube / WeChat 的 RTT | 关 |
| `-NetPerf` | 一次性开启以上三项（= -SpeedTest -DnsCheck -Reach） | 关 |

---

> **网络性能检测（可选，参考 [MyIP](https://github.com/jason5ng32/MyIP) 思路）**：脚本内置网速、DNS 解析器、服务可达性三项检测，默认关闭。
> 分别用 `-SpeedTest`（下载/上传带宽 + 延迟/抖动）、`-DnsCheck`（出口 DNS 是否泄漏/被接管）、`-Reach`（Claude/ChatGPT/Google 等 RTT）开启，或用 `-NetPerf` 一次性全开。
> 示例：`pwsh -File ClaudeIpCheck.ps1 -Once -NetPerf`（测速走 Cloudflare 公共服务，DNS 走免费 edns.ip-api.com，均无付费依赖）。

## 四、结果怎么看

### 风险等级速查

| 等级 | 含义 | 建议 |
| --- | --- | --- |
| **低风险（绿）** | 环境干净，各项通过 | 可以稳定使用 Claude |
| **中风险（黄）** | 可用但需注意 | 建议开全局 TUN、关 WebRTC 本地 IP 泄漏、用清洁 DNS（如 1.1.1.1）、避免多人共用同一 IP |
| **高风险（红）** | 多项不通过 | 不建议直接用于 Claude，易被风控/封号；优先更换为家庭/住宅 IP 或合规代理 |

### 实际运行效果示例

下面是脚本在 Windows 终端中的实际输出样例（`stormzhang/ipcheck` 的完整检测结果 + 结构化交叉验证）：

![ipcheck 输出示例](screenshots/ipcheck-output-example.png)

从图中可以看到，脚本会依次展示：

| 检测区域 | 显示内容 |
| --- | --- |
| **本机信息** | 真实 IPv4、IPv6 状态、本地 DNS |
| **出口 IP 信息** | 出口 IP、国家/省份、城市、运营商、IP 归属、所处时区 |
| **环境检测** | 环境变量代理、系统代理、TUN/VPN、机房/住宅判断、IP 风险评分、垃圾滥用记录 |
| **时区一致性** | 系统时区 vs CLI 时区是否一致（桌面版 vs CLI 版差异）|
| **端点检测** | CLI 端点可达性、Anthropic 黑名单命中状态 |
| **检测建议** | 根据各项结果给出具体改进建议 |
| **综合结论** | 最终 **低 / 中 / 高** 风险判定（红色高亮高风险）|

> 注：上图截自用户真实机器（VPN 连接后），显示为中风险 42/100——属于可用但需优化的典型场景。
> 结构化交叉验证（ip-api.com）的独立判定会在 ipcheck 结果之前单独打印一行，例如：
> `[CROSS-CHECK] 出口 IP: 45.86.221.14 | 美国 / M247 Europe SRL | ⚠️ 可能是数据中心/机房 IP`

---

## 五、常见问题

**Q：提示「未找到 Python 3.10+」？**
重装 Python 并勾选 `Add to PATH`；或在安装后重启终端/电脑让 PATH 生效。

**Q：ipcheck 装不上 / 很慢？**
手动执行 `python -m pip install -U ai-ipcheck`；如网络受限可换源
`python -m pip install -U ai-ipcheck -i https://pypi.tuna.tsinghua.edu.cn/simple`。

**Q：想每次手动在浏览器里看 ipinfo.cv 的结果？**
加 `-OpenIpInfoCv` 参数（或改 bat 加上该参数）。

**Q：公司/校园网下检测不准？**
可能是出口做了 SNAT 或代理，结论仅供参考，以实际能否登录 Claude 为准。

---

## 六、目录结构

```
Claude-IPCheck-Toolkit/
├── ClaudeIpCheck.ps1              # 主脚本
├── Start-ClaudeIpCheck.bat        # 双击：单次检测
├── Start-ClaudeIpCheck-Monitor.bat# 双击：持续监测
├── Start-ClaudeIpCheck-NetPerf.bat# 双击：单次检测 + 网络性能检测（-NetPerf）
├── SKILL.md                       # Agent Skills 标准（WorkBuddy / Qoder / Trae / Claude Code 共用）
├── AGENTS.md                      # 通用指令文件（Codex 及所有读 AGENTS.md 的工具）
├── codex.md                       # Codex 专用指令（内容同 AGENTS.md）
├── screenshots/
│   └── ipcheck-output-example.png # 输出示例截图
├── README.md
├── LICENSE
└── .gitignore
```

---

## 七、跨工具安装（同一份文件夹，复制到各自 skills 目录即可）

本 skill 遵循 **Agent Skills 开放标准**（`SKILL.md` + `name`/`description` frontmatter），
WorkBuddy、Qoder、Trae、Claude Code 共用同一套格式，只需把解压后的
`claude-ipcheck-toolkit/` 文件夹复制到对应工具的 skills 目录即可使用。

| 工具 | 用户级 skills 目录 | 项目级 |
| --- | --- | --- |
| **WorkBuddy** | `~/.workbuddy/skills/claude-ipcheck-toolkit/` | — |
| **Qoder** | `~/.qoder/skills/claude-ipcheck-toolkit/`（国内版 `~/.qoder-cn/skills/`） | `.qoder/skills/claude-ipcheck-toolkit/` |
| **Trae** | `~/.trae/skills/claude-ipcheck-toolkit/`（Win: `%userprofile%\.trae\skills\`） | `.trae/skills/claude-ipcheck-toolkit/` |
| **Claude Code** | `~/.claude/skills/claude-ipcheck-toolkit/` | — |
| **Codex** | 读取 `AGENTS.md` / `codex.md`（本包已含，放项目根或用户级） | 项目根 `AGENTS.md` |

**安装步骤（以 WorkBuddy 为例，其余同理）：**
1. 解压 `Claude-IPCheck-Toolkit.zip`，得到内层 `claude-ipcheck-toolkit/` 文件夹。
2. 复制到目标工具的 skills 目录（文件夹名须与 `name:` 一致，即 `claude-ipcheck-toolkit`）。
3. 触发方式：直接说"检测我的网络能不能用 Claude"，或 `/claude-ipcheck-toolkit`。

> 注：Qoder 国内版路径为 `~/.qoder-cn/skills/`；Trae 旧版全局路径为 `~/.traecli/skills/`，以实际客户端为准。
> Codex 通过本包随附的 `AGENTS.md` / `codex.md` 自动读取本工具说明。

---

## 免责声明

本工具仅用于**网络环境自检与学习**，不提供、不推荐任何绕开服务地区限制的手段。
检测结果受出口 IP、DNS、WebRTC、时区等多因素影响，仅供参考，不构成任何保证。
请遵守你所使用服务的官方条款与当地法律法规。
