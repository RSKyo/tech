#!/usr/bin/env bash
# =============================================================================
# SHID: 1v2RKqV4
# DO NOT REMOVE OR MODIFY THIS BLOCK.
# Used for script identity / indexing.
# =============================================================================

IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# files_enrich.audio.sh
#
# stdin:  file [\t ...]
# stdout: 原始整行 + audio 字段
# =============================================================================

AUDIO_FIELDS=( duration codec bitrate sample_rate channels )
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
  echo "错误：audio enrich 必须显式指定 --select" >&2
  exit 1
}

NEED_AUDIO=0
for f in "${SELECT_FIELDS[@]}"; do
  case "$f" in
    duration|codec|bitrate|sample_rate|channels)
      NEED_AUDIO=1
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

probe_audio() {
  local file="$1"
  ffprobe -v error \
    -select_streams a:0 \
    -show_entries stream=codec_name,sample_rate,channels \
    -of default=noprint_wrappers=1 "$file" 2>/dev/null || true

  ffprobe -v error \
    -show_entries format=duration,bit_rate \
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

  duration=""; codec=""; bitrate=""; sample_rate=""; channels=""

  if (( NEED_AUDIO )); then
    while IFS='=' read -r k v; do
      case "$k" in
        duration) duration="$v" ;;
        bit_rate) bitrate="$v" ;;
        codec_name) codec="$v" ;;
        sample_rate) sample_rate="$v" ;;
        channels) channels="$v" ;;
      esac
    done < <(probe_audio "$file")
  fi

  declare -A row=(
    [duration]="$duration"
    [codec]="$codec"
    [bitrate]="$bitrate"
    [sample_rate]="$sample_rate"
    [channels]="$channels"
  )

  out=( "${cols[@]}" )
  for f in "${SELECT_FIELDS[@]}"; do
    out+=( "${row[$f]}" )
  done

  printf '%s\n' "$(IFS=$'\t'; echo "${out[*]}")"
done
