#!/bin/bash
# PyPI 镜像连通性测试
for u in \
  "https://pypi.tuna.tsinghua.edu.cn/simple/" \
  "https://mirrors.aliyun.com/pypi/simple/" \
  "https://mirrors.ustc.edu.cn/pypi/simple/"; do
  code=$(curl -4 -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 20 "$u" 2>/dev/null)
  printf '%-48s -> %s\n' "$u" "${code:-FAIL}"
done
