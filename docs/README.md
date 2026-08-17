# miloco-dsh — Miloco × DeepSeek Harness 适配

让 **DeepSeek Harness** 拥有与官方 OpenClaw/Hermes 插件等价的 Miloco 能力:
查设备、控制设备、触发场景、感知事件复盘、账号绑定、系统状态、米家通知。

> 设计细节见 [DESIGN.md](DESIGN.md)。

## 交付物

```
miloco-dsh/
├── server/
│   ├── miloco-mcp.js     # ★ 核心:MCP stdio 服务器(零依赖、单文件、纯 Node 标准库)
│   ├── mock-backend.js   # 测试用 Miloco 后端模拟器
│   ├── test-mcp.js       # 协议冒烟测试(自制客户端)
│   ├── test-full.js      # 端到端测试(mock 后端 + 22 项断言)
│   └── test-sdk.mjs      # 官方 @modelcontextprotocol/sdk v1.30 兼容性测试
├── dsh-integration/
│   └── cordis.patch.miloco.yml   # DSH web profile 的 patch 片段(已应用到本机)
├── skills/miloco/        # DSH 技能(已安装到 $DSH_HOME/skills/miloco)
├── docs/
│   ├── DESIGN.md         # 设计文档(架构/工具面/契约)
│   ├── UPSTREAM-NOTES.md # 上游仓库安全审查笔记
│   └── README.md         # 本文件
└── upstream/             # 上游关键源码参考(路由/契约,来自 XiaoMi/xiaomi-miloco)
```

## 快速开始

### 1. 后端(Miloco 本体)

Miloco 后端**必须**跑在 macOS / Linux / WSL(官方不支持原生 Windows,无官方 Docker 部署)。
按官方方式安装:

```bash
# 在 WSL / Linux 终端
curl -LsSf https://github.com/XiaoMi/xiaomi-miloco/releases/latest/download/install.sh | bash
```

安装完成后:
- 家庭面板:`miloco-cli dashboard`(即 http://127.0.0.1:1810/)
- 首次使用:配置模型(MiMo API Key)→ 绑定小米账号 → 打开摄像头感知
- 验证:`miloco-cli service status`

### 2. 适配层(本仓库,已就绪)

本机已完成:
- ✅ `miloco-mcp` 服务器(经 22 项端到端断言 + 官方 SDK 兼容测试 + 真后端实测全通过)
- ✅ `$DSH_HOME/profiles/web/cordis.patch.yml` 已追加 `mcp-miloco` 实例
- ✅ `$DSH_HOME/skills/miloco/` 技能已安装(已在本会话生效)

### 3. 激活(唯一待做)

**重启 DSH 的 web profile**(`dsh web` 重启 / 退出 `DeepSeek Harness.exe` 后重新打开)。
重启后模型即获得 `mcp__miloco__*` 工具,共 18 个:

```
home_overview · device_list · device_status · device_spec · device_control
scene_trigger · refresh_devices · account_status · account_bind · account_authorize
account_unbind · events_recent · event_media_url · camera_list · rules_list
system_status · notify_send · omni_config
```

## 本机部署状态(2026-08-17)

| 组件 | 状态 |
|---|---|
| Miloco 后端 v2026.8.6 | ✅ 已安装在 WSL Ubuntu 26.04,`/home/<用户>/.miloco`,服务运行于 127.0.0.1:1810 |
| 安装方式 | `scripts/wsl-*.sh`(官方 install.sh 两阶段 agent 模式;bundle 经 gh-proxy.org 镜像 + SHA256 校验) |
| Windows 环境变量 | ✅ `MILOCO_TOKEN`(User 级)= WSL `config.json` 的 `server.token` |
| 米家账号 | ✅ 已绑定(nickname: Ephemeral,38 台设备 / 9 个场景 / 2 台摄像头) |
| Omni 模型(MiMo) | ⬜ 未配置(需 API Key,感知暂用内置模型) |
| DSH web profile | ⬜ 需重启 `dsh web` 使 MCP 工具生效 |

**常用命令(WSL 内,注意必须带 `MILOCO_HOME`,否则 CLI 会找错目录):**

```bash
export MILOCO_HOME=$HOME/.miloco
export PATH=$HOME/.local/bin:$PATH
miloco-cli service status        # 服务状态
miloco-cli service start/stop/restart   # 启停(Windows 重启后需手动 start)
miloco-cli account bind          # 交互式绑定账号(也可用 MCP 工具)
miloco-cli dashboard             # 打开家庭面板
```

Windows 重启后 WSL 服务不会自启,在 PowerShell 执行(或直接用 `scripts\wsl-restart-miloco.sh`):

```powershell
wsl -d Ubuntu -- bash "/mnt/c/Project Library/DeepSeek Harness WorkSpace/miloco-dsh/scripts/wsl-restart-miloco.sh"
```

## 配置

`miloco-mcp` 通过环境变量配置(在 `cordis.patch.yml` 的 `env` 段):

| 变量 | 默认 | 说明 |
|---|---|---|
| `MILOCO_BASE_URL` | `http://127.0.0.1:1810` | 后端地址;WSL 场景 localhost 自动转发,跨机改成 `http://<host>:1810` |
| `MILOCO_TOKEN` | 自动发现 | 后端 Bearer token(见下) |
| `MILOCO_HOME` | 依次探测 | config.json 所在目录(可指向 `\\wsl.localhost\<发行版>\home\<用户>\.miloco`) |
| `MILOCO_TIMEOUT_MS` | `30000` | 单次 HTTP 超时 |

**token 获取**(任一方式):
1. 在 Windows 环境变量设置 `MILOCO_TOKEN` = 后端 `~/.miloco/config.json` 里的 `server.token`(本机已设置);
2. 或不设置,由服务器自动从 `~/.miloco` / `~/.openclaw/miloco` / `~/.hermes/miloco` 的 `config.json` 发现;
3. 或设置 `MILOCO_HOME` 指向实际配置目录(含 WSL 的 UNC 路径)。

## 安全注意事项

- **后端默认只监听 127.0.0.1,`GET /` 会返回内嵌 token 的页面** —— 绝不要直接暴露到公网;
  跨机访问必须走反代 + TLS。
- `event_media_url` 返回的 URL 内嵌 token:只发给用户本人,仅限可信局域网。
- `account_unbind` 不可逆;门锁/燃气阀等高风险设备控制前必须二次确认。
- 破坏性操作全部由 agent 向用户确认后执行(技能 `miloco` 已写入纪律)。

## 测试

```powershell
node server/test-mcp.js      # 协议冒烟(无需后端)
node server/test-full.js     # 端到端(mock 后端,22 断言)
node server/test-sdk.mjs     # 官方 SDK v1.30 兼容性
```

## 回滚

若需卸载适配:
1. 编辑 `$DSH_HOME/profiles/web/cordis.patch.yml`,删除 `mcp-miloco` 所在的 `- insert:` 块;
2. 删除 `$DSH_HOME/skills/miloco/`;
3. 重启 `dsh web`。
不影响 Miloco 后端、不影响 my-coffee 等其它 MCP 实例。

## 已知边界(v1)

- 事件推送为轮询(`events_recent`),未桥接后端 SSE 实时流;
- 视频直播 / `record_clip` 二进制未桥接,用 `event_media_url` 的直链替代;
- 自动化规则只读(列表/日志),写操作请用 Miloco 家庭面板;
- Miloco 后端本身的安装/升级仍走官方 `install.sh`,本适配不重实现。
