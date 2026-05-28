#!/usr/bin/env python3
"""url_fetch.py — read user message from stdin, fetch any http(s):// URLs (up to 3),
strip HTML to text, cap each at 2500 chars, and print as a single [Web page] block.
Exits 0 with output if URLs were found, exits 0 with no output otherwise.

Extracted from a bash heredoc to avoid a fork-chain gremlin where heredocs piped
into python can be served stale content under deep bash subprocess nesting.
"""
import sys, re, subprocess, html


def main() -> int:
    text = sys.stdin.read()
    APO = chr(39)
    stop = "\\s\u4e00-\u9fff，。、！？；：)\\]}<>\"" + APO + "\\\\"
    urls = re.findall(r"https?://[^" + stop + r"]+", text)
    urls = urls[:3]
    if not urls:
        return 0

    out = ["[Web page] (fetched live):"]
    for u in urls:
        try:
            r = subprocess.run(
                ["curl", "-sL", "--max-time", "12",
                 "-A", "Mozilla/5.0 mini_bot/1.0", u],
                capture_output=True, timeout=15,
            )
            body = r.stdout.decode("utf-8", "ignore")
        except Exception as e:
            out.append(f"--- {u} ---\n(fetch failed: {e})")
            continue
        body = re.sub(r"(?is)<script.*?</script>", " ", body)
        body = re.sub(r"(?is)<style.*?</style>", " ", body)
        body = re.sub(r"(?s)<[^>]+>", " ", body)
        body = html.unescape(body)
        body = re.sub(r"[ \t]+", " ", body)
        body = re.sub(r"\n\s*\n+", "\n\n", body).strip()
        if len(body) > 2500:
            body = body[:2500] + "...[truncated]"
        out.append(f"--- {u} ---\n{body}")
    try:
        print("\n".join(out))
    except BrokenPipeError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
