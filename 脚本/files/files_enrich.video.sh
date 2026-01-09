#!/usr/bin/env bash
# =============================================================================
# SHID: vRLtu3ha
# DO NOT REMOVE OR MODIFY THIS BLOCK.
# Used for script identity / indexing.
# =============================================================================

IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# files_enrich.video.sh
#
# stdin:  file [\t ...]
# stdout: 原始整行 + video 字段
# =============================================================================

VIDEO_FIELDS=( duration codec width height fps )
SELECT_FIELDS=()

# ---------------------- 参数解析 ----------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --select)
      IFS=',' read -r -a SELECT_FIELDS <<<"$2"
      shift 2
      ;;
    *)
      echo "未知参数：$1" >&2
      exit 1
      ;;
  esac
done

[ "${#SELECT_FIELDS[@]}" -gt 0 ] || {
  echo "错误：video enrich 必须显式指定 --select" >&2
  exit 1
}

NEED_VIDEO=0
for f in "${SELECT_FIELDS[@]}"; do
  case "$f" in
    duration|codec|width|height|fps)
      NEED_VIDEO=1
      ;;
    *)
      echo "错误：非法字段 '$f'" >&2
      exit 1
      ;;
  esac
done

command -v ffprobe >/dev/null 2>&1 || {
  echo "❌ 缺少依赖：ffprobe" >&2
  exit 1
}

probe_video() {
  local file="$1"
  ffprobe -v error \
    -select_streams v:0 \
    -show_entries stream=codec_name,width,height,r_frame_rate \
    -of default=noprint_wrappers=1 "$file" 2>/dev/null || true

  ffprobe -v error \
    -show_entries format=duration \
    -of default=noprint_wrappers=1 "$file" 2>/dev/null || true
}

first_line=1

while IFS= read -r line; do
  [ -n "$line" ] || continue
  IFS=$'\t' read -r -a cols <<<"$line"
  file="${cols[0]}"

  if (( first_line )); then
    [ -f "$file" ] || { echo "错误：第一列不是文件：$file" >&2; exit 1; }
    first_line=0
  fi

  [ -f "$file" ] || continue

  duration=""; codec=""; width=""; height=""; fps=""

  if (( NEED_VIDEO )); then
    while IFS='=' read -r k v; do
      case "$k" in
        duration) duration="$v" ;;
        codec_name) codec="$v" ;;
        width) width="$v" ;;
        height) height="$v" ;;
        r_frame_rate) fps="$v" ;;
      esac
    done < <(probe_video "$file")
  fi

  declare -A row=(
    [duration]="$duration"
    [codec]="$codec"
    [width]="$width"
    [height]="$height"
    [fps]="$fps"
  )

  out=( "${cols[@]}" )
  for f in "${SELECT_FIELDS[@]}"; do
    out+=( "${row[$f]}" )
  done

  printf '%s\n' "$(IFS=$'\t'; echo "${out[*]}")"
done
