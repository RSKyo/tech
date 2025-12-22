#!/usr/bin/env bash
# ==============================================================================
# parse_tracklist.sh
# ==============================================================================
#
# 读取 tracklist.txt（每行一个 raw track），输出 JSON 数组。
#
# 每个元素结构：
# {
#   raw:  "<原始整行>",
#   time: "<时间戳>",
#   text: "<去时间戳前缀与序号后的正文>",
#   ai:   { ... } | {}
# }
#
# 特性：
# - 解析逻辑完全确定性
# - AI 为可选外挂能力
# - AI 失败 / 网络异常 / 无法判断 → ai: {}
# - AI_DEBUG=1 时，在 stderr 输出失败原因
#
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# config
# ------------------------------------------------------------------------------
ENABLE_AI=0                 # 0 = 完全关闭 AI
AI_DEBUG=0                  # 1 = 输出 AI 失败原因到 stderr

# -----------------------------------------------------------------------------
# 基础：路径与依赖检查
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_CMD="$SCRIPT_DIR/analyze_ai.sh"

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
if [ $# -lt 1 ]; then
  echo "Usage: $0 tracklist.txt" >&2
  exit 1
fi

TRACKLIST_FILE="$1"

if [ ! -f "$TRACKLIST_FILE" ]; then
  echo "Error: file not found: $TRACKLIST_FILE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# regex (single source of truth)
# ------------------------------------------------------------------------------
TIME_REGEX='([0-9]{1,2}:[0-9]{2}:[0-9]{2}|[0-9]{1,2}:[0-9]{2})'

items=()

# ------------------------------------------------------------------------------
# main loop
# ------------------------------------------------------------------------------
while IFS= read -r raw || [ -n "$raw" ]; do
  raw="${raw%$'\r'}"

  # 跳过空行
  if [[ -z "$(printf '%s' "$raw" | tr -d '[:space:]')" ]]; then
    continue
  fi

  # 提取时间戳
  if [[ "$raw" =~ $TIME_REGEX ]]; then
    time="${BASH_REMATCH[1]}"
  else
    continue
  fi

  # 去掉时间戳前的所有内容
  after_time="$(echo "$raw" | sed -E "s/^.*$TIME_REGEX[[:space:]]*//")"

  # 去掉紧跟的序号（仅时间戳之后）
  text="$(echo "$after_time" | sed -E '
    s/^[[:space:]]*([0-9]{1,3}[\.\、])[[:space:]]*//;
    s/^[[:space:]]*\([0-9]{1,3}\)[[:space:]]*//;
    s/^[[:space:]]*#[0-9]{1,3}[[:space:]]*//;
    s/^[[:space:]]*[IVXLCDM]+\.[[:space:]]*//;
  ')"

  # 仅去前后空格
  text="$(echo "$text" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  # ----------------------------------------------------------------------------
  # optional AI analysis
  # ----------------------------------------------------------------------------
  ai_json='{}'

  if (( ENABLE_AI == 1 )) \
  && [[ -x "$AI_CMD" ]] \
  && [[ -n "${OPENAI_API_KEY:-}" ]]; then

    ai_err_file="$(mktemp 2>/dev/null || true)"

    if [[ -z "$ai_err_file" ]]; then
      ai_err_file="/dev/null"
    fi


    if ai_out="$(
      "$AI_CMD" \
        --system "You analyze music playlist entries." \
        --prompt \
  "Given ONE track entry from a playlist:
  1. Identify the song title if it can be determined with reasonable confidence.
  2. Identify the artist ONLY if explicitly present.
  3. If uncertain, return null.
  4. Do NOT guess or hallucinate.
  5. Return JSON only.

  Required format:
  { \"title\": string|null, \"artist\": string|null, \"confidence\": number }" \
        --input "$raw" \
        2>"$ai_err_file"
    )"; then
      ai_json="$ai_out"
    else
      if (( AI_DEBUG == 1 )); then
        echo "[AI_DEBUG] AI skipped for raw:" >&2
        echo "  $raw" >&2
        if [ -s "$ai_err_file" ]; then
          sed 's/^/  /' "$ai_err_file" >&2
        else
          echo "  (no error output; possibly timeout or empty response)" >&2
        fi
      fi
    fi

    rm -f "$ai_err_file"
  fi

  # ----------------------------------------------------------------------------
  # assemble item
  # ----------------------------------------------------------------------------
  items+=("$(
    jq -n \
      --arg raw "$raw" \
      --arg time "$time" \
      --arg text "$text" \
      --argjson ai "$ai_json" \
      '{
        raw: $raw,
        time: $time,
        text: $text,
        ai: $ai
      }'
  )")

done < "$TRACKLIST_FILE"

# ------------------------------------------------------------------------------
# output
# ------------------------------------------------------------------------------
printf '%s\n' "${items[@]}" | jq -s .
