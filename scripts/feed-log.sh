#!/usr/bin/env bash
# 用法: ./scripts/feed-log.sh <目标目录> [important|ordinary|core] [目标host:port]
# 向 <目标目录> 追加一条测试日志行,用于手动验证(配合 logDirOverride)。
#   important/ordinary -> GUI 日志 <今天>.txt(Serilog 格式)
#   core               -> sing-box 日志 sbox_<今天>.txt(内核连接错误格式)
set -euo pipefail
DIR="${1:?需要目标目录}"
KIND="${2:-important}"
mkdir -p "$DIR"
TODAY="$(date +%Y-%m-%d)"
TS="$(date '+%Y-%m-%d %H:%M:%S.0000')"
if [ "$KIND" = "core" ]; then
  TARGET="${3:-172.18.0.1:7881}"
  LINE="+0530 $(date '+%Y-%m-%d %H:%M:%S') ERROR [$RANDOM 5.0s] connection: dial tcp ${TARGET}: i/o timeout"
  echo "$LINE" >> "$DIR/sbox_${TODAY}.txt"
  echo "wrote(core): $LINE"
  exit 0
fi
if [ "$KIND" = "ordinary" ]; then
  LINE="$TS-ERROR process (mihomo#$RANDOM) returned a non-zero exit code (1)."
else
  LINE="$TS-ERROR test core crashed unexpectedly [$RANDOM]"
fi
echo "$LINE" >> "$DIR/$TODAY.txt"
echo "已写入: $LINE"
