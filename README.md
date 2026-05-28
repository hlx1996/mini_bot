# wxbot — 微信 ↔ qoder(lite) 桥（OpenClaw 风格，无需 openclaw）

> 三个文件、一行 pip、不依赖 openclaw / Node / 任何二进制服务，公司笔记本可用。
> 支持 **多微信账号 + 账号路由规则**、文本 / 图片 / 语音 / 视频 / 文件，多轮上下文，定时任务（cron + 自然语言），
> 灵魂(persona) / 长期记忆 / 技能模板 / MCP / 配额 / 静音 / 白名单 / 管理员 / 导出 / 统计 / 欢迎语，
> **AI 联网搜索** / **AI 图片生成（多张+风格）** / **TTS 语音回复（音色+语速）** / **Hooks 可编程切面** / **RAG 知识库** /
> **自然语言自动路由（无需打 /）** / **可操作 Web 面板**。

| 文件 | 作用 |
|---|---|
| `~/wxlink.py` | Python CLI，封装 `wechat-clawbot` SDK：`login` / `whoami` / `subscribe`（NDJSON 行流）/ `send-text` / `send-media`。负责长轮询、AES 解密、SILK→WAV、context-token 持久化。 |
| `~/wxbot.sh` | Bash 事件循环。订阅 wxlink → 解析 → 路由到 `qodercli --model lite` → 回发。所有 OpenClaw 风格扩展都在这里。 |
| `~/wxweb.py` | stdlib-only HTTP 监控面板（端口 8765），实时显示状态/会话/事件流/cron/日志。 |

---

## 1. 一次性安装

```bash
pip3 install --user wechat-clawbot          # 唯一外部依赖
python3 ~/wxlink.py login                   # 扫码绑定一个微信号
```

`login` 会在控制台打印二维码，用 **目标微信** 扫码即可（小号、企业号都行）。
凭据保存到 `~/.claude/channels/wechat/account.json`。

---

## 2. 启动

```bash
# 前台（看日志）
~/wxbot.sh

# 后台
nohup ~/wxbot.sh                > ~/wxbot-state/logs/bot.out 2>&1 & disown
nohup python3 ~/wxweb.py        > ~/wxbot-state/logs/web.out 2>&1 & disown

# 自检（不连微信，只跑 qoder smoke turn）
~/wxbot.sh --self-test
```

打开 <http://127.0.0.1:8765> 看面板。

---

## 3. 目录结构（`BOT_HOME=~/wxbot-state`）

```
~/wxbot-state/
├── souls/        人格 system-prompt（default, cat, pro, coder …）
├── skills/       技能模板（translate, summarize, weather, code-review …）
├── memory/       每会话长期记忆 <chat_key>.txt
├── quota/        每日配额计数 <YYYY-MM-DD>-<chat_key>
├── sessions/     qoder UUID / model / soul / quota / peer / lock / tts
├── workspaces/   每会话独立沙箱目录（qoder cwd）
├── downloads/    wxlink 解密后的图片 / 语音 / 文件
├── logs/         bot.out, qoder.err, reply.err, wxlink-<acct>.err, events.jsonl
├── images/       /image 生成的图片
├── tts/          /tts 合成的音频回复
├── hooks/        pre_turn.sh / post_turn.sh / on_command.sh （可选切面）
├── commands/     Web 面板 POST 进来的待执行命令（JSON 文件，bot 每 2s 处理）
├── accounts/     多账号每号独立的 HOME（凭据隔离）
├── accounts.list 多账号清单 + 默认 soul/model：  <name> [soul] [model]
├── rag/          RAG 知识库：<chat_key>/*.txt 和 _global/*.txt
├── mcp.json      （可选）MCP 服务器配置，自动传给 qodercli --mcp-config
├── mute.list      静音的 chat_key 列表
├── whitelist.list 仅这些 user 允许（空=任何人都行）
├── admins.list    管理员 user-id 列表
└── welcomed.list  已发过欢迎语的 chat_key
```

---

## 4. OpenClaw 风格命令一览

所有命令在普通聊天里直接打就行；群聊里也支持，前提是 @ 了机器人或以 `/` 开头。

### 会话基础
| 命令 | 作用 |
|---|---|
| `/reset` / `/重置` | 清空本会话的 qoder 多轮记忆（不动 soul/memory）|
| `/model [name]` | 查看 / 切换本会话模型（默认 `lite`）|
| `/status` | bot 状态 + 当前 soul / model / 配额 |
| `/cancel` | 中止正在跑的 qoder 调用 |
| `/help` `/帮助` | 命令清单 |
| `/whoami` | 你的 user-id、chat_key、所在 account、是否 admin/muted、tts on/off |
| `/auto on \| off` | 🆕 自然语言自动调用 /命令（默认 on，关了才需手打 /）|
| `/rag list \| on \| off \| add <名字> <内容> \| rm <名字>` | 🆕 知识库 |
| `/tts on \| off \| engine \| voice [name\|-] \| rate [n\|-]` | 🆕 语音回复（音色/语速）|
| `/image [n=2] [style=cyberpunk\|水墨\|…] <提示词>` | 🆕 AI 生成图片（多张/风格）|
| `/search <关键词>` | 🆕 联网搜索 + qoder 综合回答（耗 1 配额）|
| `/news <关键词>` | 🆕 直接返回搜索摘要列表（不耗配额）|
| `/hooks` | 🆕 查看 pre_turn / post_turn / on_command 安装情况 |
| `/account [list\|add\|rm]` | 🆕 多微信账号管理 |
| `/cron nl <自然语言>` | 🆕 让 qoder 把"每天 8 点喝水"翻译成 cron 表达式 |

