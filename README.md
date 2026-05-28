# mini_bot

> 一个用纯 bash + 一份 Python web 面板写成的多平台聊天机器人。
> 接入 WeChat / 飞书(Lark) / Telegram，后端可对接 qoder-cli、Claude Code、Codex CLI 等任意命令行 LLM。
>
> English version: see [README.en.md](./README.en.md).

---

## 1. 一句话功能

让一个 bash 脚本 (`bot.sh`) 在多个 IM 平台同时挂机；用户在聊天里发文字 / 图片 / 视频 / 音频 / 文件，bot 调用 LLM 生成回复；自带定时任务、子代理、TTS、网页管理面板、加密备份、Prometheus 监控。

---

## 2. 快速开始（3 步）

```bash
# 1) 克隆
git clone git@github.com:hlx1996/mini_bot.git ~/mini_bot && cd ~/mini_bot

# 2) 配置账号（至少一个平台）
cat > ~/wxbot-state/accounts.list <<'EOF'
wechat:work
lark:lark_main      assistant   qoder-cli
telegram:tg_main    cat         qoder-cli
EOF

# 3) 跑起来
bash bot.sh run
```

WebUI 默认在 `http://127.0.0.1:8088`。

---

## 3. 架构总览

```
                  ┌───────────────────────────────────────┐
                  │           accounts.list               │
                  │  wechat:work  lark:main  telegram:tg  │
                  └───────────────┬───────────────────────┘
                                  │
            ┌─────────────────────┼───────────────────────┐
            ▼                     ▼                       ▼
       wxlink (WeChat)    lark.sh (Lark SDK)     telegram.sh (Bot API)
            │                     │                       │
            └──── NDJSON 事件流（统一 schema） ─────────┘
                                  │
                                  ▼
                       ┌──────────────────────┐
                       │  bot.sh handle_event │
                       │   ├ 意图路由         │
                       │   ├ 命令分发(/xxx)   │
                       │   ├ 多代理流水线     │
                       │   ├ 自动记忆/RAG     │
                       │   └ 调 qoder-cli     │
                       └──────────┬───────────┘
                                  │
                                  ▼
                          回复（文 / 图 / 音 / 视）
                                  │
                  ┌───────────────┴────────────────┐
                  │       events.jsonl 审计流       │
                  └───────────────┬────────────────┘
                                  ▼
                         web.py + /metrics
                       (面板、备份下载、Prometheus)
```

---

## 4. 目录结构

```
mini_bot/
├── bot.sh                 # 主进程，事件循环 + 命令分发 (~2400 行)
├── web.py                 # 监控面板 + /metrics
├── live-smoke.sh          # 29 项端到端冒烟测试
├── backup.sh              # 整库导出/导入
├── lib/
│   ├── lark.sh            # 飞书事件订阅 / 回复 / 卡片
│   ├── telegram.sh        # Telegram 长轮询 / 回复 / 文件下载
│   ├── agents.sh          # 子代理、team 流水线
│   ├── tts.sh             # 语音合成（say / espeak-ng）
│   └── crypt.sh           # 静态加密 (AES-256-CBC + pbkdf2)
├── dashboards/
│   └── minibot-grafana.json
├── Dockerfile
└── .github/workflows/ci.yml
```

运行时数据在 `$BOT_HOME`（默认 `~/wxbot-state`）：

```
~/wxbot-state/
├── accounts.list          # 账号配置
├── sessions/              # 每个会话的 uuid / soul / model / 语言
├── memory/                # 长期记忆（/remember 写入；可加密）
├── crons/                 # 定时任务
├── downloads/             # 接收的图片/视频/文件
├── backups/               # backup.sh 产物
├── logs/
│   ├── events.jsonl       # 审计流（驱动 Prometheus 和面板）
│   ├── bot.out / bot.err
│   └── reply.err
└── cmdq/                  # web 面板下发的命令队列
```

---

## 5. accounts.list 配置

一行一个账号，空行/`#` 注释忽略。字段：

```
<platform>:<name>   [soul]   [model]
```

- `platform`：`wechat` | `wx` | `lark` | `feishu` | `telegram` | `tg`
- `soul`（可选）：人格预设名（`assistant` / `cat` / `editor` …，文件在 `souls/`）
- `model`（可选）：执行 LLM 的命令，默认 `qoder-cli`，可换 `claude` / `codex`

例：

```
wechat:work
wechat:private          cat        qoder-cli
lark:lark_main          assistant  qoder-cli
telegram:tg_main        editor     codex
```

---

## 6. 环境变量速查

| 变量 | 用途 |
|---|---|
| `BOT_HOME` | 运行时数据根目录（默认 `~/wxbot-state`） |
| `MINIBOT_MODEL` | 默认 LLM 命令（默认 `qoder-cli`） |
| `MINIBOT_USER` / `MINIBOT_PASS` | web 面板 Basic Auth（不设则匿名） |
| `MINIBOT_GH_CLIENT_ID/SECRET` | web 面板启用 GitHub OAuth |
| `MINIBOT_GH_ALLOWED_USERS` | OAuth 白名单（逗号分隔） |
| `MINIBOT_ENCRYPT_KEY` | 启用静态加密；设了之后 sessions/memory 落盘自动 AES |
| `LARK_APP_ID` / `LARK_APP_SECRET` | 飞书自建应用凭证 |
| `TELEGRAM_BOT_TOKEN` | Telegram Bot Token（全局默认） |
| `TELEGRAM_BOT_TOKEN_<NAME>` | 单账号 Token（覆盖全局） |
| `MINIBOT_OAUTH_MOCK=1` | 跳过真 OAuth（测试用） |

---

## 7. 命令速查表

