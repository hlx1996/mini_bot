#!/usr/bin/env python3
"""approve_web.py — 内网一键 approve：fuyao job / fuyao DAG / GitLab MR。

用法:
  python3 ~/Projects/mini_bot/approve_web.py                # http://127.0.0.1:8877
  APPROVE_WEB_TOKEN=xxx python3 approve_web.py --host 0.0.0.0 --port 8877
  GITLAB_TOKEN=glpat-xxx 启用 MR approve（无则 MR 只读提示）

Endpoint:
  GET  /                 单页 HTML（输入→预检→Approve）
  POST /api/precheck     {"input": "<粘贴内容>"}  → 识别类型 + 拉取详情 + 是否可批
  POST /api/approve      {"kind": "job"|"dag"|"mr", ...precheck 透传字段}

凭证来源（只读，绝不回显）:
  fuyao : ~/.fuyao/.session (32位hex, X-Api-Key)
  gitlab: 环境变量 GITLAB_TOKEN 或 ~/.gitlab-token (PAT, scope=api 或 read_api+write)
  页面防护: 环境变量 APPROVE_WEB_TOKEN 设置后，?token= 或 X-Token 头必须匹配。
"""
from __future__ import annotations
import argparse, json, os, re, sys, time, urllib.error, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

FUYAO_BASE = os.environ.get("FUYAO_WEB_BASE", "https://your-fuyao-portal.example.com")
TIMEOUT = 15
PAGE_SIZE_NOTE = "(key 不落日志/页面)"

# ---------- credentials ----------

def fuyao_key() -> str | None:
    p = Path.home() / ".fuyao" / ".session"
    try:
        k = p.read_text().strip()
        return k or None
    except OSError:
        return None

def gitlab_token() -> str | None:
    t = os.environ.get("GITLAB_TOKEN", "").strip()
    if t:
        return t
    for p in (Path.home() / ".gitlab-token", Path.home() / ".config" / "gitlab" / "token"):
        try:
            t = p.read_text().strip()
            if t:
                return t
        except OSError:
            pass
    return None

# ---------- http helper ----------

def req_json(method: str, url: str, headers: dict, body: dict | None = None) -> tuple[int, dict]:
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Content-Type", "application/json")
    for k, v in headers.items():
        r.add_header(k, v)
    try:
        with urllib.request.urlopen(r, timeout=TIMEOUT) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {"message": "HTTP %d" % e.code}
    except Exception as e:
        return -1, {"message": str(e)}

# ---------- parse ----------

def parse_input(text: str) -> dict:
    """输入 → {kind, ...}。kind ∈ job|dag|mr|unknown"""
    t = text.strip()
    m = re.search(r"fuyao-v3\.xiaopeng\.link/#/jobs/debug\?run=([A-Za-z0-9_\-]+)", t)
    if m:
        return {"kind": "job", "run_id": m.group(1)}
    m = re.search(r"flows/dag-runs/([A-Za-z0-9_\-]+)\?query=run_id\s*==\s*([^\s&]+)", t)
    if m:
        dag_run = urllib.parse.unquote(m.group(2))
        return {"kind": "dag", "dag_id": m.group(1), "dag_run_id": dag_run}
    m = re.search(r"(https?://[^/]+)/(.+?)/-/merge_requests/(\d+)", t)
    if m:
        return {"kind": "mr", "host": m.group(1), "project": m.group(2).strip("/"), "iid": int(m.group(3))}
    if re.fullmatch(r"\d{4,}", t):
        return {"kind": "job", "run_id": t}  # 裸数字，预检时解析 cluster
    parts = t.split()
    if len(parts) == 2:  # "dag_id dag_run_id"
        return {"kind": "dag", "dag_id": parts[0], "dag_run_id": urllib.parse.unquote(parts[1])}
    if re.fullmatch(r"[A-Za-z0-9_\-]+-\d+", t):
        return {"kind": "job", "run_id": t}
    return {"kind": "unknown", "raw": t[:80]}

# ---------- precheck (read-only) ----------

