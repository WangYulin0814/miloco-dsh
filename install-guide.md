---
name: install-miloco-dsh
description: miloco-dsh 安装引导。当用户发送「帮我安装 miloco-dsh」或贴入本指南链接时激活。目标:在一台未安装 Miloco 的电脑上,完成「Miloco 后端 + DeepSeek Harness(DSH)适配」全套安装,使 DSH 获得 mcp__miloco__* 工具。
metadata:
  author: miloco-dsh
  version: "1.0"
  date: 2026-08-18
---

# miloco-dsh 安装指南(给 Agent 执行)

## 0. 概述

**要装的两部分:**

```
DSH(你所在的 agent 平台) ──mcp__miloco__*──▶ miloco-mcp ──HTTP+Bearer──▶ Miloco 后端 (127.0.0.1:1810)
        ▲ 适配层(本仓库)                          ▲ 后端(官方 XiaoMi/xiaomi-miloco)
```

| 部分 | 安装方式 | 说明 |
|---|---|---|
| A. Miloco 后端 | 官方 install.sh;Windows 装在 **WSL**,Linux/macOS 原生 | 不支持原生 Windows |
| B. miloco-dsh 适配层 | 本仓库 `install.ps1`(Windows)/ `install.sh`(Linux/macOS) | 合并 cordis patch + 装技能 + 配置 token,幂等 |

