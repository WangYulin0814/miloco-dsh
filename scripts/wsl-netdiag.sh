#!/bin/bash
# WSL 网络诊断
echo "== resolv.conf"
cat /etc/resolv.conf
echo "== DNS 解析"
for h in github.com api.github.com raw.githubusercontent.com codeload.github.com objects.githubusercontent.com; do
  printf '%s -> ' "$h"
  getent ahostsv4 "$h" | head -1 || echo "FAIL"
done
echo "== 直连测试(各 12s 超时)"
for h in github.com api.github.com; do
  printf '%s: ' "$h"
  curl -4 -sS -o /dev/null -w 'code=%{http_code} ip=%{remote_ip} time=%{time_total}s' --connect-timeout 12 --max-time 25 "https://$h/" || echo "CURL FAIL"
  echo
done
echo "== 路由/默认网关"
ip route | head -3
echo "== 可写性测试"
touch /tmp/netdiag-ok && echo "tmp writable"
