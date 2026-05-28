#!/usr/bin/env python3
"""wxlink — thin CLI around the wechat-clawbot SDK.

Mirrors the shape of `lark-cli` so that the bash bot script can stay clean:

    wxlink login                      # one-time QR setup
    wxlink whoami                     # show currently bound WeChat account
    wxlink subscribe [--download-dir D]
                                      # long-poll inbound messages, emit NDJSON
                                      # one event per line, suitable for piping
    wxlink send-text  --to <peer> --text <txt>
    wxlink send-media --to <peer> --file <path> [--caption <txt>]

Inbound NDJSON event shape (one line per message):
{
  "type": "message",
  "id": "<msg sid>",
  "from": "<peer ilink user id, e.g. wxid_xxx@im.wechat>",
  "from_name": "<best-effort display name or peer>",
  "chat_type": "direct" | "group",
  "account_id": "<bound bot account id>",
  "text": "<consolidated text body, may be empty>",
  "media": [ {"kind":"image|voice|video|file","path":"/abs/path",
              "filename":"...","mime":"..."} , ...],
  "mentioned": true|false,
  "context_token": "<opaque>",
  "ts": <unix-ms>
}

Designed to run on macOS and Linux (Python 3.10+).
"""
from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import os
import sys
import time
from dataclasses import asdict
from pathlib import Path
from typing import Any

# wechat-clawbot SDK
from wechat_clawbot.api.client import (  # type: ignore
    WeixinApiOptions,
    close_shared_client,
    get_updates,
    send_message,
)
from wechat_clawbot.api.types import (  # type: ignore
    MessageItem,
    MessageItemType,
    MessageState,
    MessageType,
    SendMessageReq,
    TextItem,
    WeixinMessage,
)
from wechat_clawbot.auth.accounts import CDN_BASE_URL  # type: ignore
from wechat_clawbot.claude_channel.credentials import (  # type: ignore
    AccountData,
    credentials_dir,
    load_credentials,
)
from wechat_clawbot.media.download import download_media_from_item  # type: ignore
from wechat_clawbot.media.mime import get_mime_from_filename  # type: ignore
from wechat_clawbot.messaging.inbound import (  # type: ignore
    body_from_item_list,
    get_restored_tokens_for_server,
    restore_context_tokens,
    set_context_token,
)
from wechat_clawbot.messaging.send_media import send_weixin_media_file  # type: ignore
from wechat_clawbot.util.random import generate_id  # type: ignore


LONG_POLL_TIMEOUT_MS = 35_000


def _account_home(name: str) -> Path:
    """Per-account fake HOME so wechat-clawbot's credentials_dir() resolves
    to an isolated directory. Lets one machine host multiple WeChat accounts."""
    base = Path(os.environ.get("WXBOT_HOME", os.environ.get("BOT_HOME", str(Path(__file__).resolve().parent / "state"))))
    return base / "accounts" / name / "home"


def _apply_account(name: str | None) -> str:
    """If --account NAME was given, point HOME at an isolated tree so all
    SDK calls (credentials_dir / sync_buf / downloads) live under it.
    Returns the effective account label (NAME or 'default')."""
    if not name or name == "default":
        return "default"
    home = _account_home(name)
    home.mkdir(parents=True, exist_ok=True)
    os.environ["HOME"] = str(home)
    return name


# NOTE: must be called via _sync_buf_file() — credentials_dir() resolves HOME live
def _sync_buf_file() -> Path:
    return credentials_dir() / "sync_buf.txt"


def _eprint(*a: Any, **kw: Any) -> None:
    print(*a, file=sys.stderr, flush=True, **kw)


def _emit(event: dict) -> None:
    """Emit one NDJSON event to stdout (one line, line-buffered)."""
    print(json.dumps(event, ensure_ascii=False, separators=(",", ":")), flush=True)


