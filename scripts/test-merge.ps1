#requires -Version 5.1
<#
.SYNOPSIS
    merge-patch.js 自测:覆盖 新建/追加/旧条目迁移/幂等/参数化 五种场景。
.DESCRIPTION
    在临时目录中模拟 $DSH_HOME/profiles/web/cordis.patch.yml 的各种初始状态,
    验证合并结果;若环境里能解析到 js-yaml,还会对结果做真实 YAML 解析校验。
    不改动真实 DSH 配置。
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$merge = Join-Path $PSScriptRoot 'merge-patch.js'
if (-not (Test-Path $merge)) { Write-Error "缺少 $merge"; exit 1 }

$tmp = Join-Path $env:TEMP ("miloco-merge-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$pass = 0; $failCount = 0

function Assert([bool]$cond, [string]$name) {
    if ($cond) { Write-Host "  [PASS] $name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  [FAIL] $name" -ForegroundColor Red; $script:failCount++ }
}

function Run-Merge([string]$patch, [string]$baseUrl = 'http://127.0.0.1:1810') {
    & node $merge $patch $repo $baseUrl '30000'
    if ($LASTEXITCODE -ne 0) { throw "merge exit=$LASTEXITCODE" }
}

# 校验 YAML(能拿到 js-yaml 时);同时文本断言 id: mcp-miloco 存在
$yamlCheck = Join-Path $env:DSH_HOME 'profiles\node_modules\js-yaml'
$validator = Join-Path $tmp 'yaml-check.js'
@'
const fs = require('fs');
let yaml = null;
try { yaml = require(process.argv[2]); } catch (e) { process.exit(2); }
const jsExpr = new yaml.Type('tag:yaml.org,2002:js', { kind: 'scalar', resolve: () => true, construct: (d) => d });
const schema = yaml.DEFAULT_SCHEMA.extend([jsExpr]);
const doc = yaml.load(fs.readFileSync(process.argv[3], 'utf8'), { schema });
if (!Array.isArray(doc)) { console.error('not an array'); process.exit(1); }
const has = doc.some((it) => it && it.insert && JSON.stringify(it.insert).includes('mcp-miloco'));
if (!has) { console.error('mcp-miloco entry missing'); process.exit(1); }
process.exit(0);
'@ | Set-Content -LiteralPath $validator -Encoding UTF8

function Check-Yaml([string]$patch, [string]$name) {
    if (Test-Path $yamlCheck) {
        & node $validator $yamlCheck $patch
        Assert ($LASTEXITCODE -eq 0) "$name → YAML 可解析且含 mcp-miloco 条目"
    } else {
        $c = Get-Content -Raw -LiteralPath $patch
        Assert ($c -match 'id:\s*mcp-miloco') "$name → 文本含 mcp-miloco 条目(未找到 js-yaml,跳过解析校验)"
    }
}

Write-Host "== 场景 1: 文件不存在 → 新建"
$p1 = Join-Path $tmp 'case1\profiles\web\cordis.patch.yml'
$r1 = Run-Merge $p1
Write-Host "  result: $r1"
Assert (Test-Path $p1) "文件已创建"
Assert ($r1 -match '"status":"added"') "status=added"
Check-Yaml $p1 "场景1"

Write-Host "== 场景 2: 已有 my-coffee 条目 → 追加,不动原内容"
$p2 = Join-Path $tmp 'case2\profiles\web\cordis.patch.yml'
New-Item -ItemType Directory -Force -Path (Split-Path $p2) | Out-Null
@'
- insert:
    - id: mcp-my-coffee
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: my-coffee
        transport: streamable-http
        url: https://example.com/mcp
'@ | Set-Content -LiteralPath $p2 -Encoding UTF8
$r2 = Run-Merge $p2
Assert ($r2 -match '"status":"added"') "status=added"
$c2 = Get-Content -Raw -LiteralPath $p2
Assert ($c2 -match 'mcp-my-coffee' -and $c2 -match 'id:\s*mcp-miloco') "两个条目共存"
Check-Yaml $p2 "场景2"

Write-Host "== 场景 3: 旧的无标记条目(id: mcp-miloco)→ 原位迁移"
$p3 = Join-Path $tmp 'case3\profiles\web\cordis.patch.yml'
New-Item -ItemType Directory -Force -Path (Split-Path $p3) | Out-Null
@'
- insert:
    - id: mcp-my-coffee
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: my-coffee
        transport: streamable-http
        url: https://example.com/mcp

# Legacy miloco entry (no markers, old path)
- insert:
    - id: mcp-miloco
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: miloco
        transport: stdio
        command: node
        args:
          - 'C:\old\path\miloco-mcp.js'
        env:
          MILOCO_BASE_URL: http://127.0.0.1:1810
          MILOCO_TIMEOUT_MS: '30000'
          MILOCO_TOKEN: !!js process.env.MILOCO_TOKEN || ''
'@ | Set-Content -LiteralPath $p3 -Encoding UTF8
$r3 = Run-Merge $p3
Assert ($r3 -match '"status":"migrated"') "status=migrated"
$c3 = Get-Content -Raw -LiteralPath $p3
Assert ($c3 -match 'mcp-my-coffee') "my-coffee 条目保留"
Assert ($c3 -match '>>> miloco-dsh begin' -and $c3 -match '<<< miloco-dsh end') "标记块已写入"
Assert ($c3 -notmatch 'C:\\old\\path') "旧路径已替换"
Assert ($c3 -match [regex]::Escape($repo)) "新路径指向本仓库"
Check-Yaml $p3 "场景3"

Write-Host "== 场景 4: 幂等 —— 重跑不写盘"
$before = (Get-Item $p3).LastWriteTimeUtc
$bakBefore = (Get-ChildItem (Split-Path $p3) -Filter '*.bak-*').Count
Start-Sleep -Milliseconds 1100
$r4 = Run-Merge $p3
Assert ($r4 -match '"status":"unchanged"') "status=unchanged"
$after = (Get-Item $p3).LastWriteTimeUtc
Assert ($before -eq $after) "文件未被改写"
$bakAfter = (Get-ChildItem (Split-Path $p3) -Filter '*.bak-*').Count
Assert ($bakBefore -eq $bakAfter) "未产生多余备份"

Write-Host "== 场景 5: 参数化 —— 自定义 BaseUrl 更新标记块内容"
$r5 = Run-Merge $p3 'http://192.168.1.5:1810'
Assert ($r5 -match '"status":"updated"') "status=updated"
$c5 = Get-Content -Raw -LiteralPath $p3
Assert ($c5 -match 'http://192\.168\.1\.5:1810') "BaseUrl 已更新"
Check-Yaml $p3 "场景5"

Write-Host ""
Write-Host "===== 结果: PASS=$pass FAIL=$failCount =====" -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($failCount -ne 0) { exit 1 }
exit 0
