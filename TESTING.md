# mini_bot 测试指南

> 最近全量通过日期：2026-07-03
> 默认测试模型：lite（节省配额）
> 测试方式：通过 `lark-cli im +messages-send --as user` 向机器人发消息，检查 `state/logs/events.jsonl` 中的回复

---

## 测试方法

### 发送消息

```bash
lark-cli im +messages-send --as user \
  --chat-id oc_7ea1907fb067c8d49a705c56591460d0 \
  --text "<command>"
```

### 检查回复

```bash
tail -2 state/logs/events.jsonl | grep '"kind":"reply"' | jq -r '.text'
```

### 测试前准备

```bash
# 切到测试模型（默认 lite，省配额）
/model lite

# 测试完成后恢复
/model lite
```

### 切换模型全量测试

任意模型（含 Fuyao 系列）都应完整跑完 §1–§12 全部用例。Fuyao 模型通过 opencode harness 运行，功能与 qodercli 模型完全对等（多轮对话、工具调用、文件读写、联网搜索、定时任务等），不应为其单独缩减测试范围。

步骤：

```bash
# 1. 切到目标模型
/model select   # 选 15(fuyao-deepseek) / 16(fuyao-glm) / 17(fuyao-kimi) 等

# 2. 按 §1 → §12 顺序跑全部用例
#    每节之间留足时间等回复（Fuyao 模型响应较慢，建议每节间隔 30-60s）

# 3. 测试完毕切回 lite
/model lite
```

注意事项：
- Fuyao 模型响应延迟约 15-25s（复杂任务更长），命令批量测试时建议每节间隔 30-60s
- Fuyao 模型的 `/image`、`/diagram`、`/qrcode` 走 opencode 工具链，行为与 qodercli 一致
- 多轮记忆：Fuyao 通过 opencode 原生 session 持久化，`/reset` 会清除 `.oc_session` 文件
- `/run`、`/calc`、`/bg`、`/digest` 等工具类命令：Fuyao 通过 opencode shell 工具执行，结果格式一致（/bg 使用独立的 `${key}.bg` session 避免与主会话竞争）
- `/mcp` 曾因 `$MCP_CONFIG；`（变量名紧邻全角分号）在 `set -u` 下触发 unbound-variable 而崩溃，已修（`${MCP_CONFIG}`）
- `/map` 依赖外部 Nominatim，可能偶发失败（与 Fuyao 无关）
- GitHub trending cron 任务（抓页 + 建飞书文档 + 发群）在 fuyao-glm 下实测通过，需要 `FUYAO_TIMEOUT=1200`
- 如某节在 Fuyao 下失败，记录到该节状态列并在「已知限制」中注明

---

## 测试用例

### 1. 核心命令

| # | 命令 | 期望结果 | 状态 |
|---|------|----------|------|
| 1.1 | `/help` | 返回分组命令列表（包含"会话""灵魂"等分类） | ✅ |
| 1.2 | `/reset` | "✅ 已清空本会话记忆" | ✅ |
| 1.3 | `/status` | 返回 host/qoder/soul/model/quota 信息 | ✅ |
| 1.4 | `/model` | "当前模型：lite" | ✅ |
| 1.5 | `/model select` | 显示 17 个模型编号列表 | ✅ |
| 1.6 | (回复数字 `12`) | "✅ 已切换模型为：Qwen3.7-Max (qmodel_latest) [5x credit]" | ✅ |
| 1.7 | `/model select` → 回复 `99` | "❌ Out of range (1-17)" | ✅ |
| 1.8 | `/model select` → 回复非数字 | 正常走聊天（不报错） | ✅ |
| 1.9 | `/model ultimate` | "✅ 已切换模型为：ultimate" | ✅ |
| 1.10 | `/quota` | 显示配额数字 + 模型名 + 模式（quality/thrifty） | ✅ |
| 1.11 | `/cancel` (有运行中请求时) | "🛑 已中止当前请求。" | ✅ |
| 1.12 | `/cancel` (无请求时) | "(没有正在处理的请求)" | ✅ |
| 1.13 | `/lang en` → `/help` | 英文帮助 | ✅ |

### 2. 会话管理

