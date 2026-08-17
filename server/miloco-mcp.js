#!/usr/bin/env node
/**
 * miloco-mcp — Miloco backend bridge for DeepSeek Harness (MCP stdio server).
 *
 * 零依赖,单文件,纯 Node 标准库。把 Miloco 后端 HTTP API(默认 127.0.0.1:1810)
 * 包装成 MCP 工具,供 DeepSeek Harness 通过 @deepseek-ai/dsh-mcp-client 以
 * `mcp__miloco__<tool>` 名称调用。
 *
 * 配置(环境变量):
 *   MILOCO_BASE_URL   后端地址,默认 http://127.0.0.1:1810
 *   MILOCO_TOKEN      后端 Bearer token;缺省时按 MILOCO_HOME 自动找 config.json
 *   MILOCO_HOME       Miloco 配置目录,默认依次探测 ~/.miloco / ~/.openclaw/miloco / ~/.hermes/miloco
 *   MILOCO_TIMEOUT_MS 单次 HTTP 超时,默认 30000
 *
 * 协议: MCP 2025-06-18,stdio 换行分隔 JSON-RPC 2.0。
 * 日志一律写 stderr,stdout 只输出协议帧。
 */

'use strict';

const readline = require('readline');
const fs = require('fs');
const path = require('path');
const os = require('os');

const PROTOCOL_VERSION = '2025-06-18';
const SERVER_NAME = 'miloco-mcp';
const SERVER_VERSION = '0.1.0';

// ---------------------------------------------------------------------------
// 配置解析
// ---------------------------------------------------------------------------

function readConfigCandidates() {
  const cands = [];
  if (process.env.MILOCO_HOME) cands.push(path.join(process.env.MILOCO_HOME, 'config.json'));
  const home = os.homedir();
  cands.push(path.join(home, '.miloco', 'config.json'));
  cands.push(path.join(home, '.openclaw', 'miloco', 'config.json'));
  cands.push(path.join(home, '.hermes', 'miloco', 'config.json'));
  return cands;
}

function tokenFromConfigFile(file) {
  try {
    if (!fs.existsSync(file)) return null;
    const raw = fs.readFileSync(file, 'utf8');
    const cfg = JSON.parse(raw);
    const t = cfg && cfg.server && cfg.server.token;
    if (typeof t === 'string' && t) return t;
    // 兼容:部分部署把 token 放顶层(如 agent.auth_bearer 仅供 webhook,不用于 API)
    if (typeof cfg === 'object' && cfg && typeof cfg.token === 'string' && cfg.token) return cfg.token;
    return null;
  } catch {
    return null;
  }
}

function resolveConfig() {
  const baseUrl = (process.env.MILOCO_BASE_URL || 'http://127.0.0.1:1810').replace(/\/+$/, '');
  let token = process.env.MILOCO_TOKEN || '';
  let tokenSource = 'env:MILOCO_TOKEN';
  if (!token) {
    for (const f of readConfigCandidates()) {
      const t = tokenFromConfigFile(f);
      if (t) { token = t; tokenSource = `file:${f}`; break; }
    }
  }
  const timeoutMs = Number.parseInt(process.env.MILOCO_TIMEOUT_MS || '30000', 10) || 30000;
  return { baseUrl, token, tokenSource, timeoutMs };
}

let CFG = resolveConfig();

// ---------------------------------------------------------------------------
// HTTP 辅助
// ---------------------------------------------------------------------------

