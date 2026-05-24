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

# 2. 三选一:
./install.sh claude   # 只配 Claude Code(默认)
./install.sh codex    # 只配 Codex CLI,不动 Claude 现有 settings.json
./install.sh both     # 同时配两边
```

三种模式干的事:

| 步骤 | claude | codex | both |
|---|:-:|:-:|:-:|
| 写 `~/.claude/notify-bark.conf`(mode 600) | ✓ | ✓ | ✓ |
| 装 `~/.claude/notify-bark.sh`(已存在则先 `.bak.<时间戳>` 备份) | ✓ | ✓ | ✓ |
| 合并 Stop/Notification 到 `~/.claude/settings.json`(保留其他键) | ✓ | — | ✓ |
| 发一条 Claude 测试推送 | ✓ | — | ✓ |
| 打印 Codex shell 包装函数 + 发一条 Codex 测试推送 | — | ✓ | ✓ |

`codex` 模式适合你已经手工配好了 Claude Code 推送、不想被覆盖的情况 —— 这条路径完全不碰 `settings.json`,只装共享的 conf + script,然后让你把打印出来的 shell 函数贴到 `~/.zshrc`。

## 自定义配置

四个可调项,分两类存放:

| 配置项 | 存在哪 | 生效时机 |
|---|---|---|
| Device Key | `~/.claude/notify-bark.conf` 的 `BARK_DEVICE_KEY` | **立刻** —— 下一次推送即用新值 |
| Claude 通知**标题** | `~/.claude/notify-bark.conf` 的 `BARK_TITLE` | **立刻** —— 下一次推送即用新值 |
| Claude 通知**图标** | `~/.claude/notify-bark.conf` 的 `BARK_ICON` | **立刻** —— 下一次推送即用新值 |
| Codex 通知**标题** | `.env` 的 `CODEX_TITLE`,由 install.sh 嵌进 wrapper 的 `--title` 参数 | 重跑 `./install.sh codex` / `both` 后,重新粘 wrapper 到 `~/.zshrc` |
| Codex 通知**图标** | `.env` 的 `CODEX_ICON`,由 install.sh 嵌进 wrapper 的 `--icon` 参数 | 同上 |
| 声音(`bell`/`alarm` 等) | `~/.claude/settings.json` 里 hook command 的 `--sound` 参数(Claude),或 wrapper 里的 `--sound`(Codex) | 需**新开 Claude Code 会话**(或重新 source `~/.zshrc`)才生效 |
| Stop 时的固定**正文**(默认「任务完成」) | `~/.claude/settings.json` 里 Stop hook command 的 `--body` 参数 | 需**新开 Claude Code 会话**才生效 |

> 原理:`notify-bark.sh` 每次被 hook 触发时都重新 `source` 一遍 conf,所以 conf 改完立刻反映;而 `settings.json` 是 Claude Code 启动时加载的,改完要重开会话(`/exit` 后重新进 `claude`)才会重读。

> Notification 钩子的正文是 Claude Code 通过 stdin 传进来的动态文本,无法在配置里固定。

### 场景 1:已经装过,想改标题 / 图标 / Device Key

```bash
$EDITOR ~/.claude/notify-bark.conf
# 改完保存即可,下一次推送就用新值。无需重启 Claude Code,无需重跑 install.sh。
```

可以先发一条测试推送验证:

```bash
echo '{"message":"测试新标题/图标"}' | bash ~/.claude/notify-bark.sh
```

### 场景 2:新机器首次安装

编辑 `.env`(从 `.env.example` 复制来的)把这四项填上,再跑 `./install.sh claude`:

```ini
BARK_DEVICE_KEY=你的Bark Key
BARK_SERVER=https://api.day.app
BARK_TITLE=Claude on MacBook         # ← 改这里换标题(中文/空格都行,不用加引号)
BARK_ICON=https://example.com/x.png  # ← 改这里换图标,留空则不带图标
```

### 场景 3:想改声音、或者 Stop 时的固定文案「任务完成」

这两项写在 `~/.claude/settings.json` 的 hook 命令里,而不在 conf 里。直接编辑:

```bash
$EDITOR ~/.claude/settings.json
```

找到 `hooks.Stop` 这一段,例子:

```json
"Stop": [{ "hooks": [{
  "type": "command",
  "command": "bash /Users/<你>/.claude/notify-bark.sh --sound bell --body 任务完成"
}]}]
```

- `--sound bell` 改成 `--sound minuet` / `--sound alarm` / 等等 —— Bark 支持的声音列表见 [Bark 文档 - 推送声音](https://bark.day.app/#/tutorial?id=%e6%8e%a8%e9%80%81%e5%a3%b0%e9%9f%b3)。
- `--body 任务完成` 改成想要的固定文案。中文/空格按原样写即可,**不要加引号**(JSON 里这一整段已经是字符串了,内部再加双引号会破坏 JSON;若想嵌空格,用 `--body "Job done"` 这种带引号写法也可以,但要确保整个 command 字段的引号成对)。

`hooks.Notification` 那一段同理,只是它没有 `--body`(由 stdin 决定)。

### 图标 URL 的要求

- 必须是**公开可访问**的 HTTP/HTTPS URL —— Bark 服务端会去拉这张图,然后推到你的 iPhone。
- 推荐:正方形 PNG,边长 ≥ 100 px;太大的图浪费流量。
- 不能用 `file://` 或本地路径。
- 留空(`BARK_ICON=`)则推送不带图标。
- 现成图标库:[jairitAge/bark-icons](https://github.com/jairitAge/bark-icons),用 raw 链接(`https://raw.githubusercontent.com/jairitAge/bark-icons/main/<文件名>`)直接填进去就行。
- 想用自己的图,可以传到任意公开图床 / 自己的 GitHub raw / 自己的 CDN。

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
