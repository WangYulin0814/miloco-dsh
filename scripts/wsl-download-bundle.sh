#!/bin/bash
# 经 gh-proxy.org 镜像下载 linux-x86_64 bundle(断点续传 + sha256 校验)
set -u
cd /tmp

NAME="miloco-linux-x86_64-2026.8.6.tar.gz"
SHA="18a068829e08341dc096ca6b13f9df2ecf8e156c2cb5a88c403628fc091ce504"
SIZE=68710797
URL="https://gh-proxy.org/https://github.com/XiaoMi/xiaomi-miloco/releases/download/v2026.8.6/$NAME"

if [ -f "/tmp/$NAME" ]; then
  SZ=$(stat -c %s "/tmp/$NAME" 2>/dev/null || echo 0)
  echo "续传起点: $SZ / $SIZE"
fi

ok=0
for i in $(seq 1 30); do
  echo "== attempt $i ($(date +%H:%M:%S))"
  curl -4 -L -C - -sS --connect-timeout 15 --max-time 600 \
    -o "/tmp/$NAME" "$URL"
  rc=$?
  SZ=$(stat -c %s "/tmp/$NAME" 2>/dev/null || echo 0)
  echo "rc=$rc size=$SZ / $SIZE"
  if [ "$SZ" = "$SIZE" ]; then
    echo "$SHA  /tmp/$NAME" | sha256sum -c - && { ok=1; echo "BUNDLE_OK"; break; }
    echo "sha 不符,重下"; rm -f "/tmp/$NAME"
  fi
  sleep 5
done
[ "$ok" = "1" ] || echo "BUNDLE_FAILED"
