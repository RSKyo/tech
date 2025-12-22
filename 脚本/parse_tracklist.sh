#!/usr/bin/env bash
# --------------------------------------------
# parse_tracklist.sh
# --------------------------------------------
# 读取一个 tracklist.txt
# 调用 parse_track.sh 逐条解析
# 输出 JSON 数组
# --------------------------------------------

set -euo pipefail

# ---------- config ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/parse_track.sh"

# ---------- check ----------
if [ $# -lt 1 ]; then
  echo "Usage: $0 tracklist.txt" >&2
  exit 1
fi

TRACKLIST_FILE="$1"

if [ ! -f "$TRACKLIST_FILE" ]; then
  echo "Error: file not found: $TRACKLIST_FILE" >&2
  exit 1
fi

if [ ! -x "$PARSER" ]; then
  echo "Error: parse_track.sh not found or not executable" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 1
fi

# ---------- read & normalize ----------
# 规则：
# 1. 空行跳过
# 2. 如果某行后面紧跟着一行以 "/" 开头 → 合并成一个输入
# 3. 其他情况：一行就是一个 track

tracks=()
pending=""

while IFS= read -r line || [ -n "$line" ]; do
  # 去掉行尾回车（防 Windows CRLF）
  line="${line%$'\r'}"

  # 空行：直接跳过
  if [[ -z "$(printf '%s' "$line" | tr -d '[:space:]')" ]]; then
    continue
  fi

  # 如果是 slug 行（以 / 开头）
  if [[ "$line" =~ ^[[:space:]]*/ ]]; then
    if [ -n "$pending" ]; then
      pending="$pending"$'\n'"$line"
      tracks+=("$pending")
      pending=""
    fi
    continue
  fi

  # 如果 pending 里已有一行，说明它是“单行 track”
  if [ -n "$pending" ]; then
    tracks+=("$pending")
    pending=""
  fi

  # 当前行作为新的 pending
  pending="$line"
done < "$TRACKLIST_FILE"

# 文件结束后，如果还有 pending，收尾
if [ -n "$pending" ]; then
  tracks+=("$pending")
fi

# ---------- parse each track ----------
# 输出 JSON 数组

jq -n --argjson items "$(
  for t in "${tracks[@]}"; do
    "$PARSER" "$t"
  done | jq -s .
)" '$items'
