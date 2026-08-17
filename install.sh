#!/usr/bin/env bash
# miloco-dsh 一键安装 (Linux / macOS)
#
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/WangYulin0814/miloco-dsh/main/install.sh | bash
# 或在本仓库内执行:
#   ./install.sh
#
# 行为(幂等,可重复执行):
#   - 将 mcp-miloco 条目合并进 $DSH_HOME/profiles/web/cordis.patch.yml(写入前自动备份)
#   - 安装 miloco 技能到 $DSH_HOME/skills/miloco
#   - 自动发现 MILOCO_TOKEN(本机 ~/.miloco/config.json),写入 shell rc 并导出
#   - 运行 MCP 冒烟验证(server/test-mcp.js,无需后端)
# 安装后重启 dsh web 生效。
set -u

# ---- 默认值(可用同名环境变量覆盖)----
OWNER="${MILOCO_DSH_OWNER:-WangYulin0814}"
REPO="${MILOCO_DSH_REPO:-miloco-dsh}"
BRANCH="${MILOCO_DSH_BRANCH:-main}"
BASE_URL="${MILOCO_BASE_URL:-http://127.0.0.1:1810}"

# ---- 参数 ----
REPO_PATH=""
INSTALL_DIR=""
DSH_HOME_ARG=""
TOKEN_ARG=""
NO_TOKEN=0
FORCE=0
SKIP_VERIFY=0
DRY_RUN=0

usage() {
  cat <<'EOF'
选项:
  --repo-path <dir>   使用已有仓库目录(不下载)
  --install-dir <dir> 下载安装目录(默认 $HOME/miloco-dsh)
  --owner <o>         仓库所有者(默认 WangYulin0814)
  --repo <r>          仓库名(默认 miloco-dsh)
  --branch <b>        分支(默认 main)
  --dsh-home <dir>    DSH 家目录(默认 $DSH_HOME 或 ~/.dsh)
  --base-url <url>    Miloco 后端地址(默认 http://127.0.0.1:1810)
  --token <t>         直接指定后端 token
  --no-token          跳过 token 检查/自动发现
  --force             强制重新下载覆盖
  --skip-verify       跳过 MCP 冒烟验证
  --dry-run           只打印将执行的动作
  -h|--help           显示本帮助
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-path)    REPO_PATH="$2"; shift 2 ;;
    --install-dir)  INSTALL_DIR="$2"; shift 2 ;;
    --owner)        OWNER="$2"; shift 2 ;;
    --repo)         REPO="$2"; shift 2 ;;
    --branch)       BRANCH="$2"; shift 2 ;;
    --dsh-home)     DSH_HOME_ARG="$2"; shift 2 ;;
    --base-url)     BASE_URL="$2"; shift 2 ;;
    --token)        TOKEN_ARG="$2"; shift 2 ;;
    --no-token)     NO_TOKEN=1; shift ;;
    --force)        FORCE=1; shift ;;
    --skip-verify)  SKIP_VERIFY=1; shift ;;
    --dry-run)      DRY_RUN=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "[ERROR] 未知参数: $1"; usage; exit 2 ;;
  esac
done

info() { echo "==> $*"; }
fail() { echo "[ERROR] $*" >&2; exit 1; }
# dry <描述>: DRY_RUN 时打印并返回 0,否则返回 1
dry() { if [ "$DRY_RUN" = 1 ]; then echo "[DRY-RUN] $*"; return 0; fi; return 1; }

