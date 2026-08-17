#!/bin/bash
# 用正确的 MILOCO_HOME 重启 Miloco 服务(修复上次重启脚本漏导出环境变量)
export MILOCO_HOME="$HOME/.miloco"
export PATH="$HOME/.local/bin:$PATH"
hash -r

echo "== 清掉可能存在的错误-home 残留进程"
pkill -f "supervisord.*miloco" 2>/dev/null && sleep 2 || true
pgrep -af supervisord || echo "(无 supervisord 进程)"

echo "== 用正确 home 启动服务"
miloco-cli service start
sleep 12

echo "== 状态"
miloco-cli service status

echo "== 健康检查"
curl -sS --max-time 10 http://127.0.0.1:1810/health; echo

echo "== 后端日志尾部(如失败,便于诊断)"
tail -n 25 "$MILOCO_HOME/log/miloco-backend.log" 2>/dev/null || echo "(无日志文件)"