### 灵魂 / 人格（Souls）
每个会话有一个激活的 soul，对应 `souls/<name>.txt` 的内容。切换 soul 会自动 `/reset`（防止旧人格污染上下文）。

| 命令 | 作用 |
|---|---|
| `/soul` | 显示当前 soul |
| `/soul list` | 列出所有 soul |
| `/soul <name>` | 切换 soul（如 `cat`, `pro`, `coder`, `default`）|
| `/soul show [name]` | 查看 soul 内容 |
| `/soul save <name>=<system-prompt>` | 自定义并持久化 soul |

默认自带：`default`（通用助手）、`cat`（猫娘喵～）、`pro`（专业助理）、`coder`（程序员）。

### 长期记忆（Memory）
跨 `/reset` 永久保留，每次调用自动注入 system-prompt：
```
[Long-term memory for this chat — treat as ground truth]:
…
```

| 命令 | 作用 |
|---|---|
| `/memory` / `/memory show` | 显示本会话长期记忆 |
| `/memory add <文本>` | 追加一条 |
| `/memory clear` | 清空 |

实测：`/memory add 我叫小明` 之后再问"我叫什么"，回答会是"你叫小明。"，
即使中途 `/reset` 也不影响。

### 技能（Skills）
技能就是 `skills/<name>.txt` 模板，支持 `{{1}}` 和 `{{rest}}` 占位符：

```bash
/skill list                       # 列出可用技能
/skill show translate             # 看模板内容
/skill translate en 你好世界      # → "Hello world"
/skill summarize    一段很长的文字…
/skill weather      北京
/skill code-review  python  def f(): return 1
```

要新增技能：直接往 `~/wxbot-state/skills/` 里丢 `.txt` 文件即可，无需重启。

### MCP（Model Context Protocol）
把 `mcp.json` 放到 `~/wxbot-state/mcp.json`，wxbot 会自动给每次 qoder 调用加 `--mcp-config`。

```json
{
  "mcpServers": {
    "filesystem": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"] },
    "fetch":      { "command": "uvx", "args": ["mcp-server-fetch"] }
  }
}
```

| 命令 | 作用 |
|---|---|
| `/mcp` | 列出已配置的 MCP 服务器 |
| `/mcp reload` | 提示下次调用会重读（每次都重读，所以基本是 no-op）|

> 注意：MCP 服务器的实际可用性取决于 `npx`/`uvx`/`python` 等命令在 PATH 中能否解析。
> qoder 启动 MCP 失败时会自己日志报错，不影响主流程。

### 定时任务（Cron）
通过系统 `crontab` 实现，便于跨平台、无需常驻。
```bash
/cron list
/cron add "0 9 * * *" 早安，给我今天的天气和我日历上的会议
/cron add "*/30 * * * *" 提醒我活动一下身体
/cron rm  <id>
```
触发时 wxbot 用同一会话的 soul/memory/model 跑一轮，结果直接发到对方。

### 治理 — 静音 / 白名单 / 管理员 / 配额
| 命令 | 谁能用 | 作用 |
|---|---|---|
| `/mute` | 任何人 | 静音本会话（机器人不再自动回复）|
| `/unmute` | 自己 / admin | 解除静音 |
| `/quota` | 任何人 | 看今日用量 |
| `/quota set <n>` | admin | 设置本会话每日配额（默认 `QUOTA_DEFAULT=200`，0=不限）|
| `/whitelist list / add <user> / rm <user>` | admin | 启用后只接受名单中的 user（admin 永远放行）|
| `/admin list / add <user> / rm <user>` | admin | 管理员列表。**第一次** `/admin add` 可 bootstrap（空列表时谁来都行）|
| `/say <user> <text>` | admin | 代发一条消息 |

超出配额会收到友好提示，不打扰 qoder。

### 导出 & 统计
```
/export [n]   # 最近 n 条本会话的消息（默认 20，含双方）
/stats        # 全局统计：事件数 / 今日收发 / 活跃会话 / 黑白名单大小
```

### 欢迎语
新会话第一次发消息时自动发一条：
> 👋 你好，我是 wxbot（qoder lite 驱动）。
> 直接发文字/图片/语音/视频/文件即可，多轮上下文我会记住。
> 发 /help 查看全部命令。

`welcomed.list` 记录已发欢迎语的 chat_key，删掉该文件可重新触发。

