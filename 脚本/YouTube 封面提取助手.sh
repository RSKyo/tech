#!/usr/bin/env bash
IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# YouTube 封面提取助手.sh
#
# 纯入口封装脚本（wrapper）
#
# 功能：
#   - 接收一个 YouTube 地址 或 一个地址列表文件
#   - 通过 yt/yt_urls.sh 生成 URL 列表
#   - 逐个调用 yt/yt_thumbnail.sh
#   - 在上游显示处理进度 [i/total]
#
# 特殊规则：
#   - 若未显式指定 --out，则自动构造：
#       --out "$SCRIPT_DIR/thumbnail"
#
# 设计原则：
#   - 不联网
#   - 不解析 URL
#   - 不处理封面细节
#   - 不改动 yt_thumbnail.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YT_DIR="$SCRIPT_DIR/yt"

YT_URLS_CMD="$YT_DIR/yt_urls.sh"
YT_THUMB_CMD="$YT_DIR/yt_thumbnail.sh"

# ---------------------------------------------------------------------------
# dependency check
# ---------------------------------------------------------------------------
missing=0

check_dep() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo "[ERROR] missing required script: $f" >&2
    missing=1
  elif [[ ! -x "$f" ]]; then
    echo "[ERROR] script not executable: $f" >&2
    missing=1
  fi
}

check_dep "$YT_URLS_CMD"
check_dep "$YT_THUMB_CMD"

[[ $missing -eq 0 ]] || exit 1

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  local cmd
  cmd="$(basename "$0")"

  cat >&2 <<EOF
Usage:
  $cmd <url> [options...]
  $cmd <urls.txt> [options...]

Description:
  Wrapper script for extracting YouTube thumbnails.

Notes:
  If --out is not specified, it defaults to:
    $SCRIPT_DIR/thumbnail/

Options:
  All other options are passed through to yt_thumbnail.sh, such as:
    --with-title
    --force
EOF
}

# ---------------------------------------------------------------------------
# argument handling
# ---------------------------------------------------------------------------
[[ $# -ge 1 ]] || { usage; exit 1; }

INPUT="$1"
shift

# ---------------------------------------------------------------------------
# detect --out
# ---------------------------------------------------------------------------
HAS_OUT=0
for arg in "$@"; do
  if [[ "$arg" == "--out" ]]; then
    HAS_OUT=1
    break
  fi
done

THUMB_ARGS=("$@")

# 若未指定 --out，则由入口脚本兜底构造
if [[ $HAS_OUT -eq 0 ]]; then
  THUMB_ARGS=(--out "$SCRIPT_DIR/thumbnail" "${THUMB_ARGS[@]}")
fi

# ---------------------------------------------------------------------------
# expand URLs (一次性获取，用于统计 total)
# ---------------------------------------------------------------------------
mapfile -t URLS < <("$YT_URLS_CMD" "$INPUT")

total=${#URLS[@]}
if [[ $total -eq 0 ]]; then
  echo "[WARN] no valid URLs found" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# main loop with progress
# ---------------------------------------------------------------------------
idx=0
for url in "${URLS[@]}"; do
  idx=$((idx + 1))
  echo "[$idx/$total] $url" >&2
  "$YT_THUMB_CMD" "$url" "${THUMB_ARGS[@]}"
done
