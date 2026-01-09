#!/usr/bin/env bash
# =============================================================================
# SHID: FB5uMYAc
# DO NOT REMOVE OR MODIFY THIS BLOCK.
# Used for script identity / indexing.
# =============================================================================

IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# files_view.sh
#
# 用法：
#   files_view.sh 3,1,5
#
# 说明：
#   - 输入必须是 files table stream
#   - 第一列 file 永远保留、永远是第 1 列
#   - 参数中的数字表示：file 后的第 N 列
#   - 仅改变“视图顺序”，不改变实体
# =============================================================================

# -----------------------------------------------------------------------------
# 参数解析（仅接受一个参数：逗号分隔的列号）
# -----------------------------------------------------------------------------
[ $# -eq 1 ] || {
  echo "用法：$(basename "$0") 3,1,5" >&2
  exit 1
}

IFS=',' read -r -a VIEW_COLS <<<"$1"

# 校验参数必须是正整数
for n in "${VIEW_COLS[@]}"; do
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || {
    echo "错误：非法列号 '$n'（必须是正整数）" >&2
    exit 1
  }
done

# -----------------------------------------------------------------------------
# 主循环（逐行流式）
# -----------------------------------------------------------------------------
first_line=1

while IFS= read -r line; do
  [ -n "$line" ] || continue

  IFS=$'\t' read -r -a cols <<<"$line"
  file="${cols[0]}"

  # 第一行校验
  if (( first_line )); then
    if [ ! -f "$file" ]; then
      echo "错误：输入不是 files table（第一列不是文件路径）：$file" >&2
      exit 1
    fi
    first_line=0
  fi

  # 后续行：文件不存在直接跳过
  [ -f "$file" ] || continue

  # 组装输出：file + 选中的视图列
  out=( "$file" )

  for n in "${VIEW_COLS[@]}"; do
    idx=$n   # 逻辑列号：file 后的第 n 列
    if [ "$idx" -lt "${#cols[@]}" ]; then
      out+=( "${cols[$idx]}" )
    else
      out+=( "" )
    fi
  done

  printf '%s\n' "$(IFS=$'\t'; echo "${out[*]}")"
done
