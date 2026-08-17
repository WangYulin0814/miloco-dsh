// mock-backend.js — 模拟 Miloco 后端 HTTP API,用于本地测试 miloco-mcp 的工具链路。
// 覆盖:鉴权校验、miot home/devices/control、account、events、rules、admin/status、notify、omni-config。
'use strict';
const http = require('http');

const TOKEN = process.env.MOCK_TOKEN || 'test-token-123';
const PORT = Number(process.env.MOCK_PORT || 1810);

const devices = [
  { did: 'did-light-1', name: '客厅灯', type: 'light', props: { 'prop.2.1': true, 'prop.2.2': 4000 } },
  { did: 'did-ac-1', name: '卧室空调', type: 'ac', props: { 'prop.2.1': false, 'prop.2.2': 26 } },
];
const scenes = [{ scene_id: 'scene-1', name: '离家模式' }, { scene_id: 'scene-2', name: '回家模式' }];
const events = [
  { event_id: 'evt-1', device_ids: ['did-cam-1'], type: 'person_detected', timestamp_ms: Date.now() - 60000 },
];
const rules = [{ rule_id: 'rule-1', name: '进门开灯', enabled: true }];

function json(res, obj, status = 200) {
  const body = JSON.stringify(obj);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(body);
}
function norm(res, data, message = 'ok') { json(res, { code: 0, message, data }); }

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  const p = url.pathname;
  const auth = req.headers.authorization || '';

  if (p === '/health') return json(res, { status: 'ok' });

  // 鉴权(与真实后端一致:除 /health 外全部要求 Bearer token)
  if (auth !== `Bearer ${TOKEN}`) return json(res, { detail: 'Not authenticated' }, 401);

  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    let payload = {};
    try { payload = body ? JSON.parse(body) : {}; } catch { return json(res, { detail: 'invalid json' }, 400); }

    const m = p.match(/^\/api\/miot\/devices\/([^/]+)\/(status|spec|control)$/);
    if (m) {
      const dev = devices.find((d) => d.did === decodeURIComponent(m[1]));
      if (!dev) return json(res, { detail: 'device not found' }, 404);
      if (m[2] === 'status') return norm(res, dev.props);
      if (m[2] === 'spec') return norm(res, { services: [{ siid: 2, name: 'switch', properties: [{ iid: 'prop.2.1', name: 'on', access: 'rw' }] }] });
      if (m[2] === 'control') {
        if (payload.type === 'set_property') dev.props[payload.iid] = payload.value;
        if (payload.type === 'set_properties') for (const it of payload.properties || []) dev.props[it.iid] = it.value;
        if (payload.type === 'call_action') return norm(res, { executed: payload.iid, params: payload.params });
        return norm(res, { did: dev.did, props: dev.props });
      }
    }

    switch (p) {
      case '/api/miot/home': return norm(res, { homes: [{ home_id: 'home-1', name: '我的家' }], devices, scenes, rooms: [{ name: '客厅' }], persons: [] });
      case '/api/miot/device_list': return norm(res, devices);
      case '/api/miot/camera_list': return norm(res, [{ did: 'did-cam-1', name: '门口摄像头' }]);
      case '/api/miot/status': return norm(res, { is_bound: true });
      case '/api/miot/login_status': return norm(res, { is_login: true });
      case '/api/miot/user_info': return norm(res, { nickname: '测试用户', uid: '12345' });
      case '/api/miot/bind': return norm(res, { url: 'https://account.xiaomi.com/oauth2/authorize?mock=1', state: 'state-abc' });
      case '/api/miot/authorize': return norm(res, { bound: true });
      case '/api/miot/unbind': return norm(res, null, 'unbound');
      case '/api/miot/send_notify': return norm(res, { sent: true });
      case '/api/miot/refresh_miot_devices': return norm(res, { refreshed: devices.length });
      case '/api/miot/scenes/scene-1/trigger': return norm(res, { triggered: true });
      case '/api/events': return norm(res, { events });
      case '/api/events/evt-1/crop/did-cam-1': return norm(res, { region_xyxy: [10, 20, 300, 400], frame_size_wh: [640, 480] });
      case '/api/rules': return norm(res, rules);
      case '/api/rules/logs': return norm(res, [{ rule_id: 'rule-1', at: Date.now(), ok: true }]);
      case '/api/admin/status': return norm(res, { miot: { ok: true }, sqlite: { ok: true }, perception: { ok: true }, rule_engine: { total_rules: 1, enabled_rules: 1 } });
      case '/api/admin/omni-config': return norm(res, { active: { model: 'xiaomi/mimo-v2.5', base_url: 'https://api.xiaomimimo.com/v1', api_key_masked: 'sk-1****abcd' } });
      default: return json(res, { detail: `mock 404: ${p}` }, 404);
    }
  });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[mock-miloco] listening on http://127.0.0.1:${PORT} token=${TOKEN}`);
});
