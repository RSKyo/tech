#!/usr/bin/env bash
# ==============================================================================
# media_find_tracklist.sh
# ------------------------------------------------------------------------------
# 接收一个视频文件路径（本地路径），如果文件名在扩展名前包含形如：
#   xxxxxx[LS7vyhX74Uk].webm
# 则认为中括号里的 11 位字符串是 YouTube ID。
#
# 查找规则（只查两个目录，且只查当前层，不递归）：
#   1) 视频同级目录
#   2) 视频同级目录下的 yt_tracklist/ 目录
#
# 在上述目录中查找文件名包含：
#   [ID].tracklist.txt
# 的文件（例如：xxx [LS7vyhX74Uk].tracklist.txt）。
#
# 输出：
#   - 若找到：输出该 tracklist 文件的绝对路径（无额外文字）
#   - 若未找到或无法提取 ID：输出空字符串（无换行也可，建议保持换行）
#
# 用法：
#   media_find_tracklist.sh "/path/to/xxx [LS7vyhX74Uk].webm"
# ==============================================================================

set -euo pipefail

VIDEO_PATH="${1:-}"
if [[ -z "$VIDEO_PATH" ]]; then
  # 无参数：按约定返回空字符串
  printf '%s\n' ""
  exit 0
fi

# 允许上层传相对路径；这里尽量转绝对路径（文件不存在也尽量解析目录）
abs_path() {
  local p="$1"
  if [[ -e "$p" ]]; then
    (cd "$(dirname "$p")" && printf '%s/%s\n' "$(pwd)" "$(basename "$p")")
  else
    # 文件不存在时仍尽量标准化目录
    (cd "$(dirname "$p")" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$(basename "$p")") || printf '%s\n' "$p"
  fi
}

VIDEO_PATH="$(abs_path "$VIDEO_PATH")"
VIDEO_DIR="$(cd "$(dirname "$VIDEO_PATH")" 2>/dev/null && pwd || true)"
VIDEO_BASE="$(basename "$VIDEO_PATH")"

# 从文件名中提取：扩展名前紧邻的 [ID]
# 例如：xxxxxx[LS7vyhX74Uk].webm  ->  LS7vyhX74Uk
ID=""
if [[ "$VIDEO_BASE" =~ \[([A-Za-z0-9_-]{11})\]\.[^.]+$ ]]; then
  ID="${BASH_REMATCH[1]}"
else
  # 没有符合规则的 ID：返回空字符串
  printf '%s\n' ""
  exit 0
fi

# 候选搜索目录：同级目录 + 同级/yt_tracklist
SEARCH_DIRS=()
if [[ -n "$VIDEO_DIR" ]]; then
  SEARCH_DIRS+=("$VIDEO_DIR")
  SEARCH_DIRS+=("$VIDEO_DIR/yt_tracklist")
fi

# 收集匹配项（仅当前层）
matches=()
for d in "${SEARCH_DIRS[@]}"; do
  [[ -d "$d" ]] || continue
  # 只匹配包含 “[ID].tracklist.txt” 的文件名
  while IFS= read -r -d '' f; do
    matches+=("$f")
  done < <(find "$d" -maxdepth 1 -type f -name "*\[$ID\].tracklist.txt" -print0 2>/dev/null || true)
done

if [[ "${#matches[@]}" -eq 0 ]]; then
  printf '%s\n' ""
  exit 0
fi

# 若多个匹配：选择“最后修改时间最新”的那个（macOS: stat -f %m）
best="${matches[0]}"
best_ts=0
for f in "${matches[@]}"; do
  ts="$(stat -f %m "$f" 2>/dev/null || echo 0)"
  if [[ "$ts" -ge "$best_ts" ]]; then
    best_ts="$ts"
    best="$f"
  fi
done

printf '%s\n' "$best"
