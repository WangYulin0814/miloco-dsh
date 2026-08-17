#requires -Version 5.1
<#
.SYNOPSIS
    miloco-dsh 一键安装(Windows / PowerShell 5.1+ 与 PowerShell 7)
.DESCRIPTION
    把小米 Miloco 智能家居能力装进 DeepSeek Harness(DSH):
      * 将 mcp-miloco 条目幂等合并进 $DSH_HOME\profiles\web\cordis.patch.yml(写入前自动备份)
      * 安装 miloco 技能到 $DSH_HOME\skills\miloco
      * 自动发现并设置 MILOCO_TOKEN(本机 ~\.miloco\config.json 或 WSL 发行版内的后端)
      * 运行 MCP 冒烟验证(server\test-mcp.js,无需后端)
    可重复执行,幂等。安装后重启 dsh web 生效。
.EXAMPLE
    # 标准一句话安装
    irm https://raw.githubusercontent.com/WangYulin0814/miloco-dsh/main/install.ps1 | iex
.EXAMPLE
    # 用本机已有的仓库目录(不重新下载)
    .\install.ps1 -RepoPath "C:\path\to\miloco-dsh"
.EXAMPLE
    # 下载后预览将执行的动作(不实际修改)
    irm https://raw.githubusercontent.com/WangYulin0814/miloco-dsh/main/install.ps1 -OutFile install.ps1
    .\install.ps1 -WhatIf
#>
[CmdletBinding()]
param(
    [string]$RepoPath = '',   # 已有仓库目录;缺省时若脚本自身就在仓库内则直接用
    [string]$InstallDir = '', # 下载安装目录,默认 $HOME\miloco-dsh
    [string]$Owner = 'WangYulin0814',
    [string]$Repo = 'miloco-dsh',
    [string]$Branch = 'main',
    [string]$DshHome = '',    # DSH 家目录;默认 $env:DSH_HOME 或 $HOME\.dsh
    [string]$BaseUrl = 'http://127.0.0.1:1810',
    [string]$Token = '',      # 可选:直接指定后端 token(写入用户环境变量)
    [switch]$NoToken,         # 跳过 token 检查/自动发现
    [switch]$Force,           # 强制重新下载覆盖已存在的仓库目录
    [switch]$SkipVerify,      # 跳过 MCP 冒烟验证
    [switch]$WhatIf           # 只打印将要执行的动作
)

$ErrorActionPreference = 'Stop'

# PowerShell 5.1 需要显式启用 TLS 1.2
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

function Write-Step([string]$msg) { Write-Host "==> $msg" }
function Fail([string]$msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

# ---------- 仓库目录解析(下载或使用本地) ----------
function Get-RemoteRepo {
    param([string]$Dir, [string]$Owner, [string]$Repo, [string]$Branch, [switch]$Force)
    $serverJs = Join-Path $Dir 'server\miloco-mcp.js'
    if ((Test-Path $serverJs) -and -not $Force) {
        if (Test-Path (Join-Path $Dir '.git')) {
            Write-Step "更新已有仓库: git pull"
            $prev = Get-Location
            Set-Location $Dir
            git pull --ff-only 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Host "git pull 完成" } else { Write-Warning "git pull 失败(忽略),继续使用现有文件" }
            Set-Location $prev
        } else {
            Write-Host "已存在 $Dir(使用现有文件;加 -Force 可重新下载)"
        }
        return
    }
    if ($WhatIf) { Write-Host "[WhatIf] 将下载 https://github.com/$Owner/$Repo (branch=$Branch) 到 $Dir"; return }
    Write-Step "下载仓库 $Owner/$Repo (branch=$Branch) -> $Dir"
    $zip = Join-Path $env:TEMP "miloco-dsh-$Branch.zip"
    $url = "https://codeload.github.com/$Owner/$Repo/zip/refs/heads/$Branch"
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 300
    } catch {
        Fail "下载失败: $($_.Exception.Message) (请检查网络;或改用 -RepoPath 指向已有仓库)"
    }
    $tmp = Join-Path $env:TEMP "miloco-dsh-extract"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    if (-not $inner) { Fail "解压失败: zip 内容异常" }
    if (Test-Path $Dir) { Remove-Item $Dir -Recurse -Force }
    Move-Item $inner.FullName $Dir
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path (Join-Path $Dir 'server\miloco-mcp.js'))) { Fail "下载内容不完整(缺少 server\miloco-mcp.js)" }
}