### 群聊
- 群里只在 (a) `@bot`，(b) 以 `/` 开头，或 (c) 带媒体 时回复
- 触发后会自动剥掉 `@xxx` 前缀，再走正常流程
- soul/memory/quota 等都按 (account_id × group_id) 维度独立

---

## 5. 媒体 & 多轮

- **图片**：自动解密下载到本地 → 复制进会话 workspace → 用 `--attachment` 传给 qoder
- **语音**：自动 SILK→WAV，附带 prompt 提示模型先听写再回复
- **视频 / 文件**：原样附件
- **多轮**：首轮 `--session-id <UUID>`，后续 `--resume <UUID>`。`/reset` 才会换新 UUID

---

## 6. 高级配置（环境变量）

| 变量 | 默认 | 作用 |
|---|---|---|
| `BOT_HOME` | `~/wxbot-state` | 状态目录 |
| `BOT_MODEL` | `lite` | qoder 默认模型 |
| `QODER_BIN` | `qodercli` | qoder 可执行文件 |
| `PYTHON_BIN` | `python3` | Python 解释器 |
| `WXLINK_BIN` | `~/wxlink.py` | wxlink 路径 |
| `QUOTA_DEFAULT` | `200` | 每会话每日默认配额（0=不限）|

`wxweb.py` 的 host/port 通过命令行：`python3 ~/wxweb.py --host 0.0.0.0 --port 9000`。

---

## 7. Web 监控面板

`http://127.0.0.1:8765` 暗色主题单页应用，每 3 秒自动刷新：

- 🟢 bot 进程状态 / pid / uptime / 登录状态
- 💬 每个活跃会话（peer 名 / soul / model / uuid / 消息数 / last active）
- 📨 事件流（IN / OUT，含媒体标签、群组标签、@bot 标签）
- 📅 定时任务（含 base64 解码后的 prompt）
- 📜 `bot.out` tail 200

API endpoints（用脚本拉数据也行）：
```
/api/status   /api/sessions   /api/events?n=200   /api/crons   /api/log?n=200
```

---

## 8. 调试 & 自检

```bash
~/wxbot.sh --self-test       # 检依赖 + 跑一个 PONG turn
~/wxbot.sh --simulate '<event-json>'   # 喂一条假事件
~/wxbot.sh --cron-fire <to> <key> <b64-prompt>  # 内部用，cron 触发
tail -f ~/wxbot-state/logs/bot.out      # 主日志
tail -f ~/wxbot-state/logs/qoder.err    # qoder stderr
tail -f ~/wxbot-state/logs/events.jsonl # 结构化事件流
```

`--simulate` 不需要登录微信，可以本地完整跑通命令/记忆/技能/配额/欢迎语逻辑。

---

## 9. 迁移到 Linux

三个脚本完全 POSIX，没有 macOS 专属调用，区别只在：
- Linux 上 `crontab` 不需要 TCC 授权，直接能写
- 用 systemd 替代 nohup：
  ```ini
  # /etc/systemd/system/wxbot.service
  [Service]
  ExecStart=/home/you/wxbot.sh
  Restart=always
  Environment=BOT_HOME=/home/you/wxbot-state
  [Install]
  WantedBy=default.target
  ```

---

## 9b. 联网搜索 / AI 图片 / 语音 / Hooks / 多账号 / 自然语言定时（v2 扩展）

### 🌐 联网搜索 `/search` `/news`
- 后端：**Bing**（主）/ **DuckDuckGo HTML**（备）；都不需要 API key，纯 curl + Python 标准库解析。
- `/search <关键词>` → 抓取 top 5 结果 → 喂给 qoder 用本会话上下文综合回答（会消耗一条配额）。
- `/news <关键词>` → 直接返回 top 8 标题+摘要+URL（不调用 qoder，不耗配额）。

```
/search 2024 诺贝尔物理学奖得主
/news   k8s 最新 release notes
```

### 🖼 AI 图片生成 `/image`
- 后端：**pollinations.ai** — 完全免费、无需注册、无 API key，GET URL 即返回图片。
- 中英文 prompt 都行；图片 768×768 JPG，约 2-10 秒生成。

```
/image a tiny red apple on a white background, photo
/image 中国山水画风格的下雪场景
```

> 如果断网或后端挂了会回复 `⚠️ 图片生成失败`。需要换后端只要改 `wxbot.sh` 里的 `image_generate()` 一段。

### 🔊 TTS 语音回复 `/tts`
- 自动检测引擎：macOS 优先 `say`（带 `ffmpeg` 自动转 mp3），Linux 用 `espeak-ng` 或 `piper`，都没有则提示。
- `/tts on` 后，bot 回复同时发文字 + 语音；`/tts off` 关闭；`/tts engine` 查看当前引擎。
- 开关是 **per-chat** 的，存在 `sessions/<key>.tts`。

```
/tts on        # 开
/tts engine    # → TTS 引擎：say
/tts off       # 关
```

### 🪝 Hooks（可编程切面）
往 `~/wxbot-state/hooks/` 丢可执行脚本即可生效，无需重启：

