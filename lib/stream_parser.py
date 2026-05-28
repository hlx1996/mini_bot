#!/usr/bin/env python3
"""stream_parser.py — read qodercli `--output-format stream-json` NDJSON from
stdin, emit one progress line per interesting event to fd 3 (progress channel),
and print the final assistant text to stdout at the end.

Stream protocol from qodercli (observed):
  {"type":"system","subtype":"init",...}              # session init
  {"type":"assistant","message":{...,"content":[
       {"type":"thinking","thinking":"..."} | ...
       {"type":"tool_use","name":"Read","input":{...}} | ...
       {"type":"text","text":"final answer..."}
  ]}}                                                  # may appear multiple times
  {"type":"user","message":{"role":"user","content":[
       {"type":"tool_result","content":"..."}
  ]}}                                                  # tool results
  {"type":"result","subtype":"success","result":"..."} # final, authoritative

Progress channel is fd 3 if open, else /dev/null. Caller wires up via
`exec 3>>progress.fifo` before launching.
"""
import sys, json, os

ICONS = {
    "Read": "📄 读取",
    "Write": "📝 写入",
    "Edit": "✏️ 编辑",
    "Bash": "💻 运行",
    "Grep": "🔎 搜索",
    "Glob": "📂 列举",
    "WebFetch": "🌐 抓取",
    "WebSearch": "🔍 联网搜索",
    "ImageGen": "🎨 生成图片",
    "ImageSearch": "🖼️ 找图",
    "Skill": "🧩 调用技能",
    "TodoWrite": "📌 记录待办",
    "Agent": "🤖 子智能体",
}


def progress(msg: str) -> None:
    try:
        os.write(3, (msg + "\n").encode("utf-8"))
    except (OSError, BrokenPipeError):
        pass


def short_input(name: str, inp: dict) -> str:
    if not isinstance(inp, dict):
        return ""
    if name in ("Read", "Write", "Edit"):
        p = inp.get("file_path") or inp.get("path") or ""
        return f" {os.path.basename(p)}" if p else ""
    if name == "Bash":
        cmd = inp.get("command", "")
        return f" `{cmd[:60]}{'…' if len(cmd) > 60 else ''}`"
    if name in ("Grep", "Glob"):
        return f" {inp.get('pattern', '')[:40]}"
    if name in ("WebFetch", "WebSearch"):
        return f" {(inp.get('url') or inp.get('query') or '')[:60]}"
    return ""


def main() -> int:
    final_text = ""
    sent_first_thinking = False
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except Exception:
            continue
        t = ev.get("type")
        if t == "assistant":
            msg = ev.get("message") or {}
            for blk in (msg.get("content") or []):
                bt = blk.get("type")
                if bt == "thinking" and not sent_first_thinking:
                    sent_first_thinking = True
                    progress("🤔 思考中…")
                elif bt == "tool_use":
                    name = blk.get("name", "?")
                    label = ICONS.get(name, f"🛠 {name}")
                    progress(f"{label}{short_input(name, blk.get('input') or {})}")
                elif bt == "text":
                    txt = (blk.get("text") or "").strip()
                    if txt:
                        final_text = txt
        elif t == "result":
            res = (ev.get("result") or "").strip()
            if res:
                final_text = res
            break
    try:
        sys.stdout.write(final_text)
        sys.stdout.flush()
    except BrokenPipeError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
