#!/bin/bash
# 只跑 agent-finish 阶段:强制非交互(setsid 脱离控制终端 + stdin=/dev/null),
# 账号/模型/插件全部跳过。之后启动服务并输出 token。
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

echo "== 0. 准备 install.sh 与 bundle"
[ -f "$INSTALL_SH" ] || { echo "install.sh 不在工作区"; exit 1; }
cp "$INSTALL_SH" /tmp/miloco-install.sh
if [ ! -f "/tmp/$NAME" ]; then
  [ -f "$BUNDLE_WS" ] || { echo "BUNDLE MISSING"; exit 1; }
  cp "$BUNDLE_WS" "/tmp/$NAME"
fi
echo "$SHA  /tmp/$NAME" | sha256sum -c - || exit 1

echo "== 1. 本地 HTTP 供包"
mkdir -p "/tmp/bundle-serve/$TAG"
ln -sf "/tmp/$NAME" "/tmp/bundle-serve/$TAG/$NAME"
nohup python3 -m http.server 8000 --bind 127.0.0.1 --directory /tmp/bundle-serve >/tmp/bundle-http.log 2>&1 &
sleep 1
curl -sS -o /dev/null -w "local http: %{http_code}\n" "http://127.0.0.1:8000/$TAG/$NAME"

echo "== 2. PyPI 镜像"
export UV_DEFAULT_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"

echo "== 3. agent-finish(强制非交互)"
set -e
setsid bash /tmp/miloco-install.sh --agent-finish --agent-platform=openclaw --skip-openclaw </dev/null
set +e

echo "== 4. 启动服务"
export PATH="$HOME/.local/bin:$PATH"
hash -r
miloco-cli service start
sleep 10
miloco-cli service status
echo "---- 健康检查 ----"
curl -sS --max-time 10 http://127.0.0.1:1810/health; echo

echo "== 5. 读取 token"
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
echo INSTALL_DONE
