# Miloco × DeepSeek Harness 适配设计

## 1. 背景与目标

小米 Miloco(`XiaoMi/xiaomi-miloco`)是开源的智能家居中枢:后端(感知引擎 + MIoT 设备控制)+
前端 Web + 面向 agent 平台的插件(官方仅支持 **OpenClaw** 与 **Hermes Agent**,原生 Windows 不支持,
须跑在 Linux / WSL / Docker 中)。

本适配的目标:让 **DeepSeek Harness(DSH)** 能像官方插件一样使用 Miloco 的能力 ——
查设备、控制设备、触发场景、查看感知事件、绑定账号、查看系统状态等。

## 2. 为什么用 MCP 而不是写原生 Cordis 插件

- DSH 原生支持 MCP 客户端:`@deepseek-ai/dsh-mcp-client` 在 profile 的 `cordis.patch.yml`
  里按实例声明(`stdio` / `streamable-http` 两种传输),工具以 `mcp__<serverName>__<tool>` 注册。
  本机现成的 `mcp-my-coffee` 就是先例。
- MCP 服务器是与 DSH 内部 API 解耦的独立进程,升级 Miloco / DSH 互不影响;
  同一个 `miloco-mcp` 还能给 Claude Code / Codex 等任何 MCP 客户端复用。
- 官方 OpenClaw 插件本身就是「调 Miloco 后端 HTTP API」,我们把同一份 API 面包装成 MCP 工具,
  功能等价且不依赖 OpenClaw 运行时。

## 3. 总体架构

```
┌─────────────────────────── DeepSeek Harness (web profile) ──────────────────────────┐
│  agent (模型)  ──工具调用──▶  mcp__miloco__device_control  (ctx.tools)                 │
│                                    │                                                  │
│                        @deepseek-ai/dsh-mcp-client (stdio)                            │
│                                    │ JSON-RPC over stdin/stdout                       │
└────────────────────────────────────┼──────────────────────────────────────────────────┘
                                     ▼
                          miloco-mcp (本仓库 server/)
                                     │ HTTP + Bearer(server.token)
                                     ▼
                          Miloco 后端 http://127.0.0.1:1810 /api/*
                          (Linux / WSL / Docker,官方安装)
```

- `miloco-mcp` 是零依赖的单文件 Node.js 进程,实现 MCP stdio 协议(2025-06-18),纯标准库。
- 鉴权:后端要求 `Authorization: Bearer <server.token>`。token 解析顺序:
  环境变量 `MILOCO_TOKEN` → `$MILOCO_HOME/config.json` 的 `server.token`
  → `~/.miloco`、`~/.openclaw/miloco`、`~/.hermes/miloco` 的 `config.json`。
- 连接参数:`MILOCO_BASE_URL`(默认 `http://127.0.0.1:1810`)、`MILOCO_TIMEOUT_MS`(默认 30000)。

## 4. 工具面(serverName = miloco)

| MCP 工具 | 后端端点 | 说明 |
|---|---|---|
| `home_overview` | GET /api/miot/home | 家庭/房间/设备/场景/成员总览(推荐首选) |
| `device_list` | GET /api/miot/device_list | 设备列表 |
| `device_status` | GET /api/miot/devices/{did}/status | 读属性(iid=prop.siid.piid,逗号分隔) |
| `device_spec` | GET /api/miot/devices/{did}/spec | 单设备属性/动作规格 |
| `device_control` | POST /api/miot/devices/{did}/control | set_property / set_properties / call_action |
| `scene_trigger` | POST /api/miot/scenes/{id}/trigger | 执行手动场景 |
| `refresh_devices` | GET /api/miot/refresh_miot_devices | 刷新云端设备缓存 |
| `account_status` | GET /api/miot/status + login_status | 米家账号绑定/登录状态 |
| `account_bind` | POST /api/miot/bind | 生成 OAuth 授权链接 |
| `account_authorize` | POST /api/miot/authorize | 提交授权码完成绑定 |
| `account_unbind` | POST /api/miot/unbind | 解绑(危险,清空 MIoT 状态) |
| `events_recent` | GET /api/events | 感知事件列表(摄像头看到了什么) |
| `event_media_url` | GET /api/events/{id}/clip\|ref\|crop/{did} | 事件片段/参考帧 URL(crop 直接返回元数据) |
| `camera_list` | GET /api/miot/camera_list | 摄像头列表 |
| `rules_list` | GET /api/rules + /api/rules/logs | 自动化规则及执行日志 |
| `system_status` | GET /api/admin/status + /health | 系统组件状态 |
| `notify_send` | POST /api/miot/send_notify | 向米家 App 推送通知 |
| `omni_config` | GET /api/admin/omni-config | 感知模型配置(API Key 已打码) |

## 5. 关键后端契约(来自上游源码)

- 控制请求体(见 `backend/miloco/src/miloco/miot/schema.py`):
  `{type: "set_property", iid: "prop.2.1", value: true}`
  `{type: "set_properties", properties: [{iid, value}, ...]}`
  `{type: "call_action", iid: "action.2.1", params: [...]}`
- 统一响应:`{code: 0, message, data}`;非 0 / HTTP 错误映射为工具错误文本。
- 后端默认只监听 127.0.0.1,`/`(index.html)会把 `server.token` 注入页面 ——
  **不要把后端端口暴露到公网**;跨机部署应走反代 + TLS。

## 6. DSH 接入方式(web profile)

在 `$DSH_HOME/profiles/web/cordis.patch.yml` 的 patch 列表追加一行 `insert`:

```yaml
- insert:
    - id: mcp-miloco
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: miloco
        transport: stdio
        command: node
        args: ['<绝对路径>/miloco-dsh/server/miloco-mcp.js']
        env:
          MILOCO_BASE_URL: http://127.0.0.1:1810
          MILOCO_TOKEN: !!js process.env.MILOCO_TOKEN
```

重启 `dsh web` 后,模型即获得 `mcp__miloco__*` 工具。另附 `skills/miloco/SKILL.md`,
放进 `$DSH_HOME/skills/miloco/` 让 agent 掌握标准工作流(状态检查 → 设备发现 → 控制 → 事件复盘)。

## 7. 已知边界(v1)

- 不实现事件 SSE 实时推送(DSH 无外部消息入口);用 `events_recent` 轮询覆盖。
- 不桥接视频流 / `record_clip`(mp4 二进制);通过 `event_media_url` 给浏览器直连 URL。
- 规则只读(列表/日志);写操作留给 Miloco 官方 Web 面板。
- Miloco 后端本身仍需官方途径安装(Linux/WSL/Docker),本适配不重实现后端。
