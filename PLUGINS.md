# mini_bot 插件大全

截至本文档发布，仓库共 **80 个插件**（66 个 `plugins/` core + 14 个 `plugins-extra/` opt-in），
注册了 **97+ 个命令**（含别名）。

> **Core / Extra 双层**
> - `plugins/` 默认全部加载，覆盖 90% 日常用法（dev 工具、文本、网络、查询、提醒）。
> - `plugins-extra/` 默认全部 **不加载**，按需 opt-in：
>   ```
>   /plugins extra list                # 列出 extras
>   /plugins extra enable anime        # 写入 state/plugins.extra.enabled
>   /plugins extra disable anime
>   PLUGINS_EXTRA_ALL=1                # 环境变量全开
>   ```
>   当前 extras：`anime` `manga` `lyrics` `movie` `stock` `hn` `reddit` `video`
>   `broadcast` `code_search` `docker` `npm` `pypi` `translate_image`
>   （多媒体/特定平台 API/重依赖 placeholder）。

所有插件都在聊天里直接用：把命令当一句普通消息发给 bot 即可。

> 在 IM 里发 `/commands` 可让 bot 把当前注册的所有命令吐出来（按字母序）。
> 发 `/help` 则是内置的中英文双语分组帮助。

## 目录

- [A. 必备 / Bot 管理](#a-必备--bot-管理)
- [B. 开发者工具](#b-开发者工具)
- [C. 网络 / 域名 / DNS](#c-网络--域名--dns)
- [D. Web 抓取 / 搜索 / 总结](#d-web-抓取--搜索--总结)
- [E. 内容查询（百科 / 词典 / 论文 / 包）](#e-内容查询百科--词典--论文--包)
- [F. 生活 / 提醒 / 时间](#f-生活--提醒--时间)
- [G. 娱乐 / 文化](#g-娱乐--文化)
- [H. 文本 / 编码转换](#h-文本--编码转换)
- [I. 多媒体 / 创作](#i-多媒体--创作)
- [J. 高级 / Agent / Skill](#j-高级--agent--skill)

---

## A. 必备 / Bot 管理

| 命令 | 一句话 | 示例 |
|---|---|---|
| `/help` | 内置帮助（中英双语） | `/help` |
| `/commands` (alias `/cmds`) | 列出所有 plugin 命令 | `/cmds` |
| `/reset` | 清空当前会话记忆 | `/reset` |
| `/model [name]` | 查看 / 切换模型 | `/model lite` |
| `/status` | bot 状态 | `/status` |
| `/cancel` | 中止当前请求 | `/cancel` |
| `/lang [en|zh]` | 切换 /help 语言 | `/lang en` |
| `/whoami` | 看自己的 ID / 名字 | `/whoami` |
| `/say <text>` | 让 bot 复读 | `/say hello` |
| `/mute` / `/unmute` | 屏蔽 / 解除某人 | `/mute @Alice` |
| `/admin add|rm|list` | 管理员名单 | `/admin add open_id_x` |
| `/alias [add|rm|clear|list]` | 自定义命令别名 | `/alias add /yt /youtube` |
| `/plugins list|info|disable|enable|reload` | 插件管理 | `/plugins disable joke` |
| `/pin list|on|off|add|rm` | 常驻提示词 | `/pin add 用中文回答` |
| `/stats` `/usage` `/export` `/quota` | 用量统计 | `/stats` |
| `/backup [now|list|restore]` | 备份会话/状态（管理员） | `/backup now` |
| `/metrics` | 插件调用次数排行 | `/metrics` |
| `/news <关键词>` | 新闻搜索（联网） | `/news AI` |
| `/hooks` | hook 信息 | `/hooks` |
| `/card` | 名片 | `/card` |

## B. 开发者工具

| 命令 | 一句话 | 示例 |
|---|---|---|
| `/base64 enc|dec <text>` | base64 编解码 | `/base64 enc hello world` |
| `/hash <md5|sha1|sha256|sha512> <text>` | 哈希 | `/hash sha256 hello` |
| `/uuid [n]` | 生成 n 个 UUIDv4 | `/uuid 5` |
| `/json fmt|min|get <内容>` | JSON 格式化 / 路径取值 | `/json fmt {"a":1}` |
| `/regex <pat> ::: <text>` | 正则测试（含 groups） | `/regex \d+ ::: ord 42` |
| `/urltool enc|dec|parse <url>` | URL 编解码 / 分解 | `/urltool parse https://x.com/y?a=1` |
| `/diff <a> ::: <b>` | 文本 diff -u | `/diff foo bar ::: foo baz` |
| `/wc <text>` | 行数/词数/字符数/CJK 数 | `/wc Hello 你好` |
| `/pw [len] [ns]` | 随机密码（ns=不含符号） | `/pw 24` |
| `/calc <expr>` | python AST 安全计算 | `/calc sqrt(2)*pi` |
| `/run <py|bash|js> <code>` | 代码沙箱（ulimit） | `/run py print(2+2)` |
| `/code <q>` | GitHub 代码搜索（需 GITHUB_TOKEN） | `/code language:go fsnotify` |
| `/gitignore <lang,...>` | .gitignore 模板 (gitignore.io) | `/gitignore python,node,macos` |
| `/license <key>` | 开源协议模板 (GitHub API) | `/license mit` |
| `/tldr <cmd>` | tldr-pages 简明示例 | `/tldr tar` |
| `/cheat <cmd>[/topic]` | cheat.sh | `/cheat python/list comprehension` |

## C. 网络 / 域名 / DNS

| 命令 | 一句话 | 示例 |
|---|---|---|
| `/ip [addr]` | IP 地理（ip-api.com） | `/ip 8.8.8.8` |
| `/dns <host> [type]` | Google DoH JSON | `/dns github.com MX` |
| `/whois <domain>` | 本机 whois / rdap.org | `/whois google.com` |
| `/headers <url>` | HTTP 响应头 | `/headers https://example.com` |
| `/cidr <CIDR>` | 网段计算（v4/v6） | `/cidr 192.168.1.0/24` |
| `/shorturl <url>` | tinyurl + is.gd | `/shorturl https://a.long/url` |
| `/qrcode <text|url>` | 二维码（本地 qrencode 优先） | `/qrcode https://github.com` |

## D. Web 抓取 / 搜索 / 总结

| 命令 | 一句话 | 示例 |
|---|---|---|
| `/web <url> [问题]` | 抓正文 → qoder 总结 | `/web https://news.ycombinator.com 总结今天热点` |
| `/browse <url>` | playwright 无头浏览（可复用本地登录态） | `/browse https://twitter.com/x` |
| `/translate-doc <url|text> [target=zh]` | 整篇翻译 | `/translate-doc https://example.com` |
| `/feed <rss-url>` | RSS/Atom 最近 5 条 | `/feed https://hnrss.org/frontpage` |
| `/readlater add|list|read|rm|clear` | 稍后读 + /web 总结 | `/rl add https://post.dev/x` |
| `/news <关键词>` | 联网搜索 | `/news 大语言模型` |
| `/digest now [小时]|add <cron>|rm` | 聊天摘要 | `/digest now 24` |

## E. 内容查询（百科 / 词典 / 论文 / 包）

| 命令 | 一句话 | 示例 |
|---|---|---|
| `/wiki <kw> [lang=zh]` | 维基百科摘要 | `/wiki 量子计算 lang=zh` |
| `/dict <word>` | 英文词典（音标/释义/例句） | `/dict ephemeral` |
| `/translate [target=zh] <text>` | 纯文本翻译 | `/translate target=en 你好世界` |
| `/idiom <成语>` | 成语解释（拼音/出处/典故） | `/idiom 守株待兔` |
| `/poem [random|关键词]` | 诗词（jinrishici 或 qoder 选） | `/poem 夜雨` |
| `/paper <arxiv-id|doi|kw>` | OpenAlex+arXiv+S2 三档 | `/paper 2310.06825` |
| `/github owner/repo \| @user \| kw` | GitHub 仓库/用户/搜索 | `/github torvalds/linux` |
| `/pypi <pkg>` | PyPI 包信息 | `/pypi requests` |
| `/npm <pkg>` | npm 包信息 | `/npm express` |
| `/docker <image>` | Docker Hub 镜像信息 | `/docker library/nginx` |
| `/recipe <食材> [n=3]` | 菜谱（TheMealDB） | `/recipe chicken` |
| `/movie <title>` | 电影（iTunes / Wikipedia） | `/movie inception` |
| `/anime <kw>` | 动漫（jikan.moe） | `/anime naruto` |
| `/manga <kw>` | 漫画（jikan.moe） | `/manga onepiece` |
| `/lyrics <artist> - <title>` | 歌词（lrclib.net） | `/lyrics Adele - Hello` |
| `/hn [N=10]` | Hacker News Top | `/hn 5` |
| `/reddit <sub> [n]` | Reddit 热帖 | `/reddit programming 10` |
| `/youtube <url|kw>` | YouTube 视频信息/搜索 | `/youtube dQw4w9WgXcQ` |
| `/joke [zh|en]` | 随机笑话（默认中文让 qoder 编） | `/joke en` |
| `/quote` | 英文名言（zenquotes/quotable） | `/quote` |

## F. 生活 / 提醒 / 时间

| 命令 | 一句话 | 示例 |
|---|---|---|
| `/timer <90s|5m|2h|22:30> [备注]` | 通用 timer | `/timer 5m 开会` |
| `/pomodoro <分钟> [备注]` | 番茄钟 | `/pomodoro 25 写代码` |
| `/calendar add|list|rm|clear` | 日历提醒（后台 watcher） | `/cal add 2026-01-01 09:00 元旦` |
| `/notes add|list|rm|search|show|clear` | 速记本（.md 文件） | `/notes add 想到一个 idea` |
| `/cron add <cron> <消息>|list|rm` | 定时任务 | `/cron add "0 9 * * *" 早安` |
| `/now [tz|epoch]` | 时区/时间换算 | `/now Asia/Tokyo` |
| `/weather <地名>` | 天气 (wttr.in) | `/weather Beijing` |
| `/map <地名>` | 地名 → 坐标 + 静态地图 | `/map 故宫` |
| `/currency <amount> <FROM> <TO>` | 汇率 | `/currency 100 USD CNY` |
| `/stock <ticker>` | 股票/加密 | `/stock sh600519` |

## G. 娱乐 / 文化

`/joke` `/quote` `/anime` `/manga` `/lyrics` `/movie` `/poem` `/idiom` `/recipe` — 见上面 E/F 节。

## H. 文本 / 编码转换

| 命令 | 一句话 | 示例 |
|---|---|---|
| `/case <type> <text>` | upper/lower/title/snake/camel/kebab/pascal | `/case snake helloWorld` |
| `/morse enc|dec <text>` | 摩斯密码 | `/morse enc SOS` |
| `/unicode <c|U+|name>` | Unicode codepoint+name | `/unicode U+1F600` |
| `/color <hex|rgb|name>` | 颜色 → hex/RGB/HSL/互补 | `/color #336699` |
| `/lorem [p|s|w] [n]` | Lorem Ipsum | `/lorem p 3` |
| `/wc` `/diff` `/regex` `/json` `/urltool` `/base64` `/hash` `/uuid` — 见 B 节 | | |

## I. 多媒体 / 创作

| 命令 | 一句话 | 示例 |
|---|---|---|
| `/image [n=N] [style=…] <提示词>` (alias `/img`) | 文生图（pollinations 免 key） | `/img 一只柴犬戴墨镜` |
| `/diagram <需求>` | 自然语言转 mermaid → PNG | `/diagram 用户登录时序图` |
| `/video <提示词>` | Hailuo 海螺视频（playwright + 本地 Chrome） | `/video 一只猫跳舞` |
| `/tts <文本>` | 语音合成（Azure / 本机） | `/tts 你好，今天天气真好` |
| `/ocr [图片]` | 图转文字（tesseract → qoder） | `/ocr` |
| `/translate-image [target=zh] [图片]` | 图片 OCR + 翻译 | `/translate-image target=en` |
| `/qrcode <text|url>` | 二维码 | `/qrcode hi` |

## J. 高级 / Agent / Skill

| 命令 | 一句话 |
|---|---|
| `/skill list|use|unstick|route` | 人格 skill 持久化 + 关键词路由 |
| `/soul list|<name>|show|save` | persona/灵魂切换 |
| `/memory all|recent|search|clear` | 全局记忆 / 最近 / 检索 |
| `/agent <soul> <text>` / `/agent route` | 单 agent / 关键词触发 |
| `/team run <text>` | 多 agent 协作 |
| `/mcp list|test|run` | Model Context Protocol 桥接 |
| `/router on|off` | 自动路由（联网/画图/定时） |
| `/rag ingest|ask` | 文档 RAG |
| `/bg <问题>` | 后台思考（立刻回 🤔，跑完再推） |
| `/hooks` | 查看 hook |
| `/card` | bot 名片 |
| `/broadcast <ids> <msg>` | 群发 |

---

## 通用约定

- **免 key 优先**：所有插件默认走免 key API；少数（`/code` 需 `GITHUB_TOKEN`，
  `/paper` 高密度调用建议 `SEMANTIC_SCHOLAR_KEY`）有说明。
- **离线可用**：`/calc` `/run` `/qrcode (+qrencode)` `/ocr (+tesseract)`
  `/wc` `/diff` `/regex` `/json` `/base64` `/hash` `/uuid` `/case` `/morse`
  `/color` `/unicode` `/lorem` `/now` `/cidr` `/pw` `/notes` `/timer`
  `/calendar` 都 100% 本机。
- **bash 3.2 兼容**：macOS 自带 bash 也能跑（仓库 `lib/*.sh` 没用关联数组）。
- **跨 fork 状态**：alias / plugins.disabled / notes / readlater / calendar
  全部走文件，每条消息读一次，不依赖运行时内存。
- **插件开发**：见 README "自定义插件" 一节；模板：
  ```bash
  plugin_foo() { local to="$1" key="$2" rest="$3"; reply_text "$to" "hi $rest"; }
  register_command "/foo" plugin_foo "demo plugin"
  ```
  `lib/plugin_utils.sh` 提供 `pu_url_encode` / `pu_http_get` /
  `pu_http_get_retry` / `pu_json_get` / `pu_truncate` / `pu_ask_qoder` 等通用助手。

## 关闭某个插件

```bash
/plugins disable joke      # 写入 state/plugins.disabled
/plugins enable joke       # 启用
/plugins reload            # 重启 bot 才真正生效
```

或手动：

```bash
echo joke >> state/plugins.disabled
# 重启 bot
```
