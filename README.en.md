# mini_bot

> A bash chat bot. Plug **WeChat** or **Lark (Feishu)** into qoder-cli (or any CLI LLM); users chat in IM, the bot replies.
>
> 中文：[README.md](./README.md)

---

## 0. What it does

- Send a message in WeChat/Lark → bot calls qoder-cli → you get an AI reply.
- Context auto-continues; `/reset` starts fresh.
- Accepts text, images, video, audio, files.
- Built-in: cron reminders, long-term memory, image gen, TTS, web search, multi-account, auto backups.
- Tiny web dashboard.

---

## 1. Three minutes to run (WeChat only)

```bash
# 1) clone
git clone git@github.com:hlx1996/mini_bot.git
cd mini_bot

# 2) install wxlink deps, log in once
pip install --user wechat-clawbot
python3 wxlink.py login           # scan QR with your phone

# 3) configure and start
echo "wechat:default" > state/accounts.list   # state/ is created automatically
bash bot.sh run
```

Open WeChat → message "File Transfer" → reply arrives = success.

> Second WeChat account? `python3 wxlink.py --account work login`, then add `wechat:work` to `state/accounts.list`.

---

## 2. Add Lark / Feishu (5 steps)

```bash
# 1) install lark-cli
npm install -g @larksuiteoapi/lark-cli
lark-cli auth login               # browser QR

# 2) On https://open.feishu.cn/app create a "self-built app"
#    - enable the Bot capability
#    - subscribe event: im.message.receive_v1
#    - copy App ID + App Secret

# 3) Export creds (put in ~/.zshrc)
export LARK_APP_ID=cli_xxxxxxxxxxxxxxxx
export LARK_APP_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# 4) Add account line
echo "lark:default" >> state/accounts.list

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
| `/soul cat` | Switch persona (`assistant`/`cat`/`editor`/…) |
| `/model claude` | Switch backend LLM command |
| `/search latest news` | Web search |
| `/image a cyberpunk cat` | Generate image |
| `/tts hello world` | Text to speech |
| `/cron add "0 9 * * *" Good morning` | Daily reminder |
| `/remember my birthday is May 1` | Long-term memory |
| `/memory` / `/forget` | Show / clear memory |
| `/backup` | Snapshot now |
| `/usage day` | Today's usage stats |

`/help` for the full list.

---

## 4. Where does data live?

By default, in the **`state/` subdirectory of the repo** (`mini_bot/state/`, already gitignored).
Override with:

```bash
export BOT_HOME=/some/other/path
```

Layout:

```
state/
├── accounts.list
├── sessions/
├── memory/
├── crons/
├── downloads/
├── backups/
└── logs/
```

---

## 5. Web dashboard (optional)

```bash
python3 web.py --port 8088
```

Open `http://127.0.0.1:8088`.

Add a password:

```bash
export MINIBOT_USER=admin MINIBOT_PASS=secret
python3 web.py --port 8088
```

---

## 6. Advanced toggles

### Encrypt conversations + memory at rest

```bash
export MINIBOT_ENCRYPT_KEY="some-passphrase"
bash bot.sh run
```

Files in `state/memory/` are AES-256 encrypted (`.enc` suffix). Unset the var to revert to plain files (zero migration).

### Prometheus + Grafana

`web.py` exposes `/metrics` (unauthenticated). Import `dashboards/minibot-grafana.json` into Grafana.

### Docker

```bash
docker build -t mini_bot .
docker run -d --name mini_bot -p 8088:8088 \
  -v $(pwd)/state:/app/state \
  mini_bot
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
wechat:work         assistant   qoder-cli
lark:lark_main      cat         qoder-cli
```

- `platform`: `wechat` or `lark`
- `soul` / `model` optional

---

## 8. Env vars

| Var | Purpose |
|---|---|
| `BOT_HOME` | Data dir (default `<repo>/state`) |
| `MINIBOT_MODEL` | Default LLM command (default `qoder-cli`) |
| `MINIBOT_USER` / `MINIBOT_PASS` | Dashboard Basic Auth |
| `MINIBOT_ENCRYPT_KEY` | Enable at-rest encryption |
| `LARK_APP_ID` / `LARK_APP_SECRET` | Lark app creds |
| `LARK_AS` / `LARK_AS_<NAME>` | lark-cli identity name (default `bot`; rarely needed) |
| `MINIBOT_GH_CLIENT_ID` / `MINIBOT_GH_CLIENT_SECRET` / `MINIBOT_GH_ALLOWED_USERS` | GitHub OAuth for dashboard |

---

## 9. Tests

```bash
bash live-smoke.sh    # expect PASS: 28  FAIL: 0
```

CI in `.github/workflows/ci.yml`.

---

## 10. License

MIT
