#!/usr/bin/env bash
IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# dir_files — 列出目录中的普通文件
#
# 设计原则：
#   - 仅接受目录作为输入（不支持单文件）
#   - 默认不递归（可通过 --recursive 开启）
#   - 只列出普通文件（忽略目录、设备、链接等）
#   - 所有使用说明与参数含义见 usage()
#
# 定位：
#   通用、可管道的目录文件列表工具
# =============================================================================

usage() {
  cat <<EOF
用法：
  $(basename "$0") <目录>
    [--type video|audio|media|all]
    [--ext ext1,ext2,...]
    [--recursive]
    [--count]
    [--name-only]

参数说明：
  <目录>
      要扫描的目录路径（必选，仅支持目录）

  --type video|audio|media|all
      预设的文件类型过滤（默认：all）
        video   常见视频文件
        audio   常见音频文件
        media   视频 + 音频
        all     不按扩展名过滤，列出所有普通文件

  --ext ext1,ext2,...
      自定义扩展名过滤（逗号分隔）
      可带前导点，大小写不敏感
      示例：--ext txt,xls,.XLSX
      注意：提供 --ext 时会覆盖 --type

  --recursive
      递归扫描子目录
      默认只扫描当前目录一层

  --count
      仅输出匹配文件的数量
      启用时不输出文件路径，并忽略 --name-only

  --name-only
      仅输出文件名（basename）
      默认输出文件的绝对路径

示例：
  $(basename "$0") ./Downloads
  $(basename "$0") ./Downloads --type media
  $(basename "$0") ./Downloads --ext txt,xls --name-only
  $(basename "$0") ./Downloads --recursive --count
EOF
}

# ---------- 参数解析 ----------
[ $# -ge 1 ] || { usage >&2; exit 1; }

DIR=""
TYPE="all"
EXT_CSV=""
RECURSIVE=0
COUNT_ONLY=0
NAME_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --type)
      shift || true
      TYPE="${1:-}"
      [ -n "$TYPE" ] || { echo "错误：--type 需要一个值" >&2; exit 1; }
      ;;
    --ext)
      shift || true
      EXT_CSV="${1:-}"
      [ -n "$EXT_CSV" ] || { echo "错误：--ext 需要一个值" >&2; exit 1; }
      ;;
    --recursive)
      RECURSIVE=1
      ;;
    --count)
      COUNT_ONLY=1
      ;;
    --name-only)
      NAME_ONLY=1
      ;;
    -h|--help)
      usage; exit 0 ;;
    -*)
      echo "未知参数：$1" >&2; exit 1 ;;
    *)
      if [ -z "$DIR" ]; then
        DIR="$1"
      else
        echo "错误：仅支持一个目录参数" >&2; exit 1
      fi
      ;;
  esac
  shift || true
done

[ -n "$DIR" ] || { usage >&2; exit 1; }
[ -d "$DIR" ] || { echo "错误：必须是目录：$DIR" >&2; exit 1; }

# ---------- 扩展名预设 ----------
VIDEO_EXTS=( mp4 m4v mov mkv webm avi flv ts mpeg mpg ogv 3gp mts m2ts )
AUDIO_EXTS=( m4a mp3 flac wav ogg opus wma aac aiff aif alac )

# ---------- 工具函数 ----------
to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

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

build_exts_from_csv() {
  local csv="$1" IFS=',' p
  exts=()
  for p in $csv; do
    p="${p#.}"
    p="$(to_lower "$p")"
    [ -n "$p" ] && exts+=( "$p" )
  done
}

# ---------- 构造过滤模式 ----------
exts=()
FILTER_MODE="exts"

if [ -n "$EXT_CSV" ]; then
  build_exts_from_csv "$EXT_CSV"
else
  case "$TYPE" in
    video) exts=( "${VIDEO_EXTS[@]}" ) ;;
    audio) exts=( "${AUDIO_EXTS[@]}" ) ;;
    media) exts=( "${VIDEO_EXTS[@]}" "${AUDIO_EXTS[@]}" ) ;;
    all)   FILTER_MODE="all" ;;
    *)
      echo "错误：--type 无效" >&2; exit 1 ;;
  esac
fi

# ---------- 主逻辑 ----------
count=0

emit() {
  [ "$COUNT_ONLY" -eq 1 ] && return

  if [ "$NAME_ONLY" -eq 1 ]; then
    printf '%s\n' "$(basename "$1")"
  else
    abs_path "$1"
  fi
}

scan_files() {
  local f

  if [ "$RECURSIVE" -eq 1 ]; then
    while IFS= read -r f; do
      handle_file "$f"
      if [ "$COUNT_ONLY" -eq 1 ]; then
        ((count++))
      fi
    done < <(find "$DIR" -type f)
  else
    shopt -s nullglob
    for f in "$DIR"/*; do
      [ -f "$f" ] || continue
      handle_file "$f"
      if [ "$COUNT_ONLY" -eq 1 ]; then
        ((count++))
      fi
    done
    shopt -u nullglob
  fi
}

handle_file() {
  local f="$1" ext e

  if [ "$FILTER_MODE" = "all" ]; then
    emit "$f"
    return
  fi

  [[ "$f" == *.* ]] || return
  ext="$(to_lower "${f##*.}")"

  [ "${#exts[@]}" -gt 0 ] || return

  for e in "${exts[@]}"; do
    if [ "$ext" = "$e" ]; then
      emit "$f"
      return
    fi
  done

}

scan_files

[ "$COUNT_ONLY" -eq 1 ] && printf '%d\n' "$count"
exit 0