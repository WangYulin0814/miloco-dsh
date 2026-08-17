#!/usr/bin/env node
'use strict';
// merge-patch.js —— 把 mcp-miloco 的 cordis patch 条目幂等地合并进
// $DSH_HOME/profiles/web/cordis.patch.yml(由 install.ps1 / install.sh 调用)。
//
// 用法: node merge-patch.js <cordis.patch.yml> <repoDir> [baseUrl] [timeoutMs]
//
// 行为:
//   - 文件不存在              → 新建(带头部注释)
//   - 已有标记块(begin/end)   → 原位替换为最新内容
//   - 已有无标记旧条目(id: mcp-miloco)→ 迁移:只替换该顶层条目,其余内容不动
//   - 没有该条目              → 追加到文件末尾
//   - 写入前先备份 <file>.bak-<yyyyMMddHHmmss>;内容无变化则不写盘(幂等)
//
// 输出: 单行 JSON {status: added|updated|migrated|unchanged, patchFile, backup, serverPath}
// 退出码: 0 成功;2 参数错误;1 其它错误

const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
if (args.length < 2) {
  console.error('usage: node merge-patch.js <cordis.patch.yml> <repoDir> [baseUrl] [timeoutMs]');
  process.exit(2);
}

const patchFile = args[0];
const repoDir = args[1];
const baseUrl = args[2] || 'http://127.0.0.1:1810';
const timeoutMs = args[3] || '30000';
const serverPath = path.join(repoDir, 'server', 'miloco-mcp.js');

const BEGIN = '# >>> miloco-dsh begin (由 miloco-dsh 安装脚本维护,请勿手动修改) >>>';
const END = '# <<< miloco-dsh end <<<';

const HEADER = [
  '# Your patch layer for this dsh profile, applied after every bundle layer:',
  '# a top-level YAML array of loader patch entries (id-targeted config',
  '# overrides, disables, and insert lists; `!!js` expressions allowed).',
  '',
].join('\n');

// YAML 单引号标量:反斜杠原样保留,内部单引号翻倍
function yq(s) {
  return "'" + String(s).replace(/'/g, "''") + "'";
}

function buildBlock(eol) {
  return [
    BEGIN,
    '- insert:',
    '    - id: mcp-miloco',
    "      name: '@deepseek-ai/dsh-mcp-client'",
    '      config:',
    '        serverName: miloco',
    '        transport: stdio',
    '        command: node',
    '        args:',
    '          - ' + yq(serverPath),
    '        env:',
    '          MILOCO_BASE_URL: ' + yq(baseUrl),
    "          MILOCO_TIMEOUT_MS: '" + timeoutMs + "'",
    "          MILOCO_TOKEN: !!js process.env.MILOCO_TOKEN || ''",
    END,
  ].join(eol) + eol;
}

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// 按列 0 的 "- " 拆成顶层条目(数组元素),保留 preamble 注释块
function splitEntries(text) {
  const lines = text.split(/\r?\n/);
  const chunks = [];
  let cur = [];
  for (const line of lines) {
    if (/^- /.test(line) && cur.length > 0) {
      chunks.push(cur);
      cur = [];
    }
    cur.push(line);
  }
  if (cur.length > 0) chunks.push(cur);
  return chunks;
}

function timestamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return (
    d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) +
    p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds())
  );
}

function main() {
  let existing = null;
  try {
    existing = fs.readFileSync(patchFile, 'utf8');
  } catch (e) {
    if (e.code !== 'ENOENT') throw e;
  }

  const eol = existing && existing.includes('\r\n') ? '\r\n' : '\n';
  const block = buildBlock(eol);
  const blockLines = block.split(/\r?\n/);

  let status = 'added';
  let text = '';

  if (existing === null) {
    // 新建文件
    text = HEADER + buildBlock('\n');
    status = 'added';
  } else if (existing.includes(BEGIN) && existing.includes(END)) {
    // 已有标记块 → 原位替换
    const re = new RegExp(escapeRe(BEGIN) + '[\\s\\S]*?' + escapeRe(END) + '\\s*');
    const hit = re.test(existing);
    text = hit ? existing.replace(re, block) : existing + eol + block;
    status = hit ? 'updated' : 'added';
  } else if (/^\s*-?\s*id:\s*mcp-miloco\s*$/m.test(existing)) {
    // 旧的无标记条目 → 只替换该顶层条目
    const chunks = splitEntries(existing);
    let migrated = false;
    for (let i = 0; i < chunks.length; i++) {
      if (chunks[i].some((l) => /^\s*-?\s*id:\s*mcp-miloco\s*$/.test(l))) {
        chunks[i] = blockLines.slice();
        migrated = true;
        break;
      }
    }
    if (migrated) {
      text = chunks.map((c) => c.join(eol).replace(/\s+$/, '')).join(eol) + eol;
      status = 'migrated';
    } else {
      text = existing.replace(/\s+$/, '') + eol + eol + block;
      status = 'added';
    }
  } else {
    // 没有 → 追加
    text = existing.replace(/\s+$/, '') + eol + eol + block;
    status = 'added';
  }

  if (existing !== null && text === existing) {
    console.log(JSON.stringify({ status: 'unchanged', patchFile, backup: null, serverPath }));
    return 0;
  }

  let backup = null;
  if (existing !== null) {
    backup = patchFile + '.bak-' + timestamp();
    fs.copyFileSync(patchFile, backup);
  }
  const dir = path.dirname(patchFile);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(patchFile, text, 'utf8');
  console.log(JSON.stringify({ status, patchFile, backup, serverPath }));
  return 0;
}

try {
  process.exit(main());
} catch (e) {
  console.error('merge-patch failed:', e && e.message ? e.message : e);
  process.exit(1);
}