| 文件 | 触发时机 | stdin | stdout 怎么用 |
|---|---|---|---|
| `pre_turn.sh`   | 每次调用 qoder 之前 | 用户文本 | 追加到 prompt 作为 `[Hook context]:` |
| `post_turn.sh`  | 每次 qoder 返回之后 | qoder 回复 | 忽略（适合做日志/转发/告警）|
| `on_command.sh` | 任何 `/command` 被分发时 | 原始命令行 | 忽略（适合做审计/计数）|

环境变量：`WX_HOOK / WX_ACCOUNT / WX_FROM / WX_FROM_NAME / WX_CHAT_TYPE / WX_CHAT_KEY / WX_MODEL`。

示例（让"今天天气"自动注入实时气象数据）：
```bash
# ~/wxbot-state/hooks/pre_turn.sh
#!/usr/bin/env bash
read -r text
if [[ "$text" == *天气* ]]; then
  curl -s 'https://wttr.in/?format=3'
fi
```

`/hooks` 命令可在微信里查看哪些脚本已生效。

### 🗓 自然语言定时 `/cron nl`
- 调用 `qodercli` 单轮把中文 / 英文描述转成 5 段式 crontab，再写入 `crontab -l`。
- 与 `/cron add "<expr>" <prompt>` 共享底层存储，`/cron list` `/cron rm <id>` 通用。

```
/cron nl 每天早上8点提醒喝水
   → ✅ 已添加 wxcron:KEY:ID
     cron: 0 8 * * *  任务: 提醒喝水

/cron nl every 15 minutes ping
   → cron: */15 * * * *  任务: ping
```

### 📱 多微信账号
一台机器同时挂多个微信号，每号独立凭据 / 会话 / 记忆 / 配额。

```bash
# 1. 把账号名加入清单
echo work    >> ~/wxbot-state/accounts.list
echo private >> ~/wxbot-state/accounts.list

# 2. 每个号单独登录（凭据写到 ~/wxbot-state/accounts/<name>/home/.claude/...）
python3 ~/wxlink.py --account work    login
python3 ~/wxlink.py --account private login

# 3. 启动 wxbot —— 会自动为每个 account 起一条 subscribe 循环
~/wxbot.sh
# [2026-...] Starting wxbot ... accounts=work private
```

微信里的命令：
| 命令 | 说明 |
|---|---|
| `/account` / `/account list` | 列出所有账号、标出当前消息来自哪个号 |
| `/account add <name>` *admin* | 加入清单（重启后生效） |
| `/account rm <name>` *admin*  | 从清单移除 |
| `/whoami` | 会显示 `account: <name> (<account_id>)` |

每个事件的 JSON 现在带 `account_name` 字段，会话 key = `sha1(account_name + 0x1f + from)`，所以同一个人在你不同的微信号里看到的会话是 **隔离** 的。

> `default` 账号始终存在，对应 `~/.claude/channels/wechat/`，不写入 `accounts.list` 也能工作（向后兼容单账号模式）。

### 🎛 Web 面板 v2（POST 操作）
打开 <http://127.0.0.1:8765>：

- 状态卡：账号、PID、uptime、model、events.jsonl 大小
- **会话表**：每行带 `reset` / `mute` / `unmute` 按钮
- **事件流**：所有 IN/OUT 实时刷新
- **定时任务**：每行带 `rm` 按钮
- **微信账号**：每行显示是否登录、account_id
- **快捷发送**：选账号 + 填 to + 文本 → POST 排队 → bot 2 秒内代发
- bot.out tail 200 行

所有按钮通过 `POST /api/action` 写一个 JSON 文件到 `~/wxbot-state/commands/`，bot 主循环里的 `cmdq_loop` 每 2 秒扫描并执行（`reset`/`mute`/`unmute`/`cron_rm`/`quota_set`/`cancel`/`send_text`）。

---

## 9c. 自然语言自动路由 · RAG · 进阶 TTS / 图片 / 账号路由（v3 扩展）

### 🤖 自然语言自动调用所有 / 命令（默认开启）
你不再需要打 `/` 也能用全部能力 —— bot 会在每条普通消息进来时做一次轻量意图分类，**自动**改写成对应的 `/cmd`：

| 你直接说 | bot 自动调用 |
|---|---|
| 「搜一下 OpenAI 最近发布了啥」 / 「最新…」 / 「查一下…」 | `/search` |
| 「画一只穿西装的猫」 / 「来张图」 / `draw me a sunset` | `/image` |
| 「每天早上 8 点提醒我喝水」 | `/cron nl 每天早上8点提醒我喝水` |
| 「重置 / 清空 / 重新开始」 | `/reset` |
| 「今天的新闻」 | `/news` |
| 其他普通聊天 | 直接 chat（不改写） |

实现：先做一组中文关键词速判（零成本）；命中不了再请 qodercli `--no-resume` 输出
`{"intent":"...","args":"..."}` JSON（1 次 lite 调用，~1 秒）。

