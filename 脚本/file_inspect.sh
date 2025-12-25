#!/usr/bin/env bash
IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# file_inspect.sh
#
# 域模型：
#   - 基础域（默认启用）：
#       abs_path basename filename ext size mtime
#   - 媒体域（--media）：
#       duration codec bitrate width height fps sample_rate channels
#
# 规则：
#   - 未启用域，其字段不会出现
#   - 已启用域，但文件不适用 → 字段为空
#   - --select 只能选择已启用域中的字段
# =============================================================================

usage() {
  cat <<EOF
用法：
  $(basename "$0") <file|dir> [options]

选项：
  --media
      启用媒体域解析（调用 ffprobe）

  --select field1,field2,...
      指定输出字段（顺序按给定顺序）

目录扫描参数（透传给 dir_files.sh）：
  --type video|audio|media|all
  --ext ext1,ext2,...
  --recursive
EOF
}

# -----------------------------------------------------------------------------
# 路径与依赖
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR_FILES_SH="$SCRIPT_DIR/dir_files.sh"

require_executable() {
  [[ -x "$1" ]] || {
    echo "❌ 缺少依赖脚本或无执行权限：$1" >&2
    exit 1
  }
}

# -----------------------------------------------------------------------------
# 字段定义（单一真源）
# -----------------------------------------------------------------------------
BASE_FIELDS=(abs_path basename filename ext size mtime)
MEDIA_FIELDS=(duration codec bitrate width height fps sample_rate channels)

ALL_FIELDS=( "${BASE_FIELDS[@]}" )

# -----------------------------------------------------------------------------
# 参数解析
# -----------------------------------------------------------------------------
INPUT=""
ENABLE_MEDIA=0
DIR_FILES_ARGS=()
SELECT_FIELDS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --media)
      ENABLE_MEDIA=1
      shift
      ;;
    --select)
      [ $# -ge 2 ] || { echo "错误：--select 需要参数" >&2; exit 1; }
      IFS=',' read -r -a SELECT_FIELDS <<<"$2"
      shift 2
      ;;
    --type|--ext)
      [ $# -ge 2 ] || { echo "错误：$1 需要参数" >&2; exit 1; }
      DIR_FILES_ARGS+=( "$1" "$2" )
      shift 2
      ;;
    --recursive)
      DIR_FILES_ARGS+=( "$1" )
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "未知参数：$1" >&2
      exit 1
      ;;
    *)
      [ -z "$INPUT" ] || { echo "错误：只能指定一个 file 或 dir" >&2; exit 1; }
      INPUT="$1"
      shift
      ;;
  esac
done

[ -n "$INPUT" ] || { usage >&2; exit 1; }
[ -e "$INPUT" ] || { echo "错误：不存在：$INPUT" >&2; exit 1; }

# -----------------------------------------------------------------------------
# 域启用
# -----------------------------------------------------------------------------
if [ "$ENABLE_MEDIA" -eq 1 ]; then
  ALL_FIELDS+=( "${MEDIA_FIELDS[@]}" )
  command -v ffprobe >/dev/null 2>&1 || {
    echo "❌ 启用 --media 需要 ffprobe" >&2
    exit 1
  }
fi

# -----------------------------------------------------------------------------
# select 校验
# -----------------------------------------------------------------------------
if [ "${#SELECT_FIELDS[@]}" -eq 0 ]; then
  SELECT_FIELDS=( "${ALL_FIELDS[@]}" )
else
  for f in "${SELECT_FIELDS[@]}"; do
    if ! printf '%s\n' "${ALL_FIELDS[@]}" | grep -qx "$f"; then
      echo "错误：字段 '$f' 未启用或不存在" >&2
      exit 1
    fi
  done
fi

# -----------------------------------------------------------------------------
# 文件列表
# -----------------------------------------------------------------------------
files=()

abs_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
  else
    python3 - <<'PY' "$1"
import os,sys
print(os.path.realpath(sys.argv[1]))
PY
  fi
}

if [ -f "$INPUT" ]; then
  files+=( "$(abs_path "$INPUT")" )
elif [ -d "$INPUT" ]; then
  require_executable "$DIR_FILES_SH"
  mapfile -t files < <(
    "$DIR_FILES_SH" "$INPUT" "${DIR_FILES_ARGS[@]}"
  )
else
  exit 1
fi

probe_media() {
  local file="$1"

  # 优先从 video stream 取（webm / mkv 更可靠）
  ffprobe -v error \
    -select_streams v:0 \
    -show_entries stream=duration,codec_name,width,height,r_frame_rate \
    -of default=noprint_wrappers=1 "$file" 2>/dev/null || true

  # 再从 container(format) 兜底补充
  ffprobe -v error \
    -show_entries format=duration,bit_rate \
    -of default=noprint_wrappers=1 "$file" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# 主输出
# -----------------------------------------------------------------------------
for path in "${files[@]}"; do
  [ -f "$path" ] || continue

  basename="$(basename "$path")"
  filename="${basename%.*}"
  ext="${basename##*.}"
  [[ "$basename" == *.* ]] || ext=""

  size="$(stat -f%z "$path" 2>/dev/null || echo "")"
  mtime="$(stat -f%m "$path" 2>/dev/null || echo "")"

  duration=""
  codec=""
  bitrate=""
  width=""
  height=""
  fps=""
  sample_rate=""
  channels=""

  if [ "$ENABLE_MEDIA" -eq 1 ]; then
    while IFS='=' read -r key value; do
      case "$key" in
        duration)     duration="$value" ;;
        bit_rate)     bitrate="$value" ;;
        codec_name)   codec="$value" ;;
        width)        width="$value" ;;
        height)       height="$value" ;;
        r_frame_rate) fps="$value" ;;
        sample_rate)  sample_rate="$value" ;;
        channels)     channels="$value" ;;
      esac
    done < <(probe_media "$path")
  fi

  declare -A row=(
    [abs_path]="$path"
    [basename]="$basename"
    [filename]="$filename"
    [ext]="$ext"
    [size]="$size"
    [mtime]="$mtime"
    [duration]="$duration"
    [codec]="$codec"
    [bitrate]="$bitrate"
    [width]="$width"
    [height]="$height"
    [fps]="$fps"
    [sample_rate]="$sample_rate"
    [channels]="$channels"
  )

  out=()
  for f in "${SELECT_FIELDS[@]}"; do
    out+=( "${row[$f]}" )
  done

  printf '%s\n' "$(IFS=$'\t'; echo "${out[*]}")"
done

exit 0
