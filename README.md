# miloco-dsh

**Miloco × DeepSeek Harness 适配**:让 DSH 拥有与官方 OpenClaw/Hermes 插件等价的
小米 Miloco 智能家居能力 —— 设备查询与控制、场景触发、感知事件复盘、账号绑定、
系统状态、米家通知。

```
DSH (agent) ──mcp__miloco__*──▶ @deepseek-ai/dsh-mcp-client ──stdio──▶ miloco-mcp ──HTTP+Bearer──▶ Miloco 后端 (Linux/WSL)
```

- **`server/miloco-mcp.js`** — 零依赖单文件 MCP 服务器,18 个工具,经官方
  `@modelcontextprotocol/sdk` v1.30 实测兼容;
- **`dsh-integration/`** — DSH web profile 的 `cordis.patch.yml` 接入片段;
- **`skills/miloco/`** — DSH 技能(agent 工作流与安全纪律);
- **`scripts/wsl-*.sh`** — WSL 内安装/重启 Miloco 后端的可复用脚本
  (含网络诊断、镜像加速、SHA256 校验);
- **`docs/`** — 设计文档、部署手册、上游安全审查笔记。

## 快速开始

见 [docs/README.md](docs/README.md)。TL;DR:

1. 在 Linux/WSL 按官方方式安装 Miloco 后端;
2. 把 `dsh-integration/cordis.patch.miloco.yml` 的 `insert` 块追加到
   `$DSH_HOME/profiles/web/cordis.patch.yml`(改好 `miloco-mcp.js` 的绝对路径);
3. 设置环境变量 `MILOCO_TOKEN`(后端 `config.json` 的 `server.token`);
4. 重启 `dsh web`。

## 测试

```powershell
node server/test-mcp.js      # MCP 协议冒烟(无需后端)
node server/test-full.js     # 端到端(mock 后端,22 断言)
node server/test-sdk.mjs     # 官方 MCP SDK 兼容性
node server/test-live.mjs    # 真后端实测(需运行中的 Miloco)
```

## 说明

- 本项目**不重实现 Miloco 后端**,只做 agent 侧适配;后端本身归
  [XiaoMi/xiaomi-miloco](https://github.com/XiaoMi/xiaomi-miloco)(非商业许可,以官方 LICENSE 为准)。
- `upstream/` 下保存的上游源码/安装器文件仅供离线参考,版权归 Xiaomi。
- 事件推送为轮询(`events_recent`),未桥接 SSE;视频直播用 `event_media_url` 直链替代。
