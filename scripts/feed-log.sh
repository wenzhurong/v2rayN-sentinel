#!/usr/bin/env bash
# 用法: ./scripts/feed-log.sh <目标目录> [important|ordinary]
# 向 <目标目录>/<今天>.txt 追加一条测试日志行,用于手动验证(配合 logDirOverride)。
set -euo pipefail
DIR="${1:?需要目标目录}"
KIND="${2:-important}"
mkdir -p "$DIR"
TODAY="$(date +%Y-%m-%d)"
TS="$(date '+%Y-%m-%d %H:%M:%S.0000')"
if [ "$KIND" = "ordinary" ]; then
  LINE="$TS-ERROR process (mihomo#$RANDOM) returned a non-zero exit code (1)."
else
  LINE="$TS-ERROR test core crashed unexpectedly [$RANDOM]"
fi
echo "$LINE" >> "$DIR/$TODAY.txt"
echo "已写入: $LINE"
