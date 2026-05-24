#!/usr/bin/env bash
# Bark 推送助手。安装后位于 ~/.claude/notify-bark.sh。
#
# 配置来源(优先级从高到低):
#   1. 命令行 --sound / --body / --title 参数
#   2. 环境变量 BARK_* (含从 BARK_CONF 指定的文件 source 进来的)
#   3. 默认 conf 文件 $HOME/.claude/notify-bark.conf
#
# 用法:
#   echo '{"message":"待办"}' | bash notify-bark.sh          # 读 stdin JSON 的 message 字段
#   bash notify-bark.sh --sound bell --body "任务完成"      # 直接给定 body

set +e

CONF="${BARK_CONF:-$HOME/.claude/notify-bark.conf}"
[ -r "$CONF" ] && . "$CONF"

: "${BARK_SERVER:=https://api.day.app}"
: "${BARK_TITLE:=Claude Code}"
: "${BARK_ICON:=}"
: "${BARK_DEVICE_KEY:=}"

SOUND="alarm"
BODY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --sound) SOUND="$2"; shift 2;;
    --body)  BODY="$2";  shift 2;;
    --title) BARK_TITLE="$2"; shift 2;;
    *)       shift;;
  esac
done

if [ -z "$BODY" ]; then
  BODY=$(python3 -c "import json,sys
d=json.load(sys.stdin) if not sys.stdin.isatty() else {}
print(d.get('message','Claude Code'))" 2>/dev/null)
  [ -z "$BODY" ] && BODY="Claude Code"
fi

# Device Key 未配置就静默退出,不打扰宿主进程
[ -z "$BARK_DEVICE_KEY" ] && exit 0

enc() { python3 -c "import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=''))" "$1"; }
ENC_TITLE=$(enc "$BARK_TITLE")
ENC_BODY=$(enc "$BODY")

URL="${BARK_SERVER%/}/${BARK_DEVICE_KEY}/${ENC_TITLE}/${ENC_BODY}?sound=${SOUND}"
[ -n "$BARK_ICON" ] && URL="${URL}&icon=${BARK_ICON}"

curl -s "$URL" >/dev/null 2>&1 || true
