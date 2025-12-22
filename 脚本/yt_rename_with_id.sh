#!/usr/bin/env bash
# =============================================================================
# yt_rename_with_id.sh
# -----------------------------------------------------------------------------
# 功能：
#   - 从本地媒体文件的元信息中提取来源 URL
#   - 若 URL 中可解析出 YouTube 视频 ID
#     → 将文件重命名为：原名 [ID].ext
#   - 若 URL 为空或无法解析 ID，则不改名
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

file="${1:-}"
[[ -f "$file" ]] || exit 0

# -----------------------------------------------------------------------------
# deps
# -----------------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || exit 0
command -v ffprobe >/dev/null 2>&1 || exit 0

# -----------------------------------------------------------------------------
# URL extraction helpers
# -----------------------------------------------------------------------------
extract_url_from_text() {
  local text="${1:-}"
  [[ -z "$text" ]] && return 0

  printf '%s\n' "$text" \
    | grep -Eo 'https?://[^[:space:]"'"'"'<>()]+' \
    | head -n 1 || true
}

get_url_from_wherefroms() {
  local file="$1"

  command -v mdls >/dev/null 2>&1 || return 0

  local raw
  raw="$(mdls -name kMDItemWhereFroms -raw "$file" 2>/dev/null || true)"

  [[ -z "$raw" || "$raw" == "(null)" ]] && return 0
  extract_url_from_text "$raw"
}


get_url_from_ffprobe_tags() {
  local file="$1"

  local tags_text
  tags_text="$(ffprobe -v error \
    -show_entries format_tags \
    -of default=noprint_wrappers=1:nokey=1 \
    "$file" 2>/dev/null || true)"

  [[ -z "$tags_text" ]] && return 0
  extract_url_from_text "$tags_text"
}

# -----------------------------------------------------------------------------
# get url
# -----------------------------------------------------------------------------
url="$(get_url_from_wherefroms "$file")"
if [[ -z "$url" ]]; then
  url="$(get_url_from_ffprobe_tags "$file")"
fi

# URL 为空 → 不改名
[[ -z "$url" ]] && exit 0

# -----------------------------------------------------------------------------
# extract YouTube video ID (string parsing only)
# -----------------------------------------------------------------------------
video_id=""

re_short='youtu\.be/([^?&/]+)'
re_watch='[?&]v=([^?&/]+)'

if [[ "$url" =~ $re_short ]]; then
  video_id="${BASH_REMATCH[1]}"
elif [[ "$url" =~ $re_watch ]]; then
  video_id="${BASH_REMATCH[1]}"
fi

# 无法解析 ID → 不改名
[[ -z "$video_id" ]] && exit 0

# -----------------------------------------------------------------------------
# rename
# -----------------------------------------------------------------------------
dir="$(dirname "$file")"
ext="${file##*.}"
base="$(basename "$file" ".$ext")"

# 已包含 [ID] → 不重复改名
[[ "$base" == *"[$video_id]" ]] && exit 0

new_file="$dir/$base [$video_id].$ext"

mv -n "$file" "$new_file"
