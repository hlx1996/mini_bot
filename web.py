#!/usr/bin/env python3
"""wxweb.py — read-only web dashboard for wxbot.sh.

Usage:
  python3 ~/wxweb.py                       # serve on http://127.0.0.1:8765
  python3 ~/wxweb.py --port 9000 --host 0.0.0.0
  BOT_HOME=/tmp/wxbot-test python3 ~/wxweb.py

Endpoints:
  GET /                  -> dashboard HTML (single page, auto-refreshes)
  GET /api/status        -> {bot_running, pid, uptime, model_default, account, ...}
  GET /api/sessions      -> [{key,uuid,model,last_active,workspace,msg_count}]
  GET /api/events?n=200  -> [{kind,...}]  recent inbound events + replies
  GET /api/crons         -> [{id,expr,key,prompt,to}]
  GET /api/log?n=200     -> tail of bot.out
"""
from __future__ import annotations
import argparse, base64, http.server, json, os, re, socketserver, subprocess, sys, time
from pathlib import Path
from urllib.parse import urlparse, parse_qs

BOT_HOME      = Path(os.environ.get("BOT_HOME", str(Path.home() / "wxbot-state")))
LOG_DIR       = BOT_HOME / "logs"
SESS_DIR      = BOT_HOME / "sessions"
WORK_ROOT     = BOT_HOME / "workspaces"
EVENT_LOG     = LOG_DIR / "events.jsonl"
BOT_OUT       = LOG_DIR / "bot.out"
CMDQ_DIR      = BOT_HOME / "commands"
MUTE_FILE     = BOT_HOME / "mute.list"
ADMINS_FILE   = BOT_HOME / "admins.list"
ACCOUNTS_FILE = BOT_HOME / "accounts.list"
DEFAULT_MODEL = os.environ.get("BOT_MODEL", "lite")
ACCOUNT_JSON  = Path.home() / ".claude" / "channels" / "wechat" / "account.json"

CMDQ_DIR.mkdir(parents=True, exist_ok=True)

# ---------- helpers ----------

def tail(path: Path, n: int) -> list[str]:
    if not path.exists():
        return []
    with path.open("rb") as f:
        f.seek(0, 2)
        size = f.tell()
        buf = b""
        block = 8192
        while size > 0 and buf.count(b"\n") <= n:
            read = min(block, size)
            size -= read
            f.seek(size)
            buf = f.read(read) + buf
    lines = buf.decode("utf-8", "replace").splitlines()
    return lines[-n:]

def read_json(path: Path):
    try:
        return json.loads(path.read_text())
    except Exception:
        return None

# ---------- data collectors ----------

def status() -> dict:
    pid, uptime = None, None
    try:
        out = subprocess.check_output(
            ["pgrep", "-f", "wxbot.sh"], text=True, stderr=subprocess.DEVNULL
        ).strip()
        pids = [int(x) for x in out.splitlines() if x.strip().isdigit()]
        pids = [p for p in pids if p != os.getpid()]
        if pids:
            pid = pids[0]
            try:
                ps = subprocess.check_output(
                    ["ps", "-o", "etime=", "-p", str(pid)], text=True
                ).strip()
                uptime = ps or None
            except Exception:
                pass
    except Exception:
        pass
    acct = read_json(ACCOUNT_JSON) or {}
    return {
        "bot_running": pid is not None,
        "pid": pid,
        "uptime": uptime,
        "bot_home": str(BOT_HOME),
        "model_default": DEFAULT_MODEL,
        "account_id": acct.get("account_id"),
        "user_id": acct.get("user_id"),
        "logged_in": bool(acct.get("token")),
        "events_log_size": EVENT_LOG.stat().st_size if EVENT_LOG.exists() else 0,
        "now": int(time.time()),
    }

