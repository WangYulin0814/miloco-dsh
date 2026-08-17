#!/bin/bash
# WSL 出网通道矩阵:哪些下载源可用
echo "== 各下载源连通性"
test_host() {
  local name="$1" url="$2"
  local code
  code=$(curl -4 -sS -L -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 "$url" 2>/dev/null)
  printf '%-28s -> %s\n' "$name" "${code:-FAIL}"
}
test_host "api.github.com"        "https://api.github.com/repos/XiaoMi/xiaomi-miloco/releases/latest"
test_host "objects.githubusercontent" "https://objects.githubusercontent.com/"
test_host "codeload.github.com"   "https://codeload.github.com/"
test_host "gh-proxy.com"          "https://gh-proxy.com/https://github.com/"
test_host "gh.idayer.com"         "https://gh.idayer.com/https://github.com/"
test_host "astral.sh"             "https://astral.sh/uv/install.sh"
test_host "github-release-ua"     "https://github.com/XiaoMi/xiaomi-miloco/releases/latest/download/install.sh"

echo "== github.com 各 IP 尝试"
for ip in 20.205.243.166 20.205.243.165 140.82.112.4; do
  code=$(curl -4 -sS -o /dev/null -w '%{http_code}' --connect-timeout 8 --max-time 15 --resolve "github.com:443:$ip" "https://github.com/" 2>/dev/null)
  printf 'github.com via %-15s -> %s\n' "$ip" "${code:-FAIL}"
done

echo "== api.github.com 拿最新 release 资产清单"
curl -4 -sS --max-time 30 -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/XiaoMi/xiaomi-miloco/releases/latest" \
  | python3 -c "
import json,sys
j=json.load(sys.stdin)
print('tag:', j.get('tag_name'))
for a in j.get('assets',[]):
    print(' asset:', a['name'], a['size'], a['browser_download_url'])
" 2>&1 | head -30
