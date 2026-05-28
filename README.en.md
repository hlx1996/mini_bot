# mini_bot

> A bash chat bot.
> Plug your **WeChat** or **Lark (Feishu)** account into a CLI LLM (default `qoder-cli`); users chat in IM, the bot replies.
>
> 中文：[README.md](./README.md)

---

## 0. What it does

- You send a message in WeChat/Lark → bot calls qoder-cli → you get an AI reply.
- Context auto-continues. `/reset` starts a new conversation.
- Accepts text, images, video, audio, files as input.
- Bonus built-in: cron reminders, long-term memory, image gen, TTS, web search, multi-account, auto backups.
- Tiny web dashboard for messages, usage, backup downloads.

---

## 1. Three-minute start (WeChat only)

```bash
# 1) clone
git clone git@github.com:hlx1996/mini_bot.git ~/mini_bot
cd ~/mini_bot

# 2) install wxlink (WeChat bridge), log in once
pip install --user wechat-clawbot
python3 -m wxlink login          # scan QR with your phone

# 3) configure account and run
mkdir -p ~/wxbot-state
echo "wechat:default" > ~/wxbot-state/accounts.list
bash bot.sh run
```

Done. Open WeChat → message "File Transfer" → you'll get a reply.

> Want a second WeChat account? `python3 -m wxlink login --account work`, then add `wechat:work` to `accounts.list`.

---

## 2. Add Lark / Feishu (5 steps)

```bash
# 1) install lark-cli
npm install -g @larksuiteoapi/lark-cli
lark-cli auth login              # browser QR

# 2) Create a "self-built app" on Lark open platform, get App ID/Secret
#    https://open.feishu.cn/app
#    Enable the Bot capability and subscribe event: im.message.receive_v1

# 3) Export creds (put in ~/.zshrc or ~/.bashrc)
export LARK_APP_ID=cli_xxxxxxxxxxxxxxxx
export LARK_APP_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# 4) Add an account line
echo "lark:default" >> ~/wxbot-state/accounts.list

# 5) Restart
bash bot.sh run
```

Then `@your-bot` in any Lark chat (or DM it).

---

## 3. Common commands (send in chat)

| Command | Effect |
|---|---|
| `/reset` | Clear context, start fresh |
| `/help` | Full command list |
| `/lang zh` | Switch to Chinese (`/lang en` to switch back) |
| `/soul cat` | Switch persona (`assistant` / `cat` / `editor` …) |
| `/model claude` | Switch backend LLM |
| `/search latest news` | Web search |
| `/image a cyberpunk cat` | Generate image |
| `/tts hello world` | Text to speech |
| `/cron add "0 9 * * *" Good morning` | Daily reminder |
| `/remember my birthday is May 1` | Long-term memory |
| `/memory` | Show what's remembered |
| `/forget` | Clear memory |
| `/backup` | Snapshot now |
| `/usage day` | Today's usage stats |

Send `/help` for the full list.

---

## 4. Web dashboard (optional)

```bash
python3 web.py --port 8088
```

Open `http://127.0.0.1:8088` for the event stream, usage, backups.

Want a password?

```bash
export MINIBOT_USER=admin
export MINIBOT_PASS=secret
python3 web.py --port 8088
```

---

## 5. A few advanced toggles

### Encrypt conversation + memory at rest

```bash
export MINIBOT_ENCRYPT_KEY="some-passphrase"
bash bot.sh run
```

Memory files on disk are AES-256 encrypted (`.enc` suffix). Unset the var to revert to plain files (zero migration).

### Prometheus + Grafana

`web.py` exposes `/metrics` (unauthenticated). Import `dashboards/minibot-grafana.json` into Grafana.

### Docker

```bash
docker build -t mini_bot .
docker run -d --name mini_bot -p 8088:8088 \
  -v ~/wxbot-state:/data -e BOT_HOME=/data \
  mini_bot
```

---

## 6. Where everything lives

Code:

```
mini_bot/
├── bot.sh         # main loop
├── web.py         # dashboard
├── live-smoke.sh  # 28-test suite
├── backup.sh      # export/import
└── lib/
    ├── lark.sh
    ├── agents.sh
    ├── tts.sh
    └── crypt.sh
```

Data (default `~/wxbot-state/`):

```
~/wxbot-state/
├── accounts.list
├── sessions/
├── memory/
├── crons/
├── downloads/
├── backups/
└── logs/
```

---

## 7. accounts.list format

One line per account:

```
<platform>:<name>   [soul]   [model]
```

Example:

```
wechat:default
wechat:work          assistant   qoder-cli
lark:lark_main       cat         qoder-cli
```

`platform`: `wechat` or `lark`. `soul` / `model` optional.

---

## 8. Env vars

| Var | Purpose |
|---|---|
| `BOT_HOME` | Data dir (default `~/wxbot-state`) |
| `MINIBOT_MODEL` | Default LLM command (default `qoder-cli`) |
| `MINIBOT_USER` / `MINIBOT_PASS` | Dashboard Basic Auth |
| `MINIBOT_ENCRYPT_KEY` | Enable at-rest encryption |
| `LARK_APP_ID` / `LARK_APP_SECRET` | Lark app creds |
| `MINIBOT_GH_CLIENT_ID` / `MINIBOT_GH_CLIENT_SECRET` / `MINIBOT_GH_ALLOWED_USERS` | GitHub OAuth for dashboard |

---

## 9. Tests / CI

```bash
bash live-smoke.sh    # expect PASS: 28  FAIL: 0
```

GitHub Actions: `.github/workflows/ci.yml`.

---

## 10. License

MIT
