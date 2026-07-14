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
      - 修复向导（-Remediate）：检测后根据「使用建议」逐项列出可自动修复项
        （禁用 IPv6 / 清洁 DNS / 刷新 DNS 缓存 / 设置系统代理 /
         按出口 IP 自动设置系统时区并对时），每项先展示将要执行的命令、人工确认后再执行。
        非管理员运行时，向导会询问是否自动以管理员身份重新启动，确保需提权的项真正生效。
        注：禁用 IPv6、修改 DNS、设置时区 需管理员权限；TUN、WebRTC 泄漏为浏览器/代理软件侧，
        脚本仅给出手动操作指引，无法直接修改。

    全程不修改默认浏览器、不写入任何注册表（修复项仅改网络适配器绑定 / DNS /
    系统代理与环境变量，均可在系统设置中还原）。无需管理员权限即可运行检测；
    修复向导中需管理员权限的项会在非管理员下提示并以管理员身份重跑。

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

.PARAMETER Remediate
    检测完成后启动「网络修复向导」：根据「使用建议」逐项列出可自动修复项，
    每项先展示将要执行的命令、人工确认（Y/N）后再执行。可输入多个编号（如 1,2,3）或 0 退出。
    需要管理员权限的项（禁用 IPv6、修改 DNS、按 IP 设置时区）在非管理员下，
    向导会询问是否自动以管理员身份重新启动；同意后在新窗口中完成完整修复。
    其中「按出口 IP 自动设置系统时区」会读取出口 IP 的时区（如日本→Tokyo Standard Time），
    调用 Set-TimeZone 修改系统时区后再对时，解决「多次对时仍是原时区」的问题。
    双击 Start-ClaudeIpCheck-Remediate.bat 即为此模式。

.EXAMPLE
    # 一键检测（双击 Start-ClaudeIpCheck.bat 即为此模式）
    .\ClaudeIpCheck.ps1 -Once

.EXAMPLE
    # 检测后启动修复向导，逐项确认并自动修复
    .\ClaudeIpCheck.ps1 -Once -Remediate

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
    [switch]$Once,
    [switch]$Remediate
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

# ===================== 可选：网络修复向导 =====================
# 说明：以下修复项仅修改网络适配器绑定 / DNS / 系统代理与环境变量，
#       均可在系统设置中还原，不会写入敏感注册表。

function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Disable-IPv6OnAdapters {
    Write-Step '禁用所有活动网络适配器的 IPv6（防止 IPv6 泄漏真实地址）...'
    try {
        $adapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }
        if ($null -eq $adapters -or @($adapters).Count -eq 0) { Write-Warn '未找到活动网络适配器'; return }
        $ok = 0
        foreach ($a in $adapters) {
            try {
                Disable-NetAdapterBinding -Name $a.Name -ComponentID ms_tcpip6 -ErrorAction Stop
                Write-Ok ('  已禁用 IPv6: ' + $a.Name)
                $ok++
            }
            catch {
                # 回退到 netsh
                try {
                    & netsh interface ipv6 set interface "$($a.Name)" disabled 2>&1 | Out-Null
                    Write-Ok ('  已禁用 IPv6 (netsh): ' + $a.Name)
                    $ok++
                }
                catch {
                    Write-Warn ('  禁用失败 ' + $a.Name + ': ' + $_.Exception.Message)
                }
            }
        }
        if ($ok -gt 0) { Write-Ok ('共禁用 ' + $ok + ' 个适配器的 IPv6') }
    }
    catch {
        Write-Err ('获取网络适配器失败（可能不支持 NetAdapter 模块）: ' + $_.Exception.Message)
    }
}

function Clear-DnsCache {
    Write-Step '刷新 DNS 缓存 (ipconfig /flushdns) ...'
    try {
        $r = (ipconfig /flushdns 2>&1 | Out-String)
        if ($r -match 'successfully' -or $r -match '已成功') { Write-Ok 'DNS 缓存已刷新' }
        else { Write-Info $r.Trim() }
    }
    catch {
        Write-Warn ('刷新失败: ' + $_.Exception.Message)
    }
}

