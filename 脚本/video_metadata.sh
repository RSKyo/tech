#!/usr/bin/env bash
# ==============================================================================
# video_metadata.sh
# ------------------------------------------------------------------------------
# 【用途】
#   读取本地视频文件的元信息，并以 JSON 形式输出统一、可直接消费的数据，
#   供其他脚本（如 media_segment_plan.sh、视频转MP3助手.sh）调用。
#
#   本脚本的定位是“基础元数据服务”，输出结果已做规范化与兜底处理，
#   上层脚本无需再关心 ffprobe 细节或来源推断逻辑。
#
# ------------------------------------------------------------------------------
# 【依赖】
#   - ffprobe  （FFmpeg 套件的一部分，用于读取媒体元数据）
#   - jq       （用于构造与解析 JSON）
#   - mdls     （可选，仅 macOS，用于读取 Finder 的 WhereFroms 元数据）
#
# ------------------------------------------------------------------------------
# 【输出 JSON 结构】
#   {
#     "duration": <number>,      视频总秒数（float；失败时为 0）
#     "title": "<string>",       视频标题（tags.title；若不存在则使用文件名）
#     "artist": "<string>",      艺术家（tags.artist；缺失为空字符串）
#     "album": "<string>",       专辑名（tags.album；缺失为空字符串）
#     "genre": "<string>",       流派（tags.genre；缺失为空字符串）
#     "url": "<string>"          视频来源网页 URL（http/https；缺失为空字符串）
#   }
#
# ------------------------------------------------------------------------------
# 【使用示例】
#
# 1) 直接查看完整元数据 JSON
#
#     ./video_metadata.sh "/path/to/video.webm"
#
#     输出示例：
#     {
#       "duration": 13267.848,
#       "title": "Morning drifts in soft and low",
#       "artist": "",
#       "album": "",
#       "genre": "",
#       "url": "https://www.youtube.com/watch?v=LS7vyhX74Uk"
#     }
#
# 2) 在脚本中读取并使用字段（推荐方式）
#
#     META_JSON="$(./video_metadata.sh "$VIDEO")"
#
#     duration="$(jq -r '.duration' <<<"$META_JSON")"
#     title="$(jq -r '.title' <<<"$META_JSON")"
#     artist="$(jq -r '.artist' <<<"$META_JSON")"
#     url="$(jq -r '.url' <<<"$META_JSON")"
#
#     if [ -n "$url" ]; then
#       echo "来源 URL：$url"
#     fi
#
# 3) 命令行快速提取单个字段
#
#     ./video_metadata.sh "$VIDEO" | jq -r '.title'
#     ./video_metadata.sh "$VIDEO" | jq -r '.url'
#
# ------------------------------------------------------------------------------
# 【契约说明（空字符串规则）】
#
#   - 所有字段在 JSON 中一定存在
#   - 所有字符串字段：
#       - 有值 → 非空字符串
#       - 无法获取 → 空字符串 ""
#   - 不返回 null，避免在 Shell 中产生歧义
#   - 上层脚本应使用 -n / -z 判断是否存在值，例如：
#
#       if [ -n "$artist" ]; then
#         ...
#       fi
#
#   - duration 始终为 number，失败或未知时为 0
#
# ==============================================================================

set -euo pipefail

# ---------- args ----------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <video_file>" >&2
  exit 1
fi

VIDEO="$1"

if [[ ! -f "$VIDEO" ]]; then
  echo "Error: file not found: $VIDEO" >&2
  exit 1
fi

# ---------- deps ----------
if ! command -v ffprobe >/dev/null 2>&1; then
  echo "Error: ffprobe is required (install ffmpeg)" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required" >&2
  exit 1
fi

# ==============================================================================
# URL 提取（只接受 http/https）
# ==============================================================================

extract_url_from_text() {
  local text="${1:-}"
  if [[ -z "$text" ]]; then
    printf '%s\n' ""
    return 0
  fi

  printf '%s\n' "$text" \
    | grep -Eo 'https?://[^[:space:]"'"'"'<>()]+' \
    | head -n 1 || true
}

get_url_from_wherefroms() {
  if ! command -v mdls >/dev/null 2>&1; then
    printf '%s\n' ""
    return 0
  fi

  local raw=""
  raw="$(mdls -name kMDItemWhereFroms -raw "$VIDEO" 2>/dev/null || true)"

  if [[ -z "$raw" || "$raw" == "(null)" ]]; then
    printf '%s\n' ""
    return 0
  fi

  extract_url_from_text "$raw"
}

get_url_from_ffprobe_tags() {
  local tags_text=""
  tags_text="$(ffprobe -v error \
    -show_entries format_tags \
    -of default=noprint_wrappers=1:nokey=1 \
    "$VIDEO" 2>/dev/null || true)"

  if [[ -z "$tags_text" ]]; then
    printf '%s\n' ""
    return 0
  fi

  extract_url_from_text "$tags_text"
}

# ==============================================================================
# ffprobe metadata
# ==============================================================================

FF_JSON="$(ffprobe -v quiet -print_format json -show_format "$VIDEO")"

duration="$(printf '%s' "$FF_JSON" | jq -r '.format.duration // 0 | tonumber')"

title="$(printf '%s' "$FF_JSON" | jq -r '.format.tags.title // ""')"
artist="$(printf '%s' "$FF_JSON" | jq -r '.format.tags.artist // ""')"
album="$(printf '%s' "$FF_JSON" | jq -r '.format.tags.album // ""')"
genre="$(printf '%s' "$FF_JSON" | jq -r '.format.tags.genre // ""')"

# ---------- fallback title ----------
if [[ -z "$title" ]]; then
  title="$(basename "$VIDEO")"
fi

# ---------- url ----------
url="$(get_url_from_wherefroms)"
if [[ -z "$url" ]]; then
  url="$(get_url_from_ffprobe_tags)"
fi

# ---------- output ----------
jq -n \
  --argjson duration "$duration" \
  --arg title "$title" \
  --arg artist "$artist" \
  --arg album "$album" \
  --arg genre "$genre" \
  --arg url "$url" \
'{
  duration: $duration,
  title:    $title,
  artist:   $artist,
  album:    $album,
  genre:    $genre,
  url:      $url
}'