function Resolve-RepoDir {
    param([string]$Explicit, [string]$DefaultDir)
    if ($Explicit) {
        if (-not (Test-Path (Join-Path $Explicit 'server\miloco-mcp.js'))) {
            Fail "RepoPath 无效: 未找到 server\miloco-mcp.js ($Explicit)"
        }
        return (Resolve-Path $Explicit).Path
    }
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'server\miloco-mcp.js'))) {
        return $PSScriptRoot
    }
    if (-not $DefaultDir) { $DefaultDir = Join-Path $HOME 'miloco-dsh' }
    Get-RemoteRepo -Dir $DefaultDir -Owner $Owner -Repo $Repo -Branch $Branch -Force:$Force
    return $DefaultDir
}

# ---------- DSH 家目录解析 ----------
function Resolve-DshHome {
    param([string]$Explicit)
    if ($Explicit) { $h = $Explicit }
    elseif ($env:DSH_HOME) { $h = $env:DSH_HOME }
    else { $h = Join-Path $HOME '.dsh' }
    if (-not (Test-Path (Join-Path $h 'profiles'))) {
        Fail "DSH 家目录无效(未找到 profiles 子目录): $h`n请用 -DshHome 指定,或先安装 DeepSeek Harness。"
    }
    return $h
}

# ---------- token 自动发现 ----------
function Read-TokenFromConfig([string]$cfgPath) {
    try {
        $cfg = Get-Content -Raw -LiteralPath $cfgPath | ConvertFrom-Json
        $t = $cfg.server.token
        if ($t -is [string] -and $t.Length -gt 0) { return $t }
    } catch { }
    return $null
}