function Set-CleanDns([string[]]$DnsServers) {
    Write-Step ('设置清洁 DNS 为 ' + ($DnsServers -join ' / ') + ' ...')
    try {
        $adapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }
        if ($null -eq $adapters -or @($adapters).Count -eq 0) { Write-Warn '未找到活动网络适配器'; return }
        $ok = 0
        foreach ($a in $adapters) {
            try {
                Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $DnsServers -ErrorAction Stop
                Write-Ok ('  已设置 DNS: ' + $a.Name + ' -> ' + ($DnsServers -join ', '))
                $ok++
            }
            catch {
                try {
                    & netsh interface ip set dns name="$($a.Name)" static $($DnsServers[0]) 2>&1 | Out-Null
                    for ($i = 1; $i -lt $DnsServers.Count; $i++) {
                        & netsh interface ip add dns name="$($a.Name)" $($DnsServers[$i]) index=2 2>&1 | Out-Null
                    }
                    Write-Ok ('  已设置 DNS (netsh): ' + $a.Name)
                    $ok++
                }
                catch {
                    Write-Warn ('  设置失败 ' + $a.Name + ': ' + $_.Exception.Message)
                }
            }
        }
        if ($ok -gt 0) {
            Write-Ok ('共设置 ' + $ok + ' 个适配器的 DNS')
            Clear-DnsCache
        }
    }
    catch {
        Write-Err ('获取网络适配器失败: ' + $_.Exception.Message)
    }
}

function Set-SystemProxy {
    Write-Step '设置系统代理 ...'
    $addr = Read-Host '请输入代理服务器地址（如 127.0.0.1:7890，留空跳过）'
    if ([string]::IsNullOrWhiteSpace($addr)) { Write-Info '已跳过代理设置'; return }
    try {
        # 设置系统代理（注册表，当前用户）
        $reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        Set-ItemProperty -Path $reg -Name ProxyEnable -Value 1 -ErrorAction Stop
        Set-ItemProperty -Path $reg -Name ProxyServer -Value $addr -ErrorAction Stop
        # 写入环境变量（当前进程 + 用户级，供后续命令行工具使用）
        $env:HTTP_PROXY  = "http://$addr"; $env:HTTPS_PROXY = "http://$addr"
        $env:http_proxy  = "http://$addr"; $env:https_proxy = "http://$addr"
        [Environment]::SetEnvironmentVariable('HTTP_PROXY',  "http://$addr", 'User')
        [Environment]::SetEnvironmentVariable('HTTPS_PROXY', "http://$addr", 'User')
        [Environment]::SetEnvironmentVariable('http_proxy',  "http://$addr", 'User')
        [Environment]::SetEnvironmentVariable('https_proxy', "http://$addr", 'User')
        Write-Ok ('已设置系统代理为 ' + $addr + ' 并写入用户级环境变量')
        Write-Warn '提示：需重启浏览器 / 部分应用才能生效；取消代理可在「设置 → 网络 → 代理」中关闭「使用代理服务器」。'
    }
    catch {
        Write-Err ('设置代理失败: ' + $_.Exception.Message)
    }
}

function Sync-TimeForce {
    Write-Step '时间同步 (w32tm /resync) ...'
    try {
        $r = (w32tm /resync 2>&1 | Out-String)
        if ($r -match 'successfully' -or $r -match '成功') { Write-Ok '时钟已同步' }
        else { Write-Warn ('同步结果: ' + $r.Trim()) }
    }
    catch { Write-Warn '需要管理员权限才能同步时钟，已跳过' }
}

