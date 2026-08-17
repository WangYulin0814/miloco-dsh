// test-full.js — 端到端测试:mock 后端 + miloco-mcp 真实工具调用链路。
'use strict';
const { spawn } = require('child_process');
const path = require('path');

const MOCK = spawn(process.execPath, [path.join(__dirname, 'mock-backend.js')], { stdio: ['ignore', 'inherit', 'inherit'] });
let mcp;
let buf = '';
const pending = new Map();
let nextId = 1;

function connect(env) {
  if (mcp) mcp.kill();
  buf = '';
  pending.clear();
  mcp = spawn(process.execPath, [path.join(__dirname, 'miloco-mcp.js')], {
    stdio: ['pipe', 'pipe', 'inherit'],
    env: { ...process.env, MILOCO_BASE_URL: 'http://127.0.0.1:1810', MILOCO_TIMEOUT_MS: '5000', ...env },
  });
  mcp.stdout.on('data', (chunk) => {
    buf += chunk.toString('utf8');
    let idx;
    while ((idx = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, idx).trim();
      buf = buf.slice(idx + 1);
      if (!line) continue;
      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      if (msg.id !== undefined && pending.has(msg.id)) {
        pending.get(msg.id)(msg);
        pending.delete(msg.id);
      }
    }
  });
}

function send(method, params) {
  const id = nextId++;
  mcp.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  return new Promise((resolve) => pending.set(id, resolve));
}

async function call(name, args) {
  const r = await send('tools/call', { name, arguments: args || {} });
  const text = r.result && r.result.content && r.result.content[0] && r.result.content[0].text;
  let parsed = null;
  try { parsed = text ? JSON.parse(text) : null; } catch {}
  return { isError: !!r.result.isError, parsed };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  await sleep(600); // 等 mock 起
  let failures = 0;
  const check = (name, cond, extra) => {
    console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`);
    if (!cond) failures++;
  };

  // 场景 1:正确 token
  connect({ MILOCO_TOKEN: 'test-token-123' });
  await send('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 't', version: '1' } });

  let r = await call('system_status', {});
  check('system_status', r.parsed && r.parsed.ok && r.parsed.data.miot.ok, JSON.stringify(r.parsed && r.parsed.data));

  r = await call('home_overview', {});
  const devs = r.parsed && r.parsed.data && r.parsed.data.devices;
  check('home_overview 设备数', Array.isArray(devs) && devs.length === 2);

  r = await call('device_control', { did: 'did-light-1', type: 'set_property', iid: 'prop.2.1', value: false });
  check('device_control set_property', r.parsed && r.parsed.ok && r.parsed.data.props['prop.2.1'] === false, JSON.stringify(r.parsed && r.parsed.data));

  r = await call('device_status', { did: 'did-light-1', iids: 'prop.2.1' });
  check('device_status 读回关闭态', r.parsed && r.parsed.data['prop.2.1'] === false);

  r = await call('device_control', { did: 'did-ac-1', type: 'set_properties', properties: [{ iid: 'prop.2.1', value: true }, { iid: 'prop.2.2', value: 24 }] });
  check('device_control set_properties', r.parsed && r.parsed.ok);

  r = await call('device_control', { did: 'did-ac-1', type: 'call_action', iid: 'action.2.1', params: [] });
  check('device_control call_action', r.parsed && r.parsed.ok && r.parsed.data.executed === 'action.2.1');

  r = await call('scene_trigger', { scene_id: 'scene-1' });
  check('scene_trigger', r.parsed && r.parsed.ok && r.parsed.data.triggered === true);

  r = await call('account_bind', {});
  check('account_bind 返回 OAuth url + state', r.parsed && r.parsed.ok && r.parsed.data.url.startsWith('https://') && r.parsed.data.state === 'state-abc');

  r = await call('account_authorize', { code: 'c1', state: 'state-abc' });
  check('account_authorize', r.parsed && r.parsed.ok && r.parsed.data.bound === true);

  r = await call('account_status', {});
  check('account_status 聚合三接口', r.parsed && r.parsed.ok && r.parsed.data.bind.is_bound === true && r.parsed.data.user.nickname === '测试用户');

  r = await call('events_recent', { limit: 10 });
  check('events_recent', r.parsed && r.parsed.ok && r.parsed.data.events.length === 1 && r.parsed.data.events[0].event_id === 'evt-1');

  r = await call('event_media_url', { event_id: 'evt-1', device_id: 'did-cam-1', kind: 'clip' });
  const clipUrl = r.parsed && r.parsed.data && r.parsed.data.url;
  check('event_media_url clip 带 token query', !!clipUrl && clipUrl.includes('token=test-token-123') && clipUrl.includes('/clip/'), clipUrl);

  r = await call('event_media_url', { event_id: 'evt-1', device_id: 'did-cam-1', kind: 'crop' });
  check('event_media_url crop 返回元数据', r.parsed && r.parsed.ok && Array.isArray(r.parsed.data.region_xyxy));

  r = await call('rules_list', {});
  check('rules_list', r.parsed && r.parsed.ok && r.parsed.data.rules.length === 1 && r.parsed.data.logs.length === 1);

  r = await call('notify_send', { text: '测试通知' });
  check('notify_send', r.parsed && r.parsed.ok && r.parsed.data.sent === true);

  r = await call('omni_config', {});
  check('omni_config key 打码', r.parsed && r.parsed.ok && r.parsed.data.active.api_key_masked === 'sk-1****abcd');

  r = await call('camera_list', {});
  check('camera_list', r.parsed && r.parsed.ok && r.parsed.data.length === 1);

  r = await call('refresh_devices', {});
  check('refresh_devices', r.parsed && r.parsed.ok);

  r = await call('device_status', { did: 'no-such-did' });
  check('不存在的设备 → isError', r.isError === true && r.parsed && /HTTP 404/.test(r.parsed.message));

  // 场景 2:错误 token → 401 清晰报错
  connect({ MILOCO_TOKEN: 'wrong-token' });
  await send('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 't', version: '1' } });
  r = await call('system_status', {});
  check('错误 token → 401 提示', r.isError === true && r.parsed && /鉴权失败\(401\)/.test(r.parsed.message), r.parsed && r.parsed.message);

  // 场景 3:无 token(自动发现不可用)→ 401 提示含来源
  connect({ MILOCO_HOME: path.join(__dirname, 'no-such-home') });
  await send('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 't', version: '1' } });
  r = await call('system_status', {});
  check('无 token → 401 提示', r.isError === true && r.parsed && /鉴权失败\(401\)/.test(r.parsed.message), r.parsed && r.parsed.message);

  mcp.kill();
  MOCK.kill();
  console.log(failures === 0 ? '\nALL PASS' : `\n${failures} FAILURES`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((e) => {
  console.error('TEST FAILED:', e);
  try { mcp.kill(); MOCK.kill(); } catch {}
  process.exit(1);
});
