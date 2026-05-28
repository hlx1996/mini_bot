#!/usr/bin/env bash
# lib/crypt.sh — opt-in AES-256-CBC at-rest encryption for sensitive state files.
# Enabled when MINIBOT_ENCRYPT_KEY env is set (any string; pbkdf2 derives the key).
# Encrypted files have suffix .enc; helpers transparently route plain ↔ enc.
#
# Usage from elsewhere in bot.sh:
#   enc_write  <path> <content>
#   enc_append <path> <line>
#   enc_read   <path>            # echoes plaintext or empty
#   enc_remove <path>            # removes both plain and .enc variants
#   enc_exists <path>            # 0 if plain or .enc exists
#
# When MINIBOT_ENCRYPT_KEY is empty, all helpers degrade to plain file I/O.

is_encrypted() { [[ -n "${MINIBOT_ENCRYPT_KEY:-}" ]] && command -v openssl >/dev/null 2>&1; }

_enc_path() { printf '%s.enc' "$1"; }

enc_read() {
  local p="$1"
  if is_encrypted; then
    local ep; ep=$(_enc_path "$p")
    if [[ -f "$ep" ]]; then
      MINIBOT_ENCRYPT_KEY="$MINIBOT_ENCRYPT_KEY" \
        openssl enc -d -aes-256-cbc -pbkdf2 -pass env:MINIBOT_ENCRYPT_KEY -in "$ep" 2>/dev/null
      return
    fi
  fi
  [[ -f "$p" ]] && cat "$p" || true
}

enc_write() {
  local p="$1" content="$2"
  if is_encrypted; then
    local ep; ep=$(_enc_path "$p")
    printf '%s' "$content" \
      | openssl enc -aes-256-cbc -pbkdf2 -pass env:MINIBOT_ENCRYPT_KEY -out "$ep" 2>/dev/null
    rm -f "$p"
  else
    printf '%s' "$content" > "$p"
  fi
}

enc_append() {
  local p="$1" content="$2"
  if is_encrypted; then
    local prev; prev=$(enc_read "$p")
    enc_write "$p" "${prev}${content}"$'\n'
  else
    printf '%s\n' "$content" >> "$p"
  fi
}

enc_remove() { rm -f "$1" "$(_enc_path "$1")"; }

enc_exists() {
  if is_encrypted; then
    [[ -f "$(_enc_path "$1")" ]] || [[ -f "$1" ]]
  else
    [[ -f "$1" ]]
  fi
}
