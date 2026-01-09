#!/usr/bin/env bash
# =============================================================================
# SHID: lBi78Us8
# DO NOT REMOVE OR MODIFY THIS BLOCK.
# Used for script identity / indexing.
# =============================================================================

IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# files_scan.sh
#
# 目标：
#   接收一个文件或目录路径，输出“文件列表”
#   - 支持递归 / 非递归
#   - 支持隐藏目录剪枝
#   - 支持系统噪音文件过滤
#
# 职责边界：
#   - 本脚本只负责“扫描 + 基础过滤”
#   - 不做业务级分类、不解释文件类型
#
# 配置来源优先级：
#   CLI 参数 > files_scan.sh.conf > 内置默认值
# =============================================================================

usage() {
  cat <<EOF
用法：
  $(basename "$0") <path> [options]

说明：
  接收一个文件或目录路径，输出扫描得到的文件列表。

选项：
  --recursive
      递归扫描子目录（默认：仅当前目录）

  --include-system-files
      包含系统文件

  --include-hidden-dirs
      包含隐藏目录

  -h, --help
      显示本帮助信息

示例：
  $(basename "$0") ./Downloads
  $(basename "$0") ./Downloads --recursive
  $(basename "$0") ./movie.mp4
EOF
}

# -----------------------------------------------------------------------------
# 路径与配置文件
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/files_scan.sh.conf"


# -----------------------------------------------------------------------------
# 内置默认值（兜底用，配置文件可覆盖）
# -----------------------------------------------------------------------------
RECURSIVE=0

EXCLUDE_SYSTEM_FILES=1
SYSTEM_FILES=()
SYSTEM_FILE_PREFIXES=()

EXCLUDE_HIDDEN_DIRS=1
HIDDEN_DIRS=()

# -----------------------------------------------------------------------------
# 加载配置文件（直接 source，配置文件不得产生输出）
# -----------------------------------------------------------------------------
if [[ -f "$CONF_FILE" ]]; then
  source "$CONF_FILE"
fi

# -----------------------------------------------------------------------------
# CLI 参数解析
# -----------------------------------------------------------------------------
INPUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --recursive)
      RECURSIVE=1
      shift
      ;;
    --include-system-files)
      EXCLUDE_SYSTEM_FILES=0
      shift
      ;;
    --include-hidden-dirs)
      EXCLUDE_HIDDEN_DIRS=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "未知参数：$1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$INPUT_PATH" ]]; then
        INPUT_PATH="$1"
      else
        echo "错误：只能指定一个路径参数" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

[[ -n "$INPUT_PATH" ]] || { echo "缺少路径参数" >&2; exit 1; }
[[ -e "$INPUT_PATH" ]] || { echo "路径不存在：$INPUT_PATH" >&2; exit 1; }

# -----------------------------------------------------------------------------
# 工具函数
# -----------------------------------------------------------------------------
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


# -----------------------------------------------------------------------------
# 过滤判定：是否为系统噪音文件
# -----------------------------------------------------------------------------
is_system_noise_file() {
  [[ "$EXCLUDE_SYSTEM_FILES" -eq 1 ]] || return 1

  local base_name
  base_name="$(basename "$1")"

  local sys_name
  for sys_name in "${SYSTEM_FILES[@]}"; do
    [[ "$base_name" == "$sys_name" ]] && return 0
  done

  local prefix
  for prefix in "${SYSTEM_FILE_PREFIXES[@]}"; do
    [[ "$base_name" == "$prefix"* ]] && return 0
  done

  return 1
}


# -----------------------------------------------------------------------------
# 扫描核心：path → 文件列表（逐行输出）
# -----------------------------------------------------------------------------
ROOT_PATH="$(abs_path "$INPUT_PATH")"

scan_files() {

  # 情况一：输入本身就是文件
  if [[ -f "$ROOT_PATH" ]]; then
    printf '%s\n' "$ROOT_PATH"
    return
  fi

  # 情况二：输入是目录
  if [[ "$RECURSIVE" -eq 1 ]]; then

    # 递归扫描（使用 -prune 在结构层剪枝）
    local find_expr=()

    if [[ "$EXCLUDE_HIDDEN_DIRS" -eq 1 ]]; then
      # 剪掉所有隐藏目录 + 明确列出的隐藏目录
      find_expr+=( \( -type d \( -name '.*' )

      local hidden_dir
      for hidden_dir in "${HIDDEN_DIRS[@]:-}"; do
        find_expr+=( -o -name "$hidden_dir" )
      done

      find_expr+=( \) -prune \) -o -type f -print0 )
    else
      find_expr+=( -type f -print0 )
    fi

    find "$ROOT_PATH" "${find_expr[@]}" \
      | while IFS= read -r -d '' file_path; do
          printf '%s\n' "$file_path"
        done

  else
    # 非递归：仅扫描当前目录一层
    find "$ROOT_PATH" -maxdepth 1 -type f -print0 \
      | while IFS= read -r -d '' file_path; do
          printf '%s\n' "$file_path"
        done
  fi
}


# -----------------------------------------------------------------------------
# 执行管线：扫描 → 去重 → 系统文件过滤 → 输出
# -----------------------------------------------------------------------------
scan_files \
  | awk '!seen[$0]++' \
  | while IFS= read -r file_path; do
      is_system_noise_file "$file_path" && continue
      printf '%s\n' "$file_path"
    done

exit 0
