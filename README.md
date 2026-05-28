# mini_bot

> 一个 bash 写的聊天机器人。
> 把你的 **微信** 或 **飞书** 账号接到一个命令行 LLM（默认 qoder-cli），用户在聊天里发消息就能拿到 AI 回复。
>
> English: [README.en.md](./README.en.md)

---

## 0. 它到底是干嘛的？

- 你在微信/飞书里发一句话 → bot 调 qoder-cli → 回你一句话。
- 上下文会自动续上。`/reset` 重开一段对话。
- 支持发图片、视频、语音、文件作为输入。
- 顺手内置了：定时提醒、长期记忆、文生图、TTS、网页搜索、多账号、自动备份。
- 自带一个网页面板看消息、用量、备份。

---

## 1. 三分钟跑起来（先只用微信）

只需要 3 步：

```bash
# 1) 拉代码
git clone git@github.com:hlx1996/mini_bot.git ~/mini_bot
cd ~/mini_bot

# 2) 装好 wxlink（微信桥），扫码登录一次
pip install --user wechat-clawbot
python3 -m wxlink login          # 弹二维码，手机扫码

# 3) 配置账号并启动
mkdir -p ~/wxbot-state
echo "wechat:default" > ~/wxbot-state/accounts.list
bash bot.sh run
```

完成。回到微信，给自己（文件传输助手）发条消息，就会收到回复。

> 想用更多个微信号？再 `python3 -m wxlink login --account work` 登一个，然后在 `accounts.list` 加一行 `wechat:work` 即可。

---

## 2. 接飞书（5 步）

```bash
# 1) 装飞书 CLI（lark-cli）
npm install -g @larksuiteoapi/lark-cli
lark-cli auth login              # 浏览器扫码

# 2) 去飞书开放平台建一个"自建应用"，拿到 App ID 和 App Secret
#    https://open.feishu.cn/app
#    在应用里开启「机器人」能力，订阅事件 im.message.receive_v1

# 3) 把凭证写到 shell（建议 ~/.zshrc 或 ~/.bashrc）
export LARK_APP_ID=cli_xxxxxxxxxxxxxxxx
export LARK_APP_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# 4) 在 accounts.list 加一行
echo "lark:default" >> ~/wxbot-state/accounts.list

# 5) 重启 bot
bash bot.sh run
```

之后在飞书里 `@你的机器人` 即可触发回复。私聊直接发也行。

---

## 3. 常用命令（直接在聊天里发）

| 命令 | 作用 |
|---|---|
| `/reset` | 清掉上下文，开始新对话 |
| `/help` | 查所有命令 |
| `/lang en` | 切英文回复（`/lang zh` 切回） |
| `/soul cat` | 换人格（默认有 assistant / cat / editor …） |
| `/model claude` | 换底层 LLM 命令（默认 qoder-cli） |
| `/search 今天的新闻` | 联网搜一下 |
| `/image 一只赛博朋克猫` | 文生图 |
| `/tts 你好` | 文字转语音 |
| `/cron add "0 9 * * *" 早安` | 每天 9 点提醒 |
| `/remember 我的生日是 5 月 1 号` | 长期记忆 |
| `/memory` | 看记的什么 |
| `/forget` | 清空记忆 |
| `/backup` | 立刻整库备份一份 |
| `/usage day` | 看今日用量 |

完整列表发 `/help`。

---

## 4. 网页面板（可选）

```bash
python3 web.py --port 8088
```

浏览器打开 `http://127.0.0.1:8088`，可以看消息流、用量统计、下载备份。

想加密码？

```bash
export MINIBOT_USER=admin
export MINIBOT_PASS=secret
python3 web.py --port 8088
```

---

## 5. 几个进阶设置（按需打开）

### 加密保存对话和记忆

```bash
export MINIBOT_ENCRYPT_KEY="一个你记得住的密码"
bash bot.sh run
```

启用后 `~/wxbot-state/memory/*.txt` 自动 AES-256 加密落盘，文件后缀变 `.enc`。
不设这个变量就跟以前一样（明文，零迁移）。

### 给监控加 Prometheus

`web.py` 自带 `/metrics`（不鉴权，方便 Prometheus 抓取）。
Grafana 仪表盘 JSON 在 `dashboards/minibot-grafana.json`，直接 Import。

### Docker 一键跑

```bash
docker build -t mini_bot .
docker run -d --name mini_bot -p 8088:8088 \
  -v ~/wxbot-state:/data -e BOT_HOME=/data \
  mini_bot
```

---

## 6. 文件都在哪？

代码：

```
mini_bot/
├── bot.sh        # 主程序
├── web.py        # 网页面板
├── live-smoke.sh # 一键测试（28 项）
├── backup.sh     # 备份/还原
└── lib/
    ├── lark.sh     # 飞书
    ├── agents.sh   # 子代理 / team
    ├── tts.sh      # 语音合成
    └── crypt.sh    # AES 加密
```

数据（默认在 `~/wxbot-state/`）：

```
~/wxbot-state/
├── accounts.list   # 你配的账号
├── sessions/       # 每段对话的 uuid
├── memory/         # 长期记忆
├── crons/          # 定时任务
├── downloads/      # 收到的图片/文件
├── backups/        # 备份产物
└── logs/           # 日志 + events.jsonl
```

---

## 7. accounts.list 格式

一行一个账号：

```
<platform>:<name>   [soul]   [model]
```

例：

```
wechat:default
wechat:work          assistant   qoder-cli
lark:lark_main       cat         qoder-cli
```

- `platform`：`wechat` 或 `lark`
- `soul`（可选）：默认人格
- `model`（可选）：默认 LLM 命令

---

## 8. 环境变量一览

| 变量 | 用途 |
|---|---|
| `BOT_HOME` | 数据目录（默认 `~/wxbot-state`） |
| `MINIBOT_MODEL` | 默认 LLM 命令（默认 `qoder-cli`） |
| `MINIBOT_USER` / `MINIBOT_PASS` | 网页面板 Basic Auth |
| `MINIBOT_ENCRYPT_KEY` | 启用对话/记忆加密 |
| `LARK_APP_ID` / `LARK_APP_SECRET` | 飞书凭证 |
| `MINIBOT_GH_CLIENT_ID` / `MINIBOT_GH_CLIENT_SECRET` / `MINIBOT_GH_ALLOWED_USERS` | 网页面板用 GitHub OAuth 登录 |

---

## 9. 测试 & CI

```bash
bash live-smoke.sh    # 本地全套，期望 PASS: 28  FAIL: 0
```

GitHub Actions 见 `.github/workflows/ci.yml`，每次 push 自动跑。

---

## 10. License

MIT