def _require_account() -> AccountData:
    acc = load_credentials()
    if not acc:
        _eprint(
            "ERROR: no WeChat credentials found. Run `wxlink login` first.\n"
            f"  expected: {credentials_dir()/'account.json'}"
        )
        sys.exit(2)
    return acc


# ---------------------------------------------------------------------------
# login (delegates to wechat-clawbot-cc setup; this is the only blessed path)
# ---------------------------------------------------------------------------


def cmd_login(_args: argparse.Namespace) -> int:
    from wechat_clawbot.claude_channel.setup import do_qr_login

    async def _run() -> int:
        acc = await do_qr_login()
        return 0 if acc else 1

    return asyncio.run(_run())


def cmd_whoami(_args: argparse.Namespace) -> int:
    acc = _require_account()
    print(json.dumps(
        {
            "account_id": acc.account_id,
            "user_id": acc.user_id,
            "base_url": acc.base_url,
            "saved_at": acc.saved_at,
        },
        ensure_ascii=False,
        indent=2,
    ))
    return 0


# ---------------------------------------------------------------------------
# subscribe — long-poll getUpdates and stream NDJSON events
# ---------------------------------------------------------------------------


def _make_save_media_cb(download_dir: Path):
    """Return a save_media callback compatible with download_media_from_item."""
    download_dir.mkdir(parents=True, exist_ok=True)

    async def save(buf: bytes, content_type: str | None, subdir: str,
                   _max_bytes: int, original_filename: str | None = None) -> dict[str, str]:
        # Choose an extension.
        ext = ""
        if original_filename and "." in original_filename:
            ext = "." + original_filename.rsplit(".", 1)[-1]
        elif content_type:
            ct = content_type.lower()
            if "jpeg" in ct or "jpg" in ct: ext = ".jpg"
            elif "png" in ct:               ext = ".png"
            elif "gif" in ct:               ext = ".gif"
            elif "webp" in ct:              ext = ".webp"
            elif "mp4" in ct:               ext = ".mp4"
            elif "wav" in ct:               ext = ".wav"
            elif "silk" in ct:              ext = ".silk"
            elif "ogg" in ct:               ext = ".ogg"
            elif "pdf" in ct:               ext = ".pdf"
        base = (original_filename and original_filename.rsplit("/", 1)[-1]) or \
               f"wx-{int(time.time()*1000)}-{os.urandom(3).hex()}{ext or '.bin'}"
        out = download_dir / subdir / base
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(buf)
        return {"path": str(out)}

    return save


def _restore_sync_buf() -> str:
    try:
        return _sync_buf_file().read_text("utf-8")
    except (FileNotFoundError, OSError):
        return ""


def _persist_sync_buf(buf: str) -> None:
    try:
        _sync_buf_file().parent.mkdir(parents=True, exist_ok=True)
        _sync_buf_file().write_text(buf, "utf-8")
    except OSError:
        pass


def _item_kind(item: MessageItem) -> str:
    return {
        MessageItemType.IMAGE: "image",
        MessageItemType.VOICE: "voice",
        MessageItemType.VIDEO: "video",
        MessageItemType.FILE:  "file",
    }.get(item.type, "")


