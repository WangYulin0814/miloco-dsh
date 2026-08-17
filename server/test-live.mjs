// test-live.mjs — 真实链路测试:官方 MCP SDK → miloco-mcp → WSL 里的真 Miloco 后端。
import { Client } from 'file:///C:/Users/Ephemeral/AppData/Local/npm-cache/_npx/1e7f6d9597241db0/node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js';
import { StdioClientTransport } from 'file:///C:/Users/Ephemeral/AppData/Local/npm-cache/_npx/1e7f6d9597241db0/node_modules/@modelcontextprotocol/sdk/dist/esm/client/stdio.js';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TOKEN = process.env.MILOCO_TOKEN || '';

const transport = new StdioClientTransport({
  command: process.execPath,
  args: [path.join(__dirname, 'miloco-mcp.js')],
  env: {
    ...process.env,
    MILOCO_BASE_URL: 'http://127.0.0.1:1810',
    MILOCO_TOKEN: TOKEN,
    MILOCO_TIMEOUT_MS: '30000',
  },
});

const client = new Client({ name: 'live-test', version: '1.0' });
let failures = 0;
const check = (name, cond, extra) => {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + JSON.stringify(extra).slice(0, 200) : ''}`);
  if (!cond) failures++;
};

async function call(name, args) {
  const r = await client.callTool({ name, arguments: args || {} });
  const text = r.content.find((c) => c.type === 'text')?.text || '';
  let parsed = null;
  try { parsed = JSON.parse(text); } catch {}
  return { isError: !!r.isError, parsed, text };
}

try {
  await client.connect(transport);
  check('连接真后端(MCP 握手)', true);

  let r = await call('system_status', {});
  check('system_status', r.parsed?.ok === true, r.parsed?.data);

  r = await call('account_status', {});
  const bound = r.parsed?.data?.bind?.is_bound;
  check('account_status(应为未绑定)', r.parsed?.ok === true && bound === false, { bound });

  r = await call('rules_list', {});
  check('rules_list(空列表)', r.parsed?.ok === true, r.parsed?.data);

  r = await call('events_recent', { limit: 5 });
  check('events_recent(空)', r.parsed?.ok === true, r.parsed?.data);

  r = await call('omni_config', {});
  check('omni_config(未配置模型)', r.parsed?.ok === true, r.parsed?.data?.active);

  r = await call('device_list', {});
  check('device_list(未绑定:空或业务错误均可)', r.parsed !== null || r.isError, r.isError ? r.parsed?.message : r.parsed?.data);

  r = await call('home_overview', {});
  check('home_overview(未绑定:空或业务错误均可)', r.parsed !== null || r.isError, r.isError ? r.parsed?.message : JSON.stringify(r.parsed?.data).slice(0, 150));

  // 关键:拿真实绑定链接
  r = await call('account_bind', {});
  const bindUrl = r.parsed?.data?.url;
  check('account_bind 返回真实 OAuth 链接', r.parsed?.ok === true && /^https:\/\/account\.xiaomi\.com\//.test(bindUrl || ''), { url: bindUrl, state: r.parsed?.data?.state });
  if (bindUrl) console.log('\nBIND_URL_FOR_USER=' + bindUrl + '\n');

  await client.close();
  console.log(failures === 0 ? '\nLIVE TEST: ALL PASS' : `\n${failures} FAILURES`);
  process.exitCode = failures === 0 ? 0 : 1;
} catch (e) {
  console.error('LIVE TEST FAILED:', e);
  process.exitCode = 1;
}
