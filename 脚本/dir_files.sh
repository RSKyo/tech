#!/usr/bin/env bash
IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# dir_files.sh
#
# 目标：
#   - 枚举目录中的普通文件（默认不递归；--recursive 递归）
#   - 将文件列表（逐行）输入 files_filter.sh，过滤后输出（逐行）
#
# 参数：
#   dir_files.sh <dir> [--recursive] [--type <type>] [--ext ext1,ext2,...]
#
# 说明：
#   - --type / --ext 仅做透传，不在本脚本内解释
#   - files_filter.sh 必须与本脚本同目录，且可执行
# =============================================================================

usage() {
  cat <<EOF
用法：
  $(basename "$0") <dir> [options]

options:
  --recursive
      递归扫描子目录（默认：只扫描一层）

  --type <type>
      透传给 files_filter.sh

  --ext ext1,ext2,...
      透传给 files_filter.sh（逗号分隔）

  -h, --help
      显示帮助

示例：
  $(basename "$0") ./Downloads
  $(basename "$0") ./Downloads --recursive
  $(basename "$0") ./Downloads --type video
  $(basename "$0") ./Downloads --ext mp3,flac
  $(basename "$0") ./Downloads --recursive --type audio
EOF
}

# -----------------------------------------------------------------------------
# 路径与依赖
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_FILTER_SH="${SCRIPT_DIR}/files_filter.sh"

require_executable() {
  local p="$1"
  [[ -x "$p" ]] || {
    echo "❌ 缺少依赖脚本或无执行权限：${p}" >&2
    exit 1
  }
}

abs_path() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p"
  else
    python3 - <<'PY' "$p"
import os,sys
print(os.path.realpath(sys.argv[1]))
PY
  fi
}

# -----------------------------------------------------------------------------
# 参数解析
# -----------------------------------------------------------------------------
DIR=""
RECURSIVE=0
FORWARD_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --recursive)
      RECURSIVE=1
      shift
      ;;
    --type|--ext)
      [ $# -ge 2 ] || { echo "错误：${1} 需要参数" >&2; exit 1; }
      FORWARD_ARGS+=( "$1" "$2" )
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "未知参数：${1}" >&2
      exit 1
      ;;
    *)
      if [ -z "$DIR" ]; then
        DIR="$1"
      else
        echo "错误：只能指定一个目录参数" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

[ -n "$DIR" ] || { usage >&2; exit 1; }
[ -d "$DIR" ] || { echo "错误：必须是目录：${DIR}" >&2; exit 1; }

require_executable "$FILES_FILTER_SH"

DIR_ABS="$(abs_path "$DIR")"

# -----------------------------------------------------------------------------
# 枚举 -> 过滤 -> 输出
# -----------------------------------------------------------------------------
if [ "$RECURSIVE" -eq 1 ]; then
  # 递归：find 从绝对目录出发，输出绝对路径
  # 注：find 输出为逐行路径，保留空格；交给 files_filter.sh 逐行处理
  find "$DIR_ABS" -type f -print \
    | "$FILES_FILTER_SH" "${FORWARD_ARGS[@]}"
else
  # 非递归：仅 DIR_ABS/* 一层
  shopt -s nullglob
  {
    local_f=""
    for local_f in "$DIR_ABS"/*; do
      [ -f "$local_f" ] || continue
      printf '%s\n' "$local_f"
    done
  } | "$FILES_FILTER_SH" "${FORWARD_ARGS[@]}"
  shopt -u nullglob
fi

exit 0
