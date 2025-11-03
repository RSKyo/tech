#!/usr/bin/env bash
# =============================================================================
# media_list.sh — 列出目录中的媒体文件（视频 / 音频）
# -----------------------------------------------------------------------------
# 用法：
#   media_list.sh <文件或目录> [--type video|audio|media]
#
# 默认行为：
#   - 若未指定 --type，则等价于 --type video；
#   - 支持多数常见视频与音频格式；
#   - 只列出文件，不递归子目录；
#   - 输出完整路径（绝对路径）。
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
用法：
  media_list.sh <文件或目录> [--type video|audio|media]

说明：
  --type 控制要列出的文件类型：
    video  仅视频文件（默认）
    audio  仅音频文件
    media  音频 + 视频文件
EOF
}

[ $# -ge 1 ] || { usage; exit 1; }

TARGET=""
TYPE="video"

while [ $# -gt 0 ]; do
  case "$1" in
    --type)
      shift || true
      case "${1:-}" in
        video|audio|media) TYPE="$1" ;;
        *) echo "错误：--type 需为 video、audio 或 media" >&2; exit 1 ;;
      esac
      ;;
    -h|--help)
      usage; exit 0 ;;
    -*)
      echo "未知参数：$1" >&2; exit 1 ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$1"
      else
        echo "错误：仅支持一个参数：路径或文件" >&2; exit 1
      fi
      ;;
  esac
  shift || true
done

[ -e "$TARGET" ] || { echo "错误：找不到路径：$TARGET"; exit 1; }

# ---------- 媒体类型定义 ----------
VIDEO_EXTS=( mp4 m4v mov mkv webm avi flv ts mpeg mpg ogv 3gp mts m2ts )
AUDIO_EXTS=( m4a mp3 flac wav ogg opus wma aac aiff aif alac )

# 生成匹配列表
case "$TYPE" in
  video) exts=( "${VIDEO_EXTS[@]}" ) ;;
  audio) exts=( "${AUDIO_EXTS[@]}" ) ;;
  media) exts=( "${VIDEO_EXTS[@]}" "${AUDIO_EXTS[@]}" ) ;;
esac

# ---------- 查找逻辑 ----------
list_files() {
  local path="$1"
  if [ -f "$path" ]; then
    local ext="${path##*.}"
    ext="${ext,,}"  # 转小写
    for e in "${exts[@]}"; do
      if [ "$ext" = "$e" ]; then
        realpath "$path"
        return 0
      fi
    done
  elif [ -d "$path" ]; then
    shopt -s nullglob nocaseglob
    for f in "$path"/*; do
      [ -f "$f" ] || continue
      local ext="${f##*.}"
      ext="${ext,,}"
      for e in "${exts[@]}"; do
        if [ "$ext" = "$e" ]; then
          realpath "$f"
          break
        fi
      done
    done
    shopt -u nullglob nocaseglob
  else
    echo "警告：不支持的路径类型：$path" >&2
    return 1
  fi
}

list_files "$TARGET"
