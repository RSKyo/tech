#!/usr/bin/env bash
# ==============================================================================
# analyze_ai.sh
# ==============================================================================
#
# 通用 AI 分析工具（CLI）
#
# 示例：
#   analyze_ai.sh \
#     --system "You analyze music playlist entries." \
#     --prompt "Identify song title and artist. Return JSON only." \
#     --input "🤑 00:00 01. Right Place, Right Time — 운이 아니라 타이밍"
#
# 输出：
#   JSON（或空，表示失败 / 不可用）
#
# ==============================================================================

set -euo pipefail

# -----------------------------
# defaults
# -----------------------------
MODEL="gpt-4.1-mini"
TEMPERATURE=0
CONNECT_TIMEOUT=3
MAX_TIME=8

SYSTEM=""
PROMPT=""
INPUT=""

# -----------------------------
# args
# -----------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --system)
      SYSTEM="$2"; shift 2 ;;
    --prompt)
      PROMPT="$2"; shift 2 ;;
    --input)
      INPUT="$2"; shift 2 ;;
    --model)
      MODEL="$2"; shift 2 ;;
    --temperature)
      TEMPERATURE="$2"; shift 2 ;;
    --timeout)
      MAX_TIME="$2"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Usage:
  analyze_ai.sh --system "<system prompt>" --prompt "<user prompt>" --input "<text>"

Options:
  --system        system prompt
  --prompt        user prompt (should instruct JSON-only output)
  --input         input text
  --model         model name (default: gpt-4.1-mini)
  --temperature   sampling temperature (default: 0)
  --timeout       max request time in seconds (default: 8)
EOF
      exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1 ;;
  esac
done

# -----------------------------
# guards
# -----------------------------
[[ -n "$INPUT" ]] || exit 1
[[ -n "${OPENAI_API_KEY:-}" ]] || exit 1
command -v jq >/dev/null 2>&1 || exit 1

# -----------------------------
# build messages
# -----------------------------
messages="$(jq -n \
  --arg sys "$SYSTEM" \
  --arg usr "$PROMPT"$'\n\n'"Input:\n\"$INPUT\"" '
  [
    ( $sys | select(length > 0) | { role: "system", content: . } ),
    { role: "user", content: $usr }
  ]
')"

# -----------------------------
# call API
# -----------------------------
response="$(
  curl -s \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg model "$MODEL" \
      --argjson messages "$messages" \
      --argjson temp "$TEMPERATURE" \
      '{
        model: $model,
        messages: $messages,
        temperature: $temp
      }')"
)" || exit 1

# -----------------------------
# extract + validate JSON
# -----------------------------
content="$(echo "$response" | jq -r '.choices[0].message.content' 2>/dev/null)" || exit 1
echo "$content" | jq -e . >/dev/null 2>&1 || exit 1

# -----------------------------
# output
# -----------------------------
echo "$content"
