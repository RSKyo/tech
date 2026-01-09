#!/usr/bin/env bash
# =============================================================================
# SHID: bMZXVxPk
# DO NOT REMOVE OR MODIFY THIS BLOCK.
# Used for script identity / indexing.
# =============================================================================

IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# files_enrich.yt.sh
#
# stdin:
#   file
#   或 file <tab> colA <tab> colB ...
#
# stdout:
#   原始整行 + yt 字段
#
# 规则：
#   - 第一列必须是文件（只校验第一行）
#   - 后续行文件不存在直接跳过
#   - 逐行处理，逐行输出
# =============================================================================

YT_FIELDS=( yt_url yt_id )
SELECT_FIELDS=()

# -----------------------------------------------------------------------------
# 参数解析
# -----------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --select)
      [ $# -ge 2 ] || { echo "错误：--select 需要参数" >&2; exit 1; }
      IFS=',' read -r -a SELECT_FIELDS <<<"$2"
      shift 2
      ;;
    -h|--help)
      cat <<EOF
用法：
  cat filelist | $(basename "$0") --select yt_url,yt_id

可选字段：
  ${YT_FIELDS[*]}
EOF
      exit 0
      ;;
    *)
      echo "未知参数：$1" >&2
      exit 1
      ;;
  esac
done

[ "${#SELECT_FIELDS[@]}" -gt 0 ] || {
  echo "错误：yt enrich 必须显式指定 --select" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# 字段校验 + 执行路径预计算（封版：纯 case，无 grep）
# -----------------------------------------------------------------------------
NEED_YT=0
for f in "${SELECT_FIELDS[@]}"; do
  case "$f" in
    yt_url|yt_id)
      NEED_YT=1
      ;;
    *)
      echo "错误：非法字段 '$f'" >&2
      exit 1
      ;;
  esac
done

# -----------------------------------------------------------------------------
# URL / YouTube 识别
# -----------------------------------------------------------------------------
extract_urls_from_metadata() {
  local file="$1" text=""

  if command -v mdls >/dev/null 2>&1; then
    text+="$(mdls -name kMDItemWhereFroms "$file" 2>/dev/null)"
  fi

  if command -v ffprobe >/dev/null 2>&1; then
    text+="
$(ffprobe -v error -show_entries format_tags \
  -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)"
  fi

  printf '%s\n' "$text" \
    | grep -Eo 'https?://[^"'"'"'[:space:]]+' \
    | sort -u
}

is_youtube_url() {
  [[ "$1" =~ ^https?://(www\.)?(youtube\.com|youtu\.be)/ ]]
}

# 采用你给定的 yt_id 提取规则
extract_youtube_id() {
  local url="$1" query id

  # 1) youtu.be/VIDEO_ID
  if [[ "$url" =~ youtu\.be/([A-Za-z0-9_-]{11}) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  # 2) youtube.com/watch?v=VIDEO_ID（解析 query）
  if [[ "$url" == *"youtube.com/watch"* && "$url" == *"v="* ]]; then
    query="${url#*\?}"
    query="${query%%#*}"
    IFS='&' read -r -a params <<<"$query"
    for p in "${params[@]}"; do
      if [[ "$p" == v=* ]]; then
        id="${p#v=}"
        [[ "$id" =~ ^[A-Za-z0-9_-]{11}$ ]] || return 1
        printf '%s\n' "$id"
        return 0
      fi
    done
  fi

  # 3) /embed/VIDEO_ID
  if [[ "$url" =~ /embed/([A-Za-z0-9_-]{11}) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  # 4) /shorts/VIDEO_ID
  if [[ "$url" =~ /shorts/([A-Za-z0-9_-]{11}) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

extract_youtube_from_file() {
  local file="$1" url id
  while IFS= read -r url; do
    if is_youtube_url "$url"; then
      if id="$(extract_youtube_id "$url")"; then
        printf 'https://youtu.be/%s\t%s\n' "$id" "$id"
        return 0
      fi
    fi
  done < <(extract_urls_from_metadata "$file")
  return 1
}

# -----------------------------------------------------------------------------
# 主循环（逐行流式）
# -----------------------------------------------------------------------------
first_line=1

while IFS= read -r line; do
  [ -n "$line" ] || continue

  IFS=$'\t' read -r -a cols <<<"$line"
  file="${cols[0]}"

  if [ "$first_line" -eq 1 ]; then
    if [ ! -f "$file" ]; then
      echo "错误：输入第一列不是有效文件路径：$file" >&2
      exit 1
    fi
    first_line=0
  fi

  [ -f "$file" ] || continue

  yt_url=""
  yt_id=""

  if (( NEED_YT )); then
    if result="$(extract_youtube_from_file "$file")"; then
      yt_url="${result%%$'\t'*}"
      yt_id="${result##*$'\t'}"
    fi
  fi

  declare -A row=(
    [yt_url]="$yt_url"
    [yt_id]="$yt_id"
  )

  out=( "${cols[@]}" )
  for f in "${SELECT_FIELDS[@]}"; do
    out+=( "${row[$f]}" )
  done

  printf '%s\n' "$(IFS=$'\t'; echo "${out[*]}")"
done
