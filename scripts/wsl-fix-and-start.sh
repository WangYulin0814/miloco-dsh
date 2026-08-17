#!/bin/bash
# 修复 server.python_bin 并启动 Miloco 服务
export PATH="$HOME/.local/bin:$PATH"
hash -r

echo "== 找 miloco 的 Python"
ls -la "$HOME/.local/share/uv/tools/miloco/bin/" 2>/dev/null | head -20
PYBIN="$HOME/.local/share/uv/tools/miloco/bin/python"
[ -x "$PYBIN" ] || { echo "PYBIN 不存在: $PYBIN"; exit 1; }
echo "PYBIN=$PYBIN"

echo "== 当前 config.json 摘要"
python3 - <<'PYEOF'
import json, os
p = os.path.expanduser("~/.miloco/config.json")
cfg = json.load(open(p))
srv = cfg.get("server", {})
print("server keys:", sorted(srv.keys()))
print("python_bin =", repr(srv.get("python_bin")))
print("token 存在:", bool(srv.get("token")))
PYEOF

echo "== 写入 server.python_bin"
miloco-cli config set server.python_bin "$PYBIN"

echo "== 启动服务"
miloco-cli service start
sleep 10
miloco-cli service status

echo "== 健康检查"
curl -sS --max-time 10 http://127.0.0.1:1810/health; echo
