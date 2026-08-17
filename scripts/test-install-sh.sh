#!/usr/bin/env bash
# install.sh 自测(WSL 内运行;临时目录放 Windows 侧 %TEMP%,经 interop 调用 Windows node.exe。
# 真 Linux/macOS 上无需垫片,直接有 node;本脚本主要用于本仓库回归验证。)
set -u
WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
NODE_EXE="/mnt/c/Program Files/nodejs/node.exe"
pass=0; fail=0

assert() { # assert <0|1> <名称>
  if [ "$1" = "1" ]; then echo "  [PASS] $2"; pass=$((pass+1)); else echo "  [FAIL] $2"; fail=$((fail+1)); fi
}

if [ ! -f "$NODE_EXE" ]; then
  echo "Windows node.exe 不存在: $NODE_EXE —— 跳过(无法执行 merge 逻辑)"
  echo "===== SH TEST 结果: PASS=$pass FAIL=$fail ====="
  exit 2
fi

# node 垫片:/mnt/c 路径 → C:\ 路径,经 WSL interop 调 Windows node.exe
node() {
  local a out=()
  for a in "$@"; do
    case "$a" in
      /mnt/c/*) out+=("$(printf 'C:%s' "${a#/mnt/c}" | tr '/' '\\')") ;;
      *) out+=("$a") ;;
    esac
  done
  "$NODE_EXE" "${out[@]}"
}
export -f node
export NODE_EXE

T="$(wslpath "$(cmd.exe /c echo %TEMP% 2>/dev/null | tr -d '\r')" 2>/dev/null)/miloco-sh-test-$(date +%s)"
mkdir -p "$T/dsh-home/profiles/web" "$T/home/.miloco"

cat > "$T/dsh-home/profiles/web/cordis.patch.yml" <<'EOF'
- insert:
    - id: mcp-my-coffee
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: my-coffee
        transport: streamable-http
        url: https://example.com/mcp
EOF

cat > "$T/home/.miloco/config.json" <<'EOF'
{"server":{"token":"fake-test-token-abc123"},"agent":{"platform":"none"}}
EOF

OLD_HOME="$HOME"
export HOME="$T/home"

echo "== 场景 A: 旧条目迁移 + token 自动发现"
bash "$WS/install.sh" --repo-path "$WS" --dsh-home "$T/dsh-home" --skip-verify
patch="$T/dsh-home/profiles/web/cordis.patch.yml"
c1=$(grep -c 'mcp-my-coffee' "$patch")
c2=$(grep -c '>>> miloco-dsh begin' "$patch")
c3=$(grep -c 'id: mcp-miloco' "$patch")
assert "$([ "$c1" = 1 ] && echo 1 || echo 0)" "my-coffee 条目保留(1 条)"
assert "$([ "$c2" = 1 ] && echo 1 || echo 0)" "标记块已写入"
assert "$([ "$c3" = 1 ] && echo 1 || echo 0)" "mcp-miloco 恰好 1 条(旧条目已替换)"
assert "$([ -f "$T/dsh-home/skills/miloco/SKILL.md" ] && [ -f "$T/dsh-home/skills/miloco/manifest.json" ] && echo 1 || echo 0)" "技能已安装"
assert "$(grep -q 'export MILOCO_TOKEN="fake-test-token-abc123"' "$HOME/.bashrc" 2>/dev/null && echo 1 || echo 0)" "token 已写入 bashrc"

echo "== 场景 B: 重跑幂等(不产生新备份)"
baks_before="$(ls "$T/dsh-home/profiles/web/"*.bak-* 2>/dev/null | wc -l)"
out_b="$(bash "$WS/install.sh" --repo-path "$WS" --dsh-home "$T/dsh-home" --no-token --skip-verify 2>&1 | grep -o '"status":"[a-z]*"')"
baks_after="$(ls "$T/dsh-home/profiles/web/"*.bak-* 2>/dev/null | wc -l)"
echo "  status: $out_b"
assert "$(printf '%s' "$out_b" | grep -q 'unchanged' && echo 1 || echo 0)" "status=unchanged"
assert "$([ "$baks_before" = "$baks_after" ] && echo 1 || echo 0)" "备份数不变"

echo "== 场景 C: dry-run 不落盘"
mtime_before="$(stat -c %Y "$patch")"
bash "$WS/install.sh" --repo-path "$WS" --dsh-home "$T/dsh-home" --no-token --dry-run >/dev/null 2>&1
mtime_after="$(stat -c %Y "$patch")"
assert "$([ "$mtime_before" = "$mtime_after" ] && echo 1 || echo 0)" "dry-run 未改写文件"

echo "== 场景 D: 全新 DSH(无 cordis.patch.yml)"
mkdir -p "$T/dsh2/profiles"
bash "$WS/install.sh" --repo-path "$WS" --dsh-home "$T/dsh2" --no-token --skip-verify >/dev/null 2>&1
assert "$([ -f "$T/dsh2/profiles/web/cordis.patch.yml" ] && grep -q 'mcp-miloco' "$T/dsh2/profiles/web/cordis.patch.yml" && echo 1 || echo 0)" "新文件已创建且含条目"

export HOME="$OLD_HOME"
rm -rf "$T"
echo ""
echo "===== SH TEST 结果: PASS=$pass FAIL=$fail ====="
[ "$fail" = 0 ] || exit 1
exit 0