**前提:**
- node 已装(DSH 本身依赖 node,必有;适配层需要)
- Windows:WSL 可用(后端宿主);Linux/macOS:curl + tar
- 网络可达 GitHub(不通见 [故障排除](#故障排除) 镜像方案)

**执行纪律(重要):**
1. 严格按 Step 1 → 7 顺序,每步验证通过再进下一步。
2. **敏感信息纪律**:API Key、后端 token 一律**不回显明文**;打印时打码(首 6 位 + `...` + 末 4 位)。
3. **重操作先征求同意**:安装 WSL(需重启系统)、重启 DSH,必须先告知用户,不要擅自执行。
4. **不要重启你正在其中运行的 DSH GUI**——那会杀掉当前会话。适配层装完后,提醒用户自行重启 dsh web。
5. 全程幂等:任何一步失败都可以重跑;适配层安装器重复执行安全(自动备份、不重复写)。
6. Windows 下通过 PowerShell 调 WSL 时,**复杂命令写成 .sh 文件再执行**(PS 5.1 原生参数引号不可靠),模板见 Step 2.2。

---

## Step 1: 环境探测

先判断你运行在什么平台,并检查现有状态。Windows 用 PowerShell,Linux/macOS 用 bash。

**1.1 平台判断**
- Windows:PowerShell 中 `$env:OS` 含 `Windows`,或存在 `wsl.exe`。
- Linux/macOS:`uname`。

**1.2 检查现状**

```bash
# Linux / macOS(WSL 内也可用)
curl -sS -m 5 http://127.0.0.1:1810/health || echo "NO_BACKEND"
command -v node && node -v
ls -d "$HOME/.dsh/profiles" 2>/dev/null || ls -d "${DSH_HOME:-$HOME/.dsh}/profiles" 2>/dev/null || echo "NO_DSH"
```

```powershell
# Windows(PowerShell)
try { (Invoke-WebRequest -Uri "http://127.0.0.1:1810/health" -TimeoutSec 5 -UseBasicParsing).StatusCode } catch { "NO_BACKEND" }
node -v
Test-Path "$env:DSH_HOME\profiles"   # 若 DSH_HOME 未设置,检查 "$HOME\.dsh\profiles"
wsl -l -q                             # 看有哪些 WSL 发行版
```

**1.3 分支**
- 已有后端(1810 可达)→ 跳到 Step 3。
- 无后端:
  - Windows 且无 WSL 发行版 → 告知用户需要先装 WSL(微软商店或 `wsl --install`,**需要重启电脑**),征得同意后再继续,不要擅自重启。
  - 其余 → 进 Step 2。
- 无 DSH → 告知用户先安装 DeepSeek Harness(本适配层以 DSH 为宿主)。

---

## Step 2: 安装 Miloco 后端(官方 install.sh)

### 2.1 Linux / macOS(原生)

```bash
curl -LsSf https://github.com/XiaoMi/xiaomi-miloco/releases/latest/download/install.sh | bash
```

**非交互(agent 两阶段)模式**(推荐给 agent 用,输出含 JSON 状态):

```bash
# 阶段 1:准备环境 + 安装
curl -LsSf https://github.com/XiaoMi/xiaomi-miloco/releases/latest/download/install.sh | bash -s -- --agent-prepare --agent-platform=openclaw --skip-openclaw
# 阶段 2:完成安装、启动服务(若卡在交互询问,加 </dev/null 或改用 setsid 强制非交互)
curl -LsSf https://github.com/XiaoMi/xiaomi-miloco/releases/latest/download/install.sh | bash -s -- --agent-finish --agent-platform=openclaw --skip-openclaw </dev/null
```

> `--skip-openclaw` 表示只装独立后端,不装 OpenClaw 插件 —— DSH 适配层不需要官方 agent 插件。

### 2.2 Windows(在 WSL 内装)

1. 确认发行版名(如 `Ubuntu`):`wsl -l -q`(输出带 `\0` 字符,取形如 `Ubuntu` 的行)。
2. **把下面的脚本写成文件再执行**(避免 PowerShell→WSL 引号问题):

```powershell
# PowerShell:生成 WSL 安装脚本并执行(把 <发行版> 换成 wsl -l -q 看到的发行版名)
$sh = @"
set -e
export MILOCO_HOME="`$HOME/.miloco"
export PATH="`$HOME/.local/bin:`$PATH"
echo '== installing miloco backend =='
curl -LsSf https://github.com/XiaoMi/xiaomi-miloco/releases/latest/download/install.sh | bash -s -- --agent-prepare --agent-platform=openclaw --skip-openclaw
curl -LsSf https://github.com/XiaoMi/xiaomi-miloco/releases/latest/download/install.sh | bash -s -- --agent-finish --agent-platform=openclaw --skip-openclaw </dev/null
echo '== starting service =='
hash -r
miloco-cli service start
sleep 10
miloco-cli service status
curl -sS -m 10 http://127.0.0.1:1810/health; echo
"@
$tmp = [IO.Path]::GetTempPath()
[IO.File]::WriteAllText((Join-Path $tmp 'miloco-backend-install.sh'), $sh, (New-Object Text.UTF8Encoding $false))
# Windows 路径 → WSL 路径(纯字符串转换,避免 PowerShell 5.1 传参给 wslpath 的引号问题)
$lin = ($tmp -replace '\\','/').TrimEnd('/')
$wslPath = '/mnt/' + $lin.Substring(0,1).ToLower() + $lin.Substring(2)
wsl -d <发行版> -- bash "$wslPath/miloco-backend-install.sh"
```

> 网络不通(GitHub 下载失败)时,把上面的下载地址换成镜像前缀:
> `https://gh-proxy.org/https://github.com/XiaoMi/xiaomi-miloco/releases/latest/download/install.sh`
> 也可用仓库 `scripts/wsl-netmatrix.sh` 探测哪个镜像可用(需先克隆本仓库)。

### 2.3 验证后端

```bash
curl -sS -m 10 http://127.0.0.1:1810/health; echo
```

预期返回 `{"status":"ok"}` 类内容。Windows 场景从 PowerShell 验证:
`(Invoke-WebRequest -Uri "http://127.0.0.1:1810/health" -UseBasicParsing).Content`

> 备注:Windows 重启后 WSL 服务**不会自启**。告诉用户:重启电脑后执行
> `wsl -d <发行版> -- bash /mnt/c/.../miloco-dsh/scripts/wsl-restart-miloco.sh`
> (适配层装好后路径即可用;该脚本会导出正确的 MILOCO_HOME 并启动服务)。

---

## Step 3: 读取后端 token(打码处理,不回显明文)

token 在 `~/.miloco/config.json` 的 `server.token`。

```bash
# Linux / macOS(WSL 内)
python3 - <<'PYEOF'
import json, os
t = json.load(open(os.path.expanduser("~/.miloco/config.json")))["server"]["token"]
print("TOKEN_MASKED=" + (t[:6] + "..." + t[-4:] if t else "EMPTY"))
PYEOF
```

```powershell
# Windows:从 WSL 读取(只打印打码值;与 install.ps1 的自动发现逻辑同款)
$out = wsl -d Ubuntu -- bash -lc 'cat ~/.miloco/config.json' 2>$null
$json = ($out -join "`n")
$tok = [regex]::Match($json, '"token"\s*:\s*"([^"]+)"').Groups[1].Value
Write-Host ("TOKEN_MASKED=" + $tok.Substring(0,6) + "..." + $tok.Substring($tok.Length-4))
```

把完整 token 记在变量里供 Step 5 使用,**不要打印完整值**。若读取失败,先确认服务已启动、`~/.miloco/config.json` 存在。

---

## Step 4: 安装 miloco-dsh 适配层(本仓库)

### 4.1 Windows(PowerShell)

```powershell
irm https://raw.githubusercontent.com/WangYulin0814/miloco-dsh/main/install.ps1 | iex
```

带 token 直接装:`irm https://raw.githubusercontent.com/WangYulin0814/miloco-dsh/main/install.ps1 -OutFile install.ps1; .\install.ps1 -Token "<token>"`

### 4.2 Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/WangYulin0814/miloco-dsh/main/install.sh | bash
```

安装器自动完成:下载/更新仓库到 `~/miloco-dsh` → 把 `mcp-miloco` 条目幂等合并进
`$DSH_HOME/profiles/web/cordis.patch.yml`(自动备份)→ 安装技能到 `$DSH_HOME/skills/miloco`
→ 自动发现 token → 跑 `server/test-mcp.js` 冒烟验证(18 个工具)。
重复执行安全(status 为 `added|updated|migrated|unchanged` 均属正常)。

### 4.3 回退:手动安装(仅当安装器不可用时)

1. 克隆仓库:`git clone https://github.com/WangYulin0814/miloco-dsh.git ~/miloco-dsh`
2. 把 `dsh-integration/cordis.patch.miloco.yml` 里的标记块追加到
   `$DSH_HOME/profiles/web/cordis.patch.yml`(把 `<MILOCO_DSH_DIR>` 换成仓库绝对路径);
3. 复制 `skills/miloco/` 到 `$DSH_HOME/skills/miloco/`;
4. 继续 Step 5。

---

## Step 5: 配置 MILOCO_TOKEN(若安装器未自动写入)

安装器会优先自动发现(本机 `~/.miloco/config.json` 或 WSL 内的后端)。若它提示未发现:

```powershell
# Windows:写入用户环境变量(不打印值;重启 dsh web 后生效)
[Environment]::SetEnvironmentVariable('MILOCO_TOKEN', $tok, 'User')
```

```bash
# Linux / macOS:追加到 shell rc(注意引号内的值不回显)
printf '\nexport MILOCO_TOKEN="%s"\n' "$tok" >> "$HOME/.bashrc"
source "$HOME/.bashrc"
```

**纪律**:不要 echo token 明文;写入后只报"已写入(长度 N)"。跨机部署时 `MILOCO_BASE_URL` 需指向后端实际地址。

---

## Step 6: 验证

1. **MCP 冒烟(无需后端):**
   ```powershell
   node "$HOME\miloco-dsh\server\test-mcp.js"    # Windows
   ```
   ```bash
   node ~/miloco-dsh/server/test-mcp.js          # Linux / macOS
   ```
   预期:`tools/list → 18 tools`。
2. **后端健康:** `curl -sS -m 5 http://127.0.0.1:1810/health` → 200。
3. **DSH 配置检查:** `$DSH_HOME/profiles/web/cordis.patch.yml` 含
   `# >>> miloco-dsh begin` 与 `# <<< miloco-dsh end` 标记块;`$DSH_HOME/skills/miloco/` 有
   `SKILL.md` 与 `manifest.json`。
4. **重启 DSH(必须由用户操作):** 明确告知用户:
   > 请重启 DeepSeek Harness(退出后重新打开,或执行 `dsh web` 重启)。重启后模型即获得
   > `mcp__miloco__*` 18 个工具。重启前我不会替你重启,以免中断当前会话。
   重启后(下次会话)可用 `home_overview` / `account_status` 实测工具是否生效。

---

## Step 7: 首次配置引导(安装完成后告知用户)

- **绑定小米账号**:调 `account_status` 查看;未绑定时调 `account_bind` 把授权链接给用户,
  用户浏览器登录授权后把授权码交回,再调 `account_authorize` 完成绑定(授权码 5 分钟有效)。
- **感知模型**:Miloco 感知引擎需要多模态模型 API Key(推荐小米 MiMo,从
  https://platform.xiaomimimo.com 获取),可在家庭面板「模型」页配置,或让用户提供后由
  `miloco-cli config set model.omni.api_key ...` 写入(不配置则感知用内置降级模型)。
- **摄像头感知**:在家庭面板「概览」页为需要的摄像头打开开关(`miloco-cli dashboard`)。
- **米家通知**:`notify_send` 可向米家 App 推送提醒。

---

## 故障排除

| 现象 | 处理 |
|---|---|
| GitHub 下载失败/超时 | 换镜像前缀 `https://gh-proxy.org/https://github.com/...`;或先 `wsl-netmatrix.sh` 探测可用通道 |
| `uv` 未找到 / Python 版本不满足 | `curl -LsSf https://astral.sh/uv/install.sh \| sh && export PATH="$HOME/.local/bin:$PATH"`;`uv python install 3.14` |
| `miloco-cli` 未找到 | 确认 `~/.local/bin` 在 PATH(且导出 `MILOCO_HOME=$HOME/.miloco`) |
| 服务启动失败 | `miloco-cli service logs` 看日志;Windows 重启后需手动 `miloco-cli service start` |
| 工具报 401 鉴权失败 | token 未配置/已轮换:重新设置 `MILOCO_TOKEN`,或检查 `config.json` 的 `server.token` |
| 设备列表为空 | 未绑定账号或未刷新:绑定账号,或调 `refresh_devices` |
| 事件查询为空 | 摄像头感知未开:面板「概览」页开摄像头开关 |
| DSH 里没有 mcp__miloco__* 工具 | DSH 未重启;或 `cordis.patch.yml` 里标记块不存在/路径不对(重跑安装器) |
| WSL 后端 Windows 重启后不可用 | 服务不自启:跑 `wsl-restart-miloco.sh`(见 Step 2.2 备注) |

## 完成标志(全部满足才算安装成功)

- [ ] `http://127.0.0.1:1810/health` 返回 200
- [ ] `server/test-mcp.js` 输出 `18 tools`
- [ ] token 已写入环境变量(打码确认长度 > 0)
- [ ] `cordis.patch.yml` 含 miloco-dsh 标记块;`skills/miloco/` 已安装
- [ ] 已提示用户重启 DSH(并说明重启后的验证方式)