async function milocoApi(method, p, { query, body } = {}) {
  const url = new URL(CFG.baseUrl + p);
  if (query) {
    for (const [k, v] of Object.entries(query)) {
      if (v === undefined || v === null || v === '') continue;
      url.searchParams.set(k, String(v));
    }
  }
  const headers = { Accept: 'application/json' };
  if (CFG.token) headers.Authorization = `Bearer ${CFG.token}`;
  let payload;
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    payload = JSON.stringify(body);
  }
  // GET 允许重试一次:Windows↔WSL localhost 转发的首次连接偶发慢启动
  const attempts = method === 'GET' ? 2 : 1;
  let res;
  for (let attempt = 1; ; attempt++) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), CFG.timeoutMs);
    try {
      res = await fetch(url.toString(), { method, headers, body: payload, signal: ctrl.signal });
      break;
    } catch (err) {
      if (attempt < attempts && err && err.name === 'AbortError') {
        log('first GET stalled, retrying once');
        continue;
      }
      const reason = err && err.name === 'AbortError'
        ? `请求超时(>${CFG.timeoutMs}ms)`
        : `无法连接 Miloco 后端:${err.message || err}`;
      throw new Error(`[miloco] ${reason}。请确认后端已启动且 MILOCO_BASE_URL 正确(当前 ${CFG.baseUrl})。`);
    } finally {
      clearTimeout(timer);
    }
  }
  let text = '';
  try { text = await res.text(); } catch { /* ignore */ }
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* non-JSON body */ }
  if (res.status === 401) {
    throw new Error(`[miloco] 鉴权失败(401)。token 来源 ${CFG.tokenSource}${CFG.token ? '' : ' — 未找到 token'}。` +
      '请设置 MILOCO_TOKEN,或确认 config.json 中 server.token 可读。');
  }
  if (!res.ok) {
    const detail = json && json.detail ? JSON.stringify(json.detail) : (text || res.statusText).slice(0, 300);
    throw new Error(`[miloco] HTTP ${res.status} ${detail}`);
  }
  return json;
}

function okResult(data, message) {
  return { ok: true, code: 0, message: message || 'ok', data: data === undefined ? null : data };
}

function errResult(err) {
  return { ok: false, code: -1, message: String((err && err.message) || err), data: null };
}

// ---------------------------------------------------------------------------
// 工具定义
// ---------------------------------------------------------------------------

