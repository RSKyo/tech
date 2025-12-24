#!/usr/bin/env bash
IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# get_source_url.sh
# 从单个媒体文件元信息中提取来源 URL
#
# 用法：
#   ./get_source_url.sh <file> [--youtube|--yt] [--youtube-id|--ytid]
#
# 输出：
#   - 默认：命中任意 URL 则输出 URL
#   - --youtube / --yt：仅当 URL 为 YouTube 才输出 URL
#   - --youtube-id / --ytid：仅当 URL 为 YouTube 才输出视频 ID
#   - 未命中：无输出，exit 0
# =============================================================================

usage() {
  cat <<EOF >&2
用法:
  $(basename "$0") <file> [--youtube|--yt] [--youtube-id|--ytid]

参数:
  --youtube,    --yt     仅当 URL 为 YouTube 才输出（输出 URL）
  --youtube-id, --ytid   仅当 URL 为 YouTube 才输出视频 ID
EOF
}

# =============================================================================
# URL extraction helpers
# =============================================================================
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

  command -v ffprobe >/dev/null 2>&1 || return 0

  local tags_text
  tags_text="$(ffprobe -v error \
    -show_entries format_tags \
    -of default=noprint_wrappers=1:nokey=1 \
    "$file" 2>/dev/null || true)"

  [[ -z "$tags_text" ]] && return 0
  extract_url_from_text "$tags_text"
}

# =============================================================================
# YouTube detection + ID extraction
# =============================================================================
is_youtube_url() {
  local url="${1:-}"
  [[ -z "$url" ]] && return 1

  printf '%s' "$url" | grep -Eqi \
    '^https?://([a-z0-9-]+\.)*youtube\.com/|^https?://youtu\.be/'
}

youtube_id_from_url() {
  local url="${1:-}"
  [[ -z "$url" ]] && return 0

  local id=""

  # watch?v=ID
  id="$(printf '%s\n' "$url" \
    | sed -nE 's#.*[?&]v=([A-Za-z0-9_-]{6,}).*#\1#p' \
    | head -n 1 || true)"

  # youtu.be/ID
  [[ -z "$id" ]] && id="$(printf '%s\n' "$url" \
    | sed -nE 's#^https?://youtu\.be/([A-Za-z0-9_-]{6,}).*#\1#p' \
    | head -n 1 || true)"

  # /shorts/ID /embed/ID /live/ID
  [[ -z "$id" ]] && id="$(printf '%s\n' "$url" \
    | sed -nE 's#^https?://([a-z0-9-]+\.)*youtube\.com/(shorts|embed|live)/([A-Za-z0-9_-]{6,}).*#\3#p' \
    | head -n 1 || true)"

  # 常规 YouTube 视频 ID：11 位
  if [[ -n "$id" ]] && printf '%s' "$id" | grep -Eq '^[A-Za-z0-9_-]{11}$'; then
    printf '%s\n' "$id"
  fi
}

# =============================================================================
# Aggregator (single file)
# =============================================================================
get_source_url() {
  local file="$1"
  local url=""

  url="$(get_url_from_wherefroms "$file" || true)"
  [[ -n "$url" ]] && { printf '%s\n' "$url"; return 0; }

  url="$(get_url_from_ffprobe_tags "$file" || true)"
  [[ -n "$url" ]] && { printf '%s\n' "$url"; return 0; }

  return 0
}

# =============================================================================
# Main
# =============================================================================
main() {
  local file=""
  local youtube_only="0"
  local youtube_id="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --youtube|--yt) youtube_only="1"; shift ;;
      --youtube-id|--ytid) youtube_id="1"; shift ;;
      -*)
        echo "[WARN] Unknown arg: $1" >&2
        shift
        ;;
      *)
        [[ -z "$file" ]] && file="$1" || echo "[WARN] Extra arg ignored: $1" >&2
        shift
        ;;
    esac
  done

  [[ -z "$file" ]] && { usage; exit 2; }
  [[ ! -f "$file" ]] && { echo "文件不存在: $file" >&2; exit 2; }

  local url
  url="$(get_source_url "$file" || true)"
  [[ -z "$url" ]] && return 0

  # --youtube-id / --ytid（优先级最高）
  if [[ "$youtube_id" == "1" ]]; then
    is_youtube_url "$url" || return 0
    youtube_id_from_url "$url"
    return 0
  fi

  # --youtube / --yt
  if [[ "$youtube_only" == "1" ]]; then
    is_youtube_url "$url" || return 0
  fi

  printf '%s\n' "$url"
}

main "$@"