| 命令 | 作用 |
|---|---|
| `/auto on \| off` | 开关本会话的自动路由（默认 on）|

> 还想 100% 手动？直接 `/auto off` 或前缀 `/` 永远是手动模式。

### 📚 RAG 知识库
往 `~/wxbot-state/rag/<chat_key>/*.txt`（或 `_global/*.txt` 全局）丢任意 `.txt`/`.md` 文件，
bot 在每次回答前会**自动**用关键词 + 中文二元语法做 TF 评分，把 Top-3 chunk 注入到 prompt。

```
/rag list                     列出已加载的文档
/rag add <名字> <一段内容>     直接写一段进本会话 RAG
/rag rm <名字>                 删一条
/rag on | off                  per-chat 开关（默认 on）
```

也可以直接：
```bash
echo "公司Wi-Fi 密码 letmein2024" > ~/wxbot-state/rag/_global/wifi.txt
```
之后任何会话问"wifi 密码？" 都会自动命中。

### 🔊 TTS 进阶：音色 / 语速
```
/tts voice                    列出当前引擎可用音色（前 30 个）
/tts voice Mei-Jia            设置音色（举例：macOS 中文音色）
/tts voice -                  恢复默认
/tts rate 220                 设置语速（say wpm；espeak 取 80-450）
/tts rate -                   恢复默认
```
配置 per-chat 持久化在 `sessions/<key>.tts_voice` `.tts_rate`。

### 🖼 /image 多张 / 风格预设
```
/image n=3 a tabby cat                      连出 3 张
/image style=cyberpunk a samurai             加风格后缀
/image n=2 style=水墨 江南春日小桥流水         多张 + 风格
```
内建风格：`cyberpunk` / `oil` / `watercolor` / `水墨` / `pixel` / `anime` / `卡通` / `photo` / `3d`。

### 📱 多账号路由规则
`accounts.list` 第 2、3 列分别是该账号的**默认 soul** 和**默认 model**（首次出现的新会话自动 apply）：

```
# accounts.list
default
work     assistant   pro
private  cat         lite
support  helpdesk    -
```
- `-` 表示不设置该项。
- 已经 `/soul` 或 `/model` 过的会话不会被覆盖（有 `acct_applied` 标记）。
- 想强制重新 apply：删 `~/wxbot-state/sessions/<key>.acct_applied`。

> 这样一台机器同时挂"工作号 + 私号"时：工作号默认是助理 + Pro 模型；私号默认是猫娘 + lite。

---

## 10. 安全与隐私

- 凭据只存在本地 `~/.claude/channels/wechat/account.json`
- 媒体在本机解密，落盘到 `downloads/`；不要把这个目录暴露公网
- `events.jsonl` 包含明文消息内容，用于 Web 面板；如果不想留可设 `EVENT_LOG=/dev/null`
- 公司网络若拦截了 `ilinkai.weixin.qq.com` / `novac2c.cdn.weixin.qq.com`，需要做代理
- qoder 在 `--permission-mode bypass_permissions` 下跑，工作目录是每会话独立的 `workspaces/<key>/`，不会跨会话泄漏；但请勿在敏感目录启动 wxbot

---

## 11. 一句话理解架构

```
 微信用户 → iLink → wechat-clawbot SDK → wxlink subscribe (NDJSON)
   ┌──────────────────────────────────────────────────────────┐
   │ wxbot.sh 事件循环：                                       │
   │   gates(白名单/静音/配额) → 命令解析(/reset /soul …)      │
   │   构建 system prompt = soul + memory + mcp 说明           │
   │   qodercli --model lite --resume UUID --attachment …      │
   │   → 回复 wxlink send-text/send-media                      │
   └──────────────────────────────────────────────────────────┘
                          ▲
                          │ events.jsonl
                          ▼
                       wxweb.py  (http://localhost:8765)
```

---

## 12. 多平台：同时挂 微信 + 飞书/Lark（新增）

`mini_bot` 现在是 **单进程 / 多平台 / 多账号** 的：一个 `bot.sh` 进程可以
同时挂多个微信号（走 wxlink）和多个 Lark/Feishu 机器人（走 lark-cli），
所有对话共享同一套灵魂 / 记忆 / 技能 / RAG / 配额 / cron / 钩子 / Web 面板。

### 12.1 准备 Lark/Feishu

1. 安装 `lark-cli`（参考 `~/bot/README.md` 的部署文档），并已 `auth login`
   完成。每个机器人对应一个 profile，登录时给它起个名字（下文以 `bot` 为例）。
2. 给应用开 `im:message:receive_as_bot`、`im:message:send_as_bot`、`im:resource`、
   `im:message.group_at_msg` 等 scope。
3. 验证：`lark-cli event +subscribe --as bot --event-types im.message.receive_v1`
   能流出 NDJSON。

### 12.2 `accounts.list` 新格式

```
# state/accounts.list
# <platform>:<name> [default-soul] [default-model]
wechat:default
wechat:work     assistant   pro
lark:bot        cat         lite
feishu:groupbot helpful     -
```