const TOOLS = [
  {
    name: 'home_overview',
    description: '获取家庭总览:家庭(homes)、房间(rooms)、设备(devices)、场景(scenes)、成员(persons)。' +
      '这是了解全屋状态的首选入口;refresh=true 时先刷新云端设备/摄像头/场景缓存。',
    inputSchema: {
      type: 'object',
      properties: {
        refresh: { type: 'boolean', description: '是否先刷新云端缓存(默认 false)', default: false },
      },
    },
    handler: async (args) => {
      const data = await milocoApi('GET', '/api/miot/home', { query: { refresh: args.refresh ? 'true' : undefined } });
      return okResult(data.data, data.message);
    },
  },
  {
    name: 'device_list',
    description: '获取米家设备列表(扁平)。与 home_overview 的 devices 字段同源。',
    inputSchema: { type: 'object', properties: {} },
    handler: async () => {
      const data = await milocoApi('GET', '/api/miot/device_list');
      return okResult(data.data, data.message);
    },
  },
  {
    name: 'device_status',
    description: '读取单个设备的属性值。iids 为逗号分隔的属性 IID(形如 prop.2.1,prop.2.2);' +
      '缺省返回设备全部属性。属性 IID 可从 device_spec 获取。',
    inputSchema: {
      type: 'object',
      properties: {
        did: { type: 'string', description: '设备 did' },
        iids: { type: 'string', description: '逗号分隔的属性 IID 列表,如 prop.2.1,prop.2.2;缺省查全部' },
      },
      required: ['did'],
    },
    handler: async (args) => {
      const data = await milocoApi('GET', `/api/miot/devices/${encodeURIComponent(args.did)}/status`, {
        query: { iid: args.iids },
      });
      return okResult(data.data, data.message);
    },
  },
  {
    name: 'device_spec',
    description: '获取单个设备的属性/动作规格(服务 siid、属性 piid、动作 aiid 及其值域),' +
      '控制设备前用它确认 iid 与合法取值。',
    inputSchema: {
      type: 'object',
      properties: { did: { type: 'string', description: '设备 did' } },
      required: ['did'],
    },
    handler: async (args) => {
      const data = await milocoApi('GET', `/api/miot/devices/${encodeURIComponent(args.did)}/spec`);
      return okResult(data.data, data.message);
    },
  },
  {
    name: 'device_control',
    description: '控制米家设备,三种类型:\n' +
      '1) set_property:设置单个属性,iid 形如 prop.{siid}.{piid},value 为该属性值(开关类常用 bool);\n' +
      '2) set_properties:一次设置多个属性,properties 为 [{iid, value}, ...];\n' +
      '3) call_action:调用动作,iid 形如 action.{siid}.{aiid},params 为动作入参数组(无参传 [])。\n' +
      'iid 与合法取值请先用 device_spec 确认。',
    inputSchema: {
      type: 'object',
      properties: {
        did: { type: 'string', description: '设备 did' },
        type: { type: 'string', enum: ['set_property', 'set_properties', 'call_action'], description: '控制类型' },
        iid: { type: 'string', description: '属性/动作 IID;set_property 与 call_action 必填' },
        value: { description: 'set_property 的属性值(bool / number / string)' },
        properties: {
          type: 'array',
          description: 'set_properties 的属性列表',
          items: {
            type: 'object',
            properties: { iid: { type: 'string' }, value: {} },
            required: ['iid', 'value'],
          },
        },
        params: { type: 'array', description: 'call_action 的入参列表' },
      },
      required: ['did', 'type'],
    },
    handler: async (args) => {
      const body = { type: args.type };
      if (args.type === 'set_property') body.iid = args.iid, body.value = args.value;
      else if (args.type === 'set_properties') body.properties = args.properties;
      else if (args.type === 'call_action') body.iid = args.iid, body.params = args.params || [];
      const data = await milocoApi('POST', `/api/miot/devices/${encodeURIComponent(args.did)}/control`, { body });
      return okResult(data.data, data.message);
    },
  },
  {
    name: 'scene_trigger',
    description: '执行米家手动场景(一键离家/回家等)。scene_id 来自 home_overview 的 scenes 字段。',
    inputSchema: {
      type: 'object',
      properties: { scene_id: { type: 'string', description: '场景 ID' } },
      required: ['scene_id'],
    },
    handler: async (args) => {
      const data = await milocoApi('POST', `/api/miot/scenes/${encodeURIComponent(args.scene_id)}/trigger`);
      return okResult(data.data, data.message);
    },
  },
  {
    name: 'refresh_devices',
    description: '从米家云端刷新设备缓存(新增/改名设备后调用)。',
    inputSchema: { type: 'object', properties: {} },
    handler: async () => {
      const data = await milocoApi('GET', '/api/miot/refresh_miot_devices');
      return okResult(data.data, data.message);
    },
  },
  {
    name: 'account_status',
    description: '查看米家账号绑定与登录状态(是否已绑定、用户信息)。',
    inputSchema: { type: 'object', properties: {} },
    handler: async () => {
      const [st, ls, ui] = await Promise.all([
        milocoApi('GET', '/api/miot/status').catch((e) => ({ code: -1, message: e.message, data: null })),
        milocoApi('GET', '/api/miot/login_status').catch((e) => ({ code: -1, message: e.message, data: null })),
        milocoApi('GET', '/api/miot/user_info').catch((e) => ({ code: -1, message: e.message, data: null })),
      ]);
      return okResult({ bind: st.data, login: ls.data, user: ui.data }, 'account status');
    },
  },
  {
    name: 'account_bind',
    description: '发起米家账号绑定:返回 OAuth 授权链接与 state。把链接给用户,在浏览器中登录小米账号授权后,' +
      '把页面上显示的授权码交给 account_authorize 完成绑定。',
    inputSchema: { type: 'object', properties: {} },
    handler: async () => {
      const data = await milocoApi('POST', '/api/miot/bind');
      const d = data.data || {};
      const u = d.oauth_url || d.url || '';
      let state = d.state || '';
      if (!state && u) {
        try { state = new URL(u).searchParams.get('state') || ''; } catch { /* keep */ }
      }
      return okResult({ url: u, oauth_url: u, state, raw: d }, data.message);
    },
  },
  {
    name: 'account_authorize',
    description: '提交用户在授权页拿到的授权码(code)与 state,完成米家账号绑定。',
    inputSchema: {
      type: 'object',
      properties: {
        code: { type: 'string', description: 'OAuth 授权码' },
        state: { type: 'string', description: 'OAuth state(account_bind 返回值中提供)' },
      },
      required: ['code', 'state'],
    },
    handler: async (args) => {
      const data = await milocoApi('POST', '/api/miot/authorize', { body: { code: args.code, state: args.state } });
      return okResult(data.data, data.message);
    },
  },
  {
    name: 'account_unbind',
    description: '解绑米家账号(清空全部 MIoT 状态)。⚠️ 不可逆,执行后需重新绑定。',
    inputSchema: { type: 'object', properties: {} },
    handler: async () => {
      const data = await milocoApi('POST', '/api/miot/unbind');
      return okResult(data.data, data.message);
    },
  },
  {
    name: 'events_recent',
    description: '获取 Miloco 感知事件列表(摄像头/拾音看到的有意义事件,如有人出现、异常声响等)。' +
      'since/before 为 Unix 毫秒 UTC;按时间倒序,默认最近 50 条,limit 上限 200。',
    inputSchema: {
      type: 'object',
      properties: {
        since: { type: 'integer', description: '起始时间(Unix ms,含),默认 0' },
        before: { type: 'integer', description: '截止时间(Unix ms,不含),默认当前' },
        limit: { type: 'integer', description: '条数,默认 50,上限 200' },
        offset: { type: 'integer', description: '分页偏移' },
      },
    },
    handler: async (args) => {
      const data = await milocoApi('GET', '/api/events', {
        query: { since: args.since, before: args.before, limit: args.limit, offset: args.offset },
      });
      return okResult(data.data, data.message);
    },
  },
  {
    name: 'event_media_url',
    description: '获取事件的视频片段 / 全景参考帧的直接访问 URL(浏览器打开),或 Smart Crop 区域元数据。\n' +
      'kind=clip 返回 mp4/m4a 片段 URL;kind=ref 返回参考帧 JPEG URL;kind=crop 直接返回裁剪区域坐标元数据。\n' +
      'URL 已带鉴权 token,仅在可信局域网内使用。',
    inputSchema: {
      type: 'object',
      properties: {
        event_id: { type: 'string', description: '事件 ID(来自 events_recent)' },
        device_id: { type: 'string', description: '设备 did(来自事件的 device_ids)' },
        kind: { type: 'string', enum: ['clip', 'ref', 'crop'], description: '媒体类型,默认 clip' },
      },
      required: ['event_id', 'device_id'],
    },
    handler: async (args) => {
      const kind = args.kind || 'clip';
      if (kind === 'crop') {
        const data = await milocoApi('GET',
          `/api/events/${encodeURIComponent(args.event_id)}/crop/${encodeURIComponent(args.device_id)}`);
        return okResult(data.data, data.message);
      }
      const u = new URL(CFG.baseUrl + `/api/events/${encodeURIComponent(args.event_id)}/${kind}/` +
        encodeURIComponent(args.device_id));
      if (CFG.token) u.searchParams.set('token', CFG.token);
      return okResult({ url: u.toString(), kind, note: '仅局域网内可信环境使用;URL 含鉴权 token,勿外传' });
    },
  },
  {
    name: 'camera_list',
    description: '获取米家摄像头列表。',
    inputSchema: { type: 'object', properties: {} },
    handler: async () => {
      const data = await milocoApi('GET', '/api/miot/camera_list');
      return okResult(data.data, data.message);
    },
  },
  {
    name: 'rules_list',
    description: '获取自动化规则列表与最近执行日志(只读)。',
    inputSchema: { type: 'object', properties: {} },
    handler: async () => {
      const [r, l] = await Promise.all([
        milocoApi('GET', '/api/rules').catch((e) => ({ code: -1, message: e.message, data: null })),
        milocoApi('GET', '/api/rules/logs').catch((e) => ({ code: -1, message: e.message, data: null })),
      ]);
      return okResult({ rules: r.data, logs: l.data }, 'rules');
    },
  },
  {
    name: 'system_status',
    description: '查看 Miloco 系统组件状态(MIOT 登录、SQLite、感知引擎、规则引擎)。',
    inputSchema: { type: 'object', properties: {} },
    handler: async () => {
      const data = await milocoApi('GET', '/api/admin/status');
      return okResult(data.data, data.message);
    },
  },
  {
    name: 'notify_send',
    description: '通过米家向用户推送一条通知文本(如提醒、告警)。',
    inputSchema: {
      type: 'object',
      properties: { text: { type: 'string', description: '通知内容(1-200 字)' } },
      required: ['text'],
    },
    handler: async (args) => {
      const data = await milocoApi('POST', '/api/miot/send_notify', { body: { notify: args.text } });
      return okResult(data.data, data.message);
    },
  },
  {
    name: 'omni_config',
    description: '查看感知引擎的多模态模型配置(模型名、Base URL;API Key 打码显示)。',
    inputSchema: { type: 'object', properties: {} },
    handler: async () => {
      const data = await milocoApi('GET', '/api/admin/omni-config');
      return okResult(data.data, data.message);
    },
  },
];

