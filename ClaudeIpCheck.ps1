<#
.SYNOPSIS
    Claude-IPCheck Toolkit —— 一键检测当前网络是否适合稳定使用 Claude AI

.DESCRIPTION
    本脚本面向 Windows 用户，用于验证「当前网络环境能否稳定、低风控地使用 Claude AI」。
    它做两件事：

      1) 自动化交叉验证（默认开启）
         通过结构化 JSON IP API（ip-api.com，免费、无需密钥）获取出口 IP 的国家/地区、
         ISP、ASN、组织，并据此判断是否为「机房 / 数据中心 IP」——这是 Claude 风控的高风险项。

      2) 运行 stormzhang/ipcheck（ai-ipcheck，GitHub 同名仓库）
         做 Claude 专项分析：IP 属地、DNS 泄漏、代理、时区、Claude 端点可达性、
         数据中心风险，最终给出「低 / 中 / 高」风险综合结论与评分。

    可选能力：
      - 在浏览器打开 https://ipinfo.cv/claude-ai-check 供人工肉眼核对
        （该页面是纯前端 JS 渲染，无法被脚本解析，只能人工看，因此不作为自动约束）。
      - 持续监测出口 IP 变化（Monitor 模式）：IP 稳定进入目标区域后自动跑检测。
      - 可选时间同步（w32tm /resync，需管理员权限，失败不致命）。

    全程不修改默认浏览器、不写入任何注册表。无需管理员权限即可运行。

.PARAMETER Monitor
    持续监测出口 IP 变化；当同一 IP 连续稳定 StablePolls 次轮询后，自动运行检测。
    Ctrl+C 退出。

.PARAMETER Region
    目标区域，用于给出「是否适合用 Claude」的建议：
      Overseas（默认，适合用 Claude）/ China / Any。
    注意：无论区域如何，ipcheck 都会照常运行，Region 仅影响结论文案。

.PARAMETER StablePolls
    Monitor 模式下，同一 IP 连续稳定多少次轮询后才触发检测（默认 2）。

.PARAMETER PollIntervalSec
    Monitor 模式轮询间隔秒数（默认 15）。

.PARAMETER NoCrossCheck
    关闭结构化 JSON IP API 交叉验证（默认开启）。仅在你无法访问 ip-api.com 时使用。

.PARAMETER OpenIpInfoCv
    检测完成后在默认浏览器打开 ipinfo.cv/claude-ai-check 供人工核对。

.PARAMETER SkipInstall
    跳过自动安装 ai-ipcheck（若你已手动装好，可加此开关避免重复安装）。

.PARAMETER TimeSync
    开启时间同步（w32tm /resync）。默认关闭，因为会改变系统时钟、且通常需要管理员权限。

.PARAMETER Once
    只跑一次检测即退出（默认行为，可省略）。

.EXAMPLE
    # 一键检测（双击 Start-ClaudeIpCheck.bat 即为此模式）
    .\ClaudeIpCheck.ps1 -Once

.EXAMPLE
    # 持续监测，IP 稳定后自动检测，并在浏览器打开 ipinfo.cv 人工核对
    .\ClaudeIpCheck.ps1 -Monitor -OpenIpInfoCv

.EXAMPLE
    # 仅做结构化 IP 交叉验证 + ipcheck，不做时间同步、不打开网页
    .\ClaudeIpCheck.ps1
#>
[CmdletBinding()]
param(
    [switch]$Monitor,
    [ValidateSet('Overseas', 'China', 'Any')]
    [string]$Region = 'Overseas',
    [int]$StablePolls = 2,
    [int]$PollIntervalSec = 15,
    [switch]$NoCrossCheck,
    [switch]$OpenIpInfoCv,
    [switch]$SkipInstall,
    [switch]$TimeSync,
    [switch]$Once
)

# ===================== 基础设置 =====================
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LogFile   = Join-Path $scriptDir 'ClaudeIpCheck.log'

# 强制本会话使用 UTF-8，避免中文在管道 / 子进程中乱码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = 'utf-8'

# ===================== 日志 / 颜色辅助 =====================
function Write-Log($msg) {
    try { Add-Content -Path $LogFile -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) } catch { }
}
function Write-Step($m) { Write-Host ('==> ' + $m) -ForegroundColor Cyan; Write-Log $m }
function Write-Ok($m)   { Write-Host ('[OK] ' + $m) -ForegroundColor Green; Write-Log $m }
function Write-Warn($m) { Write-Host ('[!] ' + $m) -ForegroundColor Yellow; Write-Log $m }
function Write-Err($m)  { Write-Host ('[X] ' + $m) -ForegroundColor Red; Write-Log $m }
function Write-Info($m) { Write-Host $m; Write-Log $m }

# 去除 ANSI 转义序列（ipcheck 等 CLI 常带颜色码）
function Remove-Ansi($s) {
    if ($null -eq $s) { return '' }
    return [regex]::Replace($s, '\x1B\[[0-9;]*m', '')
}

