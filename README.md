# mini_bot

> 一个 bash 写的聊天机器人。把你的 **微信** 或 **飞书** 接到 qoder-cli（或任何命令行 LLM），用户聊天，bot 回复。
>
> English: [README.en.md](./README.en.md)

---

## 0. 它干嘛？

- 微信/飞书里发一句话 → bot 调 qoder-cli → 回你一句话。
- 上下文自动续；`/reset` 重开。
- 支持文字 / 图片 / 视频 / 语音 / 文件作为输入。
- 顺带内置：定时提醒、长期记忆、文生图、TTS、网页搜索、多账号、自动备份。
- 一个网页面板看消息和用量。

---

## 1. 三分钟跑起来（先只接微信）

```bash
# 1) 拉代码
git clone git@github.com:hlx1996/mini_bot.git
cd mini_bot

# 2) 装 wxlink 的依赖，扫码登录一次
pip install --user wechat-clawbot
python3 wxlink.py login           # 弹二维码，手机扫码

# 3) 配置账号，启动
echo "wechat:default" > state/accounts.list   # state/ 会被 bot 自动创建
bash bot.sh run
```

回到微信，给"文件传输助手"发条消息 → 收到回复 = 成功。

> 想接第二个微信号？`python3 wxlink.py --account work login` 登一个，再往 `state/accounts.list` 加一行 `wechat:work`。

---

## 2. 接飞书（5 步）

```bash
# 1) 装 lark-cli
npm install -g @larksuiteoapi/lark-cli
lark-cli auth login               # 浏览器扫码

# 2) 去 https://open.feishu.cn/app 建一个"自建应用"
#    - 开启「机器人」能力
#    - 订阅事件 im.message.receive_v1
#    - 拿到 App ID 和 App Secret

# 3) 把凭证写到 shell（建议放 ~/.zshrc）
export LARK_APP_ID=cli_xxxxxxxxxxxxxxxx
export LARK_APP_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# 4) 在 state/accounts.list 加一行
echo "lark:default" >> state/accounts.list

# 5) 重启
bash bot.sh run
```

之后在飞书里 `@bot` 即可触发；私聊直接发也行。

---

## 3. 常用命令（聊天里直接发）

| 命令 | 作用 |
|---|---|
| `/reset` | 清空上下文，开始新对话 |
| `/help` | 查所有命令 |
| `/lang en` | 切英文回复（`/lang zh` 切回） |
| `/soul cat` | 换人格（assistant / cat / editor …） |
| `/model claude` | 换底层 LLM 命令 |
| `/search 今天的新闻` | 联网搜 |
| `/image 一只赛博朋克猫` | 文生图 |
| `/tts 你好` | 文字转语音 |
| `/cron add "0 9 * * *" 早安` | 每天 9 点提醒 |
| `/remember 我的生日是 5/1` | 长期记忆 |
| `/memory` / `/forget` | 看 / 清记忆 |
| `/backup` | 立即整库备份 |
| `/usage day` | 看今日用量 |

完整列表发 `/help`。

---

## 4. 数据放在哪？

默认在仓库的 **`state/` 子目录**（即 `mini_bot/state/`，已经 gitignore）。
想换地方，设环境变量：

```bash
export BOT_HOME=/some/other/path
```

`state/` 里面：

```
state/
├── accounts.list   # 你配的账号
├── sessions/       # 每段对话的 uuid
├── memory/         # 长期记忆
├── crons/          # 定时任务
├── downloads/      # 收到的图片/文件
├── backups/        # 备份产物
└── logs/           # 日志 + events.jsonl
```

---

## 5. 网页面板（可选）

```bash
python3 web.py --port 8088
```

浏览器开 `http://127.0.0.1:8088`。

加密码：

```bash
export MINIBOT_USER=admin MINIBOT_PASS=secret
python3 web.py --port 8088
```

---

## 6. 进阶（按需打开）

### 加密保存对话/记忆

```bash
export MINIBOT_ENCRYPT_KEY="一个你记得住的密码"
bash bot.sh run
```

启用后 `state/memory/*.txt` 自动 AES-256 加密落盘（文件后缀 `.enc`）。
不设这个变量就跟以前一样（明文，零迁移）。

### Prometheus + Grafana

`web.py` 自带 `/metrics`（不鉴权）。Grafana 仪表盘 JSON 在 `dashboards/minibot-grafana.json`，Import 即可。

### Docker

```bash
docker build -t mini_bot .
docker run -d --name mini_bot -p 8088:8088 \
  -v $(pwd)/state:/app/state \
  mini_bot
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
wechat:work         assistant   qoder-cli
lark:lark_main      cat         qoder-cli
```

- `platform`：`wechat` | `lark`
- `soul`（可选）：默认人格
- `model`（可选）：默认 LLM 命令（默认 `qoder-cli`）

---

## 8. 环境变量

| 变量 | 用途 |
|---|---|
| `BOT_HOME` | 数据目录（默认 `<repo>/state`） |
| `MINIBOT_MODEL` | 默认 LLM 命令（默认 `qoder-cli`） |
| `MINIBOT_USER` / `MINIBOT_PASS` | 面板 Basic Auth |
| `MINIBOT_ENCRYPT_KEY` | 启用对话/记忆加密 |
| `LARK_APP_ID` / `LARK_APP_SECRET` | 飞书凭证 |
| `MINIBOT_GH_CLIENT_ID` / `MINIBOT_GH_CLIENT_SECRET` / `MINIBOT_GH_ALLOWED_USERS` | 面板用 GitHub OAuth 登录 |

---

## 9. 测试

```bash
bash live-smoke.sh    # 期望 PASS: 28  FAIL: 0
```

CI 见 `.github/workflows/ci.yml`，每次 push 自动跑。

---

## 10. License

MIT
