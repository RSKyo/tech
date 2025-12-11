#!/usr/bin/env bash
#
# ==============================================================================
# yt_tracklist_extractor.sh
# ==============================================================================
#
# 用途：
#   给定一个 YouTube 视频 URL，从“视频描述(description)”中自动提取
#   最长的、连续的、符合 track_types.json 所定义结构的“曲目列表块”。
#
# 特性：
#   ✔ 只处理单个 YouTube 地址（不做批量）
#   ✔ 不解析行内容，仅根据结构判断行是否属于 track line
#   ✔ 输出匹配到的原始多行文本，不额外添加换行
#   ✔ track_types.json 必须与脚本在同一目录，否则报错
#
# 依赖：
#   - yt-dlp    (brew install yt-dlp)
#   - jq        (brew install jq)
#
# 使用方法：
#       ./yt_tracklist_extractor.sh "https://www.youtube.com/watch?v=xxxx"
#
# 输出：
#       匹配到的最长连续曲目行块（原始文本）。
#       若未找到任何匹配块，仅输出警告至 stderr。
#
# ==============================================================================

set -euo pipefail

# ---------- locate script & types ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TYPES_FILE="$SCRIPT_DIR/track_types.json"

if [[ ! -f "$TYPES_FILE" ]]; then
echo "❌ 缺少 track_types.json（需要放在脚本同目录：$SCRIPT_DIR ）" >&2
  exit 1
fi

# ---------- check dependencies ----------
if ! command -v yt-dlp >/dev/null 2>&1; then
  echo "❌ 缺少 yt-dlp，请先安装：brew install yt-dlp" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ 缺少 jq，请先安装：brew install jq" >&2
  exit 1
fi

# ---------- verify input ----------
if [[ $# -lt 1 ]]; then
  echo "用法：$0 \"<YouTube URL>\"" >&2
  exit 1
fi

URL="$1"

# ---------- load regex types ----------
TYPES_JSON=$(cat "$TYPES_FILE")
TYPES=$(echo "$TYPES_JSON" | jq -c '.[]')

# ---------- function: match line to any track type ----------
is_track_line() {
  local line="$1"
  local obj regex

  while read -r obj; do
    regex=$(echo "$obj" | jq -r '.regex')
    if [[ "$line" =~ $regex ]]; then
      return 0  # match
    fi
  done <<< "$TYPES"

  return 1        # no match
}

# ---------- fetch description ----------
desc=$(yt-dlp --no-playlist -O "%(description)s" "$URL" 2>/dev/null || true)

if [[ -z "$desc" ]]; then
  echo "⚠️ 视频描述为空，无可提取的曲目。" >&2
  exit 0
fi

# ---------- find the longest valid tracklist block ----------
best=""
current=""
best_len=0
cur_len=0

while IFS='' read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"  # 去除 CRLF

  # 空行立即终止 current block
  if [[ -z "$(echo "$line" | tr -d '[:space:]')" ]]; then
    if ((cur_len > best_len)); then
      best="$current"
      best_len=$cur_len
    fi
    current=""
    cur_len=0
    continue
  fi

  # 是否为 track 行
  if is_track_line "$line"; then
    # 去掉前缀，只保留从时间戳开始
    cleaned=$(echo "$line" | sed -E 's/^[^0-9]*([0-9]{1,2}:[0-9]{2}(:[0-9]{2})?.*)$/\1/')
    current+="$cleaned"$'\n'

    cur_len=$((cur_len + 1))
  else
    # block 结束
    if ((cur_len > best_len)); then
      best="$current"
      best_len=$cur_len
    fi
    current=""
    cur_len=0
  fi

done <<< "$desc"

# 最后一次检查
if ((cur_len > best_len)); then
  best="$current"
fi

# ---------- output ----------
if [[ -z "$best" ]]; then
  echo "⚠ 未找到符合 track_types.json 的曲目列表。" >&2
  exit 0
fi

# 输出匹配块 —— ⚠ 不额外添加换行
printf '%s' "$best"

exit 0