const TOOL_MAP = new Map(TOOLS.map((t) => [t.name, t]));

// ---------------------------------------------------------------------------
// MCP stdio 服务
// ---------------------------------------------------------------------------

function log(...args) {
  process.stderr.write(`[${SERVER_NAME}] ${args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ')}\n`);
}

function send(message) {
  process.stdout.write(JSON.stringify(message) + '\n');
}

async function handleRequest(msg) {
  const { id, method, params } = msg || {};
  switch (method) {
    case 'initialize': {
      return {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
      };
    }
    case 'tools/list': {
      return { tools: TOOLS.map(({ name, description, inputSchema }) => ({ name, description, inputSchema })) };
    }
    case 'tools/call': {
      const tool = TOOL_MAP.get(params && params.name);
      if (!tool) {
        return { content: [{ type: 'text', text: JSON.stringify(errResult(new Error(`未知工具: ${params && params.name}`))) }], isError: true };
      }
      const args = (params && params.arguments) || {};
      const started = Date.now();
      try {
        const result = await tool.handler(args);
        log('tool', tool.name, 'ok', `${Date.now() - started}ms`);
        return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] };
      } catch (err) {
        log('tool', tool.name, 'error', err.message || err);
        return { content: [{ type: 'text', text: JSON.stringify(errResult(err), null, 2) }], isError: true };
      }
    }
    case 'ping':
      return {};
    default:
      throw new Error(`unsupported method: ${method}`);
  }
}

