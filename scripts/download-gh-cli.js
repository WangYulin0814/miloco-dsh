// 经 api.github.com 资产接口下载 GitHub CLI 官方 zip(带重试)
const fs = require('fs');
const os = require('os');
const path = require('path');

const OUT = path.join(os.tmpdir(), 'gh.zip');
const EXPECT = 11801995; // gh_2.97.0_windows_amd64.zip 参考大小,以下载为准(仅作日志参考)

async function getAssetUrl() {
  const r = await fetch('https://api.github.com/repos/cli/cli/releases/latest', {
    headers: { 'User-Agent': 'dsh', Accept: 'application/vnd.github+json' },
  });
  const j = await r.json();
  const a = (j.assets || []).find((x) => x.name === 'gh_2.97.0_windows_amd64.zip') ||
            (j.assets || []).find((x) => /windows_amd64\.zip$/.test(x.name));
  if (!a) throw new Error('asset not found: ' + JSON.stringify((j.assets || []).map((x) => x.name)));
  console.log('asset:', a.name, a.size, 'tag:', j.tag_name);
  return { url: a.url, size: a.size };
}

(async () => {
  const { url, size } = await getAssetUrl();
  let lastSize = 0;
  for (let i = 1; i <= 15; i++) {
    try {
      console.log(`attempt ${i} (${new Date().toLocaleTimeString()}), 已下载 ${lastSize}/${size}`);
      const r = await fetch(url, { headers: { 'User-Agent': 'dsh', Accept: 'application/octet-stream' } });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const buf = Buffer.from(await r.arrayBuffer());
      fs.writeFileSync(OUT, buf);
      if (buf.length === size) {
        console.log('GH_ZIP_OK ' + OUT + ' bytes=' + buf.length);
        return;
      }
      console.log('size mismatch, retry', buf.length);
      lastSize = buf.length;
    } catch (e) {
      console.log('fail:', e.message);
    }
    await new Promise((r) => setTimeout(r, 3000));
  }
  console.log('GH_ZIP_FAILED');
  process.exitCode = 1;
})();
