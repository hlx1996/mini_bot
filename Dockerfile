FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash coreutils curl jq python3 python3-pip ca-certificates \
      cron tzdata espeak-ng \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . /app

ENV BOT_HOME=/app \
    STATE_DIR=/app/state \
    PYTHON_BIN=/usr/bin/python3 \
    TZ=Asia/Shanghai

# qoder + wxlink + lark-cli must be mounted in (they are platform-specific binaries).
# Mount example:
#   -v /path/to/qoder:/usr/local/bin/qoder
#   -v /path/to/wxlink:/usr/local/bin/wxlink
#   -v /path/to/lark-cli:/usr/local/bin/lark-cli

EXPOSE 8787
RUN chmod +x /app/bot.sh /app/install.sh /app/rotate-logs.sh /app/live-smoke.sh /app/backup.sh 2>/dev/null || true
CMD ["bash", "/app/bot.sh", "run"]