| # | 命令 | 期望结果 | 状态 |
|---|------|----------|------|
| 2.1 | `/soul` | "当前 soul：default" | ✅ |
| 2.2 | `/soul list` | 列出所有可用 soul（default/cat/coder/pro...） | ✅ |
| 2.3 | `/memory` | 显示本会话记忆内容 | ✅ |
| 2.4 | `/memory add 测试项` | "✅ 已写入本会话记忆" | ✅ |
| 2.5 | `/memory recent` | 包含刚添加的"测试项" | ✅ |
| 2.6 | `/memory search 测试` | 命中"测试项" | ✅ |
| 2.7 | `/skill` | 列出可用技能（translate/summarize...） | ✅ |
| 2.8 | `/automem` | 显示当前状态和用法 | ✅ |
| 2.9 | 多轮记忆：`我叫测试员，记住` → 再发 `我叫什么` | 第二轮能正确回忆"测试员"（qodercli 走 session.jsonl；Fuyao 走 opencode 原生 session） | ✅ |
| 2.10 | `/reset` → `我叫什么` | 无法回忆（qodercli：session.jsonl 清空；Fuyao：`.oc_session` 文件被删） | ✅ |
| 2.11 | 会话上下文溢出后自动自愈 | resume 返回空（仅换行）时自动 summarize→reset→换新 uuid 重试，用户仍收到回复，日志出现 `SELF-HEAL` | ✅ |
| 2.12 | 自愈后模型选择保留 | 自动 reset 不会把模型重置为默认，`.model` 仍为用户所选 | ✅ |
| 2.13 | 工具访问：`列出当前目录下的文件` | 返回文件列表（qodercli 走内置工具；Fuyao 走 opencode shell/file 工具） | ✅ |

### 3. 联网 & 搜索

| # | 命令 | 期望结果 | 状态 |
|---|------|----------|------|
| 3.1 | `/news golang` | 返回 ≥5 条带标题+链接的搜索结果 | ✅ |
| 3.2 | `/search rust语言优势` | qoder 综合搜索结果回答（≥50 字） | ✅ |
| 3.3 | `/web https://example.com` | 抓取并总结 IANA 示例页面 | ✅ |

### 4. 多模态

| # | 命令 | 期望结果 | 状态 |
|---|------|----------|------|
| 4.1 | `/image a cute cat` | "🎨 正在生成图片…" + 后续图片 | ✅ |
| 4.2 | `/tts` | 显示当前 TTS 状态（on/off） | ✅ |
| 4.3 | `/stream` | 显示当前流式状态 + 用法 | ✅ |
| 4.4 | 发一条语音（说一句话） | 经 ASR 转写成文字后交给模型，模型按语音内容作答；日志含 `voice transcribed via <engine>`，会话内 `attachments=0`、无原始 `OggS` 二进制 | ✅ |
| 4.5 | 发一条无法识别的语音（静音/噪声） | 过滤占位符（`[blank_audio]`/`(silence)` 等），提示用户语音暂时无法识别、可改发文字 | ✅ |

### 5. 工具

| # | 命令 | 期望结果 | 状态 |
|---|------|----------|------|
| 5.1 | `/calc 2**10` | "= 1024" | ✅ |
| 5.2 | `/run py print(sum(range(1,11)))` | "🧪 /run py (exit=0)\n--- stdout ---\n55" | ✅ |
| 5.3 | `/translate target=en 你好世界` | "Hello World" | ✅ |
| 5.4 | `/diagram 用户登录流程` | "📐 生成 diagram 中…" + 后续图片 | ✅ |

### 6. 实用工具插件