- 没有 `:` 前缀的行被视为 `wechat:<name>`（向下兼容）
- 一行启一个 subscriber loop；进程退出自动重启
- 不同 `platform:account` 的会话 key 自动加 `platform` 前缀，互不串号
- 该账号下任何新会话首条消息时，自动套用第 2、3 列指定的默认 soul / model

### 12.3 命令完全等价

所有 `/soul /memory /skill /rag /cron /tts /image /search /news /quota …` 命令
在两个平台行为一致。bot 回复时自动选择正确的传输：

- 微信 → `wxlink send-text/-media`
- Lark → `lark-cli api POST /open-apis/im/v1/messages/{id}/reply`
  （图片走 `/im/v1/images`、文件走 `/im/v1/files` 上传后引用 key 回复）

群聊里多个 @ 的人会以 `[Group context]: multiple people were @-mentioned: …`
注入到 prompt，便于 qoder 一次性逐个回应。

### 12.4 启动 / 停止

```
cd ~/mini_bot
bash bot.sh                  # 前台
nohup bash bot.sh >/tmp/mini_bot.log 2>&1 &   # 后台
```

启动日志会列出每条 subscribers，例如：
```
Subscribers: wechat:default wechat:work lark:bot
```

### 12.5 从旧 `~/wxbot-state/` 迁移

```
mv ~/wxbot-state ~/mini_bot/state
# 或软链
ln -s ~/wxbot-state ~/mini_bot/state
```

旧会话 key 仍然有效；新消息会被重新打上 `platform:account` 前缀，可能让某
个对话第一次显得"重新认识"，是预期的一次性现象。

---

## 13. 新增高级特性（v4）

### 13.1 `/cwd` —— 把对话锁到本地项目目录

默认每个会话的 qoder 工作目录是 `workspaces/<key>/` 沙盒。如果你想让 bot
直接读写某个本地项目（代码、笔记、文档目录），用 `/cwd`：

```
/cwd /Users/me/code/myrepo        # 切换到该目录
/cwd                              # 查看当前 cwd
/cwd clear                        # 恢复默认沙盒
```

之后对话里说 "把 src/index.ts 的导出改成默认导出"，qoder 会真的去改那个
项目里的文件。**慎用**：bot 跑在 `bypass_permissions` 下，会真写盘。

### 13.2 URL-fetch 直读

只要消息里含 `http(s)://`，最多前 3 个 URL 会被 `curl` 拉下来、剥 HTML、
压到 2.5KB / 条，作为 `[Web page] (fetched live):` 上下文注入。

```
帮我总结一下 https://example.com 这篇文章
能从 https://news.ycombinator.com/ 摘 3 条今天的热点吗
```

无需任何命令，自动生效。失败会静默忽略原文继续回答。

### 13.3 `/cron addto` —— 跨会话定时推送

让 cron 在到点时往**另一个会话**（甚至另一个平台！）推一条消息：

```
/cron addto lark:bot:oc_xxxxxxxx "0 9 * * *" 早安，给大群发今天的待办
/cron addto wechat:default:wxid_alice "*/30 * * * *" ping
```

格式：`/cron addto <platform>:<account>:<chat_id> "<cron-expr>" <prompt>`
（`chat_id` 在微信是 `wxid_xxx@im.wechat`，在 Lark 是 `oc_xxx` / `om_xxx`）
列出和删除统一走 `/cron list` / `/cron rm <id>`。

### 13.4 群 @ 多人路由

群聊里多人 @ 你时，bot 会把 mention 列表以 `[Group context]: multiple
people were @-mentioned: A, B` 形式注入 prompt，qoder 会在同一条回复里
分别照顾到（如需逐条单独回，可在 soul 里写明）。

### 13.5 完整自动路由（v3）+ 上述新增能力组合

```
我在 /Users/me/code/myrepo 这个项目里改 README，帮我加一节"高级用法"
→ /cwd 已设置后，直接说改 README 就会落到该目录
能不能帮我每天早 9 点给团队群提醒今天日程？
→ 命中 /cron 自然语言；进一步可换成 /cron addto 推到群里
帮我看下 https://github.com/xxx/yyy 这个仓库主页讲什么
→ 命中 URL-fetch；不需要 /search
```

---

## 14. 目录布局（v4 最终）

```
~/mini_bot/
├── bot.sh                  # 主进程（多平台、多账号）
├── wxlink.py               # 微信桥（wechat-clawbot SDK）
├── web.py                  # Web 面板
├── README.md
└── state/                  # 之前的 ~/wxbot-state
    ├── accounts.list       # 多账号清单（platform:name [soul] [model]）
    ├── souls/  memory/  skills/  rag/  hooks/  tts/
    ├── sessions/           # <key>.uuid / .soul / .cwd / .platform / .account
    ├── workspaces/         # 每会话 qoder 沙盒
    ├── downloads/wechat-*/ downloads/lark-*/
    ├── logs/
    ├── events.jsonl        # Web 面板事件流
    └── commands/           # Web 面板 → bot 命令队列
```