function Find-BackendToken {
    # 1) 本机 ~\.miloco\config.json
    $localCfg = Join-Path $HOME '.miloco\config.json'
    if (Test-Path $localCfg) {
        $t = Read-TokenFromConfig $localCfg
        if ($t) { return @{ token = $t; home = ''; source = $localCfg } }
    }
    # 2) WSL 发行版内的后端
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($wsl) {
        $distros = & wsl.exe -l -q 2>$null
        foreach ($line in $distros) {
            $d = ($line -replace "`0", '').Trim()
            if (-not $d) { continue }
            if ($d -match 'docker-desktop') { continue }
            $out = & wsl.exe -d $d -- bash -lc 'cat ~/.miloco/config.json 2>/dev/null' 2>$null
            $json = ($out -join "`n")
            if ($json -match '"token"\s*:\s*"([^"]+)"') {
                $t = $Matches[1]
                $homeOut = & wsl.exe -d $d -- bash -lc 'printf %s "$HOME"' 2>$null
                $wslHome = ($homeOut -join '').Trim()
                $unc = ''
                if ($wslHome) { $unc = "\\wsl.localhost\$d" + ($wslHome -replace '/', '\') + '\.miloco' }
                return @{ token = $t; home = $unc; source = "WSL($d) ~/.miloco/config.json" }
            }
        }
    }
    return $null
}

# ============================================================
Write-Host ""
Write-Host "miloco-dsh 安装器 (Miloco x DeepSeek Harness)" -ForegroundColor Cyan

$repoDir = Resolve-RepoDir $RepoPath $InstallDir
$dshHome = Resolve-DshHome $DshHome
Write-Step "仓库目录: $repoDir"
Write-Step "DSH 家目录: $dshHome"

# ---------- 1. node 检查 ----------
Write-Step "检查 node"
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Fail "未找到 node。DeepSeek Harness 本身依赖 Node.js,请先安装 Node.js 18+ 并加入 PATH。" }
$nodeExe = $node.Source

# ---------- 2. 合并 cordis.patch.yml ----------
$patchFile = Join-Path $dshHome 'profiles\web\cordis.patch.yml'
$mergeJs = Join-Path $repoDir 'scripts\merge-patch.js'
if (-not (Test-Path $mergeJs)) {
    if ($WhatIf) { Write-Host "[WhatIf] (仓库下载后) 使用 $mergeJs" }
    else { Fail "仓库缺少 scripts\merge-patch.js" }
}
Write-Step "合并 mcp-miloco 条目 -> $patchFile (写入前自动备份)"
if ($WhatIf) {
    Write-Host "[WhatIf] node `"$mergeJs`" `"$patchFile`" `"$repoDir`" $BaseUrl 30000"
} else {
    & $nodeExe $mergeJs $patchFile $repoDir $BaseUrl '30000'
    if ($LASTEXITCODE -ne 0) { Fail "合并 patch 失败 (exit=$LASTEXITCODE)" }
}

# ---------- 3. 安装技能 ----------
$srcSkill = Join-Path $repoDir 'skills\miloco'
if (-not (Test-Path $srcSkill)) {
    if ($WhatIf) { Write-Host "[WhatIf] (仓库下载后) 使用 $srcSkill" }
    else { Fail "仓库缺少 skills\miloco" }
}
$dstSkill = Join-Path $dshHome 'skills\miloco'
Write-Step "安装技能 miloco -> $dstSkill"
if ($WhatIf) {
    Write-Host "[WhatIf] Copy-Item $srcSkill\* -> $dstSkill"
} else {
    if (-not (Test-Path $dstSkill)) { New-Item -ItemType Directory -Force -Path $dstSkill | Out-Null }
    Copy-Item -Path (Join-Path $srcSkill '*') -Destination $dstSkill -Recurse -Force
    Write-Host "技能文件: $((Get-ChildItem $dstSkill -File).Name -join ', ')"
}

# ---------- 4. MILOCO_TOKEN ----------
if (-not $NoToken) {
    Write-Step "MILOCO_TOKEN"
    if ($Token) {
        if ($WhatIf) {
            Write-Host "[WhatIf] 将写入用户环境变量 MILOCO_TOKEN"
        } else {
            [Environment]::SetEnvironmentVariable('MILOCO_TOKEN', $Token, 'User')
            Write-Host "已写入用户环境变量 MILOCO_TOKEN(重启 dsh web 生效)"
        }
    } else {
        $existingToken = $env:MILOCO_TOKEN
        if (-not $existingToken) { $existingToken = [Environment]::GetEnvironmentVariable('MILOCO_TOKEN', 'User') }
        if ($existingToken) {
            Write-Host "MILOCO_TOKEN 已配置,跳过"
        } else {
            $found = Find-BackendToken
            if ($found) {
                if ($WhatIf) {
                    Write-Host "[WhatIf] 将从 $($found.source) 发现 token 并写入用户环境变量"
                    if ($found.home) { Write-Host "[WhatIf] 并设置 MILOCO_HOME=$($found.home)" }
                } else {
                    [Environment]::SetEnvironmentVariable('MILOCO_TOKEN', $found.token, 'User')
                    if ($found.home) { [Environment]::SetEnvironmentVariable('MILOCO_HOME', $found.home, 'User') }
                    Write-Host "已从 $($found.source) 自动发现 token,写入用户环境变量(重启 dsh web 生效)"
                }
            } else {
                Write-Host "未自动发现 token。稍后手动设置(任选其一):"
                Write-Host "  1. PowerShell: [Environment]::SetEnvironmentVariable('MILOCO_TOKEN','<后端 config.json 的 server.token>','User')"
                Write-Host "  2. 或在 Miloco 后端机器上执行: cat ~/.miloco/config.json 查看 server.token"
                Write-Host "  3. 不设置也可:miloco-mcp 会自动探测 MILOCO_HOME / ~/.miloco / ~/.openclaw/miloco / ~/.hermes/miloco"
            }
        }
    }
}

# ---------- 5. 验证 ----------
if (-not $SkipVerify -and -not $WhatIf) {
    Write-Step "MCP 冒烟验证(server\test-mcp.js,无需后端)"
    Push-Location (Join-Path $repoDir 'server')
    & $nodeExe 'test-mcp.js'
    $ok = ($LASTEXITCODE -eq 0)
    Pop-Location
    if ($ok) { Write-Host "冒烟验证通过: 18 个 mcp__miloco__* 工具已注册。" -ForegroundColor Green }
    else { Write-Warning "冒烟验证失败 (exit=$LASTEXITCODE),详见上方输出。" }

    Write-Step "后端连通性检查 ($BaseUrl/health,非致命)"
    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl/health" -TimeoutSec 5 -UseBasicParsing
        Write-Host "后端可达: HTTP $($r.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Warning "后端不可达(未启动/未安装)。控制设备前请先启动 Miloco 后端。"
    }
}

# ---------- 6. 下一步 ----------
Write-Host ""
Write-Host "========== 安装完成 ==========" -ForegroundColor Cyan
Write-Host "1. 重启 dsh web(退出并重新打开 DeepSeek Harness)"
Write-Host "2. 重启后模型即获得 mcp__miloco__* 工具(共 18 个)"
Write-Host "3. 后端在 WSL 时,Windows 重启后需手动启动后端,例如:"
Write-Host "   wsl -d <发行版> -- bash `"<仓库>\scripts\wsl-restart-miloco.sh`""
Write-Host "4. 卸载: 删除 cordis.patch.yml 中 '# >>> miloco-dsh begin' 与 '# <<< miloco-dsh end' 之间的块,"
Write-Host "   删除 $dshHome\skills\miloco,重启 dsh web 即可。"
Write-Host ""
