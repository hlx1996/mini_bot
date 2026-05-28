#!/usr/bin/env bash
# lib/tts.sh — TTS detection / synthesis / per-chat enable+voice+rate.
# Depends on: SESS_DIR, TTS_DIR, LOG_DIR.
# Optional env vars:
#   TTS_ENGINE              force one of: azure | say | espeak-ng | piper
#   AZURE_SPEECH_KEY        Azure Cognitive Services Speech subscription key
#   AZURE_SPEECH_REGION     e.g. eastus, eastasia, westus2
#   AZURE_SPEECH_VOICE      default voice (e.g. zh-CN-XiaoxiaoNeural)

# ---------- TTS (voice reply) ----------
# Detect available TTS engine. Echoes one of: azure | say | espeak-ng | piper | none
tts_engine() {
  if [[ -n "${TTS_ENGINE:-}" ]]; then echo "$TTS_ENGINE"; return; fi
  if [[ -n "${AZURE_SPEECH_KEY:-}" && -n "${AZURE_SPEECH_REGION:-}" ]] \
     && command -v curl >/dev/null 2>&1; then echo azure; return
  fi
  if command -v say >/dev/null 2>&1; then echo say
  elif command -v espeak-ng >/dev/null 2>&1; then echo espeak-ng
  elif command -v piper >/dev/null 2>&1; then echo piper
  else echo none
  fi
}

# Synthesize via Azure Cognitive Services Speech (REST).
# Voice format: "<voice-name>" or "<voice-name>:<style>" or "<voice-name>:<style>:<degree>"
# e.g. "zh-CN-XiaoxiaoNeural", "zh-CN-XiaoxiaoNeural:cheerful",
#      "zh-CN-XiaoxiaoNeural:sad:2"
_tts_azure_synth() {
  local text="$1" out="$2" voice_spec="$3" rate="$4"
  local key="${AZURE_SPEECH_KEY}" region="${AZURE_SPEECH_REGION}"
  [[ -z "$voice_spec" ]] && voice_spec="${AZURE_SPEECH_VOICE:-zh-CN-XiaoxiaoNeural}"
  local voice style degree
  voice="${voice_spec%%:*}"
  local rest="${voice_spec#*:}"
  if [[ "$rest" != "$voice_spec" ]]; then
    style="${rest%%:*}"
    local rest2="${rest#*:}"
    [[ "$rest2" != "$rest" ]] && degree="$rest2"
  fi
  # Build SSML. XML-escape text minimally.
  local esc
  esc=$(printf '%s' "$text" \
        | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
              -e 's/"/\&quot;/g' -e "s/'/\&apos;/g")
  local lang="${voice%%-*}-${voice#*-}"; lang="${lang%%-*}-${voice#*-}"
  lang="${voice:0:5}"  # e.g. zh-CN
  local prosody_open="" prosody_close=""
  if [[ -n "$rate" ]]; then
    prosody_open="<prosody rate=\"${rate}%\">"; prosody_close="</prosody>"
  fi
  local express_open="" express_close=""
  if [[ -n "$style" ]]; then
    local deg_attr=""
    [[ -n "$degree" ]] && deg_attr=" styledegree=\"$degree\""
    express_open="<mstts:express-as style=\"${style}\"${deg_attr}>"
    express_close="</mstts:express-as>"
  fi
  local ssml
  ssml=$(cat <<XML
<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xmlns:mstts="http://www.w3.org/2001/mstts" xml:lang="${lang}">
<voice name="${voice}">${express_open}${prosody_open}${esc}${prosody_close}${express_close}</voice>
</speak>
XML
)
  local mp3="${out}.mp3"
  local code
  code=$(curl -sS -o "$mp3" -w '%{http_code}' \
    --max-time 30 \
    -X POST "https://${region}.tts.speech.microsoft.com/cognitiveservices/v1" \
    -H "Ocp-Apim-Subscription-Key: ${key}" \
    -H "Content-Type: application/ssml+xml" \
    -H "X-Microsoft-OutputFormat: audio-24khz-48kbitrate-mono-mp3" \
    -H "User-Agent: mini_bot" \
    --data-binary @<(printf '%s' "$ssml") 2>>"$LOG_DIR/tts.err")
  if [[ "$code" != "200" || ! -s "$mp3" ]]; then
    echo "azure TTS HTTP $code voice=$voice" >>"$LOG_DIR/tts.err"
    [[ -f "$mp3" ]] && head -c 500 "$mp3" >>"$LOG_DIR/tts.err" && echo >>"$LOG_DIR/tts.err"
    rm -f "$mp3"
    return 1
  fi
  echo "$mp3"
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
    azure)
      _tts_azure_synth "$text" "$out_base" "$voice" "$rate"  # echoes mp3 path
      return $?
      ;;
    say)
      local out="$out_base.aiff"
      local -a args=()
      [[ -n "$voice" ]] && args+=(-v "$voice")
      [[ -n "$rate"  ]] && args+=(-r "$rate")
      say ${args[@]+"${args[@]}"} -o "$out" -- "$text" 2>>"$LOG_DIR/tts.err" || return 1
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
      espeak-ng ${args[@]+"${args[@]}"} -w "$out" -- "$text" 2>>"$LOG_DIR/tts.err" || return 1
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
    azure)
      # Static list of popular Chinese + English neural voices.
      # Full list: see https://learn.microsoft.com/azure/ai-services/speech-service/language-support
      cat <<'V'
zh-CN-XiaoxiaoNeural
zh-CN-XiaoyiNeural
zh-CN-YunxiNeural
zh-CN-YunyangNeural
zh-CN-YunjianNeural
zh-CN-XiaomoNeural
zh-CN-XiaohanNeural
zh-CN-XiaoqiuNeural
zh-CN-XiaoshuangNeural
zh-CN-YunfengNeural
zh-CN-YunhaoNeural
zh-CN-XiaoxuanNeural
zh-HK-HiuMaanNeural
zh-HK-WanLungNeural
zh-TW-HsiaoChenNeural
zh-TW-YunJheNeural
en-US-JennyNeural
en-US-GuyNeural
en-US-AriaNeural
en-GB-RyanNeural
ja-JP-NanamiNeural
ko-KR-SunHiNeural
V
      ;;
    say)       say -v '?' 2>/dev/null | awk '{print $1}' ;;
    espeak-ng) espeak-ng --voices 2>/dev/null | awk 'NR>1 {print $4}' ;;
    *) : ;;
  esac
}