---

## 15. v5：Sub-Agent / 团队管线 / 自动记忆 / 部署 / Web 面板增强

### 15.1 `/agent` —— 临时人格副本

```
/agent researcher 帮我整理 LLM agent 的最新进展
/agent critic 帮我审一下我刚才写的这段代码
/agent translator 把上面这段翻成英文
```

主对话的灵魂、历史、记忆都不会受影响（独立调用，无 --resume）。

### 15.2 `/team` —— 多人格管线

把多个 soul 串成一个加工流水线，前一个人的产出会作为下一个人的上下文：

```
/team set researcher critic editor
/team run 写一段 200 字、关于 LLM 与隐私的短文
```

`/team show` 看当前管线；`/team clear` 清空。回复里每个角色一段，前缀
`━━ <role> ━━`，便于人工挑选。

### 15.3 `/automem` —— 自动事实抽取入记忆

```
/automem on        # 每轮结束后启 1 个后台 qoder 提取 0..3 条 durable facts
/automem off
```

抽到的事实直接 `memory_add`，下一次 build_system_prompt 就会被注入。
不会阻塞回复（后台异步）。

### 15.4 Web 面板增强

- 账号表格新增 `platform`、`label`（platform:name）、`default soul/model` 三列
- 事件流支持平台过滤下拉（全部 / 仅 WeChat / 仅 Lark）
- 事件每行多一个 platform tag
- 快捷发送下拉框现在用 `<platform>:<name>` label，自动选 lark 还是 wechat 传输

### 15.5 一键安装（systemd / launchd + logrotate）

```
cd ~/mini_bot
bash install.sh                # 自动识别平台
bash install.sh systemd        # 强制 Linux systemd user-service
bash install.sh launchd        # 强制 macOS LaunchAgent
bash install.sh none           # 只装日志轮转
```

会写入：
- `~/.config/systemd/user/mini_bot.service`（Linux）/ `~/Library/LaunchAgents/com.minibot.bot.plist`（macOS）
- `~/mini_bot/rotate-logs.sh`（手动也能跑）
- crontab 一条 `0 3 * * *` 调用 rotate-logs.sh：日志 >5MB 切片 / >1天 gzip / >7天删除 / events.jsonl >20MB 截尾保 10MB

管理：
- Linux: `systemctl --user status|restart|stop mini_bot`，`journalctl --user -u mini_bot -f`
- macOS: `launchctl kickstart -k gui/$(id -u)/com.minibot.bot`

### 15.6 端到端冒烟测试

```
bash live-smoke.sh
```

会在临时目录里搭一套 stub（qoder + wxlink + lark-cli + crontab），跑 8 组场景：
WeChat 回复 / Lark 回复 / URL-fetch / `/cwd` / `/cron addto` / `/agent` /
`/team` / `/automem`。预期：`PASS: 11    FAIL: 0`。

任何一次大改动后跑一遍，确认没破回归。

---

## 16. 最终目录布局（v5）

```
~/mini_bot/
├── bot.sh                # 主进程
├── wxlink.py             # 微信桥
├── web.py                # Web 面板
├── install.sh            # systemd / launchd 安装
├── rotate-logs.sh        # （install.sh 生成）日志轮转
├── live-smoke.sh         # 端到端冒烟测试
├── README.md
└── state/
    ├── accounts.list     # platform:name [soul] [model]
    ├── souls/  memory/  skills/  rag/  hooks/  tts/
    ├── sessions/         # <key>.{uuid|soul|cwd|platform|account|team|automem|...}
    ├── workspaces/
    ├── downloads/
    ├── logs/             # service.log / service.err / qoder.err / reply.err / events.jsonl 等
    └── commands/         # Web 面板 → bot 的指令队列
```


---

## 17. v6：Docker / Web 鉴权 / 备份恢复 / Lark 富消息 / 模块化重构

### 17.1 Docker 一键部署

```
cp docker-compose.yml docker-compose.local.yml   # 改一下账号密码 / volume
docker compose up -d
docker compose logs -f bot
```

Dockerfile 装好 bash / jq / python3 / curl / espeak-ng / cron。
**注意**：`qoder` / `wxlink` / `lark-cli` 是平台二进制，请用 `-v` mount 进容器，
docker-compose.yml 里有注释好的示例行。

### 17.2 Web 面板鉴权

环境变量启用 Basic Auth：
```
MINIBOT_USER=admin MINIBOT_PASS=changeme python3 web.py
```
没设 `MINIBOT_USER` 就完全关闭鉴权（默认行为，保持向后兼容）。

### 17.3 会话备份 / 恢复

```
# 本地命令行
bash backup.sh export                  # 全量备份 → state/backups/mini_bot-all-<ts>.tar.gz
bash backup.sh export --account acct1  # 单账号备份
bash backup.sh list
bash backup.sh import state/backups/mini_bot-all-xxx.tar.gz [--force]

# 聊天命令（仅管理员）
/backup create
/backup list
/backup restore <文件名>

# Web 面板
新增 "备份" 卡片：一键创建 + 下载 + 一键恢复
```

