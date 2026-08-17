// test-sdk.mjs — 用 DSH 实际依赖的 @modelcontextprotocol/sdk v1.30.0 官方客户端
// 连接 miloco-mcp(而非自制客户端),验证与官方 SDK 的完全兼容性。
import { Client } from 'file:///C:/Users/Ephemeral/AppData/Local/npm-cache/_npx/1e7f6d9597241db0/node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js';
import { StdioClientTransport } from 'file:///C:/Users/Ephemeral/AppData/Local/npm-cache/_npx/1e7f6d9597241db0/node_modules/@modelcontextprotocol/sdk/dist/esm/client/stdio.js';
import { spawn } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const mock = spawn(process.execPath, [path.join(__dirname, 'mock-backend.js')], { stdio: ['ignore', 'inherit', 'inherit'] });
await new Promise((r) => setTimeout(r, 600));

const transport = new StdioClientTransport({
  command: process.execPath,
  args: [path.join(__dirname, 'miloco-mcp.js')],
  env: {
    ...process.env,
    MILOCO_BASE_URL: 'http://127.0.0.1:1810',
    MILOCO_TOKEN: 'test-token-123',
  },
});

const client = new Client({ name: 'sdk-test', version: '1.0' });
let failures = 0;
const check = (name, cond, extra) => {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`);
  if (!cond) failures++;
};

try {
  await client.connect(transport);
  check('SDK connect 成功', true); // connect() 返回 undefined;走到这里即握手成功

  const list = await client.listTools();
  check('listTools 返回 18 个工具', list.tools.length === 18, `got ${list.tools.length}`);

  const r1 = await client.callTool({ name: 'home_overview', arguments: {} });
  const t1 = r1.content.find((c) => c.type === 'text')?.text || '';
  const d1 = JSON.parse(t1);
  check('home_overview 经官方 SDK 调用成功', d1.ok === true && d1.data.devices.length === 2);

  const r2 = await client.callTool({
    name: 'device_control',
    arguments: { did: 'did-light-1', type: 'set_property', iid: 'prop.2.1', value: true },
  });
  const d2 = JSON.parse(r2.content.find((c) => c.type === 'text')?.text || '{}');
  check('device_control 经官方 SDK 调用成功', d2.ok === true && d2.data.props['prop.2.1'] === true);

  const r3 = await client.callTool({ name: 'notify_send', arguments: { text: 'SDK 测试' } });
  const d3 = JSON.parse(r3.content.find((c) => c.type === 'text')?.text || '{}');
  check('notify_send 经官方 SDK 调用成功', d3.ok === true);

  await client.close();
  console.log(failures === 0 ? '\nSDK COMPAT: ALL PASS' : `\n${failures} FAILURES`);
} catch (e) {
  console.error('SDK TEST FAILED:', e);
  failures++;
} finally {
  await new Promise((r) => setTimeout(r, 200));
  mock.kill();
  process.exitCode = failures === 0 ? 0 : 1;
  // 不调用 process.exit:让事件循环自然收尾,规避 Windows 上强制退出的 uv 断言
}