async function main() {
  const rl = readline.createInterface({ input: process.stdin, terminal: false });
  log('start', `baseUrl=${CFG.baseUrl}`, `token=${CFG.token ? 'present(' + CFG.tokenSource + ')' : 'MISSING'}`);

  rl.on('line', (line) => {
    const trimmed = line.trim();
    if (!trimmed) return;
    let msg;
    try { msg = JSON.parse(trimmed); } catch (err) { log('bad json:', err.message); return; }

    if (msg && typeof msg.method === 'string' && msg.method.startsWith('notifications/')) {
      // 客户端通知(initialized / cancelled / roots_list_changed 等)——无需响应
      return;
    }
    if (msg && msg.id !== undefined) {
      Promise.resolve()
        .then(() => handleRequest(msg))
        .then((result) => send({ jsonrpc: '2.0', id: msg.id, result }))
        .catch((err) => send({ jsonrpc: '2.0', id: msg.id, error: { code: -32603, message: String(err.message || err) } }));
    } else {
      log('dropped request without id:', trimmed.slice(0, 200));
    }
  });

  const shutdown = () => {
    log('exit');
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
  process.stdin.on('close', () => {
    // 父进程关闭管道:自然收尾(不强制 process.exit),规避 Windows 下
    // 强制退出时 libuv 的 "UV_HANDLE_CLOSING" 断言噪音。
    log('stdin closed');
    process.exitCode = 0;
  });
}

main().catch((err) => {
  log('fatal', err && err.stack ? err.stack : err);
  process.exit(1);
});
