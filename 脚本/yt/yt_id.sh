#!/usr/bin/env bash
# =============================================================================
# yt_id.sh
#
# 本地工具：从 YouTube URL 中提取 videoId（11 位）
#
# 特性：
#   - 不联网
#   - 支持 argv / stdin（管道）
#   - 单一职责：URL -> videoId
#
# 支持的 URL 形式：
#   1) youtu.be/VIDEO_ID
#   2) youtube.com/watch?v=VIDEO_ID
#   3) youtube.com/embed/VIDEO_ID
#   4) youtube.com/shorts/VIDEO_ID
#
# 行为：
#   - 每行输入输出一个 videoId
#   - 无法解析的输入将被跳过
# =============================================================================

IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
YT_ID_RE='[A-Za-z0-9_-]{11}'

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  cat >&2 <<'EOF'
Usage:
  yt_id.sh <youtube-url>
  yt_id.sh < urls.txt

Description:
  Extract YouTube videoId (11 chars) from URL.
  This tool works locally and does not access the network.
EOF
}

# ---------------------------------------------------------------------------
# parse one URL, echo id if success
# ---------------------------------------------------------------------------
parse_url() {
  local url="$1"
  local query p id

  # -----------------------------------------
  # 1) youtu.be/VIDEO_ID
  # -----------------------------------------
  if [[ "$url" =~ youtu\.be/($YT_ID_RE) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  # -----------------------------------------
  # 2) youtube.com/watch?v=VIDEO_ID
  # -----------------------------------------
  if [[ "$url" == *"youtube.com/watch"* && "$url" == *"v="* ]]; then
    query="${url#*\?}"
    query="${query%%#*}"

    IFS='&' read -r -a params <<< "$query"
    for p in "${params[@]}"; do
      if [[ "$p" == v=* ]]; then
        id="${p#v=}"
        [[ "$id" =~ ^$YT_ID_RE$ ]] || return 1
        echo "$id"
        return 0
      fi
    done
  fi

  # -----------------------------------------
  # 3) /embed/VIDEO_ID
  # -----------------------------------------
  if [[ "$url" =~ /embed/($YT_ID_RE) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  # -----------------------------------------
  # 4) /shorts/VIDEO_ID
  # -----------------------------------------
  if [[ "$url" =~ /shorts/($YT_ID_RE) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# main: argv / stdin unified
# ---------------------------------------------------------------------------
main() {
  local had_input=0

  if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
      had_input=1
      parse_url "$arg" || true
    done
  else
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      had_input=1
      parse_url "$line" || true
    done
  fi

  [[ $had_input -eq 1 ]] || usage
}

main "$@"