def sessions() -> list[dict]:
    if not SESS_DIR.exists():
        return []
    out = []
    keys = set()
    for p in SESS_DIR.iterdir():
        if p.is_file():
            keys.add(p.stem)
    # msg counts from events.jsonl. Chat key matches wxbot.sh:
    #   sha1(account_id + 0x1f + from)[:16]
    msg_counts: dict[str, int] = {}
    if EVENT_LOG.exists():
        import hashlib
        for ln in tail(EVENT_LOG, 5000):
            try:
                e = json.loads(ln)
            except Exception:
                continue
            if e.get("kind") == "event":
                acct = e.get("account_id", "") or ""
                peer = e.get("from", "") or ""
            elif e.get("kind") == "reply":
                acct = ""  # we don't store account on outbound; tally to peer-only key too
                peer = e.get("to", "") or ""
            else:
                continue
            raw = f"{acct}\x1f{peer}".encode()
            k = hashlib.sha1(raw).hexdigest()[:16]
            msg_counts[k] = msg_counts.get(k, 0) + 1
            # Also tally a "no-account" variant so replies (which omit account) still count
            if acct:
                k2 = hashlib.sha1(f"\x1f{peer}".encode()).hexdigest()[:16]
                msg_counts.setdefault(k2, 0)
    for k in sorted(keys):
        uuid_p  = SESS_DIR / f"{k}.uuid"
        model_p = SESS_DIR / f"{k}.model"
        peer_p  = SESS_DIR / f"{k}.peer"
        wks     = WORK_ROOT / k
        last = max(
            (p.stat().st_mtime for p in [uuid_p, model_p, peer_p, wks] if p.exists()),
            default=0,
        )
        out.append({
            "key": k,
            "uuid":  uuid_p.read_text().strip()  if uuid_p.exists()  else None,
            "model": model_p.read_text().strip() if model_p.exists() else DEFAULT_MODEL,
            "peer":  peer_p.read_text().strip()  if peer_p.exists()  else None,
            "workspace": str(wks) if wks.exists() else None,
            "last_active": int(last) if last else None,
            "msg_count": msg_counts.get(k, 0),
        })
    out.sort(key=lambda x: x["last_active"] or 0, reverse=True)
    return out

def events(n: int = 200) -> list[dict]:
    if not EVENT_LOG.exists():
        return []
    res = []
    for ln in tail(EVENT_LOG, n):
        try:
            res.append(json.loads(ln))
        except Exception:
            pass
    return res

