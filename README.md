# bark-notify

一个最小化的仓库,用一条命令把 [Bark](https://bark.day.app/) 推送接到 Claude Code(以及可选的 Codex CLI)。Device Key 留在本地 `.env`,**不进 git**。

## 推送场景

- **Stop 钩子**:Claude Code 回复结束 → 推「任务完成」+ `bell` 声。
- **Notification 钩子**:Claude Code 需要权限确认/等待输入 → 推 hook stdin 里的 message + `alarm` 声。
- **Codex**:用 shell 函数包装 `codex` 命令,退出后推送(无原生 hook)。

## 前置条件

- macOS 或 Linux,自带 `bash` / `curl` / `python3`
- iPhone 装 Bark App,拿到 Device Key

## 一键安装

```bash
# 1. 把示例 env 复制为本地 env,填入你的 Device Key
cp .env.example .env
$EDITOR .env

# 2. 安装到 Claude Code
./install.sh claude

# 或同时给 Claude Code + Codex
./install.sh both
```

脚本会:

1. 写 `~/.claude/notify-bark.conf`(mode 600,只有你能读)。
2. 安装 `~/.claude/notify-bark.sh`。
3. **合并** Stop / Notification 两个钩子到 `~/.claude/settings.json`(保留你已有的其他配置)。
4. 发一条测试推送验证。
5. 选 `codex` / `both` 时,额外打印 Codex 的 shell 函数包装片段,自行粘到 `~/.zshrc`。

## 修改/轮换 Device Key

直接编辑 `~/.claude/notify-bark.conf` 即可,无需重装。或者改 `.env` 后重跑 `./install.sh claude`。

## 卸载

```bash
rm ~/.claude/notify-bark.sh ~/.claude/notify-bark.conf
# 然后手动从 ~/.claude/settings.json 里删掉 hooks.Stop 和 hooks.Notification 两段
```

## 文件清单

| 文件 | 说明 | 进 git? |
|---|---|---|
| `install.sh` | 安装器 | ✅ |
| `notify-bark.sh` | 推送脚本(会被装到 `~/.claude/`) | ✅ |
| `.env.example` | env 模板,占位 key | ✅ |
| `.env` | 你的本地真实 key | ❌(`.gitignore`) |
| `~/.claude/notify-bark.conf` | 安装后生成,mode 600 | — |

## 安全说明

- Device Key 只出现在两处:仓库本地 `.env`、`~/.claude/notify-bark.conf`。两处都不会进 git。
- 仓库里的 `notify-bark.sh` 和 `install.sh` 都不硬编码 key,push 到任何公开远端都是安全的。
- 如果误把 `.env` 提交了:立刻在 Bark App 里**重新生成 Device Key**(旧 key 一旦泄露就视为公开),然后改 `.env` 重装。
