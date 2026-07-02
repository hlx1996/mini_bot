# mini_bot

> 一个 bash 写的聊天机器人。把你的 **微信** 或 **飞书** 接到 qoder-cli（或任何命令行 LLM），用户聊天，bot 回复。
>
> English: [README.en.md](./README.en.md)
>
> **📖 66 core + 14 extra（opt-in）共 80 插件完整索引 + 示例 → [PLUGINS.md](./PLUGINS.md)**
>
> **🧪 全量测试用例 + 回归脚本 → [TESTING.md](./TESTING.md)**

---

## 0. 它干嘛？

- 微信/飞书里发一句话 → bot 调 qoder-cli → 回你一句话。
- 上下文自动续；`/reset` 重开。
- 支持文字 / 图片 / 视频 / 语音 / 文件作为输入。语音会先经 ASR 转成文字再交给模型（见 §语音识别）。
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
| `/rag watch [Nh\|off]` | 定时自动 refresh（默认每 6h，写入系统 crontab） |
| `/metrics [1h\|24h\|7d\|all]` | 收/回/失败/字符/≈token/延迟 p50·p95，按平台分组 |
| `/metrics chat` / `/metrics errors` | Top10 活跃会话 / 最近失败回复 |
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

### Skills / Souls — 两种格式

mini_bot 同时支持 **两种 skill 文件格式**：

1. **`.txt` — 模板技能（轻量、参数化）**
   - 文件放 `state/skills/<name>.txt`
   - 用 `{{1}}` 占位第一个参数，`{{rest}}` 占位剩余
   - 例：`state/skills/translate.txt` 内容是 `把下面翻译成 {{1}}：\n\n{{rest}}`
   - 调用：`/skill translate en hello world` → 替换后整句发给 qoder

2. **`.md` — Anthropic Skill 格式（人格 / 持久身份）**
   - 文件放 `state/skills/<name>.md`（也可放 `state/skills/<subdir>/<name>.md`）
   - 顶部 YAML frontmatter：
     ```yaml
     ---
     name: liu-yuchen
     description: 刘雨尘，自动驾驶算法工程师
     ---
     ```
   - 下面写人物背景 / 工作职责 / 说话风格，可任意长
   - 调用：
     - `/skill <name>` → **把它作为本会话人格**（持续，等同 `/soul`）
     - `/skill <name> <任务>` → 一次性以该人格回答（不污染会话）
     - `/skill unstick` → 退出，回到 default

```text
/skill list                   # 列出全部，显示 description
/skill show 数字刘雨尘         # 查看正文
/skill 数字刘雨尘              # 切换人格（重置会话）
/skill unstick                # 回到 default
/soul 数字刘雨尘               # 等同 /skill 数字刘雨尘（souls/skills 互通）
```

### Skills 自动选择（按关键词路由）

类似 `/route` 按关键词换模型，`/skill route` 按关键词把这一轮的 system prompt **换成某个 skill 的正文**（不污染 stuck soul）：

```text
/skill route add Robotaxi|路网|自动驾驶 数字刘雨尘
/skill route add (天气|weather) weather global
/skill route                              # 列出
/skill route rm 1
/skill route clear [global|all]
```

每条消息匹配本会话路由 → 全局路由，**首条命中**的 regex 决定本轮 skill。
只影响当前回复；要长期固定身份用 `/skill <name>`（stick）或 `/soul <name>`。

### Memory — 全局记忆 / 最近 / 检索

```text
/memory                       看本会话 + 全局
/memory add 我喜欢喝拿铁       记到本会话
/memory add -g 我用 macOS      记到全局（所有会话可见）
/memory recent 20             最近 20 条（本会话+全局合并）
/memory search 拿铁           关键词检索
/memory clear [-g|all]        清本会话 / 全局 / 全部
```

全局记忆自动注入 **每个会话的 system prompt**，适合放偏好（"我喜欢简洁回复"）、环境（"我在 macOS"）这类跨群跨人的事实。

### MCP — 测试 / 模板

```text
/mcp                       # 没配置时给完整最小模板（filesystem + fetch）
/mcp test filesystem       # 实际 spawn，5s 内活着 / 出 "running" 标志算 ok
/mcp reload                # jq 校验 mcp.json 合法性
```

带 5 个常用服务器的示例：`examples/mcp.json`。

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

### 内置 OpenClaw 风格插件

- `/diagram <需求>`（别名 `/画图`）：把自然语言转成 mermaid 流程图/时序图/类图，
  调 mermaid.ink 公网服务渲染 PNG，发回聊天。无需安装 mmdc，飞书机器人身份用
  `--image` 上传（用户身份没权限会自动降级成发链接）。
  也支持直接给源码：`/diagram mermaid: graph LR; A-->B`。