def precheck(p: dict) -> dict:
    kind = p["kind"]
    if kind == "job":
        key = fuyao_key()
        if not key:
            return {"ok": False, "err": "找不到 fuyao key（~/.fuyao/.session）"}
        st, d = req_json("GET", f"{FUYAO_BASE}/api/v1/jobs/query?id={urllib.parse.quote(p['run_id'])}",
                         {"X-Api-Key": key})
        job = ((d.get("data") or {}).get("job") or {})
        canonical = (d.get("data") or {}).get("id")
        ops = job.get("operations") or []
        state = job.get("state", "?")
        return {"ok": st == 200, "kind": "job", "run_id": canonical or p["run_id"],
                "title": job.get("job_name", "?"), "owner": job.get("account", "?"),
                "state": state, "partition": job.get("partition", "?"), "gpus": job.get("gpus", "?"),
                "approvable": ("approve" in ops) and state == "JOB_SUSPENDED",
                "note": f"operations={ops}" if ops else "无待办操作（可能已批/无需批）"}
    if kind == "dag":
        key = fuyao_key()
        if not key:
            return {"ok": False, "err": "找不到 fuyao key（~/.fuyao/.session）"}
        q = urllib.parse.quote(f"run_id == {p['dag_run_id']}")
        st, d = req_json("GET", f"{FUYAO_BASE}/api/v1/fuyao-dag/runs?query={q}&limit=5",
                         {"X-Api-Key": key})
        items = ((d.get("data") or {}).get("list") or [])
        if not items:
            return {"ok": False, "err": f"找不到 DAG run（HTTP {st}）"}
        it = items[0]
        ari = it.get("approve_run_info") or {}
        return {"ok": st == 200, "kind": "dag", "dag_id": it.get("dag_id", p["dag_id"]),
                "dag_run_id": it.get("run_id", p["dag_run_id"]),
                "title": f"DAG {it.get('dag_id')}", "owner": ari.get("user_name", "?"),
                "state": f"run={it.get('state','?')} / approve={ari.get('state','-')}",
                "approve_id": ari.get("id"),
                "approvable": ari.get("state") == "RECEIVED",
                "note": ari.get("description", "")}
    if kind == "mr":
        tok = gitlab_token()
        if not tok:
            return {"ok": False, "kind": "mr", **p, "approvable": False,
                    "err": "未配置 GITLAB_TOKEN。网页登录密码不能当 API token；需建 PAT（settings → access tokens, scope=api）后 export GITLAB_TOKEN=…"}
        proj = urllib.parse.quote(p["project"], safe="")
        st, d = req_json("GET", f"{p['host']}/api/v4/projects/{proj}/merge_requests/{p['iid']}",
                         {"PRIVATE-TOKEN": tok})
        if st != 200:
            return {"ok": False, "kind": "mr", **p, "approvable": False,
                    "err": f"MR 查询失败 HTTP {st}: {d.get('message','')}"}
        ua = (d.get("user") or {}).get("can_merge")
        return {"ok": True, "kind": "mr", **p,
                "title": d.get("title", "?"), "owner": (d.get("author") or {}).get("username", "?"),
                "state": d.get("state", "?"),
                "approvable": d.get("state") == "opened",
                "note": f"{d.get('source_branch')} → {d.get('target_branch')} can_merge={ua}"}
    return {"ok": False, "kind": "unknown", "err": f"无法识别输入: {p.get('raw','')}"}

# ---------- approve (write) ----------

def do_approve(p: dict) -> dict:
    kind = p["kind"]
    if kind == "job":
        key = fuyao_key()
        st, d = req_json("PUT", f"{FUYAO_BASE}/api/v1/jobs/operator-type",
                         {"X-Api-Key": key}, {"run_id": p["run_id"], "operator_type": "approve"})
        if st == 200 and d.get("code") == 0:
            return {"ok": True, "msg": "job approve ✓ (operator-type)"}
        st2, d2 = req_json("PUT", f"{FUYAO_BASE}/api/v1/jobs/approves",
                           {"X-Api-Key": key}, {"run_id": p["run_id"], "approval": True, "comment": ""})
        ok = st2 == 200 and d2.get("code") == 0
        return {"ok": ok, "msg": ("job approve ✓ (approves 兜底)" if ok else
                f"通道A[{st}]{d.get('message','')} 通道B[{st2}]{d2.get('message','')}")}
    if kind == "dag":
        key = fuyao_key()
        st, d = req_json("PUT", f"{FUYAO_BASE}/api/v1/fuyao-dag/workflow/approve/runs",
                         {"X-Api-Key": key},
                         {"dag_run_id": p["dag_run_id"], "dag_id": p["dag_id"],
                          "approval_state": "APPROVED", "comment": "via approve_web"})
        ok = st == 200 and d.get("code") == 0
        return {"ok": ok, "msg": f"DAG approve {'✓' if ok else '✗'} {d.get('message','')}"}
    if kind == "mr":
        tok = gitlab_token()
        if not tok:
            return {"ok": False, "msg": "未配置 GITLAB_TOKEN"}
        proj = urllib.parse.quote(p["project"], safe="")
        st, d = req_json("POST", f"{p['host']}/api/v4/projects/{proj}/merge_requests/{p['iid']}/approve",
                         {"PRIVATE-TOKEN": tok}, {})
        ok = st in (200, 201)
        return {"ok": ok, "msg": f"MR !{p['iid']} approve {'✓' if ok else '✗ HTTP %s %s' % (st, d.get('message',''))}"}
    return {"ok": False, "msg": "unknown kind"}

# ---------- page ----------