# 将 IANA 时区名（如 Asia/Tokyo）转换为 Windows 时区 ID（如 Tokyo Standard Time）
function Convert-IanaToWindowsTimeZone([string]$iana) {
    if ([string]::IsNullOrWhiteSpace($iana)) { return '' }
    # 优先使用 .NET 6+/PowerShell 7 内置转换
    try {
        $win = ''
        if ([System.TimeZoneInfo]::TryConvertIanaIdToWindowsId($iana, [ref]$win)) {
            if (-not [string]::IsNullOrWhiteSpace($win)) { return $win }
        }
    }
    catch { }
    # 回退：常见地区手工映射（覆盖代理常用出口地）
    $map = @{
        'Asia/Tokyo'         = 'Tokyo Standard Time'
        'Asia/Osaka'         = 'Tokyo Standard Time'
        'Asia/Seoul'         = 'Korea Standard Time'
        'Asia/Hong_Kong'     = 'China Standard Time'
        'Asia/Shanghai'      = 'China Standard Time'
        'Asia/Taipei'        = 'Taipei Standard Time'
        'Asia/Singapore'     = 'Singapore Standard Time'
        'Asia/Kuala_Lumpur'  = 'Singapore Standard Time'
        'Asia/Bangkok'       = 'SE Asia Standard Time'
        'Asia/Kolkata'       = 'India Standard Time'
        'Asia/Dubai'         = 'Arabian Standard Time'
        'Europe/London'      = 'GMT Standard Time'
        'Europe/Paris'       = 'W. Europe Standard Time'
        'Europe/Berlin'      = 'W. Europe Standard Time'
        'Europe/Amsterdam'   = 'W. Europe Standard Time'
        'Europe/Moscow'      = 'Russian Standard Time'
        'America/New_York'   = 'Eastern Standard Time'
        'America/Chicago'    = 'Central Standard Time'
        'America/Denver'     = 'Mountain Standard Time'
        'America/Los_Angeles'= 'Pacific Standard Time'
        'America/Toronto'    = 'Eastern Standard Time'
        'Australia/Sydney'   = 'AUS Eastern Standard Time'
        'UTC'                = 'UTC'
    }
    if ($map.ContainsKey($iana)) { return $map[$iana] }
    return ''
}

# 根据出口 IP 的时区，自动设置 Windows 系统时区并同步时间（需管理员权限）
function Set-TimeZoneByIp($ipInfo) {
    Write-Step '根据出口 IP 自动设置系统时区 ...'
    if ($null -eq $ipInfo) { $ipInfo = Get-IpApiInfo }
    if ($null -eq $ipInfo -or [string]::IsNullOrWhiteSpace($ipInfo.timezone)) {
        Write-Warn '  无法获取出口 IP 的时区信息，改为仅同步时间'
        Sync-TimeForce
        return
    }
    $iana = $ipInfo.timezone
    Write-Info ('  出口 IP 时区 (IANA): ' + $iana + '  国家: ' + $ipInfo.country)
    $winId = Convert-IanaToWindowsTimeZone $iana
    if ([string]::IsNullOrWhiteSpace($winId)) {
        Write-Warn ('  无法将 ' + $iana + ' 映射到 Windows 时区 ID，改为仅同步时间')
        Sync-TimeForce
        return
    }
    $cur = (Get-TimeZone).Id
    if ($cur -eq $winId) {
        Write-Ok ('  当前系统时区已是 ' + $winId + '，无需更改')
    }
    else {
        try {
            Set-TimeZone -Id $winId -ErrorAction Stop
            Write-Ok ('  系统时区已从 [' + $cur + '] 改为 [' + $winId + ']')
        }
        catch {
            Write-Err ('  设置时区失败（需管理员权限）: ' + $_.Exception.Message)
            return
        }
    }
    Sync-TimeForce
    $now = Get-Date
    Write-Ok ('  当前系统时间: ' + $now.ToString('yyyy-MM-dd HH:mm:ss') + '  (' + (Get-TimeZone).Id + ')')
}

function Show-WebRtcGuide {
    Write-Host ''
    Write-Warn 'WebRTC 本地 IP 泄漏需在浏览器中关闭 WebRTC，脚本无法直接修改浏览器内核：'
    Write-Info '  - Chrome / Edge：安装扩展「WebRTC Leak Prevent」或「uBlock Origin」（开启「防止 WebRTC 泄漏」）。'
    Write-Info '  - Firefox：地址栏输入 about:config，设置 media.peerconnection.enabled = false。'
    Write-Info '  - 或使用支持「禁用 WebRTC」的代理客户端（如 Clash / v2rayN 的 TUN 模式）。'
}