async def _process_message(msg: WeixinMessage, account: AccountData,
                            download_dir: Path) -> dict:
    """Convert a single inbound WeixinMessage into our NDJSON event dict."""
    save_cb = _make_save_media_cb(download_dir)

    text_body = body_from_item_list(msg.item_list) or ""
    media_records: list[dict] = []

    for item in (msg.item_list or []):
        if item.type in (MessageItemType.IMAGE, MessageItemType.VOICE,
                         MessageItemType.VIDEO, MessageItemType.FILE):
            try:
                downloaded = await download_media_from_item(
                    item,
                    CDN_BASE_URL,
                    save_cb,
                    log=lambda m: _eprint(f"[wxlink] {m}"),
                    err_log=lambda m: _eprint(f"[wxlink] ERR {m}"),
                    label="inbound",
                )
            except Exception as e:
                _eprint(f"[wxlink] download_media_from_item failed: {e}")
                continue

            kind = _item_kind(item)
            path = (downloaded.decrypted_pic_path or downloaded.decrypted_voice_path
                    or downloaded.decrypted_video_path or downloaded.decrypted_file_path)
            if path:
                filename = None
                if item.type == MessageItemType.FILE and item.file_item:
                    filename = item.file_item.file_name
                mime = (downloaded.voice_media_type or downloaded.file_media_type
                        or get_mime_from_filename(path))
                media_records.append({
                    "kind": kind, "path": path,
                    "filename": filename, "mime": mime,
                })

    sender_id = msg.from_user_id or ""
    # Persist the context_token so we can reply later.
    if msg.context_token and sender_id and account.account_id:
        set_context_token(account.account_id, sender_id, msg.context_token)

    # The iLink protocol does not currently expose a separate group-chat marker
    # in the demo deployment; we approximate by checking the suffix.
    chat_type = "group" if "@chatroom" in sender_id else "direct"

    return {
        "type": "message",
        "id": getattr(msg, "msg_sid", None) or getattr(msg, "client_id", None) or "",
        "from": sender_id,
        "from_name": sender_id.split("@", 1)[0] if sender_id else "",
        "chat_type": chat_type,
        "account_id": account.account_id,
        "account_name": os.environ.get("WXLINK_ACCOUNT_NAME", "default"),
        "text": text_body,
        "media": media_records,
        "mentioned": False,
        "context_token": msg.context_token,
        "ts": int(time.time() * 1000),
    }


async def _subscribe(download_dir: Path) -> int:
    account = _require_account()
    if account.account_id:
        restore_context_tokens(account.account_id)

    buf = _restore_sync_buf()
    _eprint(f"[wxlink] subscribing as account={account.account_id} "
            f"base={account.base_url} (resumed buf={len(buf)}B)")

    consecutive = 0
    try:
        while True:
            try:
                resp = await get_updates(
                    base_url=account.base_url,
                    token=account.token,
                    get_updates_buf=buf,
                    timeout_ms=LONG_POLL_TIMEOUT_MS,
                )
            except Exception as e:
                consecutive += 1
                _eprint(f"[wxlink] getUpdates exception ({consecutive}): {e}")
                await asyncio.sleep(min(2 * consecutive, 30))
                continue

            if (resp.ret and resp.ret != 0) or (resp.errcode and resp.errcode != 0):
                consecutive += 1
                _eprint(f"[wxlink] getUpdates error ret={resp.ret} "
                        f"errcode={resp.errcode} msg={resp.errmsg}")
                await asyncio.sleep(min(2 * consecutive, 30))
                continue

            consecutive = 0

            new_buf = resp.get_updates_buf
            if new_buf and new_buf != buf:
                buf = new_buf
                _persist_sync_buf(buf)

            for m in resp.msgs or []:
                if m.message_type != MessageType.USER:
                    continue
                try:
                    event = await _process_message(m, account, download_dir)
                except Exception as e:
                    _eprint(f"[wxlink] process_message failed: {e}")
                    continue
                _emit(event)
    finally:
        with contextlib.suppress(Exception):
            await close_shared_client()


def cmd_subscribe(args: argparse.Namespace) -> int:
    dl = Path(args.download_dir).expanduser().resolve()
    return asyncio.run(_subscribe(dl))


# ---------------------------------------------------------------------------
# send
# ---------------------------------------------------------------------------


def _lookup_context_token(account: AccountData, to: str) -> str | None:
    if account.account_id:
        restore_context_tokens(account.account_id)
    tokens = get_restored_tokens_for_server(account.account_id or "")
    return tokens.get(to)