# ===================== 结构化 IP 交叉验证 =====================
# 返回 @{ ip, country, countryCode, isp, org, as, timezone, source } 或 $null
function Get-IpApiInfo {
    $urls = @('http://ip-api.com/json/', 'https://ipinfo.io/json')
    foreach ($u in $urls) {
        try {
            $raw = Invoke-RestMethod -Uri $u -TimeoutSec 12 -ErrorAction Stop
            if ($null -eq $raw) { continue }
            $ip = if ($raw.query) { $raw.query } else { $raw.ip }
            if (-not $ip) { continue }
            return @{
                ip          = $ip
                country     = if ($raw.country) { $raw.country } else { '' }
                countryCode = if ($raw.countryCode) { $raw.countryCode } else { '' }
                isp         = if ($raw.isp) { $raw.isp } else { '' }
                org         = if ($raw.org) { $raw.org } else { '' }
                as          = if ($raw.as) { $raw.as } else { $raw.asn }
                timezone    = if ($raw.timezone) { $raw.timezone } else { '' }
                source      = $u
            }
        }
        catch {
            Write-Log ("Get-IpApiInfo failed for " + $u + ": " + $_.Exception.Message)
        }
    }
    return $null
}

# 启发式判断是否为机房 / 数据中心 IP（Claude 风控高风险项）
function Test-DatacenterIp($info) {
    $s = (($info.org) + ' ' + $info.as + ' ' + $info.isp).ToLower()
    $kw = @('datacenter', 'data center', 'cloud', 'hosting', 'server', 'vps',
            'digital', 'datacamp', 'ovh', 'hetzner', 'amazon', 'aws', 'google',
            'microsoft', 'azure', 'alibaba', 'tencent', 'leaseweb', 'colocation',
            'dedicated', 'linode', 'vultr', 'digitalocean')
    foreach ($k in $kw) { if ($s.Contains($k)) { return $true } }
    return $false
}

# ===================== Python / ipcheck =====================
function Find-Python {
    $cands = @('python', 'python3', 'py')
    foreach ($c in $cands) {
        try {
            $cmd = Get-Command $c -ErrorAction SilentlyContinue
            if ($null -eq $cmd) { continue }
            $src = $cmd.Source
            $ver = (& $src --version 2>&1 | Out-String)
            if ($ver -match 'Python (\d+)\.(\d+)') {
                $maj = [int]$Matches[1]; $min = [int]$Matches[2]
                if ($maj -ge 3 -and ($maj -gt 3 -or $min -ge 10)) {
                    return $src
                }
            }
        }
        catch { }
    }
    return $null
}

function Test-IpCheckInstalled($py) {
    try {
        $out = (& $py -m ipcheck --help 2>&1 | Out-String)
        if ($out -match 'No module named') { return $false }
        if ($out -match 'ipcheck' -or $out -match 'usage' -or $out -match 'Claude') { return $true }
        return $false
    }
    catch { return $false }
}

function Install-IpCheck($py) {
    Write-Step '正在安装 ai-ipcheck (python -m pip install --upgrade ai-ipcheck) ...'
    try {
        & $py -m pip install --upgrade ai-ipcheck 2>&1 | ForEach-Object { Write-Host $_ }
        if (Test-IpCheckInstalled $py) { Write-Ok 'ai-ipcheck 安装成功'; return $true }
        Write-Err '安装后仍未找到 ipcheck 模块'
        return $false
    }
    catch {
        Write-Err ('安装失败: ' + $_.Exception.Message)
        return $false
    }
}

function Invoke-IpCheck($py) {
    Write-Step '运行 stormzhang/ipcheck 进行 Claude 专项检测 ...'
    try {
        $lines = @()
        & $py -m ipcheck 2>&1 | ForEach-Object { $lines += $_ }
        $raw    = Remove-Ansi ($lines -join "`n")
        $verdict = '未知'
        if ($raw -match '(低|中|高)风险') { $verdict = $Matches[1] + '风险' }
        $score = $null
        if ($raw -match '(\d+)\s*/\s*100') { $score = [int]$Matches[1] }
        return @{ raw = $raw; verdict = $verdict; score = $score }
    }
    catch {
        Write-Err ('ipcheck 运行异常: ' + $_.Exception.Message)
        return @{ raw = ''; verdict = '未知'; score = $null }
    }
}

# ===================== 可选：时间同步 =====================
function Sync-Time {
    if ($NoTimeSync -or -not $TimeSync) { return }
    Write-Step '时间同步 (w32tm /resync) ...'
    try {
        $r = (w32tm /resync 2>&1 | Out-String)
        if ($r -match 'successfully' -or $r -match '成功') { Write-Ok '时钟已同步' }
        else { Write-Warn ('同步结果: ' + $r.Trim()) }
    }
    catch { Write-Warn '需要管理员权限才能同步时钟，已跳过' }
}

function Open-Browser($url) {
    try { Start-Process $url } catch { Write-Warn ('无法打开浏览器: ' + $url) }
}

