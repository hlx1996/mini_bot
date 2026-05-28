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
| `/stream on` | 实时推送『🤔 思考中 / 🔧 调用工具』进度（默认 off） |
| `/url off` | 消息含网址时关闭自动抓正文（默认 on） |
| `/route add 代码\|debug claude-sonnet` | 关键词命中时临时换模型；首匹配生效 |
| `/cost week` | 看本周 token / 估算费用（按模型分组） |
| `/agent researcher 帮我整理 LLM 进展` | 一次性子代理（独立 session，不污染主对话） |
| `/team set researcher critic editor` | 设管线；`/team run <task>` 依次跑完 |
| `/nick add 老王 last` | 把上一条消息的发件人记成「老王」（昵称簿） |
| `/msg 老王 周会改到 3 点` | 按昵称直接发消息（自动选对平台 / 账号） |
| `/bridge 老王 老李` | 双向桥接两人：消息互相转发，包括图片/文件 |
| `/broadcast 老王,老李,产品群 周会改到 3 点` | 群发到多个昵称 |
| `/digest now 24` | 立即总结本会话最近 24h；`/digest add "0 9 * * *"` 每日定时 |
| `/bg <慢问题>` | 后台思考：立即回 🤔，跑完再把结果推回来；`/bg list`、`/bg cancel <id>` |
| `/pin add 老板偏好 简洁回复` | 常驻"小抄"：每次回复都拼上（原 `/rag` 已改名 `/pin`） |
| `/rag add <feishu-doc-url>` | 真 RAG：把 Feishu 文档纳入知识库，提问时按关键词检索；**原文不落地** |
| `/rag add-folder <folder-url>` | 递归索引整个文件夹下所有 docx（上限 200） |
| `/rag add-mine [keyword]` | 索引我拥有的所有 docx（需 `search:docs:read` scope，命令会提示登录） |
| `/rag refresh` | 重新拉一遍所有已索引文档（捕获最新改动） |
| `/rag list` / `/rag rm <token>` / `/rag test <q>` / `/rag stats` | 看 / 删 / 调试检索 / 看大小 |
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

### 跨平台桥接（飞书 ⇄ 微信）

把一个飞书联系人和一个微信联系人「焊」在一起，消息互相直转，bot 不再回复 qoder。

```text
# 让 bot 「看到」目标发的至少一条消息（任何文字都行，bot 会自动记入最近联系人）
# 然后给两边各起一个昵称：
/nick add 微信老王 last        # 在微信里发一句话给 bot 后，回去飞书发这条命令
/nick add 飞书老李 last        # 在飞书 / 微信里都行，关键是上一条消息要是老李发的

/bridge 微信老王 飞书老李       # 双向桥接，老王在微信发的字会以 [微信老王]: xxx 形式出现在老李的飞书
/bridge list                  # 查所有桥
/bridge off 微信老王           # 断开老王身上的全部桥
/nick recent                  # 看最近 10 个发件人（找不到昵称时用来挑 last）
/msg 飞书老李 周会改到 3 点      # 不开桥，单条点对点发送
```

桥接转发文本 **和** 媒体（图片/语音/文件原样转给对方）；命令仍走 bot，所以随时能 `/bridge off`。

### 自定义插件（plugins/*.sh）

任何放进 `plugins/` 的 `.sh` 文件，bot 启动时会自动 source。在文件里调一次
`register_command "/foo" handler "短帮助"` 就多出一个 `/foo` 命令——所有内置
helper（`reply_text`、`run_qoder_agent`、`contact_*`、`bridge_*` …）都能直接用。
示例见 `plugins/broadcast.sh`（群发）和 `plugins/digest.sh`（聊天摘要）。

```bash
# plugins/hello.sh
plugin_hello() {
  local to="$1" key="$2" rest="$3"
  reply_text "$to" "👋 hi! 你说：$rest"
  return 0
}
register_command "/hello" plugin_hello "示例插件"
```

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

### 开机自启 / 后台常驻

```bash
./scripts/install-service.sh install     # 自动选择 launchd / systemd / 用户守护
./scripts/install-service.sh status      # 看运行状态
./scripts/install-service.sh restart     # 重启服务
./scripts/install-service.sh uninstall   # 卸载
```

- macOS：写 `~/Library/LaunchAgents/com.mini-bot.plist`（公司 Mac 没权限时自动降级为 zsh 登录守护）
- Linux：写 `~/.config/systemd/user/mini_bot.service`（无 systemctl 时同样降级）；模板在 `scripts/systemd/mini_bot.service.template`
- 降级模式：在仓库里放 `scripts/watchdog.sh` 守护进程 + 在你的 shell rc 里挂钩，登录即拉起，崩溃自动重启

#### 日志切割（logrotate）

```bash
./scripts/install-service.sh rotate
```

- 有 sudo / /etc/logrotate.d 可写时 → 装到系统级 `/etc/logrotate.d/mini_bot`
- 没权限时 → 写到 `~/.config/mini_bot/logrotate.conf`，并往用户 crontab 加一条整点跑 `logrotate` 的任务
- 默认每天切割、保留 14 份、超过 50M 强切、压缩、`copytruncate`（不需要重启 bot）

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
| `LARK_AS` / `LARK_AS_<NAME>` | lark-cli 身份名（默认 `bot`，一般无需改） |
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
