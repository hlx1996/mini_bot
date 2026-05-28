# mini_bot

> A multi-platform chat bot written as a single bash script (`bot.sh`) plus a small Python web panel.
> Plugs into WeChat / Lark (Feishu) / Telegram on the front; into any CLI LLM (qoder-cli, Claude Code, Codex CLI, …) on the back.
>
> 中文文档见 [README.md](./README.md)。

---

## 1. One-liner

Let one bash process sit on multiple IM platforms at once; users send text / images / video / audio / files; the bot routes through an LLM and replies. Built-in: cron jobs, sub-agents, TTS, web dashboard, encrypted backups, Prometheus.

---

## 2. Quickstart

```bash
git clone git@github.com:hlx1996/mini_bot.git ~/mini_bot && cd ~/mini_bot

cat > ~/wxbot-state/accounts.list <<'EOF'
wechat:work
lark:lark_main      assistant   qoder-cli
telegram:tg_main    cat         qoder-cli
EOF

bash bot.sh run
```

Web UI: `http://127.0.0.1:8088`.

---

## 3. Architecture

```
accounts.list
   │
   ▼
wxlink (WeChat) │ lark.sh (Lark SDK) │ telegram.sh (Bot API long-poll)
   │                  │                          │
   └────── NDJSON event stream (unified schema) ─┘
                      ▼
            bot.sh handle_event
              ├ intent routing
              ├ /command dispatch
              ├ multi-agent pipelines
              ├ auto-memory + RAG
              └ exec qoder-cli (or any LLM)
                      ▼
        reply(text / image / audio / video)
                      ▼
            events.jsonl  ──►  web.py + /metrics
```

---

## 4. Layout

```
mini_bot/
├── bot.sh                # main loop, command dispatch
├── web.py                # dashboard + /metrics
├── live-smoke.sh         # 29 end-to-end tests
├── backup.sh             # export / import
├── lib/
│   ├── lark.sh           # Lark subscribe / reply / cards
│   ├── telegram.sh       # Telegram long-poll / reply / file download
│   ├── agents.sh         # sub-agents, team pipelines
│   ├── tts.sh            # TTS (say / espeak-ng)
│   └── crypt.sh          # AES-256-CBC at-rest encryption
├── dashboards/
│   └── minibot-grafana.json
├── Dockerfile
└── .github/workflows/ci.yml
```

Runtime state lives in `$BOT_HOME` (default `~/wxbot-state`): `sessions/`, `memory/`, `crons/`, `downloads/`, `backups/`, `logs/events.jsonl`, `cmdq/`.

---

## 5. accounts.list

```
<platform>:<name>   [soul]   [model]
```

- `platform`: `wechat | wx | lark | feishu | telegram | tg`
- `soul`: persona preset (`assistant`, `cat`, `editor`, …)
- `model`: backend CLI (`qoder-cli`, `claude`, `codex`, …)

Example:

```
wechat:work
wechat:private    cat        qoder-cli
lark:lark_main    assistant  qoder-cli
telegram:tg_main  editor     codex
```

---

## 6. Env vars

| Var | Purpose |
|---|---|
| `BOT_HOME` | Runtime data dir (default `~/wxbot-state`) |
| `MINIBOT_MODEL` | Default LLM command (default `qoder-cli`) |
| `MINIBOT_USER` / `MINIBOT_PASS` | Web Basic Auth |
| `MINIBOT_GH_CLIENT_ID/SECRET` | Enable GitHub OAuth on web panel |
| `MINIBOT_GH_ALLOWED_USERS` | OAuth allowlist (comma-separated) |
| `MINIBOT_ENCRYPT_KEY` | Enable at-rest AES encryption for sessions/memory |
| `LARK_APP_ID` / `LARK_APP_SECRET` | Lark self-built app creds |
| `TELEGRAM_BOT_TOKEN` | Telegram Bot token (global default) |
| `TELEGRAM_BOT_TOKEN_<NAME>` | Per-account token (overrides global) |
| `MINIBOT_OAUTH_MOCK=1` | Skip real OAuth (tests) |

---

## 7. Commands cheat sheet

