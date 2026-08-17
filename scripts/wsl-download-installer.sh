#!/bin/bash
# 通过 api.github.com 资产接口下载 install.sh(绕过不可达的 github.com 主站)
set -u
cd /tmp
echo "== 取资产 ID"
curl -4 -sS --max-time 30 -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/XiaoMi/xiaomi-miloco/releases/latest" \
  | python3 -c "
import json,sys
j=json.load(sys.stdin)
for a in j.get('assets',[]):
    print(a['name'], a['id'], a['size'])
" > /tmp/assets.txt
cat /tmp/assets.txt

AID=$(grep '^install.sh ' /tmp/assets.txt | awk '{print $2}')
echo "install.sh asset id = $AID"
[ -z "$AID" ] && { echo "NO ASSET ID"; exit 1; }

echo "== 下载 install.sh"
for i in 1 2 3; do
  if curl -4 -sSL --connect-timeout 15 --max-time 180 \
      -H "Accept: application/octet-stream" \
      -o /tmp/miloco-install.sh \
      "https://api.github.com/repos/XiaoMi/xiaomi-miloco/releases/assets/$AID"; then
    [ -s /tmp/miloco-install.sh ] && break
  fi
  echo "retry $i rc=$?"
  sleep 3
done
ls -la /tmp/miloco-install.sh
echo "== 提取内嵌 install.py"
python3 - <<'PYEOF'
import re, base64
src = open('/tmp/miloco-install.sh', 'rb').read().decode('utf-8', 'replace')
m = re.search(r"base64 -d << 'B64_PY' > .*?\n(.*?)\nB64_PY", src, re.S)
if m:
    py = base64.b64decode(''.join(m.group(1).split()))
    open('/tmp/miloco-install.py', 'wb').write(py)
    print('extracted install.py bytes:', len(py))
else:
    print('marker not found; head:')
    print(src[:600])
PYEOF
cp /tmp/miloco-install.sh '/mnt/c/Project Library/DeepSeek Harness WorkSpace/miloco-dsh/upstream/install.sh.release'
cp /tmp/miloco-install.py '/mnt/c/Project Library/DeepSeek Harness WorkSpace/miloco-dsh/upstream/install.py.release'
echo DONE
