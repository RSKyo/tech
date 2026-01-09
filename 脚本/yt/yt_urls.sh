#!/usr/bin/env bash
IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# yt_urls.sh
#
# 接收：
#   - 单个 YouTube URL
#   - 或包含 YouTube URL 的文本文件
#
# 输出：
#   - URL 列表（stdout，一行一个）
#
# 设计原则：
#   - 不联网
#   - 不解析 videoId
#   - 不校验 URL 可用性
#   - 仅负责“统一输出 URL 流”
#
# 用法：
#   yt_urls.sh <url>
#   yt_urls.sh <urls.txt>
# =============================================================================

usage() {
  cat >&2 <<'EOF'
Usage:
  yt_urls.sh <url>
  yt_urls.sh <urls.txt>

Description:
  Output YouTube URL list from a single URL or a text file.
EOF
}

# ---------------------------------------------------------------------------
# 参数校验
# ---------------------------------------------------------------------------
[[ $# -eq 1 ]] || { usage; exit 1; }

input="$1"

# ---------------------------------------------------------------------------
# 主逻辑
# ---------------------------------------------------------------------------
if [[ -f "$input" ]]; then
  # 文件模式：逐行输出
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf '%s\n' "$line"
  done < "$input"
else
  # 单个 URL
  printf '%s\n' "$input"
fi