async def _send_text(to: str, text: str) -> int:
    account = _require_account()
    ctx_token = _lookup_context_token(account, to)
    if not ctx_token:
        _eprint(f"WARNING: no context_token for {to}; reply may be rejected. "
                f"User must message the bot first.")
    opts = WeixinApiOptions(base_url=account.base_url, token=account.token,
                            context_token=ctx_token)
    client_id = generate_id("wxlink")
    req = SendMessageReq(
        msg=WeixinMessage(
            from_user_id="",
            to_user_id=to,
            client_id=client_id,
            message_type=MessageType.BOT,
            message_state=MessageState.FINISH,
            item_list=[MessageItem(type=MessageItemType.TEXT,
                                   text_item=TextItem(text=text))],
            context_token=ctx_token,
        )
    )
    try:
        await send_message(opts, req)
        print(json.dumps({"ok": True, "client_id": client_id}))
        return 0
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))
        return 1
    finally:
        with contextlib.suppress(Exception):
            await close_shared_client()


async def _send_media(to: str, file_path: str, caption: str) -> int:
    account = _require_account()
    ctx_token = _lookup_context_token(account, to)
    opts = WeixinApiOptions(base_url=account.base_url, token=account.token,
                            context_token=ctx_token)
    try:
        res = await send_weixin_media_file(file_path, to, caption or "", opts, CDN_BASE_URL)
        print(json.dumps({"ok": True, **res}))
        return 0
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))
        return 1
    finally:
        with contextlib.suppress(Exception):
            await close_shared_client()


def cmd_send_text(args: argparse.Namespace) -> int:
    return asyncio.run(_send_text(args.to, args.text))


def cmd_send_media(args: argparse.Namespace) -> int:
    return asyncio.run(_send_media(args.to, args.file, args.caption or ""))


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------


def cmd_accounts(_args: argparse.Namespace) -> int:
    """List known account profiles (those with a saved credentials file)."""
    base = Path(os.environ.get("WXBOT_HOME", os.environ.get("BOT_HOME", str(Path(__file__).resolve().parent / "state")))) / "accounts"
    rows = []
    if base.is_dir():
        for d in sorted(base.iterdir()):
            cred = d / "home" / ".claude" / "channels" / "wechat" / "account.json"
            rows.append({"name": d.name, "logged_in": cred.exists(),
                         "cred_path": str(cred)})
    # default account lives at real $HOME
    default_cred = Path.home() / ".claude" / "channels" / "wechat" / "account.json"
    rows.insert(0, {"name": "default", "logged_in": default_cred.exists(),
                    "cred_path": str(default_cred)})
    print(json.dumps(rows, ensure_ascii=False, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="wxlink", description=__doc__.splitlines()[0])
    p.add_argument("--account", default=os.environ.get("WXLINK_ACCOUNT", "default"),
                   help="account profile name (multi-WeChat support). "
                        "Each name has its own isolated credentials dir. "
                        "Default: 'default'. Override with $WXLINK_ACCOUNT.")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("login", help="QR-code login (one-time setup)").set_defaults(fn=cmd_login)
    sub.add_parser("whoami", help="show bound account info").set_defaults(fn=cmd_whoami)
    sub.add_parser("accounts", help="list known account profiles").set_defaults(fn=cmd_accounts)

    ps = sub.add_parser("subscribe", help="long-poll inbound messages, emit NDJSON")
    ps.add_argument("--download-dir", default=str(Path(__file__).resolve().parent / "state" / "downloads"),
                    help="where to save downloaded media (default: <repo>/state/downloads)")
    ps.set_defaults(fn=cmd_subscribe)

    pt = sub.add_parser("send-text", help="send a text message")
    pt.add_argument("--to", required=True, help="recipient ilink user id (xxx@im.wechat)")
    pt.add_argument("--text", required=True)
    pt.set_defaults(fn=cmd_send_text)

    pm = sub.add_parser("send-media", help="send an image/video/file (auto-routed by mime)")
    pm.add_argument("--to", required=True)
    pm.add_argument("--file", required=True)
    pm.add_argument("--caption", default="")
    pm.set_defaults(fn=cmd_send_media)

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    name = _apply_account(getattr(args, "account", None))
    os.environ["WXLINK_ACCOUNT_NAME"] = name
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