- `/run <py|bash|js> <code>`（别名 `/exec`）：代码沙箱。`ulimit -t 15 -v 524288
  -f 10240` + 跨平台 timeout（GNU timeout / gtimeout / perl alarm 三选一）。
  stdout/stderr 截到 4KB。
- `/ocr [图片路径]`（别名 `/识图`）：图转文字。优先 tesseract（中文需要装
  `tesseract-lang-chi-sim`），没装就用 qoder 的多模态当 fallback。
  不给路径时自动找本会话最近一张图。
- `/agent route add <regex> agent:<soul>|team [global]`：和 `/skill route` 一样
  的关键词→agent 自动触发，命中后会把消息重写成 `/agent <soul> <text>` 或
  `/team run <text>` 再分发。
- `/web <url> [问题]`：抓网页 → 提取正文（python `html.parser` 剥标签）→ 让
  qoder 总结要点。可选 `[问题]` 让总结围绕该问题展开。
- `/translate-doc <url|text> [target=zh|en|...]`（别名 `/翻译`）：复用 `/web`
  的剥离逻辑，整篇翻译为目标语言。默认 `target=zh`。
- `/calc <expr>`：纯 python AST 沙箱表达式计算。支持 `sqrt log sin pi e` 等
  `math` 函数；遇到 `__import__` / 函数调用未在白名单内一律拒绝。
- `/image [n=N] [style=…] <提示词>`（别名 `/img` `/画`）：默认走 pollinations
  + `model=flux`（免 key），可切换 `IMAGE_ENGINE=hf` 走 HuggingFace Inference
  API（需 `HF_TOKEN`，模型 `HF_IMAGE_MODEL`，默认
  `black-forest-labs/FLUX.1-schnell`）。
- `/browse <url>`：playwright 后台无头浏览，截图 + 提取正文 + qoder 总结。
  默认每次起一个干净 chromium；设 `USE_LOCAL_CHROME=1` 时改为通过 CDP 接到
  `http://localhost:9222`（先 `chrome --remote-debugging-port=9222
  --user-data-dir=~/.chrome-debug`），可复用已登录态。
- `/video <提示词>`：通过 playwright + CDP 自动操作 Hailuo (海螺) 网页生成
  视频（纯免费、需先在本地 Chrome 里登录好）。需要打开 9222 调试端口的
  Chrome；命令本身不弹窗，全程后台。
  > 安装 playwright：`cd ~/Projects/mini_bot && npm install playwright && \
  >   npx playwright install chromium`
- `/weather <地名>`（别名 `/天气`）：查天气，走 wttr.in（免 key、无需代理）。
- `/qrcode <文本|URL>`（别名 `/二维码`）：生成二维码。本地有 `qrencode` 命令
  时走离线，否则用 api.qrserver.com。
- `/shorturl <url>`（别名 `/短链`）：短链接，先 tinyurl 再 is.gd 兜底。
- `/stock <ticker>`（别名 `/股票`）：股票/加密报价。A股/港股走腾讯免费接口
  （symbol 形如 `sh600519`/`sz000001`/`hk00700`），美股/加密走 Yahoo
  Finance（在大陆可能被墙）。