备份范围：`sessions/ memory/ souls/ skills/ hooks/ tts/ rag/ accounts.list admins.list whitelist.list mute.list`。
排除：日志、下载缓存、临时工作目录。

### 17.4 Lark 富消息 + 群 @

- **卡片回复**：`/card 标题|内容(支持 markdown)` 仅 Lark 平台触发。
  发出 `msg_type=interactive` 卡片，蓝色 header + markdown 正文。
- **群 @ 回敬**：在 Lark 群里 @ bot 提问，bot 的回复自动 `<at user_id="ou_xxx"></at> ...` 把你 @ 回来。

### 17.5 代码模块化（refactor）

`bot.sh` 从 ~2550 行精简到 ~2330 行，把三个边界清晰的功能块抽到 `lib/`：

```
lib/lark.sh       Lark 收发 + event 订阅（含 Python heredoc）
lib/agents.sh     /agent /team /automem
lib/tts.sh        TTS engine 探测 / 合成 / 音色语速
```

bot.sh 启动时 `source lib/*.sh`，行为完全不变。其他模块未拆，是因为它们和
`handle_event` 状态机耦合较紧，强拆反而降低可读性。

### 17.6 扩展后的端到端冒烟

```
bash live-smoke.sh    # 13 个场景 / 19 个断言
```

新增的 5 个场景：`/backup create`、`/card`、Lark group @ mention、
`backup.sh export 兼容性`、Web 鉴权（401 / 200）。

---

## 18. 项目结构（v6 终态）

```
~/mini_bot/
├── bot.sh                # 主进程（~2330 行）
├── lib/
│   ├── lark.sh           # Lark/Feishu 传输 + 事件订阅
│   ├── agents.sh         # /agent /team /automem
│   └── tts.sh            # TTS
├── wxlink.py             # 微信桥
├── web.py                # Web 面板（含 Basic Auth + backup UI）
├── backup.sh             # 备份/恢复 CLI
├── install.sh            # systemd / launchd / logrotate 安装
├── rotate-logs.sh        # 日志轮转
├── live-smoke.sh         # 端到端冒烟（13 场景 / 19 断言）
├── Dockerfile            # 容器化
├── docker-compose.yml    # bot + web 双服务编排
├── README.md
└── state/
    ├── accounts.list  souls/  skills/  memory/  hooks/  tts/  rag/
    ├── sessions/  workspaces/  downloads/  logs/  commands/
    ├── backups/          # tar.gz 备份目录
    ├── mute.list  admins.list  whitelist.list  welcomed.list
    └── mcp.json (optional)
```

---

## 19. v7：GitHub OAuth / CI / i18n / /usage

### 19.1 Web 面板：GitHub OAuth 登录

三档鉴权，按环境变量优先级自动选择：

| 配置的 env | 模式 |
|---|---|
| `MINIBOT_GH_CLIENT_ID` + `MINIBOT_GH_CLIENT_SECRET` | **GitHub OAuth**（推荐）— 浏览器跳 GitHub 授权 → cookie session |
| `MINIBOT_USER` + `MINIBOT_PASS`                    | **HTTP Basic Auth** |
| *(都不设)*                                          | **开放**（只建议 loopback） |

可选白名单：`MINIBOT_GH_ALLOWED_USERS=hlx1996,foo,bar`（不在名单的 GitHub 用户登录后直接被拒）。

OAuth App 创建步骤：
1. https://github.com/settings/developers → New OAuth App
2. Callback URL：`http://<your-host>:8787/oauth/callback`
3. 把 Client ID / Secret 填到 docker-compose 的 environment 或 systemd 的 EnvironmentFile

测试场景里走 `MINIBOT_OAUTH_MOCK=1` 短路 GitHub 调用，不需要真账号。

### 19.2 GitHub Actions CI

`.github/workflows/ci.yml` 每次 push / PR：
- `bash -n` 全部 .sh + `python -m py_compile` 全部 .py
- 跑 `live-smoke.sh`（13 场景 / 24 断言）
- `docker build` 镜像构建烟测

### 19.3 i18n（English /help）

```
/lang en       # switch to English (per-chat)
/lang zh       # 切回中文
/help          # uses current language
```

完整 English 文档：[README.en.md](./README.en.md)

### 19.4 `/usage` 用量统计

```
/usage           # 默认今天
/usage day
/usage week
/usage all
```

输出（基于 events.jsonl 实时聚合，无需额外存储）：
- 总计收 / 发条数 + 字符总数
- 按账号 Top
- 按用户 Top10

Web 面板也加了"用量"卡片，三档时间窗下拉切换 + 实时刷新。

### 19.5 扩展后的 live-smoke

```
bash live-smoke.sh    # 16 场景 / 24 断言，全绿
```

新增：`/usage` 报表、`/lang en` + 英文 help、OAuth 未登录重定向、OAuth cookie 放行。