| # | 命令 | 期望结果 | 状态 |
|---|------|----------|------|
| 6.1 | `/weather 北京` | 温度 + 天气符号 + 预报 | ✅ |
| 6.2 | `/now` | 当前时间 + epoch | ✅ |
| 6.3 | `/uuid` | 生成 UUIDv4 格式字符串 | ✅ |
| 6.4 | `/hash sha256 hello` | "2cf24dba5fb0a30e..." | ✅ |
| 6.5 | `/base64 enc hello world` | "aGVsbG8gd29ybGQ=" | ✅ |
| 6.6 | `/wc 你好世界abc` | chars=7 cjk=4 | ✅ |
| 6.7 | `/json fmt {"a":1,"b":2}` | 格式化 JSON 输出 | ✅ |
| 6.8 | `/regex [0-9]+ ::: abc123def` | 命中 "123" | ✅ |
| 6.9 | `/pw 16` | 16 位随机密码 | ✅ |
| 6.10 | `/color #ff5733` | RGB + HSL + 互补色 | ✅ |
| 6.11 | `/dns google.com` | DNS A 记录 | ✅ |
| 6.12 | `/ip` | 公网 IP + 地理位置 | ✅ |
| 6.13 | `/headers https://example.com` | HTTP 响应头 | ✅ |
| 6.14 | `/whois example.com` | WHOIS 信息 | ✅ |
| 6.15 | `/cidr 192.168.1.0/24` | 网段信息（network/broadcast/netmask） | ✅ |
| 6.16 | `/urltool parse https://example.com/path?q=1` | scheme/host/path/query 拆分 | ✅ |
| 6.17 | `/morse enc hello` | ".... . .-.. .-.. ---" | ✅ |
| 6.18 | `/unicode A` | "U+0041 LATIN CAPITAL LETTER A" | ✅ |
| 6.19 | `/case snake HelloWorld` | "hello_world" | ✅ |
| 6.20 | `/diff hello ::: world` | diff 输出 | ✅ |
| 6.21 | `/lorem p 1` | 一段 Lorem Ipsum 文本 | ✅ |
| 6.22 | `/qrcode https://example.com` | 生成二维码图片 | ✅ |
| 6.23 | `/shorturl https://github.com/hlx1996/mini_bot` | tinyurl 短链接 | ✅ |
| 6.24 | `/dict serendipity` | 音标 + 释义 | ✅ |
| 6.25 | `/wiki Linux` | 维基百科摘要 | ✅ |
| 6.26 | `/joke` | 返回一个笑话 | ✅ |
| 6.27 | `/poem random` | 随机古诗 | ✅ |
| 6.28 | `/idiom 画龙点睛` | 拼音 + 释义 + 出处 | ✅ |

### 7. 定时 & 计时

| # | 命令 | 期望结果 | 状态 |
|---|------|----------|------|
| 7.1 | `/cron list` | 显示已有定时任务列表 | ✅ |
| 7.2 | `/timer 5s test` | "⏰ Timer 启动：5s" → 5秒后 "⏰ 时间到（5s）：test" | ✅ |
| 7.3 | `/pomodoro list` | "(无)" + 用法 | ✅ |
| 7.4 | `/calendar list` | 日历内容或空提示 | ✅ |
| 7.5 | `/cron add "0 * * * *" "hi"` → 等下次整点触发 | 群里收到 qoder 回复（crontab PATH 由 bot.sh 启动时自动补全 `/opt/homebrew/bin` 等，cron 环境能正常找到 lark-cli / qodercli） | ✅ |

### 8. 数据持久化

| # | 命令 | 期望结果 | 状态 |
|---|------|----------|------|
| 8.1 | `/pin list` | 显示 per-chat 和 global pin 列表 | ✅ |
| 8.2 | `/pin add x 内容` → `/pin list` → `/pin rm x` | 增/查/删完整流程 | ✅ |
| 8.3 | `/notes add 笔记` → `/notes list` → `/notes rm 1` | 增/查/删完整流程 | ✅ |
| 8.4 | `/readlater` | 显示列表（空时提示用法） | ✅ |
| 8.5 | `/alias list` | 显示已有别名 | ✅ |

### 9. 管理 & 统计

| # | 命令 | 期望结果 | 状态 |
|---|------|----------|------|
| 9.1 | `/whoami` | user/name/account 信息 | ✅ |
| 9.2 | `/export 3` | 最近 3 条消息 | ✅ |
| 9.3 | `/stats` | 全部事件数 + 今日收发 | ✅ |
| 9.4 | `/usage` | 按账号分组的用量 | ✅ |
| 9.5 | `/metrics` | 24h 收/回/失败/字符/延迟 | ✅ |
| 9.6 | `/cost` | token 估算 + 费用 | ✅ |
| 9.7 | `/backup list` | 需要管理员权限（非 admin 时） | ✅ |
| 9.8 | `/admin list` | 管理员列表 | ✅ |
| 9.9 | `/mute` → `/unmute` | 静音/解除（注意：非 admin 无法自行 unmute） | ✅ |

### 10. 高级功能

| # | 命令 | 期望结果 | 状态 |
|---|------|----------|------|
| 10.1 | `/team` | 当前 team 配置或"未配置" | ✅ |
| 10.2 | `/route` | 路由规则列表（可为空） | ✅ |
| 10.3 | `/nick` | 昵称簿列表 | ✅ |
| 10.4 | `/bridge list` | 桥接列表（可为空） | ✅ |
| 10.5 | `/cwd` | 当前工作目录状态 | ✅ |
| 10.6 | `/mcp` | MCP 服务器列表 | ✅ |
| 10.7 | `/account` | 账号列表 | ✅ |
| 10.8 | `/commands` | 所有 plugin 命令字母排序 | ✅ |
| 10.9 | `/plugins list` | 插件启用/禁用状态 | ✅ |
| 10.10 | `/bg 1+1` | 立即 "🤔 收到" → 异步推回结果 | ✅ |
| 10.11 | `/digest now 1` | 最近 1h 聊天摘要 | ✅ |