# ---------- 仓库目录 ----------
fetch_repo() {
  local dir="$1"
  if [ -f "$dir/server/miloco-mcp.js" ] && [ "$FORCE" != 1 ]; then
    if [ -d "$dir/.git" ] && command -v git >/dev/null 2>&1; then
      info "更新已有仓库: git pull"
      ( cd "$dir" && git pull --ff-only >/dev/null 2>&1 ) || echo "  (git pull 失败,继续使用现有文件)"
    else
      echo "已存在 $dir (使用现有文件;--force 可重新下载)"
    fi
    return
  fi
  dry "下载 https://github.com/$OWNER/$REPO (branch=$BRANCH) 到 $dir" && return
  info "下载仓库 $OWNER/$REPO (branch=$BRANCH) -> $dir"
  local tmp url inner
  tmp="$(mktemp -d)" || fail "无法创建临时目录"
  url="https://codeload.github.com/$OWNER/$REPO/tar.gz/refs/heads/$BRANCH"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 20 --max-time 300 -o "$tmp/repo.tar.gz" "$url" \
      || fail "下载失败: $url (请检查网络;或用 --repo-path 指向已有仓库)"
  else
    rm -rf "$tmp"
    fail "需要 curl 才能下载仓库(或改用 --repo-path 指向已有仓库)"
  fi
  tar -xzf "$tmp/repo.tar.gz" -C "$tmp" || { rm -rf "$tmp"; fail "解压失败"; }
  inner="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [ -n "$inner" ] || { rm -rf "$tmp"; fail "压缩包内容异常"; }
  if [ "$FORCE" = 1 ] && [ -e "$dir" ]; then rm -rf "$dir"; fi
  mkdir -p "$(dirname "$dir")"
  mv "$inner" "$dir"
  rm -rf "$tmp"
  [ -f "$dir/server/miloco-mcp.js" ] || fail "下载内容不完整(缺少 server/miloco-mcp.js)"
}

resolve_repo_dir() {
  if [ -n "$REPO_PATH" ]; then
    [ -f "$REPO_PATH/server/miloco-mcp.js" ] || fail "RepoPath 无效: 未找到 server/miloco-mcp.js ($REPO_PATH)"
    echo "$REPO_PATH"
    return
  fi
  # 脚本自身就在仓库内(本地执行 ./install.sh 时)
  local self_dir=""
  if [ -n "${BASH_SOURCE[0]:-}" ]; then
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    if [ -f "$self_dir/server/miloco-mcp.js" ]; then echo "$self_dir"; return; fi
  fi
  local dir="${INSTALL_DIR:-$HOME/miloco-dsh}"
  fetch_repo "$dir"
  echo "$dir"
}

# ---------- DSH 家目录 ----------
resolve_dsh_home() {
  local h="${DSH_HOME_ARG:-${DSH_HOME:-$HOME/.dsh}}"
  [ -d "$h/profiles" ] || fail "DSH 家目录无效(未找到 profiles): $h (请用 --dsh-home 指定)"
  echo "$h"
}

# ---------- token ----------
set_token_env() {
  local t="$1"
  dry "写入 MILOCO_TOKEN 到 shell rc 并 export" && return
  export MILOCO_TOKEN="$t"
  local wrote=0 f stamp
  stamp="$(date +%Y%m%d%H%M%S)"
  for f in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    [ -f "$f" ] || continue
    if grep -q '^export MILOCO_TOKEN=' "$f" 2>/dev/null; then
      echo "$f 已包含 MILOCO_TOKEN,跳过"
    else
      cp "$f" "$f.bak-$stamp"
      printf '\n# miloco-dsh (由安装脚本自动添加)\nexport MILOCO_TOKEN="%s"\n' "$t" >> "$f"
      echo "已追加 MILOCO_TOKEN 到 $f(原文件备份为 $f.bak-$stamp)"
      wrote=1
    fi
  done
  if [ "$wrote" = 0 ] && [ ! -f "$HOME/.bashrc" ]; then
    printf 'export MILOCO_TOKEN="%s"\n' "$t" > "$HOME/.bashrc"
    echo "已创建 $HOME/.bashrc 并写入 MILOCO_TOKEN"
    wrote=1
  fi
  if [ "$wrote" = 1 ]; then
    echo "提示: 请执行 source ~/.bashrc(或开新终端)后再启动 dsh web,使其读到 token。"
  fi
}

# ============================================================
echo ""
echo "miloco-dsh 安装器 (Miloco x DeepSeek Harness)"

repo_dir="$(resolve_repo_dir)"
dsh_home="$(resolve_dsh_home)"
info "仓库目录: $repo_dir"
info "DSH 家目录: $dsh_home"

