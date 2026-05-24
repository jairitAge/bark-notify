#!/usr/bin/env bash
# bark-notify 安装脚本。
# 用法: ./install.sh [claude|codex|both]   默认 claude
#
# - claude: 装共享文件 + 合并 Stop/Notification 钩子到 ~/.claude/settings.json
# - codex:  装共享文件 + 合并 Stop/PermissionRequest hook 到 ~/.codex/config.toml
#           (用 marker 块,不动你其他配置;首次装完要去 codex 里跑 /hooks 信任)
# - both:   = claude + codex

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
: "${CODEX_TITLE:=Codex}"
: "${CODEX_ICON:=https://raw.githubusercontent.com/jairitAge/bark-icons/main/codex.png}"

CLAUDE_DIR="$HOME/.claude"
CONF="$CLAUDE_DIR/notify-bark.conf"
SCRIPT="$CLAUDE_DIR/notify-bark.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
CODEX_DIR="$HOME/.codex"
CODEX_CONFIG="$CODEX_DIR/config.toml"

# ---------- 2. 共享文件:conf + script(+ 自动备份现有不同版本) ----------
install_shared() {
  mkdir -p "$CLAUDE_DIR"

  # 备份现有 notify-bark.sh(只要内容跟仓库版本不同就备份一份,免得用户原脚本丢失)
  if [ -f "$SCRIPT" ] && ! cmp -s "$REPO_DIR/notify-bark.sh" "$SCRIPT"; then
    bak="$SCRIPT.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$SCRIPT" "$bak"
    echo "↩ 备份现有脚本到 $bak"
  fi

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
}

# ---------- 3. Claude Code 钩子合并 ----------
install_claude_hooks() {
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
  echo "发送 Claude 测试推送..."
  echo '{"message":"bark-notify Claude 安装成功"}' | bash "$SCRIPT"
  echo "✓ Claude 测试推送已发出,请查看 iPhone。"
}

# ---------- 4. Codex CLI 钩子合并(走真原生 hook,跟 Claude 对称) ----------
install_codex_hooks() {
  mkdir -p "$CODEX_DIR"
  python3 - "$CODEX_CONFIG" "$SCRIPT" "$CODEX_TITLE" "$CODEX_ICON" <<'PYEOF'
import os, re, sys

config_path, script_path, title, icon = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def toml_lit(s):
    """把任意字符串变成合法的 TOML 字符串字面量。优先用 literal('...'),
    如果含单引号就降级到 basic("...") 并 escape。"""
    if "'" not in s:
        return "'" + s + "'"
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

stop_cmd = f'bash {script_path} --sound bell --title "{title}" --icon "{icon}" --body "codex 完成"'
notif_cmd = f'bash {script_path} --sound alarm --title "{title}" --icon "{icon}" --body "codex 需要授权"'

block = (
    "# >>> bark-notify codex hooks >>>\n"
    "# 由 bark-notify install.sh 自动生成。marker 之间的内容会被下次安装覆盖。\n"
    "# 首次安装后,在 codex 里跑 /hooks 命令信任这两条 hook 才会生效;\n"
    "# 也可以在 codex 调用时加 --dangerously-bypass-hook-trust 绕过信任。\n"
    "[[hooks.Stop]]\n"
    "[[hooks.Stop.hooks]]\n"
    'type = "command"\n'
    f"command = {toml_lit(stop_cmd)}\n"
    "timeout = 30\n"
    "\n"
    "[[hooks.PermissionRequest]]\n"
    "[[hooks.PermissionRequest.hooks]]\n"
    'type = "command"\n'
    f"command = {toml_lit(notif_cmd)}\n"
    "timeout = 30\n"
    "# <<< bark-notify codex hooks <<<\n"
)

existing = ""
if os.path.exists(config_path):
    with open(config_path, "r", encoding="utf-8") as f:
        existing = f.read()

pattern = re.compile(
    r"\n*# >>> bark-notify codex hooks >>>.*?# <<< bark-notify codex hooks <<<\n*",
    re.DOTALL,
)
if pattern.search(existing):
    new_content = pattern.sub("\n\n" + block, existing).lstrip("\n")
    action = "更新"
else:
    new_content = (existing.rstrip() + "\n\n" + block) if existing else block
    action = "追加"

with open(config_path, "w", encoding="utf-8") as f:
    f.write(new_content)
print(f"✓ {action} hook 块到 {config_path}(marker 之间)")
PYEOF

  # 验证生成的 TOML 合法,且 hook 块结构正确
  python3 - "$CODEX_CONFIG" <<'PYEOF' 2>/dev/null
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(99)  # 99 = 无解析器,后面 bash 当 "skip" 处理
data = tomllib.load(open(sys.argv[1], 'rb'))
assert data['hooks']['Stop'][0]['hooks'][0]['type'] == 'command'
assert data['hooks']['PermissionRequest'][0]['hooks'][0]['type'] == 'command'
PYEOF
  case $? in
    0)  echo "✓ TOML 解析成功,hook 配置结构正确" ;;
    99) echo "ℹ python 无 tomllib(3.11+)/tomli,跳过严格 TOML 解析。建议安装后跑 'codex doctor' 自检。" ;;
    *)  echo "⚠ TOML 解析或 hook 结构断言失败,请人工检查 $CODEX_CONFIG" ;;
  esac

  echo
  echo "发送 Codex 测试推送(走 bark-notify 脚本验证链路)..."
  bash "$SCRIPT" \
    --sound bell \
    --title "$CODEX_TITLE" \
    --icon "$CODEX_ICON" \
    --body "bark-notify Codex hook 安装成功"
  echo "✓ Codex 测试推送已发出。"

  cat <<EOF

------------------------------------------------------------
Codex hook 已写入 ${CODEX_CONFIG}。下一步必须做一次信任,否则 hook 会被跳过:

  1. 启动一次 codex:
       codex
  2. 在 codex 里输入斜杠命令:
       /hooks
     会列出新加的 Stop 和 PermissionRequest hook,选 Trust 即可。

之后每次 codex 完成一个 turn(回复结束)会响 bell,
等你授权时会响 alarm,跟 Claude Code 那边对称。

要清除这两条 hook:删除 ${CODEX_CONFIG} 里 'bark-notify codex hooks' 标记之间的整段。
------------------------------------------------------------
EOF
}

case "$TARGET" in
  claude)
    install_shared
    install_claude_hooks
    ;;
  codex)
    install_shared
    install_codex_hooks
    ;;
  both)
    install_shared
    install_claude_hooks
    install_codex_hooks
    ;;
  *)
    echo "用法: $0 [claude|codex|both]" >&2
    exit 1
    ;;
esac

echo
echo "完成。"
