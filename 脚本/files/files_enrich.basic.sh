#!/usr/bin/env bash
# =============================================================================
# SHID: 9I3z9gZT
# DO NOT REMOVE OR MODIFY THIS BLOCK.
# Used for script identity / indexing.
# =============================================================================

IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# files_enrich.basic.sh
#
# stdin:
#   file
#   或 file <tab> colA <tab> colB ...
#
# stdout:
#   原始整行 + 追加 select 字段
#
# 规则：
#   - 仅检查第一行第一列是否为文件
#   - 后续行若文件不存在，直接跳过
#   - 逐行处理，逐行输出
# =============================================================================

# -----------------------------------------------------------------------------
# 字段定义（单一真源）
# -----------------------------------------------------------------------------
BASE_FIELDS=(abs_path basename filename ext size mtime)

# -----------------------------------------------------------------------------
# 参数解析
# -----------------------------------------------------------------------------
SELECT_FIELDS=()

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
  cat filelist | $(basename "$0") [--select field1,field2,...]

可选字段：
  ${BASE_FIELDS[*]}
EOF
      exit 0
      ;;
    *)
      echo "未知参数：$1" >&2
      exit 1
      ;;
  esac
done

# -----------------------------------------------------------------------------
# select 校验
# -----------------------------------------------------------------------------
if [ "${#SELECT_FIELDS[@]}" -eq 0 ]; then
  SELECT_FIELDS=( "${BASE_FIELDS[@]}" )
else
  for f in "${SELECT_FIELDS[@]}"; do
    if ! printf '%s\n' "${BASE_FIELDS[@]}" | grep -qx "$f"; then
      echo "错误：非法字段 '$f'" >&2
      exit 1
    fi
  done
fi

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
# 主逻辑（逐行流式）
# -----------------------------------------------------------------------------
first_line=1

while IFS= read -r line; do
  [ -n "$line" ] || continue

  # 拆分列（保持原始列）
  IFS=$'\t' read -r -a cols <<<"$line"
  file="${cols[0]}"

  # 第一行：结构校验
  if [ "$first_line" -eq 1 ]; then
    if [ ! -f "$file" ]; then
      echo "错误：输入第一列不是有效文件路径：$file" >&2
      exit 1
    fi
    first_line=0
  fi

  # 后续行：文件不存在直接跳过
  [ -f "$file" ] || continue

  # 懒加载字段
  abs_path_v=""
  basename_v=""
  filename_v=""
  ext_v=""
  size_v=""
  mtime_v=""

  for f in "${SELECT_FIELDS[@]}"; do
    case "$f" in
      abs_path)
        abs_path_v="$(abs_path "$file")"
        ;;
      basename)
        basename_v="$(basename "$file")"
        ;;
      filename)
        b="$(basename "$file")"
        filename_v="${b%.*}"
        ;;
      ext)
        b="$(basename "$file")"
        [[ "$b" == *.* ]] && ext_v="${b##*.}" || ext_v=""
        ;;
      size)
        size_v="$(stat -f%z "$file" 2>/dev/null || echo "")"
        ;;
      mtime)
        mtime_v="$(stat -f%m "$file" 2>/dev/null || echo "")"
        ;;
    esac
  done

  declare -A row=(
    [abs_path]="$abs_path_v"
    [basename]="$basename_v"
    [filename]="$filename_v"
    [ext]="$ext_v"
    [size]="$size_v"
    [mtime]="$mtime_v"
  )

  # 组装输出
  out=( "${cols[@]}" )
  for f in "${SELECT_FIELDS[@]}"; do
    out+=( "${row[$f]}" )
  done

  printf '%s\n' "$(IFS=$'\t'; echo "${out[*]}")"

done
