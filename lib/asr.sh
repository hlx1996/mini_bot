#!/usr/bin/env bash
# lib/asr.sh — speech-to-text (ASR) detection + transcription for voice messages.
# Depends on: LOG_DIR, PYTHON_BIN, and ffmpeg (for decoding to 16k mono wav).
#
# Without this layer, voice notes were passed to qodercli as raw Opus binary,
# which has no speech recognition — it inlined the bytes as escaped text, both
# producing garbage answers and bloating the session until it overflowed.
#
# Backends (auto-detected in priority order; override with ASR_ENGINE):
#   openai          — OpenAI Whisper API        (OPENAI_API_KEY[, OPENAI_BASE_URL])
#   azure           — Azure Speech-to-Text      (AZURE_SPEECH_KEY + AZURE_SPEECH_REGION)
#   whisper-cpp     — local whisper.cpp binary  (WHISPER_CPP_MODEL=/path/ggml.bin)
#   faster-whisper  — local python lib          (pip install faster-whisper)
#   none            — no backend available
#
# Optional env:
#   ASR_LANG               BCP-47/ISO hint (e.g. zh, en, zh-CN). Empty = auto
#                          (openai/whisper auto-detect; azure defaults zh-CN).
#   OPENAI_ASR_MODEL       default: whisper-1   (e.g. gpt-4o-mini-transcribe)
#   FASTER_WHISPER_MODEL   default: base        (tiny|base|small|medium|large-v3)
#   WHISPER_CPP_BEAM_SIZE  default: 8  (higher = slower but more accurate)
#   WHISPER_CPP_INITIAL_PROMPT  default: "以下是普通话的句子。" (Chinese context hint)

# Echoes one of: openai | azure | whisper-cpp | faster-whisper | none
asr_engine() {
  if [[ -n "${ASR_ENGINE:-}" ]]; then echo "$ASR_ENGINE"; return; fi
  if [[ -n "${OPENAI_API_KEY:-}" ]] && command -v curl >/dev/null 2>&1; then
    echo openai; return
  fi
  if [[ -n "${AZURE_SPEECH_KEY:-}" && -n "${AZURE_SPEECH_REGION:-}" ]] \
     && command -v curl >/dev/null 2>&1; then
    echo azure; return
  fi
  if [[ -n "${WHISPER_CPP_MODEL:-}" ]] \
     && { command -v whisper-cli >/dev/null 2>&1 \
          || command -v whisper-cpp >/dev/null 2>&1; }; then
    echo whisper-cpp; return
  fi
  if "${PYTHON_BIN:-python3}" -c "import faster_whisper" >/dev/null 2>&1; then
    echo faster-whisper; return
  fi
  echo none
}

# Decode any audio container (Opus/AMR/MP3/M4A/…) into 16kHz mono PCM wav.
_asr_to_wav() {
  local in="$1" out="$2"
  ffmpeg -y -i "$in" -ar 16000 -ac 1 -c:a pcm_s16le "$out" \
    >/dev/null 2>>"$LOG_DIR/asr.err"
}

_asr_openai() {
  local wav="$1" lang="$2"
  local base="${OPENAI_BASE_URL:-https://api.openai.com/v1}"
  base="${base%/}"
  local model="${OPENAI_ASR_MODEL:-whisper-1}"
  local args=( -sS --max-time 120 -X POST "$base/audio/transcriptions"
               -H "Authorization: Bearer ${OPENAI_API_KEY}"
               -F "file=@${wav}" -F "model=${model}"
               -F "response_format=text" )
  [[ -n "$lang" ]] && args+=( -F "language=${lang}" )
  curl "${args[@]}" 2>>"$LOG_DIR/asr.err"
}

