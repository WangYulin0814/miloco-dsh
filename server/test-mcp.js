// 冒烟测试:以客户端身份与 miloco-mcp 完成一次完整 MCP stdio 会话。
'use strict';
const { spawn } = require('child_process');
const path = require('path');

const server = spawn(process.execPath, [path.join(__dirname, 'miloco-mcp.js')], {
  stdio: ['pipe', 'pipe', 'inherit'],
});
let buf = '';
const pending = new Map();
let nextId = 1;

function send(method, params) {
  const id = nextId++;
  const msg = { jsonrpc: '2.0', id, method, params };
  server.stdin.write(JSON.stringify(msg) + '\n');
  return new Promise((resolve) => pending.set(id, resolve));
}

server.stdout.on('data', (chunk) => {
  buf += chunk.toString('utf8');
  let idx;
  while ((idx = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, idx).trim();
    buf = buf.slice(idx + 1);
    if (!line) continue;
    const msg = JSON.parse(line);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  }
});

(async () => {
  const init = await send('initialize', {
    protocolVersion: '2025-06-18',
    capabilities: {},
    clientInfo: { name: 'smoke-test', version: '0.0.1' },
  });
  console.log('initialize →', JSON.stringify(init.result || init.error));

  send('notifications/initialized', {}); // 通知无需响应

  const list = await send('tools/list', {});
  const tools = list.result && list.result.tools;
  console.log('tools/list →', tools ? `${tools.length} tools` : JSON.stringify(list.error));
  if (tools) console.log('tool names:', tools.map((t) => t.name).join(', '));

  const ping = await send('ping', {});
  console.log('ping →', JSON.stringify(ping.result));

  // 后端未启动时应得到干净的 isError 结果而非崩溃
  const call = await send('tools/call', { name: 'system_status', arguments: {} });
  const txt = call.result && call.result.content && call.result.content[0].text;
  console.log('tools/call(system_status, backend down) → isError =', call.result.isError);
  console.log('  内容:', txt ? txt.slice(0, 220) : JSON.stringify(call).slice(0, 220));

  const bad = await send('tools/call', { name: 'no_such_tool', arguments: {} });
  console.log('tools/call(unknown) → isError =', bad.result.isError);

  server.kill();
  process.exit(0);
})().catch((e) => {
  console.error('SMOKE FAILED:', e);
  server.kill();
  process.exit(1);
});