会话内直接发即可（首字符 `/`）。

| 命令 | 作用 |
|---|---|
| `/reset` | 清空当前会话上下文 |
| `/help` | 命令帮助（支持 `/lang en` 切英文） |
| `/lang zh\|en` | 切换回复语言 |
| `/soul <name>` | 切换人格预设 |
| `/model <cmd>` | 切换 LLM 命令 |
| `/auto on\|off` | 开/关意图自动路由（非 `/` 也能调命令） |
| `/search <query>` | DuckDuckGo + 摘要 |
| `/image <prompt>` | 生成图，可用 `n=3 style=cyberpunk ...` |
| `/tts <text>` | 文字转语音 |
| `/tts voice <name>` / `/tts rate <n>` | 设音色/语速 |
| `/cron add "<expr>" <text>` | 加定时任务（cron 表达式） |
| `/cron list` / `/cron rm <id>` | 管理定时任务 |
| `/remember <fact>` / `/memory` / `/forget` | 长期记忆 |
| `/automem on\|off` | 自动从对话抽取事实入库 |
| `/agent <name> <task>` | 子代理单次任务 |
| `/team set <a,b,c>` / `/team run <task>` | 多代理流水线 |
| `/rag add <name> <text>` / `/rag list` / `/rag rm` / `/rag on\|off` | 私有知识库 |
| `/card <title> <body>` | 飞书卡片 |
| `/backup` | 立即整库备份 |
| `/usage day\|week\|all` | 用量统计 |

---

## 8. 三种 IM 接入

### 8.1 WeChat
依赖 [`wxlink`](https://github.com/hlx1996/wxlink)（macOS 自动化壳）。装好后 `accounts.list` 写 `wechat:<name>` 即可，名字对应 wxlink 已登录账号。

### 8.2 飞书 / Lark
1. 飞书开放平台 → 自建应用 → 拿到 `App ID / Secret`。
2. 启用机器人能力 + 订阅事件 `im.message.receive_v1`。
3. `export LARK_APP_ID=...; export LARK_APP_SECRET=...`
4. `accounts.list` 添加 `lark:<name>`，启动即长连接订阅。
5. 群里 `@bot` 触发；卡片消息走 `/card`。

### 8.3 Telegram
1. 找 `@BotFather` 新建 bot，拿到 Token。
2. `export TELEGRAM_BOT_TOKEN=123:ABC...`（或单账号 `TELEGRAM_BOT_TOKEN_TG_MAIN=...`）。
3. `accounts.list` 添加 `telegram:tg_main`，启动即长轮询 `getUpdates`。
4. 支持 text / photo / voice / video / document 全双向。

---

## 9. Web 监控面板

```bash
python3 web.py --port 8088 --host 127.0.0.1
```

三档鉴权（按优先级）：

1. **GitHub OAuth** — 设了 `MINIBOT_GH_CLIENT_ID/SECRET` 自动启用，可叠加 `MINIBOT_GH_ALLOWED_USERS` 白名单。
2. **Basic Auth** — 设了 `MINIBOT_USER/MINIBOT_PASS` 启用。
3. **匿名** — 都没设时局域网直连。

端点：

| Path | 说明 |
|---|---|
| `/` | 面板 UI |
| `/api/status` `/api/sessions` `/api/events` `/api/usage` `/api/accounts` `/api/crons` `/api/backups` `/api/log` | JSON API |
| `/download/backup/<name>` | 下载备份 tar.gz |
| `/login` `/logout` `/oauth/callback` | GitHub OAuth 流程 |
| `/metrics` | **Prometheus**（不鉴权） |

---

## 10. 静态加密（Encryption at rest）

```bash
export MINIBOT_ENCRYPT_KEY="some-long-passphrase"
bash bot.sh run
```

启用后 `sessions/<key>.uuid` 和 `memory/<key>.txt` 落盘前用
`openssl enc -aes-256-cbc -pbkdf2 -pass env:MINIBOT_ENCRYPT_KEY` 加密，文件后缀 `.enc`。
未设置变量时完全等价于原行为（零迁移成本，已有数据继续可用）。

---

## 11. Prometheus + Grafana

`web.py` 提供 `/metrics`：

```
minibot_events_total{platform,kind}    # counter
minibot_replies_total{platform,ok}     # counter
minibot_chars_total{dir}               # counter
minibot_active_chats                   # gauge
minibot_backups_count                  # gauge
```

Prometheus 抓取示例：

```yaml
scrape_configs:
  - job_name: minibot
    static_configs:
      - targets: ['localhost:8088']
```

Grafana 仪表板 JSON：`dashboards/minibot-grafana.json`，直接 Import 即可。

---

## 12. 备份 / 恢复

- `/backup` 或 `bash backup.sh export` → 在 `backups/` 生成 `mini_bot-all-<ts>.tar.gz`。
- `bash backup.sh import <file.tar.gz>` 还原（覆盖 `$BOT_HOME`）。
- 面板可下载备份；定时任务（cron）可挂周备份。

---

## 13. Docker

```bash
docker build -t mini_bot .
docker run -d --name mini_bot \
  -v ~/wxbot-state:/data -e BOT_HOME=/data \
  -e TELEGRAM_BOT_TOKEN=... \
  -p 8088:8088 mini_bot
```

镜像基于 `debian:stable-slim`，自带 `bash jq curl openssl python3 espeak-ng`。

---

## 14. CI / 冒烟测试

```bash
bash live-smoke.sh    # 本地 29 项，预期 PASS: 29  FAIL: 0
```

GitHub Actions 见 `.github/workflows/ci.yml`：每次 push / PR 跑 `live-smoke.sh` + `docker build`。

---

## 15. License

MIT
