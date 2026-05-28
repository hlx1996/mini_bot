#!/usr/bin/env python3
"""Read lark-cli NDJSON events on stdin, emit mini_bot event JSON on stdout.

Argv: <account_name> <download_dir> <lark_as_identity>
"""
import sys
import json
import os
import subprocess
import traceback


def process(line, acct, dl_dir, as_id):
    try:
        ev = json.loads(line)
    except Exception:
        return
    if ev.get("header", {}).get("event_type") != "im.message.receive_v1":
        return
    msg = ev.get("event", {}).get("message", {}) or {}
    sender_obj = ev.get("event", {}).get("sender", {}) or {}
    sender = sender_obj.get("sender_id") or {}
    if not isinstance(sender, dict):
        sender = {}
    mtype = msg.get("message_type")
    raw = msg.get("content") or "{}"
    try:
        content = json.loads(raw)
    except Exception:
        content = {}
    text = ""
    media = []
    if mtype == "text":
        text = content.get("text", "") or ""
    elif mtype == "image":
        ikey = content.get("image_key")
        if ikey:
            fpath = os.path.join(dl_dir, ikey + ".jpg")
            try:
                subprocess.run(
                    ["lark-cli", "im", "+messages-resources-download",
                     "--message-id", msg.get("message_id", ""),
                     "--file-key", ikey, "--type", "image",
                     "--output", os.path.basename(fpath), "--as", as_id],
                    cwd=dl_dir, check=False,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    timeout=30,
                )
                if os.path.exists(fpath):
                    media.append({"kind": "image", "path": fpath})
            except Exception:
                pass
    elif mtype == "post":
        title = content.get("title", "") or ""
        texts = []
        for row in content.get("content", []) or []:
            for el in row or []:
                if isinstance(el, dict) and el.get("tag") == "text":
                    texts.append(el.get("text", "") or "")
        text = "\n".join([t for t in [title] + texts if t])
    elif mtype in ("file", "audio", "media"):
        fkey = content.get("file_key")
        if fkey:
            fpath = os.path.join(dl_dir, fkey)
            try:
                subprocess.run(
                    ["lark-cli", "im", "+messages-resources-download",
                     "--message-id", msg.get("message_id", ""),
                     "--file-key", fkey, "--type", "file",
                     "--output", os.path.basename(fpath), "--as", as_id],
                    cwd=dl_dir, check=False,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    timeout=60,
                )
                if os.path.exists(fpath):
                    kind = "audio" if mtype == "audio" else ("video" if mtype == "media" else "file")
                    media.append({"kind": kind, "path": fpath})
            except Exception:
                pass
    else:
        return

    mentions = msg.get("mentions") or ev.get("event", {}).get("mentions") or []
    out = {
        "type": "message",
        "platform": "lark",
        "id": msg.get("message_id", ""),
        "from": msg.get("chat_id", ""),
        "from_name": sender.get("user_id") or sender.get("open_id", ""),
        "from_open_id": sender.get("open_id", ""),
        "chat_type": "group" if msg.get("chat_type") == "group" else "direct",
        "account_id": acct,
        "account_name": acct,
        "text": text,
        "mentioned": bool(mentions),
        "media": media,
        "reply_to": msg.get("message_id", ""),
    }
    try:
        sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        os._exit(0)


def main():
    if len(sys.argv) < 4:
        sys.stderr.write("usage: lark_event_parser.py <acct> <dl_dir> <as_id>\n")
        sys.exit(2)
    acct, dl_dir, as_id = sys.argv[1], sys.argv[2], sys.argv[3]
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            process(line, acct, dl_dir, as_id)
        except BrokenPipeError:
            os._exit(0)
        except Exception:
            sys.stderr.write("[lark-parse-error] " + traceback.format_exc() + "\n")
            sys.stderr.flush()


if __name__ == "__main__":
    main()