function Start-Remediation($ipInfo) {
    $admin = Test-IsAdmin
    Write-Host "`n========== 网络修复向导 ==========" -ForegroundColor Magenta

    # ---- A：非管理员时，尝试自动提权重跑，确保需管理员的项真正生效 ----
    if (-not $admin) {
        Write-Warn '当前未以管理员身份运行：禁用 IPv6 / 修改 DNS / 设置系统时区 均需要管理员权限。'
        $ele = Read-Host '是否以管理员身份重新运行以启用完整修复？(Y/N)'
        if ($ele -match '^[Yy]') {
            try {
                $exe = (Get-Process -Id $PID).Path
                if ([string]::IsNullOrWhiteSpace($exe)) { $exe = 'pwsh' }
                $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-Once', '-Remediate')
                Start-Process -FilePath $exe -Verb RunAs -ArgumentList $argList
                Write-Info '已请求以管理员身份重新启动，请在新弹出的窗口中继续操作。本窗口即将退出。'
                return
            }
            catch {
                Write-Err ('提权启动失败: ' + $_.Exception.Message)
                Write-Info '将以当前权限继续（需管理员的项会被跳过）。'
            }
        }
        else {
            Write-Info '将以当前权限继续（需管理员的项会被跳过）。'
        }
    }

    $menu = @(
        @{ Key='1'; Name='禁用 IPv6（防止 IPv6 泄漏真实地址）';        NeedAdmin=$true;  Action={ Disable-IPv6OnAdapters } }
        @{ Key='2'; Name='设置清洁 DNS（1.1.1.1 / 8.8.8.8）';         NeedAdmin=$true;  Action={ Set-CleanDns @('1.1.1.1','8.8.8.8') } }
        @{ Key='3'; Name='刷新 DNS 缓存';                              NeedAdmin=$false; Action={ Clear-DnsCache } }
        @{ Key='4'; Name='设置系统代理 / 环境变量';                   NeedAdmin=$false; Action={ Set-SystemProxy } }
        @{ Key='5'; Name='按出口 IP 自动设置系统时区并对时';          NeedAdmin=$true;  Action={ Set-TimeZoneByIp $ipInfo } }
        @{ Key='6'; Name='查看 WebRTC 泄漏手动修复指引';              NeedAdmin=$false; Action={ Show-WebRtcGuide } }
    )

    while ($true) {
        Write-Host ''
        Write-Host '可修复项（输入编号，多个用逗号分隔；输入 0 退出）：' -ForegroundColor Cyan
        foreach ($m in $menu) {
            $tag = if ($m.NeedAdmin -and -not $admin) { ' [需管理员]' } else { '' }
            Write-Host ('  [' + $m.Key + '] ' + $m.Name + $tag)
        }
        $input = Read-Host '请选择'
        if ([string]::IsNullOrWhiteSpace($input) -or $input.Trim() -eq '0') { Write-Info '已退出修复向导'; break }
        $keys = $input -split '[, ]' | Where-Object { $_ -match '^\d+$' }
        $any = $false
        foreach ($k in $keys) {
            $m = $menu | Where-Object { $_.Key -eq $k }
            if ($null -eq $m) { continue }
            if ($m.NeedAdmin -and -not $admin) {
                Write-Warn ('项 [' + $m.Key + '] 需要管理员权限，当前跳过。请以管理员身份重新运行。')
                continue
            }
            $any = $true
            Write-Host ("`n>>> 即将执行：" + $m.Name) -ForegroundColor Yellow
            $confirm = Read-Host '确认执行？ (Y/N)'
            if ($confirm -match '^[Yy]') {
                & $m.Action
            }
            else {
                Write-Info ('已跳过：' + $m.Name)
            }
        }
        if (-not $any) { Write-Warn '未识别到有效选项，请重试' }
    }
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

    # ---- 6) 可选：网络修复向导 ----
    if ($Remediate) {
        Write-Host ''
        $go = Read-Host '是否根据建议进行自动修复？（Y/N）'
        if ($go -match '^[Yy]') {
            Start-Remediation $ip
        }
        else {
            Write-Info '跳过自动修复'
        }
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