| Command | Effect |
|---|---|
| `/reset` | Clear current conversation |
| `/help` | Help (use `/lang en` for English) |
| `/lang zh\|en` | Switch reply language |
| `/soul <name>` | Switch persona |
| `/model <cmd>` | Switch backend LLM |
| `/auto on\|off` | Toggle natural-language intent routing |
| `/search <query>` | DuckDuckGo + summary |
| `/image <prompt>` | Generate image (`n=3 style=cyberpunk ...`) |
| `/tts <text>` | Text-to-speech |
| `/tts voice <n>` / `/tts rate <n>` | Voice / rate |
| `/cron add "<expr>" <text>` | Schedule task |
| `/cron list` / `/cron rm <id>` | Manage tasks |
| `/remember <fact>` / `/memory` / `/forget` | Long-term memory |
| `/automem on\|off` | Auto-extract facts from chat |
| `/agent <name> <task>` | Sub-agent single shot |
| `/team set <a,b,c>` / `/team run <task>` | Multi-agent pipeline |
| `/rag add <name> <text>` / `/rag list` / `/rag rm` / `/rag on\|off` | Private knowledge base |
| `/card <title> <body>` | Lark card |
| `/backup` | Snapshot now |
| `/usage day\|week\|all` | Usage stats |

---

## 8. Transports

### 8.1 WeChat
Requires [`wxlink`](https://github.com/hlx1996/wxlink) (macOS only). Add `wechat:<name>` to `accounts.list` and matching wxlink account is auto-subscribed.

### 8.2 Lark / Feishu
1. Create a self-built app, get `App ID / Secret`.
2. Enable bot + subscribe `im.message.receive_v1`.
3. `export LARK_APP_ID=... LARK_APP_SECRET=...`
4. Add `lark:<name>` to `accounts.list`. `@bot` in group triggers reply; cards via `/card`.

### 8.3 Telegram
1. Create a bot with `@BotFather`, copy the token.
2. `export TELEGRAM_BOT_TOKEN=123:ABC...` (or `TELEGRAM_BOT_TOKEN_TG_MAIN=...`).
3. Add `telegram:tg_main` to `accounts.list`. Long-poll `getUpdates`; full text/photo/voice/video/document support.

---

## 9. Web panel

```bash
python3 web.py --port 8088 --host 127.0.0.1
```

Three auth tiers (in priority order):

1. **GitHub OAuth** — auto-on if `MINIBOT_GH_CLIENT_ID/SECRET` set; optional `MINIBOT_GH_ALLOWED_USERS` allowlist.
2. **Basic Auth** — on if `MINIBOT_USER/MINIBOT_PASS` set.
3. **Open** — neither set → LAN open.

Endpoints: `/`, `/api/{status,sessions,events,usage,accounts,crons,backups,log}`, `/download/backup/<name>`, `/login`, `/logout`, `/oauth/callback`, and unauthenticated `/metrics` (Prometheus).

---

## 10. At-rest encryption

```bash
export MINIBOT_ENCRYPT_KEY="some-long-passphrase"
bash bot.sh run
```

When set, `sessions/<key>.uuid` and `memory/<key>.txt` are written via
`openssl enc -aes-256-cbc -pbkdf2 -pass env:MINIBOT_ENCRYPT_KEY` (`.enc` suffix).
When unset, behavior is identical to the pre-encryption build (zero migration).

---

## 11. Prometheus + Grafana

`/metrics` exposes:

```
minibot_events_total{platform,kind}    counter
minibot_replies_total{platform,ok}     counter
minibot_chars_total{dir}               counter
minibot_active_chats                   gauge
minibot_backups_count                  gauge
```

Prometheus scrape:

```yaml
scrape_configs:
  - job_name: minibot
    static_configs:
      - targets: ['localhost:8088']
```

Grafana dashboard JSON: `dashboards/minibot-grafana.json` — Import as-is.

---

## 12. Backup / restore

- `/backup` or `bash backup.sh export` → `backups/mini_bot-all-<ts>.tar.gz`.
- `bash backup.sh import <file.tar.gz>` to restore.
- Dashboard provides download links; cron a weekly snapshot if you like.

---

## 13. Docker

```bash
docker build -t mini_bot .
docker run -d --name mini_bot \
  -v ~/wxbot-state:/data -e BOT_HOME=/data \
  -e TELEGRAM_BOT_TOKEN=... \
  -p 8088:8088 mini_bot
```

Image is `debian:stable-slim` with `bash jq curl openssl python3 espeak-ng`.

---

## 14. CI / smoke tests

```bash
bash live-smoke.sh    # 29 tests, expect PASS: 29  FAIL: 0
```

GitHub Actions in `.github/workflows/ci.yml` runs `live-smoke.sh` + `docker build` on every push / PR.

---

## 15. License

MIT