# ---------- 1. node ----------
info "检查 node"
command -v node >/dev/null 2>&1 || fail "未找到 node。DeepSeek Harness 本身依赖 Node.js,请先安装 Node.js 18+ 并加入 PATH。"

# ---------- 2. 合并 cordis.patch.yml ----------
patch_file="$dsh_home/profiles/web/cordis.patch.yml"
merge_js="$repo_dir/scripts/merge-patch.js"
[ -f "$merge_js" ] || fail "仓库缺少 scripts/merge-patch.js"
info "合并 mcp-miloco 条目 -> $patch_file (写入前自动备份)"
if [ "$DRY_RUN" = 1 ]; then
  echo "[DRY-RUN] node $merge_js $patch_file $repo_dir $BASE_URL 30000"
else
  node "$merge_js" "$patch_file" "$repo_dir" "$BASE_URL" 30000 || fail "合并 patch 失败"
fi

# ---------- 3. 技能 ----------
src_skill="$repo_dir/skills/miloco"
[ -d "$src_skill" ] || fail "仓库缺少 skills/miloco"
info "安装技能 miloco -> $dsh_home/skills/miloco"
if [ "$DRY_RUN" = 1 ]; then
  echo "[DRY-RUN] cp -R $src_skill -> $dsh_home/skills/"
else
  mkdir -p "$dsh_home/skills"
  cp -R "$src_skill" "$dsh_home/skills/"
  echo "技能文件: $(ls "$dsh_home/skills/miloco" | tr '\n' ' ')"
fi

# ---------- 4. MILOCO_TOKEN ----------
if [ "$NO_TOKEN" != 1 ]; then
  info "MILOCO_TOKEN"
  if [ -n "$TOKEN_ARG" ]; then
    set_token_env "$TOKEN_ARG"
  elif [ -n "${MILOCO_TOKEN:-}" ]; then
    echo "MILOCO_TOKEN 已配置,跳过"
  else
    cfg="$HOME/.miloco/config.json"
    t=""
    if [ -f "$cfg" ]; then
      t="$(node -e "try{const c=require(process.argv[1]);process.stdout.write((c.server&&c.server.token)||'')}catch(e){process.stdout.write('')}" "$cfg" 2>/dev/null)"
    fi
    if [ -n "$t" ]; then
      set_token_env "$t"
    else
      echo "未自动发现 token。请手动设置: export MILOCO_TOKEN='<后端 config.json 的 server.token>'"
      echo "(不设置也可: miloco-mcp 会自动探测 ~/.miloco / ~/.openclaw/miloco / ~/.hermes/miloco)"
    fi
  fi
fi

# ---------- 5. 验证 ----------
if [ "$SKIP_VERIFY" != 1 ] && [ "$DRY_RUN" != 1 ]; then
  info "MCP 冒烟验证(server/test-mcp.js,无需后端)"
  if ( cd "$repo_dir/server" && node test-mcp.js ); then
    echo "冒烟验证通过: 18 个 mcp__miloco__* 工具已注册。"
  else
    echo "[WARN] 冒烟验证失败,详见上方输出。"
  fi

  info "后端连通性检查 ($BASE_URL/health,非致命)"
  if curl -fsS --max-time 5 "$BASE_URL/health" >/dev/null 2>&1; then
    echo "后端可达"
  else
    echo "[WARN] 后端不可达(未启动/未安装)。控制设备前请先启动 Miloco 后端。"
  fi
fi

# ---------- 6. 下一步 ----------
echo ""
echo "========== 安装完成 =========="
echo "1. 重启 dsh web(退出并重新打开 DeepSeek Harness)"
echo "2. 重启后模型即获得 mcp__miloco__* 工具(共 18 个)"
echo "3. 卸载: 删除 cordis.patch.yml 中 '# >>> miloco-dsh begin' 与 '# <<< miloco-dsh end' 之间的块,"
echo "   删除 $dsh_home/skills/miloco,重启 dsh web 即可。"
echo ""