- `/paper <arxiv-id|url|关键词>`（别名 `/论文`）：三档源轮询 ——
  **OpenAlex**（默认，免 key、限速宽松）→ **arXiv**（公共 API，有 3 次重试）→
  **Semantic Scholar**（设 `SEMANTIC_SCHOLAR_KEY` 后启用，[申请入口](https://www.semanticscholar.org/product/api#api-key-form)）。
  拿到摘要后让 qoder 翻成中文 + 5 条要点。
- `/movie <片名> [year=YYYY] [lang=zh|en]`：查电影，Wikipedia OpenSearch +
  REST summary API，无需 key。
- `/recipe <食材或菜名> [n=3]`：查菜谱，TheMealDB（英文菜谱库），中文输入会
  自动让 qoder 翻译成英文再查。
- `/translate-image [target=zh|en|...] [图片路径]`：图片 OCR + 翻译。复用
  `/ocr` 的 tesseract / 多模态降级链，再让 qoder 翻成目标语言。不给路径时
  自动取本会话最近一张图。
- `/github owner/repo | @user | <关键词>`：GitHub 仓库/用户/搜索。
  无 key 限速 60/hr，配置 `GITHUB_TOKEN` 提升到 5000/hr。
- `/youtube <url|关键词>`：YouTube 视频信息或搜索。优先 `yt-dlp`
  （`pip install --user yt-dlp`，会被 watchdog 自动加进 PATH），兜底
  noembed.com 元数据 + piped 公开实例。
- `/map <地名>`：Nominatim 地名 → 经纬度 + OSM/高德链接 + staticmap.openstreetmap.de
  一张静态地图。免 key。
- `/currency <金额> <FROM> <TO>`：汇率换算，open.er-api.com，免 key。
  支持 `/currency 100 USD CNY` 也支持 `/currency USD CNY`（按 1 单位查）。
- `/wiki <关键词> [lang=zh|en|ja|...]`：维基百科摘要（REST API，免 key）。
- `/dict <英文单词>`：英文词典（dictionaryapi.dev，免 key，含音标 / 释义 / 例句 / 近义词）。
- `/pypi <pkg>` / `/npm <pkg>` / `/docker <image>`：包/镜像信息，pypi.org /
  registry.npmjs.org / hub.docker.com 公开 API，全部免 key。
- `/code <q>`：GitHub 代码搜索，**必须** `GITHUB_TOKEN`（GitHub 强制登录）。
- `/plugins list|info|disable|enable|reload`：插件管理。`disable/enable` 把插件
  写到 `$BOT_HOME/plugins.disabled`，重启 bot 后生效。`/plugins` 自身不能被禁。
- `/hn [N=10]`：Hacker News Top（firebaseio，免 key）。
- `/reddit <sub> [n=10]`：Reddit 热帖。Reddit 对匿名访问限速较严，频繁调用会 429。
- `/translate [target=zh|en|...] <文本>`：纯文本翻译（让 qoder 翻），保留 markdown。
- `/poem [random|<关键词>]`：诗词。无关键词走 jinrishici.com 随机；有关键词让
  qoder 选一首并解读。
- `/idiom <成语>`：中文成语解释（拼音/释义/出处/典故/用法/近反义词）。
- `/pomodoro <分钟> [备注] | list | cancel <PID>`：番茄钟，后台 sleep + 到点
  自动回 IM 提醒。
- `/alias [add|rm|clear|list]`：用户自定义命令别名。`/alias add /yt /youtube`
  即时生效（plugin_dispatch 在每次消息时读 `$BOT_HOME/aliases/*.tsv`），
  支持 `-g` 全局别名；仅能别名到 plugins 提供的命令。

> 以上插件除模型/浏览器外都是纯命令行 + 公共免费 API，可以在公司机内网映射
> 出口直跑；要离线运行的请用 `/diagram` `/calc` `/run` `/qrcode (qrencode)`
> `/ocr (tesseract)`。

#### Phase B：原生命令也已插件化

下列原本写在 `bot.sh` case 分支里的命令，已经搬到 `plugins/` 下，方便单独
关闭/替换（直接删对应 `plugins/*.sh` 即可，bot.sh 里的旧分支仍然兜底）：

- `plugins/pin.sh` — `/pin list|on|off|add|rm`（常驻提示词）
- `plugins/stats.sh` — `/stats` `/usage` `/export` `/quota`
- `plugins/backup.sh` — `/backup`（管理员）
- `plugins/admin.sh` — `/admin` `/whitelist` `/lang`
- `plugins/mute.sh` — `/mute` `/unmute` `/whoami` `/say`
- `plugins/core.sh` — `/model` `/status` `/cancel` `/news` `/hooks` `/card`

### 插件 smoke test

```
bash scripts/plugin-smoketest.sh             # 静态检查 + 联网 ping
bash scripts/plugin-smoketest.sh --no-net    # 跳过联网
```

- 静态：`bash -n` 语法 / 至少注册一个命令 / handler 签名 / CJK-跟-`$var` 模式
- 联网：对 14 个第三方 API 的 5 秒可达性探测
- 退出码 = 静态失败的插件数

GitHub Actions：`.github/workflows/plugin-smoketest.yml` 在改动 `plugins/`、
`lib/plugins.sh` 或 `scripts/plugin-smoketest.sh` 时自动跑静态检查（联网部分
仅做参考，不阻塞 PR）。

### 智能记忆检索（BM25 + 字符二元）

`/memory search <kw>` 默认精确 grep；空命中时自动走 `lib/memory_search.py` 的
BM25 + 字符二元 ranking（纯 stdlib，对中英都 OK），返回 top-8 带 score。

### 性能 / 成本调优（默认全部开启）

mini_bot 自带一组省 token + 提升响应速度的开关，默认启用、无需配置；想完全
关掉某项把对应变量设成 `0` 即可。逻辑都集中在 `lib/perf.sh`：

| 行为 | 默认 | 怎么关 / 调 |
|---|---|---|
| **lazy MCP 注入**：消息里没出现 MCP 工具关键词时不挂 `--mcp-config`，直接省一大块系统提示 | on | `BOT_MCP_LAZY=0`（始终挂） |
| **短问题回复缓存**：≤30 字符的私聊文本 SHA1 命中即原样回放，TTL 1h | on | `BOT_REPLY_CACHE=0`；`BOT_REPLY_CACHE_TTL=<秒>`；`BOT_REPLY_CACHE_MAXLEN=<字符>` |
| **注入上下文硬上限**：RAG/pin/URL 抓取/hooks 总和上限 4000 字符（≈1100 token），超出就 clip | on | `BOT_INJECT_MAX=<字符>` |
| **长会话自动压缩**：累计字符超阈值时后台让 qoder 总结 5-8 条要点写进 memory，再 reset session | on | `BOT_AUTO_COMPRESS=0`；`BOT_COMPRESS_AT=<字符，默认 120000>` |
| **automem 频控**：`/automem on` 时仅在用户消息 ≥80 字 + 每 5 轮抽一次，避免每轮都开个子进程提取 | on | `BOT_AUTOMEM_MINLEN=<字符>`；`BOT_AUTOMEM_EVERY=<轮>` |
| **plugins 懒加载**：启动只扫 manifest（一次 awk），首次匹配到 `/cmd` 才 source 插件文件 | on | `BOT_PLUGIN_LAZY=0`（启动即全部 source） |
| **system_prompt mtime 缓存**：souls/global memory 没变就直接读 cache，不重拼字符串 | on | （删 `state/.cache/sys_prompt/<key>` 强制重建） |
| **快速路径短消息**：≤80 字符且没附件的文本走 `--reasoning-effort low --max-output-tokens 1500` | on | `BOT_FASTPATH_MAXLEN=<字符>`；`BOT_EFFORT=low\|medium\|high`；`BOT_MAX_OUTPUT_TOKENS=<n>` |
| **意图直跳**：翻译 / TTS / 天气 / cron / 新闻 等措辞清晰时绕开 LLM 意图分类，直接路由到对应插件 | on | （在 `intent_shortcut` 里调 patterns，必要时 fork 改） |

观测：`tail -f state/logs/bot.log` 能看到 `REPLY-CACHE hit`、`mcp=0|1`、
`URL-FETCH injected (+N chars; used=N)`、`AUTO-COMPRESS`、`AUTO-ROUTE` 等
诊断行，对应上面每条优化是否触发。

### Fuyao 私有推理网关

`/model select` 中提供三个 Fuyao 内部模型（绕过 qodercli，直连公司 GPU 推理网关）：

| 编号 | 模型 | 底层 | 上下文 |
|---|---|---|---|
| 15 | Fuyao-DeepSeek | deepseek-v4-flash | 128K |
| 16 | Fuyao-GLM | glm-5.2 | 256K |
| 17 | Fuyao-Kimi | kimi-k2.6 | 256K |

**配置（`.env`）：**

```bash
FUYAO_API_KEY=<your-fuyao-api-key>
# FUYAO_BASE_URL=https://fuyao-ai-gateway.xiaopeng.link/v1  # 默认即此
```

获取 key：<https://fuyao-v3.xiaopeng.link/#/home> → 用户中心 → API Key。

**使用：** 聊天里发 `/model select`，选 15/16/17 切换。Fuyao 模型为纯聊天（无工具/MCP/session），但仍注入 memory/pin 长期记忆。

### 加密保存对话/记忆

```bash
export MINIBOT_ENCRYPT_KEY="一个你记得住的密码"
bash bot.sh run
```

启用后 `state/memory/*.txt` 自动 AES-256 加密落盘（文件后缀 `.enc`）。
不设这个变量就跟以前一样（明文，零迁移）。

### 语音识别（ASR）

用户发的语音消息会先用 `ffmpeg` 解码成 16k 单声道 wav，再转成文字交给模型——
**不再**把原始 Opus 音频当附件硬塞给 qoder（那样既听不懂又会把会话上下文撑爆）。
没装任何后端时，bot 会直接告诉用户「语音暂时识别不了，请改发文字」。

后端按优先级自动探测：`openai → azure → whisper-cpp → faster-whisper`，
也可用 `ASR_ENGINE` 强制指定。语言默认自动识别，可用 `ASR_LANG=zh` 给提示。

**最快：本地离线（免费、隐私，不上传语音）**

```bash
brew install whisper-cpp                      # 提供 whisper-cli
mkdir -p ~/.qoder/models/whisper && cd "$_"
curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
```

然后在 `.env` 里写：

```bash
ASR_ENGINE=whisper-cpp
WHISPER_CPP_MODEL=/Users/你/.qoder/models/whisper/ggml-small.bin
```

重启 bot 即可（`scripts/stop.sh && nohup scripts/watchdog.sh &`）。
模型选择：`tiny`(快/糙) → `base` → `small`(推荐) → `medium` → `large-v3`(慢/准)。

**云端（更准，按量计费）**：设 `OPENAI_API_KEY` 走 Whisper API，
或复用上面 Azure 的 `AZURE_SPEECH_KEY/REGION` 走 Azure 语音转文字。
完整可选项见 `.env.example` 的「ASR」段。

### TTS 高级：Azure 神经语音（情感 / 多语言）

默认 TTS 用本机 `say`（仅 macOS）或 `espeak-ng`。如果你要：

- 在 **Linux** 上有高质量语音
- 中文也想要 **情感**（开心 / 难过 / 撒娇 / 客服 / 新闻 …）
- 不想装 GPU 模型

→ 接 **Azure Cognitive Services Speech**（免费层 F0 = 50 万字/月，足够个人用）。

**注册（5 分钟）：**

1. 浏览器打开 <https://portal.azure.com>，登录（没账号就注册，要绑卡但 F0 不扣费）。
2. 顶部搜 **Speech services** → 点 **创建**。
3. 资源组随便建一个；**定价层** 一定要选 **Free F0**；区域选离你近的（`eastasia` / `japaneast` / `eastus`）。
4. 创建完 → 进资源 → 左侧菜单「**密钥和终结点**」→ 复制 **KEY 1** 和 **位置/区域**（如 `eastus`）。

**配置：**

```bash
cd ~/Projects/mini_bot
cp .env.example .env
# 编辑 .env，填进去：
#   AZURE_SPEECH_KEY=你刚复制的key
#   AZURE_SPEECH_REGION=eastus
./scripts/stop.sh && nohup ./scripts/watchdog.sh >/dev/null 2>&1 & disown
```

**验证：**

聊天里发 `/tts engine` → 应当显示 `azure`。
发 `/tts on`，再发 `/tts style 晓晓·愉悦`，再发任一句话，bot 回复的同时会发一条带情感的语音。

**voice 格式：** `<voice-name>[:style[:degree]]`，例：

| 用法 | 效果 |
|---|---|
| `/tts voice zh-CN-XiaoxiaoNeural` | 晓晓（默认女声） |
| `/tts voice zh-CN-XiaoxiaoNeural:cheerful` | 晓晓开心版 |
| `/tts voice zh-CN-XiaoxiaoNeural:sad:2` | 晓晓难过（强度 2，最大 2） |
| `/tts voice en-US-JennyNeural` | 英文 Jenny |

所有可用 voice + style 见 <https://learn.microsoft.com/azure/ai-services/speech-service/language-support>。

发 `/tts style list` 看 mini_bot 内置的中文预设（共 20 个）。

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
| `BOT_EFFORT` | qoder 推理强度 `low\|medium\|high`（默认 medium，快速路径用 low） |
| `BOT_MAX_OUTPUT_TOKENS` | 单轮回复 token 上限（默认根据消息长度 1500 / 4000 自适应） |
| `BOT_FASTPATH_MAXLEN` | 短消息走 fast-path 的字符阈值（默认 80） |
| `BOT_MCP_LAZY` | `0` 关闭 lazy MCP，始终挂 `--mcp-config`（默认 1） |
| `BOT_INJECT_MAX` | 单轮注入上下文（RAG+pin+URL+hooks）总字符上限（默认 4000） |
| `BOT_REPLY_CACHE` / `BOT_REPLY_CACHE_TTL` / `BOT_REPLY_CACHE_MAXLEN` | 短消息回复缓存开关 / TTL 秒 / 命中长度上限 |
| `BOT_AUTO_COMPRESS` / `BOT_COMPRESS_AT` | 长会话自动压缩开关 / 触发阈值（默认 120000 字符） |
| `BOT_AUTOMEM_MINLEN` / `BOT_AUTOMEM_EVERY` | `/automem` 抽取的长度门槛 / 频率（默认 80 字、每 5 轮） |
| `BOT_PLUGIN_LAZY` | `0` 关闭插件懒加载，启动即 source 全部（默认 1） |

---

## 9. 测试

```bash
bash live-smoke.sh    # 期望 PASS: 28  FAIL: 0
```

CI 见 `.github/workflows/ci.yml`，每次 push 自动跑。

---

## 10. License

MIT