### 11. 信息查询插件

| # | 命令 | 期望结果 | 状态 |
|---|------|----------|------|
| 11.1 | `/github hlx1996/mini_bot` | 仓库 star/fork/lang/license | ✅ |
| 11.2 | `/map 杭州` | 经纬度 + OSM 链接 | ✅ |
| 11.3 | `/currency 100 USD CNY` | 汇率换算结果 | ✅ |
| 11.4 | `/paper attention is all you need` | 论文标题 + 作者 | ✅ |
| 11.5 | `/tldr curl` | curl 命令速查 | ✅ |
| 11.6 | `/cheat tar` | tar 速查表 | ✅ |
| 11.7 | `/gitignore python` | Python .gitignore 模板 | ✅ |
| 11.8 | `/license mit` | MIT 协议全文 | ✅ |

### 12. Tier-aware 模式验证

| # | 操作 | 期望结果 | 状态 |
|---|------|----------|------|
| 12.1 | `/model ultimate` → `/quota` | 显示"thrifty 模式" | ✅ |
| 12.2 | `/model lite` → `/quota` | 显示"quality 模式" | ✅ |
| 12.3 | `/model qmodel_latest` → `/quota` | 显示"quality 模式" | ✅ |

---

## 已知限制

| 问题 | 说明 |
|------|------|
| `/mute` 后非 admin 无法自行 `/unmute` | 设计如此，需要 admin 操作或手动清 `state/mute.list` |
| `/image` 文本回复只有"正在生成…" | 图片通过飞书图片 API 异步发送，不记录在 events.jsonl 文本字段 |
| `/diagram` 同上 | mermaid 渲染后图片异步推送 |
| `/qrcode` 同上 | 二维码图片异步发送 |
| `/backup` 需 admin | 默认无 admin，需先 `/admin add <user-id>` |
| 上下文溢出自愈会丢失该会话历史 | 溢出会话连自身摘要也返回空，无法 compress，故该 session 的对话历史丢失；但持久记忆（`/memory`、`/pin`、automem）独立存储并重新注入，不受影响 |
| `/map` 依赖外部 Nominatim | 公网/代理环境下查询可能偶发失败，与模型无关 |

---

## 维护指南

### 新增功能时

1. 在本文件对应分类下追加测试用例
2. 如果是新分类，新增一个 `### N. 分类名` 节
3. 同步更新 README.md 的"常用命令"表格
4. 同步更新 PLUGINS.md（如果是插件）

### 修改现有功能时

1. 找到本文件中对应的测试用例
2. 更新"期望结果"列
3. 重新执行测试并更新"状态"列
4. 如果修改了命令语法，同步更新 README.md

### 运行全量测试

```bash
# 切 lite 模型
lark-cli im +messages-send --as user \
  --chat-id oc_7ea1907fb067c8d49a705c56591460d0 \
  --text "/model lite"

# 逐批发送（每批间隔 ~20s 等回复）
# 批 1: 核心
for cmd in "/help" "/reset" "/status" "/model" "/quota"; do
  lark-cli im +messages-send --as user \
    --chat-id oc_7ea1907fb067c8d49a705c56591460d0 \
    --text "$cmd"; sleep 2
done

# 检查回复
tail -12 state/logs/events.jsonl | grep '"kind":"reply"' | jq -r '.text[:80]'

# 恢复模型
lark-cli im +messages-send --as user \
  --chat-id oc_7ea1907fb067c8d49a705c56591460d0 \
  --text "/model qmodel_latest"
```

### 快速回归检查（核心路径）

如果只改了一小部分代码，至少验证这些核心路径：

```bash
cmds=("/status" "/model select" "/quota" "/calc 1+1" "/news test" "/weather 北京")
for cmd in "${cmds[@]}"; do
  lark-cli im +messages-send --as user \
    --chat-id oc_7ea1907fb067c8d49a705c56591460d0 \
    --text "$cmd"; sleep 3
done
sleep 15
tail -14 state/logs/events.jsonl | grep '"kind":"reply"' | jq -r '.text[:60]'
```

---

## 测试环境

- macOS Darwin 25.5.0 arm64
- qoder 1.0.10
- lark-cli 1.0.42
- chat-id: `oc_7ea1907fb067c8d49a705c56591460d0`
- session key: `479073399167ff3d`
