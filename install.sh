#!/usr/bin/env bash
# bark-notify 安装脚本。
# 用法: ./install.sh [claude|codex|both]   默认 claude

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-claude}"

# ---------- 1. 加载 .env ----------
if [ ! -f "$REPO_DIR/.env" ]; then
  cat >&2 <<EOF
错误: 找不到 $REPO_DIR/.env

请先执行:
  cp $REPO_DIR/.env.example $REPO_DIR/.env
然后编辑 .env 填入你的 BARK_DEVICE_KEY。
EOF
  exit 1
fi

# 用 python 解析 .env,避免 bash source 在含空格/特殊字符值上炸锅
eval "$(python3 - "$REPO_DIR/.env" <<'PYEOF'
import re, shlex, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    for raw in f:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$', line)
        if not m:
            continue
        key, val = m.group(1), m.group(2).rstrip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
            val = val[1:-1]
        print(f"export {key}={shlex.quote(val)}")
PYEOF
)"

if [ -z "${BARK_DEVICE_KEY:-}" ] || [ "$BARK_DEVICE_KEY" = "REPLACE_WITH_YOUR_DEVICE_KEY" ]; then
  echo "错误: BARK_DEVICE_KEY 未设置或仍是占位符,编辑 $REPO_DIR/.env 后重试。" >&2
  exit 1
fi

: "${BARK_SERVER:=https://api.day.app}"
: "${BARK_TITLE:=Claude Code}"
: "${BARK_ICON:=}"

CLAUDE_DIR="$HOME/.claude"
CONF="$CLAUDE_DIR/notify-bark.conf"
SCRIPT="$CLAUDE_DIR/notify-bark.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

# ---------- 2. 安装 Claude Code 钩子 ----------
install_claude() {
  mkdir -p "$CLAUDE_DIR"

  # 写 conf,权限 600
  umask 077
  cat > "$CONF" <<EOF
# 由 bark-notify install.sh 自动生成。请勿提交到 git。
BARK_DEVICE_KEY="$BARK_DEVICE_KEY"
BARK_SERVER="$BARK_SERVER"
BARK_TITLE="$BARK_TITLE"
BARK_ICON="$BARK_ICON"
EOF
  chmod 600 "$CONF"
  echo "✓ 写入 $CONF (mode 600)"

  # 拷贝脚本
  install -m 0755 "$REPO_DIR/notify-bark.sh" "$SCRIPT"
  echo "✓ 安装 $SCRIPT"

  # 合并到 settings.json(保留其他键)
  python3 - "$SETTINGS" "$SCRIPT" <<'PYEOF'
import json, os, sys
settings_path, script_path = sys.argv[1], sys.argv[2]
hooks_block = {
    "Stop": [{"hooks": [{
        "type": "command",
        "command": f"bash {script_path} --sound bell --body 任务完成"
    }]}],
    "Notification": [{"hooks": [{
        "type": "command",
        "command": f"bash {script_path} --sound alarm"
    }]}],
}
if os.path.exists(settings_path):
    with open(settings_path, "r", encoding="utf-8") as f:
        current = json.load(f)
else:
    current = {}
current.setdefault("hooks", {})
for k, v in hooks_block.items():
    current["hooks"][k] = v
with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(current, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"✓ 合并钩子到 {settings_path}")
PYEOF

  echo
  echo "发送测试推送..."
  echo '{"message":"bark-notify 安装成功"}' | bash "$SCRIPT"
  echo "✓ 测试推送已发出,请查看 iPhone。"
}

# ---------- 3. Codex CLI 集成提示 ----------
install_codex() {
  cat <<EOF

------------------------------------------------------------
Codex CLI 没有原生 hook 机制,用 shell 函数包装即可:

把下面这段加到 ~/.zshrc(或 ~/.bashrc):

  codex() {
    command codex "\$@"
    local code=\$?
    bash "$SCRIPT" --sound bell --body "codex 完成 (exit \$code)"
    return \$code
  }

然后执行 'source ~/.zshrc' 让配置生效。
------------------------------------------------------------
EOF
}

case "$TARGET" in
  claude) install_claude ;;
  codex)  install_claude; install_codex ;;
  both)   install_claude; install_codex ;;
  *) echo "用法: $0 [claude|codex|both]" >&2; exit 1 ;;
esac

echo
echo "完成。"
