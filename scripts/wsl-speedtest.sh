#!/bin/bash
# 测各通道前 2MB 的下载速度,挑最快的通道
URL_GH="https://github.com/XiaoMi/xiaomi-miloco/releases/download/v2026.8.6/miloco-linux-x86_64-2026.8.6.tar.gz"
for name_url in \
  "gh-proxy.com|https://gh-proxy.com/${URL_GH}" \
  "gh-proxy.org|https://gh-proxy.org/${URL_GH}" \
  "gh.idayer.com|https://gh.idayer.com/${URL_GH}"; do
  name="${name_url%%|*}"
  url="${name_url#*|}"
  out=$(curl -4 -sS -r 0-2097151 -o /dev/null -w '%{http_code} %{speed_download} B/s %{size_download} bytes' \
        --connect-timeout 10 --max-time 60 "$url" 2>&1)
  printf '%-18s -> %s\n' "$name" "$out"
done
