# miloco-dsh

**Miloco × DeepSeek Harness 适配**:让 DSH 拥有与官方 OpenClaw/Hermes 插件等价的
小米 Miloco 智能家居能力 —— 设备查询与控制、场景触发、感知事件复盘、账号绑定、
系统状态、米家通知。

```
DSH (agent) ──mcp__miloco__*──▶ @deepseek-ai/dsh-mcp-client ──stdio──▶ miloco-mcp ──HTTP+Bearer──▶ Miloco 后端 (Linux/WSL)
```

## 一句话安装

> 前提:已安装 [DeepSeek Harness](https://github.com/deepseek-ai/dsh)(自带 node);
> Miloco 后端已跑在 `127.0.0.1:1810`(本机 Linux/WSL,安装见下文)。

**Windows(PowerShell 5.1+ 或 PowerShell 7):**

```powershell
irm https://raw.githubusercontent.com/WangYulin0814/miloco-dsh/main/install.ps1 | iex
```

**Linux / macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/WangYulin0814/miloco-dsh/main/install.sh | bash
```

安装器做的事(全部**幂等、可重复执行、写入前自动备份**):

1. 下载(或更新)本仓库到 `~/miloco-dsh`;
2. 把 `mcp-miloco` 条目合并进 `$DSH_HOME/profiles/web/cordis.patch.yml`;
3. 安装 `miloco` 技能到 `$DSH_HOME/skills/miloco`;
4. 自动发现后端 token(本机 `~/.miloco/config.json` 或 WSL 内的后端)并写入环境变量;
5. 跑 MCP 冒烟验证(`server/test-mcp.js`,18 个工具,无需后端)+ 后端连通性检查。

最后**重启 `dsh web`**,模型即获得 18 个 `mcp__miloco__*` 工具。

### 安装器选项

| 选项(ps1 / sh) | 说明 |
|---|---|
| `-RepoPath` / `--repo-path` | 用已有仓库目录,不下载 |
| `-DshHome` / `--dsh-home` | 指定 DSH 家目录(默认 `$DSH_HOME` 或 `~/.dsh`) |
| `-BaseUrl` / `--base-url` | Miloco 后端地址(默认 `http://127.0.0.1:1810`) |
| `-Token` / `--token` | 直接指定后端 token |
| `-NoToken` / `--no-token` | 跳过 token 自动发现 |
| `-WhatIf` / `--dry-run` | 只预览动作,不修改 |

> 提示:`irm ... | iex` 需要本仓库为 **Public**(私有仓库 raw 地址会 404);
> fork 后请同时修改 install.ps1 顶部的 `-Owner`/`-Repo` 默认值(install.sh 用
> `MILOCO_DSH_OWNER`/`MILOCO_DSH_REPO` 环境变量)。

## 后端(Miloco 本体)

Miloco 后端**必须**跑在 macOS / Linux / WSL(官方不支持原生 Windows):

```bash
# 在 WSL / Linux 终端,按官方方式安装
curl -LsSf https://github.com/XiaoMi/xiaomi-miloco/releases/latest/download/install.sh | bash
```

安装后:`miloco-cli dashboard` 打开家庭面板(即 http://127.0.0.1:1810/),
首次配置模型(MiMo API Key)→ 绑定小米账号 → 打开摄像头感知;
`miloco-cli service status` 查看服务状态。

> `scripts/wsl-*.sh` 是作者在 WSL 内安装/重启/诊断后端用的脚本(含镜像加速、
> SHA256 校验、网络诊断),可参考使用;其中依赖 `upstream/`(未随仓库分发)的
> 文件只在本机有效,他人请走上方官方安装命令。

## 工具面(18 个)

```
home_overview · device_list · device_status · device_spec · device_control
scene_trigger · refresh_devices · account_status · account_bind · account_authorize
account_unbind · events_recent · event_media_url · camera_list · rules_list
system_status · notify_send · omni_config
```

各工具与后端端点的对应关系见 [docs/DESIGN.md](docs/DESIGN.md)。

## 配置(miloco-mcp 环境变量)

| 变量 | 默认 | 说明 |
|---|---|---|
| `MILOCO_BASE_URL` | `http://127.0.0.1:1810` | 后端地址;WSL 场景 localhost 自动转发,跨机改成 `http://<host>:1810` |
| `MILOCO_TOKEN` | 自动发现 | 后端 Bearer token(取 `~/.miloco/config.json` 的 `server.token`) |
| `MILOCO_HOME` | 依次探测 | config.json 所在目录(可指向 `\\wsl.localhost\<发行版>\home\<用户>\.miloco`) |
| `MILOCO_TIMEOUT_MS` | `30000` | 单次 HTTP 超时 |

## 测试

```powershell
node server/test-mcp.js      # MCP 协议冒烟(无需后端)
node server/test-full.js     # 端到端(mock 后端,22 断言)
node server/test-sdk.mjs     # 官方 MCP SDK 兼容性
node server/test-live.mjs    # 真后端实测(需运行中的 Miloco)
```

## 卸载

1. 编辑 `$DSH_HOME/profiles/web/cordis.patch.yml`,删除
   `# >>> miloco-dsh begin` 与 `# <<< miloco-dsh end` 之间的块(含标记行);
2. 删除 `$DSH_HOME/skills/miloco/`;
3. 删除环境变量 `MILOCO_TOKEN`(如安装器写过);
4. 重启 `dsh web`。

不影响 Miloco 后端,不影响 my-coffee 等其它 MCP 实例。

## 安全注意事项

- **后端默认只监听 127.0.0.1,`GET /` 会返回内嵌 token 的页面** —— 绝不要直接暴露到公网;
  跨机访问必须走反代 + TLS。
- `event_media_url` 返回的 URL 内嵌 token:只发给用户本人,仅限可信局域网。
- `account_unbind` 不可逆;门锁/燃气阀等高风险设备控制前必须二次确认。

## 已知边界(v1)

- 事件推送为轮询(`events_recent`),未桥接后端 SSE 实时流;
- 视频直播 / `record_clip` 二进制未桥接,用 `event_media_url` 的直链替代;
- 自动化规则只读(列表/日志),写操作请用 Miloco 家庭面板;
- Miloco 后端本身的安装/升级仍走官方 `install.sh`,本适配不重实现。

## 说明

- 本项目**不重实现 Miloco 后端**,只做 agent 侧适配;后端本身归
  [XiaoMi/xiaomi-miloco](https://github.com/XiaoMi/xiaomi-miloco)(非商业许可,以官方 LICENSE 为准)。
- 本仓库不含 Xiaomi 上游源码/安装包(`upstream/` 已 gitignore,仅作者本地保留参考)。
