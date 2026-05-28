#!/usr/bin/env bash
# lib/tts.sh — TTS detection / synthesis / per-chat enable+voice+rate.
# Depends on: SESS_DIR, TTS_DIR, LOG_DIR.

# ---------- TTS (voice reply) ----------
# Detect available TTS engine. Echoes one of: say | espeak-ng | piper | none
tts_engine() {
  if command -v say >/dev/null 2>&1; then echo say
  elif command -v espeak-ng >/dev/null 2>&1; then echo espeak-ng
  elif command -v piper >/dev/null 2>&1; then echo piper
  else echo none
  fi
}

# Synthesize text -> audio file path. Echoes path on success, empty on failure.
tts_synthesize() {
  local text="$1" out_base="$2" key="${3:-}"
  local engine; engine=$(tts_engine)
  local voice="" rate=""
  if [[ -n "$key" ]]; then
    voice=$(tts_voice_get "$key")
    rate=$(tts_rate_get "$key")
  fi
  case "$engine" in
    say)
      local out="$out_base.aiff"
      local -a args=()
      [[ -n "$voice" ]] && args+=(-v "$voice")
      [[ -n "$rate"  ]] && args+=(-r "$rate")
      say "${args[@]}" -o "$out" -- "$text" 2>>"$LOG_DIR/tts.err" || return 1
      # Try to convert to mp3 with ffmpeg for better WeChat compatibility
      if command -v ffmpeg >/dev/null 2>&1; then
        local mp3="$out_base.mp3"
        ffmpeg -y -i "$out" -codec:a libmp3lame -qscale:a 4 "$mp3" \
          >/dev/null 2>>"$LOG_DIR/tts.err" && { rm -f "$out"; echo "$mp3"; return 0; }
      fi
      echo "$out"; return 0
      ;;
    espeak-ng)
      local out="$out_base.wav"
      local -a args=()
      [[ -n "$voice" ]] && args+=(-v "$voice")
      [[ -n "$rate"  ]] && args+=(-s "$rate")
      espeak-ng "${args[@]}" -w "$out" -- "$text" 2>>"$LOG_DIR/tts.err" || return 1
      echo "$out"; return 0
      ;;
    piper)
      local out="$out_base.wav"
      printf '%s' "$text" | piper --output_file "$out" 2>>"$LOG_DIR/tts.err" || return 1
      echo "$out"; return 0
      ;;
    *) return 1 ;;
  esac
}

# Per-chat TTS toggle: $SESS_DIR/<key>.tts (file present == enabled)
tts_is_on()   { [[ -f "$SESS_DIR/$1.tts" ]]; }
tts_enable()  { : > "$SESS_DIR/$1.tts"; }
tts_disable() { rm -f "$SESS_DIR/$1.tts"; }

# Per-chat TTS voice/rate (empty -> engine default)
tts_voice_get() { local f="$SESS_DIR/$1.tts_voice"; [[ -f "$f" ]] && cat "$f" || true; }
tts_voice_set() { printf '%s' "$2" > "$SESS_DIR/$1.tts_voice"; }
tts_rate_get()  { local f="$SESS_DIR/$1.tts_rate";  [[ -f "$f" ]] && cat "$f" || true; }
tts_rate_set()  { printf '%s' "$2" > "$SESS_DIR/$1.tts_rate"; }

# List available TTS voices for current engine (newline-separated).
tts_list_voices() {
  local engine; engine=$(tts_engine)
  case "$engine" in
    say)       say -v '?' 2>/dev/null | awk '{print $1}' ;;
    espeak-ng) espeak-ng --voices 2>/dev/null | awk 'NR>1 {print $4}' ;;
    *) : ;;
  esac
}
