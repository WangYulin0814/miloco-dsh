#!/bin/bash
# WSL 内安装 Miloco 后端(DSH 适配专用:standalone 家目录 ~/.miloco,不装 agent 插件)
# 持久化策略:install.sh 与 bundle 都放在 /mnt/c 工作区(WSL /tmp 会随 VM 关闭丢失)。
set -u

NAME="miloco-linux-x86_64-2026.8.6.tar.gz"
TAG="v2026.8.6"
SHA="18a068829e08341dc096ca6b13f9df2ecf8e156c2cb5a88c403628fc091ce504"
WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
INSTALL_SH="$WS/upstream/install.sh.release"
BUNDLE_WS="$WS/upstream/$NAME"

export MILOCO_HOME="$HOME/.miloco"
export MILOCO_LANG=zh
export MILOCO_DOWNLOAD_URL="http://127.0.0.1:8000"

echo "== 0. 确认 install.sh"
[ -f "$INSTALL_SH" ] || { echo "install.sh 不在工作区"; exit 1; }
cp "$INSTALL_SH" /tmp/miloco-install.sh
ls -la /tmp/miloco-install.sh

echo "== 1. 确认 bundle(必要时从工作区恢复)"
if [ ! -f "/tmp/$NAME" ]; then
  echo "/tmp 无 bundle,检查工作区备份"
  if [ -f "$BUNDLE_WS" ]; then
    cp "$BUNDLE_WS" "/tmp/$NAME"
    echo "已从工作区恢复"
  else
    echo "BUNDLE MISSING: 先跑 wsl-download-bundle.sh"
    exit 1
  fi
fi
echo "$SHA  /tmp/$NAME" | sha256sum -c - || exit 1
if [ ! -f "$BUNDLE_WS" ]; then
  cp "/tmp/$NAME" "$BUNDLE_WS"
  echo "bundle 已备份到工作区(68MB)"
fi

echo "== 2. 本地 HTTP 供包服务"
mkdir -p "/tmp/bundle-serve/$TAG"
ln -sf "/tmp/$NAME" "/tmp/bundle-serve/$TAG/$NAME"
nohup python3 -m http.server 8000 --bind 127.0.0.1 --directory /tmp/bundle-serve >/tmp/bundle-http.log 2>&1 &
echo $! > /tmp/bundle-http.pid
sleep 1
curl -sS -o /dev/null -w "local bundle http: %{http_code}\n" "http://127.0.0.1:8000/$TAG/$NAME"

echo "== 3. PyPI 镜像选择"
if curl -4 -sS -o /dev/null --connect-timeout 5 --max-time 8 https://pypi.org/simple/; then
  echo "pypi 直连 OK"
else
  export UV_DEFAULT_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"
  echo "pypi 直连失败 → 清华镜像: $UV_DEFAULT_INDEX"
fi

set -e
echo "== 4. PHASE 1: --agent-prepare"
bash /tmp/miloco-install.sh --agent-prepare --agent-platform=openclaw --skip-openclaw

echo "== 5. PHASE 2: --agent-finish"
bash /tmp/miloco-install.sh --agent-finish --agent-platform=openclaw --skip-openclaw
set +e

echo "== 6. 启动服务"
export PATH="$HOME/.local/bin:$PATH"
hash -r
miloco-cli service start
sleep 10
miloco-cli service status
echo "---- 健康检查 ----"
curl -sS --max-time 10 http://127.0.0.1:1810/health; echo

echo "== 7. 读取 token 与配置"
python3 - <<'PYEOF'
import json, os
p = os.path.expanduser("~/.miloco/config.json")
try:
    cfg = json.load(open(p))
    t = (cfg.get("server") or {}).get("token", "")
    print("CONFIG_OK path=" + p)
    print("TOKEN_FULL=" + t)
    print("TOKEN_MASKED=" + (t[:6] + "..." + t[-4:] if t else "EMPTY"))
    print("AGENT_PLATFORM=" + str(cfg.get("agent", {}).get("platform")))
except Exception as e:
    print("CONFIG_READ_FAIL", e)
PYEOF

echo "== 8. 关键路径"
ls -la "$MILOCO_HOME" 2>/dev/null | head -20
echo INSTALL_DONE