# ===================== 主检测流程 =====================
function Run-Once($ip) {
    Write-Host ('`n========== Claude-IPCheck 检测 ==========') -ForegroundColor Magenta
    Write-Info ('目标区域建议: ' + $Region)

    if ($null -eq $ip -and -not $NoCrossCheck) {
        $ip = Get-IpApiInfo
    }

    # ---- 1) 结构化交叉验证 ----
    if (-not $NoCrossCheck -and $ip) {
        Write-Step '交叉验证 (ip-api.com 结构化数据)'
        Write-Info ('  出口 IP : ' + $ip.ip)
        Write-Info ('  国家    : ' + $ip.country + ' (' + $ip.countryCode + ')')
        Write-Info ('  ISP     : ' + $ip.isp)
        Write-Info ('  组织    : ' + $ip.org)
        Write-Info ('  ASN     : ' + $ip.as)

        if (Test-DatacenterIp $ip) {
            Write-Warn '  [!] 该 IP 疑似机房 / 数据中心 IP（Claude 风控高风险项）'
        }
        else {
            Write-Ok '  未命中常见机房特征（仍以 ipcheck 结论为准）'
        }

        $isChina = ($ip.countryCode -eq 'CN')
        if ($isChina) {
            Write-Warn '  [!] 当前为国内 (CN) 出口，使用 Claude 风险较高'
        }
        else {
            Write-Ok '  当前为海外出口，可作为 Claude 使用环境'
        }
    }
    elseif ($NoCrossCheck) {
        Write-Warn '交叉验证已关闭，跳过结构化 IP 核查'
    }
    else {
        Write-Warn '无法获取出口 IP 信息（可能无网络或被墙），仍尝试运行 ipcheck'
    }

    # ---- 2) Python + ipcheck ----
    $py = Find-Python
    if (-not $py) {
        Write-Err '未找到 Python 3.10+。请先安装 Python 3.10+ 并勾选「Add to PATH」，再重试。'
        Write-Info '下载地址: https://www.python.org/downloads/'
        return
    }
    Write-Ok ('找到 Python: ' + $py)

    if (-not $SkipInstall) {
        if (-not (Test-IpCheckInstalled $py)) {
            $ok = Install-IpCheck $py
            if (-not $ok) {
                Write-Err 'ai-ipcheck 安装失败，请手动执行: python -m pip install ai-ipcheck'
                return
            }
        }
        else { Write-Ok 'ai-ipcheck 已就绪' }
    }

    # ---- 3) 可选时间同步 ----
    Sync-Time

    # ---- 4) 运行 ipcheck ----
    $res = Invoke-IpCheck $py

    Write-Host ('`n----- ipcheck 综合结论 -----') -ForegroundColor Cyan
    if ($null -ne $res.score) { Write-Info ('  评分: ' + $res.score + '/100') }
    if ($res.verdict -ne '未知') {
        $col = if ($res.verdict -eq '低风险') { 'Green' }
                elseif ($res.verdict -eq '中风险') { 'Yellow' }
                else { 'Red' }
        Write-Host ('  结论: ' + $res.verdict) -ForegroundColor $col
    }
    else {
        Write-Warn '未能解析 ipcheck 结论，已输出原始结果：'
    }
    Write-Host ($res.raw)

    # ---- 5) 使用建议 ----
    Write-Host ('`n----- 使用建议 -----') -ForegroundColor Cyan
    if ($res.verdict -eq '高风险') {
        Write-Warn '高风险：当前网络环境不建议直接用于 Claude，易被风控 / 封号。建议更换为更干净的家庭 / 住宅 IP 或合规代理，并开启全局 TUN、关闭 WebRTC 泄漏。'
    }
    elseif ($res.verdict -eq '中风险') {
        Write-Warn '中风险：可尝试使用，但建议开启全局 TUN、关闭 WebRTC 本地 IP 泄漏、使用清洁 DNS（如 1.1.1.1）、避免多人共享同一 IP。'
    }
    else {
        Write-Ok '低风险：当前网络环境适合稳定使用 Claude。'
    }

    if ($OpenIpInfoCv) {
        Write-Step '打开 ipinfo.cv 供人工核对 ...'
        Open-Browser 'https://ipinfo.cv/claude-ai-check'
    }
}

# ===================== 入口 =====================
if ($Monitor) {
    Write-Step ('进入监测模式：每 ' + $PollIntervalSec + ' 秒检测出口 IP，稳定 ' + $StablePolls + ' 次后运行检测 (Ctrl+C 退出)')
    $lastIp = $null; $stable = 0; $checked = $null
    try {
        while ($true) {
            $ip = Get-IpApiInfo
            if ($null -eq $ip) { Start-Sleep -Seconds $PollIntervalSec; continue }
            if ($ip.ip -eq $lastIp) { $stable++ } else { $lastIp = $ip.ip; $stable = 1 }
            Write-Info ('轮询: IP=' + $ip.ip + ' 稳定次数=' + $stable + '/' + $StablePolls)
            if ($stable -ge $StablePolls -and $ip.ip -ne $checked) {
                $checked = $ip.ip
                Run-Once $ip
            }
            Start-Sleep -Seconds $PollIntervalSec
        }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        Write-Info '`n已退出监测模式'
    }
}
else {
    Run-Once $null
}