def crons() -> list[dict]:
    try:
        out = subprocess.check_output(["crontab", "-l"], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return []
    res = []
    pat = re.compile(r"^(?P<expr>\S+\s+\S+\s+\S+\s+\S+\s+\S+)\s+(?P<cmd>.*?)\s+#\s+wxcron:(?P<key>[^:]+):(?P<id>\S+)\s*$")
    for ln in out.splitlines():
        m = pat.match(ln)
        if not m:
            continue
        cmd = m.group("cmd").split()
        to, b64 = None, None
        if "--cron-fire" in cmd:
            i = cmd.index("--cron-fire")
            if len(cmd) >= i + 4:
                to = cmd[i + 1]
                b64 = cmd[i + 3]
        prompt = ""
        if b64:
            try:
                prompt = base64.b64decode(b64).decode("utf-8", "replace")
            except Exception:
                prompt = "[?]"
        res.append({
            "id": m.group("id"),
            "key": m.group("key"),
            "expr": m.group("expr"),
            "to": to,
            "prompt": prompt,
        })
    return res


def accounts() -> list[dict]:
    """List configured accounts: WeChat + Lark/Feishu.
    accounts.list rows are now: <platform>:<name> [soul] [model] (default platform=wechat)."""
    rows: list[dict] = []
    seen: set[str] = set()
    if ACCOUNTS_FILE.exists():
        for ln in ACCOUNTS_FILE.read_text().splitlines():
            ln = ln.split("#", 1)[0].strip()
            if not ln: continue
            first = ln.split()[0]
            if ":" in first:
                platform, name = first.split(":", 1)
            else:
                platform, name = "wechat", first
            key = f"{platform}:{name}"
            if key in seen: continue
            seen.add(key)
            parts = ln.split()
            default_soul  = parts[1] if len(parts) > 1 else ""
            default_model = parts[2] if len(parts) > 2 else ""
            if platform == "wechat":
                cred = (Path.home() if name == "default"
                        else (BOT_HOME / "accounts" / name / "home")) / ".claude" / "channels" / "wechat" / "account.json"
                meta = read_json(cred) or {}
                rows.append({
                    "platform": "wechat",
                    "name": name,
                    "label": key,
                    "logged_in": bool(meta.get("token")),
                    "account_id": meta.get("account_id"),
                    "user_id": meta.get("user_id"),
                    "default_soul": default_soul,
                    "default_model": default_model,
                })
            else:
                rows.append({
                    "platform": platform,
                    "name": name,
                    "label": key,
                    "logged_in": True,  # lark-cli profile assumed configured
                    "account_id": name,
                    "user_id": None,
                    "default_soul": default_soul,
                    "default_model": default_model,
                })
    if not any(r["platform"] == "wechat" and r["name"] == "default" for r in rows):
        cred = Path.home() / ".claude" / "channels" / "wechat" / "account.json"
        meta = read_json(cred) or {}
        rows.insert(0, {
            "platform": "wechat", "name": "default", "label": "wechat:default",
            "logged_in": bool(meta.get("token")), "account_id": meta.get("account_id"),
            "user_id": meta.get("user_id"), "default_soul": "", "default_model": "",
        })
    return rows


def list_backups() -> list[dict]:
    d = BOT_HOME / "backups"
    if not d.exists():
        return []
    out = []
    for p in sorted(d.glob("*.tar.gz"), key=lambda x: x.stat().st_mtime, reverse=True):
        st = p.stat()
        out.append({"name": p.name, "size": st.st_size, "mtime": int(st.st_mtime)})
    return out


def enqueue_command(payload: dict) -> dict:
    """Persist a command for the bot to process on the next tick.
    Returns {ok,id} or {ok:false,error}."""
    try:
        cid = f"{int(time.time()*1000)}-{os.getpid()}.json"
        path = CMDQ_DIR / cid
        path.write_text(json.dumps(payload, ensure_ascii=False))
        return {"ok": True, "id": cid}
    except Exception as e:
        return {"ok": False, "error": str(e)}

# ---------- HTML ----------

INDEX_HTML = r"""<!doctype html>
<html lang="zh"><head>
<meta charset="utf-8"><title>wxbot 监控面板</title>
<style>
body{font:14px/1.5 -apple-system,Segoe UI,Helvetica,Arial,sans-serif;margin:0;background:#0e1116;color:#e8eaed}
header{background:#1c2128;padding:12px 20px;display:flex;align-items:center;gap:16px;border-bottom:1px solid #30363d}
header h1{margin:0;font-size:16px;font-weight:600}
.dot{width:10px;height:10px;border-radius:50%;display:inline-block;margin-right:6px}
.up{background:#3fb950}.down{background:#f85149}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:16px;padding:16px}
.card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:14px}
.card h2{margin:0 0 10px;font-size:13px;color:#7d8590;text-transform:uppercase;letter-spacing:.5px;font-weight:600}
.kv{display:grid;grid-template-columns:140px 1fr;gap:4px 12px;font-family:ui-monospace,Menlo,monospace;font-size:12px}
.kv b{color:#7d8590;font-weight:400}
table{width:100%;border-collapse:collapse;font-size:12px;font-family:ui-monospace,Menlo,monospace}
th,td{padding:6px 8px;border-bottom:1px solid #21262d;text-align:left;vertical-align:top}
th{color:#7d8590;font-weight:500;background:#0d1117;position:sticky;top:0}
.events{max-height:520px;overflow:auto}
.ev-in{color:#79c0ff}.ev-out{color:#a5d6a7}.ev-bad{color:#ffa198}
.txt{white-space:pre-wrap;word-break:break-word;max-width:600px}
.muted{color:#7d8590}
.tag{display:inline-block;padding:1px 6px;border-radius:3px;background:#21262d;font-size:11px;margin-right:4px}
.logbox{max-height:300px;overflow:auto;background:#0d1117;padding:8px;border-radius:4px;font:11px/1.45 ui-monospace,Menlo,monospace;white-space:pre-wrap}
.full{grid-column:span 2}
button{background:#238636;color:#fff;border:0;padding:4px 10px;border-radius:4px;cursor:pointer;font-size:12px}
button:hover{background:#2ea043}
</style></head><body>
<header>
  <h1>📲 wxbot 监控面板</h1>
  <span id="badge"></span>
  <span class="muted" id="now"></span>
  <span style="margin-left:auto">
    <label class="muted"><input type="checkbox" id="auto" checked> 自动刷新</label>
    <button onclick="refresh()">刷新</button>
  </span>
</header>
<div class="grid">
  <div class="card">
    <h2>状态</h2>
    <div class="kv" id="status"></div>
  </div>
  <div class="card">
    <h2>会话 / Chats</h2>
    <table><thead><tr><th>peer</th><th>model</th><th>uuid</th><th>msgs</th><th>last</th><th>操作</th></tr></thead>
    <tbody id="sessions"></tbody></table>
  </div>
  <div class="card full">
    <h2>事件流 / Events
      <span style="font-weight:400;font-size:12px;margin-left:8px">
        过滤：
        <select id="ev_filter" onchange="refresh()" style="background:#0d1117;border:1px solid #30363d;color:#e8eaed;font-size:11px">
          <option value="">全部</option>
          <option value="wechat">仅 WeChat</option>
          <option value="lark">仅 Lark/Feishu</option>
        </select>
      </span>
    </h2>
    <div class="events"><table><thead><tr><th style="width:80px">time</th><th style="width:60px">plat</th><th style="width:60px">dir</th><th style="width:220px">peer</th><th>text</th></tr></thead>
    <tbody id="events"></tbody></table></div>
  </div>
  <div class="card">
    <h2>定时任务 / Cron</h2>
    <table><thead><tr><th>id</th><th>cron</th><th>to</th><th>prompt</th><th></th></tr></thead>
    <tbody id="crons"></tbody></table>
  </div>
  <div class="card">
    <h2>账号 / Accounts <span class="muted">(WeChat + Lark)</span></h2>
    <table><thead><tr><th>label</th><th>platform</th><th>account_id</th><th>default soul/model</th><th>logged_in</th></tr></thead>
    <tbody id="accounts"></tbody></table>
    <p class="muted" style="margin-top:8px">accounts.list 格式 <code>&lt;platform&gt;:&lt;name&gt; [soul] [model]</code>。新加微信号：<code>python3 wxlink.py --account &lt;name&gt; login</code>。新加 Lark：<code>lark-cli auth login --as &lt;name&gt;</code>。</p>
  </div>
  <div class="card">
    <h2>快捷发送 / Quick Send</h2>
    <div style="display:flex;flex-direction:column;gap:6px">
      <select id="qs_acct" style="background:#0d1117;border:1px solid #30363d;color:#e8eaed;padding:6px;border-radius:4px"></select>
      <input id="qs_to" placeholder="收件人 (wxid_xxx@im.wechat 或 lark oc_xxx)" style="background:#0d1117;border:1px solid #30363d;color:#e8eaed;padding:6px;border-radius:4px"/>
      <input id="qs_text" placeholder="文本" style="background:#0d1117;border:1px solid #30363d;color:#e8eaed;padding:6px;border-radius:4px"/>
      <button onclick="qsSend()">发送</button>
      <div class="muted" id="qs_msg"></div>
    </div>
  </div>
  <div class="card">
    <h2>备份 / Backup</h2>
    <div style="display:flex;gap:8px;margin-bottom:8px">
      <button onclick="bkCreate()">创建新备份</button>
    </div>
    <table><thead><tr><th>文件</th><th>大小</th><th>时间</th><th></th></tr></thead>
    <tbody id="backups"></tbody></table>
    <div class="muted" id="bk_msg"></div>
  </div>
  <div class="card">
    <h2>bot.out (tail 200)</h2>
    <div class="logbox" id="log"></div>
  </div>
</div>
<script>
const $ = id => document.getElementById(id);
const esc = s => (s||"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const fmtTs = ts => ts ? new Date(ts*1000).toLocaleString() : "—";
const ago = ts => { if(!ts) return "—"; let d=Math.floor(Date.now()/1000)-ts; if(d<60)return d+"s"; if(d<3600)return Math.floor(d/60)+"m"; if(d<86400)return Math.floor(d/3600)+"h"; return Math.floor(d/86400)+"d";};
async function jget(u){const r=await fetch(u);return r.json();}
async function refresh(){
  try{
    const [s,se,ev,cr,lg,ac] = await Promise.all([
      jget("/api/status"),jget("/api/sessions"),jget("/api/events?n=200"),
      jget("/api/crons"),jget("/api/log?n=200"),jget("/api/accounts")
    ]);
    $("badge").innerHTML = `<span class="dot ${s.bot_running?'up':'down'}"></span>${s.bot_running?'运行中':'未运行'}`;
    $("now").textContent = "更新于 "+new Date().toLocaleTimeString();
    $("status").innerHTML = [
      ["bot_running", (s.bot_running?"✅ ":"❌ ")+(s.pid?`pid=${s.pid}`:"")],
      ["uptime", s.uptime||"—"],
      ["bot_home", s.bot_home],
      ["model_default", s.model_default],
      ["logged_in", s.logged_in?"✅":"❌ (run `wxlink login`)"],
      ["account_id", s.account_id||"—"],
      ["user_id", s.user_id||"—"],
      ["events_log_size", s.events_log_size+" B"],
    ].map(([k,v])=>`<b>${k}</b><div>${esc(String(v))}</div>`).join("");
    $("sessions").innerHTML = se.length ? se.map(r=>`<tr>
      <td>${esc(r.peer||r.key)}</td><td>${esc(r.model)}</td>
      <td class="muted">${esc((r.uuid||"").slice(0,8))}…</td>
      <td>${r.msg_count}</td><td class="muted">${ago(r.last_active)}</td>
      <td>
        <button onclick="act('reset',{key:'${esc(r.key)}'})">reset</button>
        <button onclick="act('mute',{key:'${esc(r.key)}'})">mute</button>
        <button onclick="act('unmute',{key:'${esc(r.key)}'})">unmute</button>
      </td></tr>`).join("")
      : `<tr><td colspan=6 class="muted">暂无会话</td></tr>`;
    $("events").innerHTML = (()=>{
      const filt = $("ev_filter") ? $("ev_filter").value : "";
      const items = ev.slice().reverse().filter(e => {
        if (!filt) return true;
        const p = (e.platform||"wechat");
        return filt==="lark" ? (p==="lark"||p==="feishu") : (p===filt);
      });
      if (!items.length) return `<tr><td colspan=5 class="muted">暂无事件</td></tr>`;
      return items.map(e=>{
        const t = new Date((e.ts||0)*1000).toLocaleTimeString();
        const plat = esc(e.platform||"wechat");
        if(e.kind==="event"){
          const peer = esc(e.from_name||e.from||"");
          const tags = (e.media||[]).map(m=>`<span class="tag">${esc(m.kind)}</span>`).join("");
          const mention = e.mentioned?'<span class="tag">@bot</span>':"";
          const ctype = e.chat_type==="group"?'<span class="tag">group</span>':"";
          return `<tr><td class="muted">${t}</td><td><span class="tag">${plat}</span></td><td class="ev-in">⇨ IN</td><td>${peer}</td>
            <td class="txt">${ctype}${mention}${tags}${esc(e.text||"")}</td></tr>`;
        } else if(e.kind==="reply"){
          return `<tr><td class="muted">${t}</td><td><span class="tag">${plat}</span></td><td class="${e.ok?'ev-out':'ev-bad'}">⇦ ${e.ok?'OUT':'ERR'}</td>
            <td>${esc(e.to||"")}</td><td class="txt">${esc(e.text||"")}</td></tr>`;
        }
        return `<tr><td class="muted">${t}</td><td></td><td>${esc(e.kind||'?')}</td><td></td><td>${esc(JSON.stringify(e))}</td></tr>`;
      }).join("");
    })();
    $("crons").innerHTML = cr.length ? cr.map(c=>`<tr>
      <td class="muted">${esc(c.id)}</td><td>${esc(c.expr)}</td>
      <td>${esc(c.to||"")}</td><td class="txt">${esc(c.prompt)}</td>
      <td><button onclick="act('cron_rm',{id:'${esc(c.id)}'})">rm</button></td></tr>`).join("")
      : `<tr><td colspan=5 class="muted">暂无定时任务</td></tr>`;
    $("accounts").innerHTML = ac.length ? ac.map(a=>`<tr>
      <td><b>${esc(a.label||a.name)}</b></td>
      <td><span class="tag">${esc(a.platform||'wechat')}</span></td>
      <td class="muted">${esc(a.account_id||'—')}</td>
      <td class="muted">${esc(a.default_soul||'-')} / ${esc(a.default_model||'-')}</td>
      <td>${a.logged_in?'✅':'❌'}</td></tr>`).join("") : "";
    // populate quick-send account dropdown (use label so bot knows platform)
    const sel = $("qs_acct");
    const labels = ac.map(a=>a.label||a.name).join("|");
    if (sel.dataset.labels !== labels) {
      sel.dataset.labels = labels;
      sel.innerHTML = ac.map(a=>`<option value="${esc(a.label||a.name)}">${esc(a.label||a.name)}</option>`).join("");
    }
    $("log").textContent = (lg.lines||[]).join("\n");
    $("log").scrollTop = $("log").scrollHeight;
  }catch(e){ console.error(e); $("badge").innerHTML='<span class="dot down"></span>面板出错'; }
}
async function act(action, data){
  const body = Object.assign({action}, data);
  const r = await fetch("/api/action", {method:"POST", headers:{"Content-Type":"application/json"}, body: JSON.stringify(body)});
  const j = await r.json();
  if(!j.ok){ alert("失败: "+(j.error||"未知")); } else { refresh(); }
}
async function qsSend(){
  const to=$("qs_to").value.trim(), text=$("qs_text").value, acct=$("qs_acct").value;
  if(!to||!text){ $("qs_msg").textContent="请填写收件人和文本"; return; }
  const r = await fetch("/api/action",{method:"POST",headers:{"Content-Type":"application/json"},
    body: JSON.stringify({action:"send_text",to,text,account:acct})});
  const j = await r.json();
  $("qs_msg").textContent = j.ok ? "✅ 已排队，几秒内由 bot 发出" : ("❌ "+(j.error||""));
}
async function bkRefresh(){
  const bk = await jget("/api/backups");
  $("backups").innerHTML = (bk||[]).map(b=>`<tr>
    <td><a href="/download/backup/${esc(b.name)}" download>${esc(b.name)}</a></td>
    <td>${(b.size/1024).toFixed(1)} KB</td>
    <td>${fmtTs(b.mtime)}</td>
    <td><button onclick="bkRestore('${esc(b.name)}')">恢复</button></td>
  </tr>`).join("");
}
async function bkCreate(){
  $("bk_msg").textContent = "创建中...";
  const r = await fetch("/api/action",{method:"POST",headers:{"Content-Type":"application/json"},
    body: JSON.stringify({action:"backup_create"})});
  const j = await r.json();
  $("bk_msg").textContent = j.ok ? "✅ 已排队，2-3 秒后刷新列表" : ("❌ "+(j.error||""));
  setTimeout(bkRefresh, 2500);
}
async function bkRestore(name){
  if(!confirm("确认从 "+name+" 恢复？将覆盖现有 sessions/memory/souls。")) return;
  const r = await fetch("/api/action",{method:"POST",headers:{"Content-Type":"application/json"},
    body: JSON.stringify({action:"backup_restore",name})});
  const j = await r.json();
  $("bk_msg").textContent = j.ok ? "✅ 已排队恢复" : ("❌ "+(j.error||""));
}
refresh(); bkRefresh();
setInterval(()=>{ if($("auto").checked){ refresh(); bkRefresh(); } }, 3000);
</script></body></html>
"""

# ---------- HTTP ----------

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *a):
        sys.stderr.write("[%s] %s\n" % (self.log_date_time_string(), fmt % a))

    # ---- Basic Auth (enabled when MINIBOT_USER set) ----
    def _auth_ok(self) -> bool:
        user = os.environ.get("MINIBOT_USER", "")
        if not user:
            return True
        pwd = os.environ.get("MINIBOT_PASS", "")
        h = self.headers.get("Authorization", "")
        if not h.startswith("Basic "):
            return False
        try:
            raw = base64.b64decode(h[6:]).decode("utf-8", "ignore")
        except Exception:
            return False
        if ":" not in raw:
            return False
        u, p = raw.split(":", 1)
        return u == user and p == pwd

    def _require_auth(self) -> bool:
        if self._auth_ok():
            return True
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="mini_bot"')
        self.send_header("Content-Length", "0")
        self.end_headers()
        return False

    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False, default=str).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _html(self, html: str):
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self._require_auth(): return
        u = urlparse(self.path)
        q = parse_qs(u.query)
        try:
            if u.path == "/":              return self._html(INDEX_HTML)
            if u.path == "/api/status":    return self._json(status())
            if u.path == "/api/sessions":  return self._json(sessions())
            if u.path == "/api/events":    return self._json(events(int(q.get("n",[200])[0])))
            if u.path == "/api/crons":     return self._json(crons())
            if u.path == "/api/accounts":  return self._json(accounts())
            if u.path == "/api/backups":   return self._json(list_backups())
            if u.path == "/api/log":
                n = int(q.get("n",[200])[0])
                return self._json({"lines": tail(BOT_OUT, n)})
            if u.path.startswith("/download/backup/"):
                name = u.path.rsplit("/", 1)[-1]
                return self._send_backup(name)
            self.send_error(404)
        except Exception as e:
            self._json({"error": str(e)}, 500)

    def _send_backup(self, name: str):
        if not re.fullmatch(r"[A-Za-z0-9._:-]+\.tar\.gz", name):
            return self.send_error(400)
        d = BOT_HOME / "backups"
        p = d / name
        if not p.exists() or not p.is_file():
            return self.send_error(404)
        data = p.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "application/gzip")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Content-Disposition", f'attachment; filename="{name}"')
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if not self._require_auth(): return
        u = urlparse(self.path)
        if u.path != "/api/action":
            return self.send_error(404)
        try:
            n = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(n) if n else b"{}"
            payload = json.loads(body.decode("utf-8") or "{}")
        except Exception as e:
            return self._json({"ok": False, "error": f"bad payload: {e}"}, 400)
        action = payload.get("action", "")
        if action not in {"reset","mute","unmute","cron_rm","send_text","quota_set","cancel","backup_create","backup_restore"}:
            return self._json({"ok": False, "error": f"unknown action: {action}"}, 400)
        return self._json(enqueue_command(payload))

class ThreadedServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()
    print(f"wxweb listening on http://{args.host}:{args.port}", file=sys.stderr)
    print(f"BOT_HOME = {BOT_HOME}", file=sys.stderr)
    ThreadedServer((args.host, args.port), Handler).serve_forever()

if __name__ == "__main__":
    main()