# Azure short-audio REST: best for clips < 60s. Needs a concrete language.
_asr_azure() {
  local wav="$1" lang="${2:-zh-CN}"
  [[ -z "$lang" ]] && lang="zh-CN"
  local key="${AZURE_SPEECH_KEY}" region="${AZURE_SPEECH_REGION}"
  local url="https://${region}.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=${lang}"
  local resp
  resp=$(curl -sS --max-time 60 -X POST "$url" \
          -H "Ocp-Apim-Subscription-Key: ${key}" \
          -H "Content-Type: audio/wav; codecs=audio/pcm; samplerate=16000" \
          -H "Accept: application/json" \
          --data-binary @"$wav" 2>>"$LOG_DIR/asr.err")
  printf '%s' "$resp" \
    | jq -r 'select(.RecognitionStatus=="Success") | .DisplayText // empty' 2>/dev/null
}

_asr_whisper_cpp() {
  local wav="$1" lang="$2"
  local bin
  bin=$(command -v whisper-cli 2>/dev/null || command -v whisper-cpp 2>/dev/null)
  [[ -z "$bin" ]] && return 1
  local of="${wav%.wav}"
  local bs="${WHISPER_CPP_BEAM_SIZE:-8}"
  local prompt="${WHISPER_CPP_INITIAL_PROMPT:-以下是普通话的句子。}"
  local args=( -m "${WHISPER_CPP_MODEL}" -f "$wav" -nt -otxt -of "$of"
               -l "${lang:-auto}" -bs "$bs" -bo "$bs" )
  [[ -n "$prompt" ]] && args+=( --prompt "$prompt" )
  "$bin" "${args[@]}" >/dev/null 2>>"$LOG_DIR/asr.err"
  if [[ -f "${of}.txt" ]]; then
    cat "${of}.txt"
    rm -f "${of}.txt"
  fi
}

_asr_faster_whisper() {
  local wav="$1" lang="$2"
  ASR_WAV="$wav" ASR_LANG_HINT="$lang" "${PYTHON_BIN:-python3}" - <<'PY' 2>>"$LOG_DIR/asr.err"
import os
try:
    from faster_whisper import WhisperModel
except Exception as e:
    raise SystemExit(0)
wav = os.environ["ASR_WAV"]
lang = os.environ.get("ASR_LANG_HINT") or None
size = os.environ.get("FASTER_WHISPER_MODEL", "base")
model = WhisperModel(size, device="cpu", compute_type="int8")
segments, _ = model.transcribe(wav, language=lang, vad_filter=True)
print("".join(s.text for s in segments).strip())
PY
}

# asr_transcribe <audio_file> [lang]  → echoes transcript text, empty on failure.
asr_transcribe() {
  local audio="$1" lang="${2:-${ASR_LANG:-}}"
  [[ -f "$audio" ]] || return 1
  local engine; engine=$(asr_engine)
  [[ "$engine" == none ]] && { echo "asr: no backend (see lib/asr.sh)" >>"$LOG_DIR/asr.err"; return 1; }
  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "asr: ffmpeg missing — cannot decode audio" >>"$LOG_DIR/asr.err"; return 1
  fi
  local tmp; tmp=$(mktemp -t asr.XXXXXX) || return 1
  local wav="${tmp}.wav"; rm -f "$tmp"
  if ! _asr_to_wav "$audio" "$wav" || [[ ! -s "$wav" ]]; then
    rm -f "$wav"; echo "asr: ffmpeg decode failed for $audio" >>"$LOG_DIR/asr.err"; return 1
  fi
  local text=""
  case "$engine" in
    openai)          text=$(_asr_openai "$wav" "$lang") ;;
    azure)           text=$(_asr_azure "$wav" "$lang") ;;
    whisper-cpp)     text=$(_asr_whisper_cpp "$wav" "$lang") ;;
    faster-whisper)  text=$(_asr_faster_whisper "$wav" "$lang") ;;
  esac
  rm -f "$wav"
  # Trim whitespace; collapse the result so a blank transcript reads as failure.
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  # whisper emits placeholder tokens for non-speech / undetected audio — treat
  # those as a failed transcription rather than echoing them to the user.
  local _low; _low=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')
  case "$_low" in
    "(speaking in foreign language)"|"[blank_audio]"|"[ silence ]"|"(silence)"|"[silence]"|"[music]"|"[ music ]"|"(music)"|"[applause]"|"(applause)")
      return 1 ;;
  esac
  [[ -z "$text" ]] && return 1
  printf '%s' "$text"
}
