#!/usr/bin/env bash
# ==============================================================================
# video_metadata.sh
# ------------------------------------------------------------------------------
# 用途：
#   读取任意视频文件的元信息，输出标准化 JSON，供其他脚本使用。
#
# 必须使用 ffprobe（FFmpeg 套件的一部分）。
#
# 输出 JSON 结构（全部字段保证存在）：
#
# {
#   "duration": <number>,              视频总秒数（float）
#   "title": "<string|null>",          来自 tags.title 或文件名
#   "artist": "<string|null>",         来自 tags.artist
#   "album": "<string|null>",          来自 tags.album
#   "tags": {
#       "title": "<string|null>",
#       "artist": "<string|null>",
#       "album": "<string|null>",
#       "genre": "<string|null>"
#   }
# }
#
# 调用方式：
#       ./video_metadata.sh "/path/to/video.mp4"
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

# ---------- check ffprobe ----------
if ! command -v ffprobe >/dev/null 2>&1; then
  echo "Error: ffprobe is required (install ffmpeg)" >&2
  exit 1
fi

# ---------- extract metadata via ffprobe ----------
# -v quiet : 不输出日志
# -print_format json : 输出 JSON
# -show_format : 仅格式级信息（包含 tags, duration）

FF_JSON=$(ffprobe -v quiet -print_format json -show_format "$VIDEO")

# ---------- parse fields ----------
duration=$(printf '%s' "$FF_JSON" | jq -r '.format.duration // 0 | tonumber')

tag_title=$(printf '%s' "$FF_JSON" | jq -r '.format.tags.title // empty')
tag_artist=$(printf '%s' "$FF_JSON" | jq -r '.format.tags.artist // empty')
tag_album=$(printf '%s' "$FF_JSON" | jq -r '.format.tags.album // empty')
tag_genre=$(printf '%s' "$FF_JSON" | jq -r '.format.tags.genre // empty')

# ---------- fallback title ----------
# 若 tags.title 不存在，则取文件名（去掉路径）
if [[ -z "$tag_title" ]]; then
  file_base="$(basename "$VIDEO")"
  tag_title="$file_base"
fi

# ---------- build final JSON ----------
jq -n \
  --arg duration "$duration" \
  --arg title "$tag_title" \
  --arg artist "$tag_artist" \
  --arg album "$tag_album" \
  --arg genre "$tag_genre" \
'{
    duration: ($duration | tonumber),
    title: ($title | if .=="" then null else . end),
    artist: ($artist | if .=="" then null else . end),
    album: ($album | if .=="" then null else . end),

    tags: {
        title:   ($title   | if .=="" then null else . end),
        artist:  ($artist  | if .=="" then null else . end),
        album:   ($album   | if .=="" then null else . end),
        genre:   ($genre   | if .=="" then null else . end)
    }
}'
