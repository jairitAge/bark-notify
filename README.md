# bark-notify

一个最小化的仓库,用一条命令把 [Bark](https://bark.day.app/) 推送接到 Claude Code **和** Codex CLI。两边都用各自的**原生 hook 机制**(Claude 的 `settings.json` / Codex 的 `config.toml`),完全对称。Device Key 只放本地 `.env`,**不进 git**。

## 推送场景(Claude 和 Codex 对称)

| 事件 | Claude Code | Codex CLI | 默认声音 |
|---|---|---|---|
| 一个 turn / 回复结束 | `hooks.Stop` | `hooks.Stop` | `bell` |
| 需要授权 / 等待用户输入 | `hooks.Notification` | `hooks.PermissionRequest` | `alarm` |

## 前置条件

- macOS 或 Linux,自带 `bash` / `curl` / `python3`
- iPhone 装 [Bark App](https://apps.apple.com/app/bark-customed-notifications/id1403753865),拿到 Device Key
- 配 Codex 那条路径需要 `codex` CLI ≥ 0.133

## 配置项总览(`.env` 字段)

复制 `.env.example` 为 `.env` 后,要填这几项:

| 字段 | 必填 | 含义 | 怎么填 |
|---|:-:|---|---|
| `BARK_DEVICE_KEY` | ✅ | Bark 给你 iPhone 的唯一推送凭证 | 见下方「获取 Device Key」 |
| `BARK_SERVER` | — | Bark 服务器 URL | 默认 `https://api.day.app`(官方);自建服务器换成自己的域名 |
| `BARK_TITLE` | — | **Claude Code** 推送的标题 | 任意字符串,中文/空格直接写、无需引号。例:`Claude Code LOCAL` |
| `BARK_ICON` | — | **Claude Code** 推送的图标 URL | 公开可访问的 HTTP/HTTPS 图片;留空则不带图标。见下方「图标 URL」 |
| `CODEX_TITLE` | — | **Codex** 推送的标题 | 同 `BARK_TITLE`,但用于 Codex。例:`Codex LOCAL` |
| `CODEX_ICON` | — | **Codex** 推送的图标 URL | 同 `BARK_ICON`,但用于 Codex |

> Claude 和 Codex 的标题/图标分两套,是为了在 iPhone 通知中一眼区分是哪边发的。

### 获取 Device Key

打开 iPhone 上的 **Bark App** → 首页正上方会显示一段 URL,格式像:

```
https://api.day.app/<your-device-key>/
                    └────── Device Key ──────┘
```

中间那段约 22 个字母数字混合的字符串就是你的 Device Key。点右上角图标可以「复制 URL」/「复制 Key」,把 Key 单独复制出来填到 `.env` 里。

> **Device Key 等价于一把推送钥匙** —— 任何人拿到 key 都能给你 iPhone 推任意通知。**别发到聊天、别贴到公开 issue、别 commit 到任何 git 仓库**。本仓库的 `.gitignore` 会拦截 `.env`,所以正常使用不会泄露。
> 如果不小心公开了:打开 Bark App → 设置 → 重新生成 Key,旧 key 立即失效。

### 图标 URL 怎么获取

- **必须是公开可访问的 HTTP/HTTPS URL** —— Bark 服务端会去这个 URL 拉图片,再推到你的 iPhone。
- 推荐:正方形 PNG,边长 ≥ 100 px。GIF/JPG 也行,但 PNG 最稳。
- **不能用** `file://` 或本地路径,Bark 服务器拉不到。
- **留空**(`BARK_ICON=`)→ 推送不带图标。
- **现成图标库**:[jairitAge/bark-icons](https://github.com/jairitAge/bark-icons) 里有 `claude.png` 和 `codex.png`,直接用 raw 链接填进去:
  ```
  https://raw.githubusercontent.com/jairitAge/bark-icons/main/claude.png
  https://raw.githubusercontent.com/jairitAge/bark-icons/main/codex.png
  ```
- **想用自己的图**:传到任意公开图床(imgur / GitHub raw / 自建 CDN),拿到 raw 直链填进来即可。

## 一键安装

```bash
# 1. 把示例 env 复制为本地 env,填入你的 Device Key
cp .env.example .env
$EDITOR .env

# 2. 三选一:
./install.sh claude   # 只配 Claude Code(默认)
./install.sh codex    # 只配 Codex CLI
./install.sh both     # 同时配两边
```

三种模式干的事:

| 步骤 | claude | codex | both |
|---|:-:|:-:|:-:|
| 写 `~/.claude/notify-bark.conf`(mode 600) | ✓ | ✓ | ✓ |
| 装 `~/.claude/notify-bark.sh`(已存在则先 `.bak.<时间戳>` 备份) | ✓ | ✓ | ✓ |
| 合并 `Stop` / `Notification` 到 `~/.claude/settings.json`(保留其他键) | ✓ | — | ✓ |
| 合并 `Stop` / `PermissionRequest` 到 `~/.codex/config.toml`(marker 块,保留其他键) | — | ✓ | ✓ |
| 发一条 Claude 测试推送 | ✓ | — | ✓ |
| 发一条 Codex 测试推送 | — | ✓ | ✓ |

`codex` 模式**只动 `~/.codex/config.toml` 里的 marker 块**(`# >>> bark-notify codex hooks >>>` ... `# <<< bark-notify codex hooks <<<` 之间),不碰你已有的 `model` / `sandbox_mode` / `[projects.*]` / `[plugins.*]` 等任何配置。

## 信任 Codex hook(只做一次)

Codex 出于安全考虑,新增/改动的 hook 默认会被**跳过**,直到你明确信任过。装完之后:

```bash
codex                    # 启动 codex
> /hooks                 # 在 codex 里输入这条斜杠命令,选择 Trust
```

之后 hook 才会真的开始触发。临时绕过可加 `--dangerously-bypass-hook-trust`(不推荐长期使用)。

> 已知 bug:codex `~/.codex/config.toml`(全局)的 hook 正常,但仓库本地 `.codex/config.toml` 在 interactive 模式下可能不触发,见 [openai/codex#17532](https://github.com/openai/codex/issues/17532)。本仓库**只动全局**配置,不受影响。

## 自定义配置

| 配置项 | 存在哪 | 生效时机 |
|---|---|---|
| Device Key | `~/.claude/notify-bark.conf` 的 `BARK_DEVICE_KEY` | **立刻** —— 下次推送就用新值 |
| Claude 通知**标题** | `~/.claude/notify-bark.conf` 的 `BARK_TITLE` | **立刻** |
| Claude 通知**图标** | `~/.claude/notify-bark.conf` 的 `BARK_ICON` | **立刻** |
| Codex 通知**标题** | `.env` 的 `CODEX_TITLE`(被 install 嵌进 TOML 的 hook command) | 重跑 `./install.sh codex` 后,下次 codex 启动 |
| Codex 通知**图标** | `.env` 的 `CODEX_ICON`(同上) | 同上 |
| 声音 / Stop 时的正文 | hook command 的 `--sound` / `--body` 参数:Claude 在 `~/.claude/settings.json`,Codex 在 `~/.codex/config.toml` | Claude 需新开会话;Codex 需重启 + `/hooks` 重新信任(因为命令哈希变了) |

> 原理:`notify-bark.sh` 每次被 hook 触发都重新 `source` 一遍 conf,所以 conf 改完立刻反映;而 `settings.json` / `config.toml` 是 Claude / Codex **启动时**加载的,改完要重启对应 CLI 才会重读。

### 场景 1:改标题 / 图标 / Device Key(Claude 侧)

```bash
$EDITOR ~/.claude/notify-bark.conf   # 改完即生效,无需重装、无需重启
```

测试推送:

```bash
echo '{"message":"测试新标题/图标"}' | bash ~/.claude/notify-bark.sh
```

### 场景 2:改 Codex 标题 / 图标 / 声音

Codex 的 hook command 是 install 时把 `.env` 里 `CODEX_TITLE` / `CODEX_ICON` 嵌进 TOML 里的,所以要:

```bash
$EDITOR .env                  # 改 CODEX_TITLE / CODEX_ICON
./install.sh codex            # 重新生成 TOML marker 块
# 然后在 codex 里跑 /hooks 重新信任(因为命令哈希变了)
```

也可以直接编辑 `~/.codex/config.toml` 里 marker 块之间的 `command = '...'` 字段,但 marker 之间的内容下次跑 `install.sh codex` 会被覆盖。

## 卸载

```bash
# 共享文件
rm ~/.claude/notify-bark.sh ~/.claude/notify-bark.conf

# Claude:手动从 ~/.claude/settings.json 删掉 hooks.Stop 和 hooks.Notification 两段
# Codex:删掉 ~/.codex/config.toml 里 'bark-notify codex hooks' 标记之间的整段
```

## 文件清单

| 文件 | 说明 | 进 git? |
|---|---|---|
| `install.sh` | 安装器 | ✅ |
| `notify-bark.sh` | 推送脚本(被装到 `~/.claude/`) | ✅ |
| `.env.example` | env 模板,占位 key | ✅ |
| `.env` | 你的本地真实 key | ❌(`.gitignore`) |
| `~/.claude/notify-bark.conf` | 安装后生成,mode 600 | — |

## 安全说明

- Device Key 只出现在两处:仓库本地 `.env`(`.gitignore` 拦截)、`~/.claude/notify-bark.conf`(mode 600)。**仓库里所有进 git 的文件都不硬编码 key**,push 到任何公开远端都安全。
- 如果误把 `.env` 提交了:立刻在 Bark App 里**重新生成 Device Key**(旧 key 一旦泄露就视为公开),再改 `.env` 重装。
