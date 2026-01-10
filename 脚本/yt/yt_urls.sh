#!/usr/bin/env bash
# =============================================================================
# SHID: Yjd7EHuw
# DO NOT REMOVE OR MODIFY THIS BLOCK.
# Used for script identity / indexing.
# =============================================================================

IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# yt_urls.sh
#
# 目标：
#   将多种输入来源统一归一为 YouTube URL 列表。
#
# 支持的输入来源：
#   第一类（直接 URL 语义）：
#     1) 单个 YouTube URL
#     2) URL 列表文件（.txt，每行以 https:// 开头）
#
#   第二类（媒体反推语义）：
#     3) 单个已下载的视频文件（从元数据中反推出来源 URL）
#     4) 指定目录（仅扫描当前目录一层，不递归）
#
# 输出：
#   stdout：
#     - YouTube URL（逐行输出）
#
# 设计说明：
#   - 目录扫描为“非递归”，不会进入子目录
#   - 媒体相关处理全部委托给 files_* 管线
#   - 本脚本不会扫描大体积二进制文件内容，确保性能安全
# =============================================================================

# -----------------------------------------------------------------------------
# 通过 SHID 解析并注入依赖命令
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)"

# source-only 依赖解析器（必须使用 source）
source "$ROOT_DIR/source/resolve_deps.source.sh"

# 将 SHID 解析为可执行命令路径，并注入当前 shell 作用域
resolve_deps \
  ROOT_DIR="$ROOT_DIR" \
  FILES_SCAN_CMD=lBi78Us8 \
  FILES_FILTER_CMD=Aa2p1cxL \
  FILES_ENRICH_YT_CMD=bMZXVxPk

# -----------------------------------------------------------------------------
# 辅助判定函数
# -----------------------------------------------------------------------------

# 判断是否为直接 URL 输入
is_url() {
  [[ "$1" =~ ^https?:// ]]
}

# 判断是否为 URL 列表文件
# 约定：
#   - 仅支持 .txt
#   - 文件中至少存在一行以 https:// 开头
is_url_list_file() {
  local f="$1"
  [[ "$f" == *.txt ]] || return 1
  [[ -f "$f" ]] || return 1
  grep -qE '^https?://' "$f"
}

# 从 URL 列表文件中输出 URL
emit_urls_from_txt() {
  grep -E '^https?://' "$1"
}

# 从媒体路径（文件或目录）中反推出 YouTube URL
# 实际逻辑：
#   files_scan → files_filter(video) → files_enrich.yt → 提取 yt_url 列
emit_urls_from_media_path() {
  "$FILES_SCAN_CMD" "$1" \
    | "$FILES_FILTER_CMD" --type video \
    | "$FILES_ENRICH_YT_CMD" --select yt_url \
    | awk -F'\t' '{ if ($NF != "") print $NF }'
}

# -----------------------------------------------------------------------------
# 输入收集
# -----------------------------------------------------------------------------
INPUTS=()

# 优先使用 argv；若无参数则从 stdin 读取
if [[ $# -gt 0 ]]; then
  INPUTS=( "$@" )
else
  while IFS= read -r line; do
    [[ -n "$line" ]] && INPUTS+=( "$line" )
  done
fi

# -----------------------------------------------------------------------------
# 主分发逻辑
# -----------------------------------------------------------------------------
for item in "${INPUTS[@]}"; do
  # 第一类：直接 URL
  if is_url "$item"; then
    printf '%s\n' "$item"
    continue
  fi

  # 第一类：URL 列表文件（.txt）
  if is_url_list_file "$item"; then
    emit_urls_from_txt "$item"
    continue
  fi

  # 第二类：媒体路径（文件或目录）
  emit_urls_from_media_path "$item"
done

exit 0