PAGE = """<!doctype html><html lang=zh><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>一键 Approve</title><style>
body{font-family:-apple-system,sans-serif;max-width:640px;margin:40px auto;padding:0 16px;background:#f6f7f9}
.card{background:#fff;border-radius:10px;padding:16px;margin:12px 0;box-shadow:0 1px 3px rgba(0,0,0,.08)}
input,button{font-size:15px;padding:10px;border-radius:8px;border:1px solid #ddd;box-sizing:border-box}
input{width:100%}
button{background:#07c160;color:#fff;border:none;cursor:pointer;width:100%;margin-top:10px}
button:disabled{background:#bbb}
.kv{display:flex;justify-content:space-between;padding:4px 0;font-size:14px}
.k{color:#888}.v{text-align:right;word-break:break-all;max-width:70%}
.ok{color:#07c160}.bad{color:#e64545}.dim{color:#999;font-size:12px}
h1{font-size:18px}
</style></head><body>
<h1>✅ 一键 Approve</h1>
<div class=card>
<input id=inp placeholder="粘贴 fuyao job 数字 / run_id / URL、DAG runs URL、或 GitLab MR URL" autofocus>
<button onclick="pre()">解析</button>
</div>
<div id=out style="display:none" class=card></div>
<div id=res style="display:none" class=card></div>
<script>
let pending=null;
function row(k,v){return `<div class=kv><span class=k>${k}</span><span class=v>${v}</span></div>`}
async function pre(){
  const t=encodeURIComponent; const inp=document.getElementById('inp').value.trim(); if(!inp)return;
  const r=await fetch('/api/precheck'+qs(),{method:'POST',headers:h(),body:JSON.stringify({input:inp})});
  const d=await r.json(); const o=document.getElementById('out'); o.style.display='block';
  if(!d.ok){o.innerHTML=`<div class=bad>✗ ${d.err||'解析失败'}</div>`;pending=null;return;}
  pending=d;
  o.innerHTML=row('类型',d.kind)+row('对象',d.title||d.run_id||'')+row('提交人',d.owner||'')+row('状态',d.state||'')+(d.note?row('备注',d.note):'')
   +(d.approvable?'<div class=ok>● 待批，可执行</div>':'<div class=dim>● 当前状态无需/不可批</div>')
   +`<button ${d.approvable?'':'disabled'} onclick="go()">Approve</button>`;
}
async function go(){
  if(!pending)return;
  const r=await fetch('/api/approve'+qs(),{method:'POST',headers:h(),body:JSON.stringify(pending)});
  const d=await r.json(); const o=document.getElementById('res'); o.style.display='block';
  o.innerHTML=`<div class="${d.ok?'ok':'bad'}">${d.ok?'✅':'❌'} ${d.msg}</div>`;
}
function qs(){const t=new URLSearchParams(location.search).get('token');return t?('?token='+t):''}
function h(){const t=new URLSearchParams(location.search).get('token');return t?{'X-Token':t,'Content-Type':'application/json'}:{'Content-Type':'application/json'}}
</script></body></html>"""

# ---------- server ----------

def make_handler(token: str | None):
    class H(BaseHTTPRequestHandler):
        def _auth(self) -> bool:
            if not token:
                return True
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            return q.get("token", [""])[0] == token or self.headers.get("X-Token") == token
        def _send(self, code: int, body, ctype="application/json; charset=utf-8"):
            data = body.encode() if isinstance(body, str) else json.dumps(body, ensure_ascii=False).encode()
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        def log_message(self, fmt, *a):
            pass  # 静默（不记录含 key 可能性）
        def do_GET(self):
            if not self._auth():
                return self._send(403, {"err": "token 无效"})
            path = urllib.parse.urlparse(self.path).path
            if path == "/health":
                return self._send(200, {"ok": True, "fuyao_key": bool(fuyao_key()), "gitlab_token": bool(gitlab_token())})
            if path == "/":
                return self._send(200, PAGE, "text/html; charset=utf-8")
            self._send(404, {"err": "not found"})
        def do_POST(self):
            if not self._auth():
                return self._send(403, {"err": "token 无效"})
            try:
                n = int(self.headers.get("Content-Length", 0))
                body = json.loads(self.rfile.read(n) or b"{}")
            except Exception:
                return self._send(400, {"err": "bad json"})
            path = urllib.parse.urlparse(self.path).path
            if path == "/api/precheck":
                inp = str(body.get("input", ""))[:4000]
                r = precheck(parse_input(inp))
                return self._send(200 if r.get("ok") else 400, r)
            if path == "/api/approve":
                if body.get("kind") not in ("job", "dag", "mr"):
                    return self._send(400, {"ok": False, "msg": "kind 不合法"})
                # 不做无预检直批：服务端复核一次状态
                chk = precheck(body)
                if not chk.get("approvable"):
                    return self._send(409, {"ok": False, "msg": f"服务器复核：当前不可批（{chk.get('state') or chk.get('err')}）"})
                return self._send(200, do_approve(body))
            self._send(404, {"err": "not found"})
    return H

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8877)
    a = ap.parse_args()
    token = os.environ.get("APPROVE_WEB_TOKEN") or None
    if a.host != "127.0.0.1" and not token:
        print("⚠️  非本机监听建议设 APPROVE_WEB_TOKEN（页面可执行 approve）", file=sys.stderr)
    print(f"approve_web → http://{a.host}:{a.port}/  fuyao_key={'✓' if fuyao_key() else '✗'} gitlab_token={'✓' if gitlab_token() else '✗'}")
    ThreadingHTTPServer((a.host, a.port), make_handler(token)).serve_forever()

if __name__ == "__main__":
    main()
