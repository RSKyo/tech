#!/usr/bin/env bash
IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# file_inspect.yt.sh
#
# 职责：
#   - 调用 file_inspect.sh
#   - 基于 abs_path 提取 YouTube 信息
#   - 在输出行尾追加：yt_url  yt_id
#
# select 规则（当前阶段）：
#   - 未传 --select：完全不干预
#   - 传了 --select：
#       * 若不含 abs_path：内部临时插入 abs_path
#       * 若已含 abs_path：原样使用
#   - 若 abs_path 是“内部插入”的，最终输出时移除该列
#
# 注意：
#   - --select 的合法性校验由 file_inspect.sh 负责
#   - 本脚本假定上游输出是合法 schema
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE_INSPECT="$SCRIPT_DIR/file_inspect.sh"

[[ -x "$FILE_INSPECT" ]] || {
  echo "❌ 未找到 file_inspect.sh 或无执行权限：$FILE_INSPECT" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# 参数解析：只关心 --select，其余全部转发
# -----------------------------------------------------------------------------
UPSTREAM_ARGS=()
HAS_SELECT=0
ABS_PATH_TEMP_INSERTED=0
SELECT_VALUE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --select)
      HAS_SELECT=1
      SELECT_VALUE="${2-}"
      shift 2
      ;;
    *)
      UPSTREAM_ARGS+=( "$1" )
      shift
      ;;
  esac
done

ABS_PATH_COL=1

if [[ "$HAS_SELECT" -eq 1 ]]; then
  # 如果 select 中不包含 abs_path，则临时插入
  if [[ ! ",$SELECT_VALUE," =~ ,abs_path, ]]; then
    ABS_PATH_TEMP_INSERTED=1
    SELECT_VALUE="abs_path,$SELECT_VALUE"
  fi

  # 计算 abs_path 是第几列（数逗号）
  prefix="${SELECT_VALUE%%abs_path*}"
  comma_count="${prefix//[^,]/}"
  ABS_PATH_COL=$(( ${#comma_count} + 1 ))

  UPSTREAM_ARGS+=( "--select" "$SELECT_VALUE" )
fi

# -----------------------------------------------------------------------------
# URL / YouTube 识别（分层实现）
# -----------------------------------------------------------------------------

extract_urls_from_metadata() {
  local file="$1"
  local text=""

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
  [[ "$1" =~ ^https?://(www\.)?(youtube\.com/watch\?|youtu\.be/) ]]
}

extract_youtube_id() {
  if [[ "$1" =~ (youtube\.com/watch\?v=|youtu\.be/)([A-Za-z0-9_-]{11}) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
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
# 主流程
# -----------------------------------------------------------------------------
"$FILE_INSPECT" "${UPSTREAM_ARGS[@]}" | while IFS= read -r line; do
  yt_url=""
  yt_id=""

  IFS=$'\t' read -r -a cols <<<"$line"
  abs_path="${cols[$((ABS_PATH_COL - 1))]}"

  if [[ -n "$abs_path" && -f "$abs_path" ]]; then
    if result="$(extract_youtube_from_file "$abs_path")"; then
      yt_url="${result%%$'\t'*}"
      yt_id="${result##*$'\t'}"
    fi
  fi

  # 如果 abs_path 是内部插入的，移除该列再输出
  if [[ "$ABS_PATH_TEMP_INSERTED" -eq 1 ]]; then
    cols=( "${cols[@]:0:$((ABS_PATH_COL-1))}" "${cols[@]:$ABS_PATH_COL}" )
  fi

  printf '%s\t%s\t%s\n' "$(IFS=$'\t'; echo "${cols[*]}")" "$yt_url" "$yt_id"
done

exit 0
