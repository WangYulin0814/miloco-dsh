---
name: miloco
description: Use when users ask about Miloco, Xiaomi smart home control, 米家 devices, cameras, home automation, scenes, or say 打开/关闭/调节 devices, 家里情况, 摄像头事件, 米家账号绑定, or mention 小米智能家居、Miloco、设备列表、场景、感知事件、自动化规则.
keywords:
  - miloco
  - 小米智能家居
  - 米家
  - 智能家居
  - 设备控制
  - 摄像头
  - 感知事件
  - 场景
  - 自动化
  - 家里情况
packageType: instruction-skill
instructionOnly: true
metadata:
  version: 0.1.0
  openclaw:
    requiredMcp:
      - miloco
    requiresNetwork: true
    dataClassification: smart-home
---

# Miloco 智能家居助手

## 前置条件

**必需 MCP Server**: `miloco`(工具名为 `mcp__miloco__*`)。

若当前会话没有 `mcp__miloco__*` 工具:
1. Miloco 后端可能未启动。请用户确认后端运行状态(如 WSL 内 `miloco-cli service status`)。
2. 或 DSH 未加载 mcp-miloco 实例。请用户检查 `$DSH_HOME/profiles/web/cordis.patch.yml` 是否包含
   `mcp-miloco` 条目,并重启 `dsh web`。

## 标准工作流

1. **看全局** — 先调 `home_overview`(或 `device_list`)拿到家庭/设备/场景全貌;
   涉及账号问题时先调 `account_status`;涉及系统故障先调 `system_status`。
2. **看细节** — 控制设备前用 `device_spec` 确认该设备的属性/动作 IID 与合法取值
   (iid 形如 `prop.{siid}.{piid}`、`action.{siid}.{aiid}`);读状态用 `device_status`。
3. **执行** — `device_control` 控制设备,`scene_trigger` 执行场景。
4. **感知复盘** — 用户问"刚才发生了什么"时用 `events_recent` 拉事件列表,
   需要看画面用 `event_media_url`(kind=clip 视频 / ref 参考帧 / crop 裁剪元数据)拿 URL 给用户。
5. **主动提醒** — 需要向用户手机推送提醒时用 `notify_send`(仅用户要求时)。

## 设备控制要点

- 开关类属性常用 bool:`device_control { did, type: "set_property", iid: "prop.2.1", value: true }`
- 一次改多个属性用 `set_properties` + `properties: [{iid, value}, ...]`
- 动作(如暂停、回充)用 `call_action` + `iid: "action.{siid}.{aiid}"` + `params: []`(无参时)
- 不确定 iid / 值域时,**必须先** `device_spec`,不要猜;值不合规后端会拒绝。

## 账号绑定流程

1. `account_status` 看是否已绑定。
2. 未绑定:调 `account_bind` 拿到 `url` 与 `state`,把 url 发给用户,
   请用户在浏览器登录小米账号授权,把授权码复制回来。
3. 调 `account_authorize { code: <授权码>, state: <state> }` 完成绑定。
4. 授权码 5 分钟过期,提醒用户尽快操作。

## 安全纪律(重要)

- **token 永不外传**:`event_media_url` 返回的 URL 内嵌后端 Bearer token,只发给用户本人,
  不要写入日志/摘要/分享内容;仅限可信局域网使用。
- **不静默改动**:**解绑账号**(`account_unbind`)、**批量关摄像头感知**等破坏性操作,
  执行前必须征得用户明确同意,并说明后果。
- **控制物理设备前确认**:用户描述模糊(如"开灯"但有多个灯)时,先列出候选设备让用户选择;
  高危设备(门锁、燃气阀等)必须二次确认。
- **账号与配置**只读优先:不主动修改 omni 模型配置、不主动解绑。

## 故障排查

| 现象 | 处理 |
|---|---|
| 工具报 401 鉴权失败 | token 未配置或已轮换:让用户设置 `MILOCO_TOKEN` 或检查 `config.json` 的 `server.token` |
| 工具报"无法连接 Miloco 后端" | 后端未启动 / 端口不对:请用户检查服务状态与 `MILOCO_BASE_URL` |
| 设备列表为空 | 未绑定账号或未刷新:引导绑定账号,或调 `refresh_devices` |
| 事件查询为空 | 摄像头感知未开启:提醒用户在 Miloco 家庭面板「概览」页打开摄像头开关 |
