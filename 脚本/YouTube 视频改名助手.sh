#!/usr/bin/env bash
# =============================================================================
# YouTube 视频改名助手.sh
# -----------------------------------------------------------------------------
# 功能概述
#   一个“基于来源 URL 的批量视频改名”编排脚本。
#
#   本脚本本身不解析视频来源、不提取 ID，也不决定是否改名，
#   仅负责：
#     - 接收文件或目录输入
#     - 在目录模式下通过 media_list.sh 枚举媒体文件
#     - 对每个文件调用 yt_rename_with_id.sh 执行实际改名
#
# 工作模式
#   1) 单文件模式
#      - 输入：单个媒体文件
#      - 行为：
#          * 直接调用 yt_rename_with_id.sh
#
#   2) 目录模式
#      - 输入：目录路径
#      - 行为：
#          a. 调用 media_list.sh 列出目录中的媒体文件
#          b. 对每个文件调用 yt_rename_with_id.sh
#
# 关于 --type 参数（重要）
#   - --type 是一个“可选透传参数”，仅在用户显式指定时才会传给
#     media_list.sh
#   - 未指定 --type 时：
#       * 本脚本不会向 media_list.sh 传 --type
#       * 实际筛选策略完全由 media_list.sh 的默认行为决定
#   - 指定 --type 时：
#       * 可选值：video | audio | media
#       * 仅用于限制目录模式下被处理的文件类型
#
# 设计原则
#   - 本脚本不擅自决定“默认类型”，避免与 media_list.sh 的默认策略
#     发生隐性耦合
#   - 所有“是否改名”的判断逻辑均下沉至 yt_rename_with_id.sh
#
# 依赖脚本（默认与本脚本位于同一目录）
#   - media_list.sh          （必需：列出媒体文件）
#   - yt_rename_with_id.sh   （必需：执行实际改名）
#
# 用法
#   YouTube 视频改名助手.sh <文件或目录>
#     [--type video|audio|media]   # 仅目录模式生效
# =============================================================================

set -Eeo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# 基础：路径与依赖检查
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MEDIA_LIST="$SCRIPT_DIR/media_list.sh"
YT_RENAME="$SCRIPT_DIR/yt_rename_with_id.sh"

need_exec() {
  local p="$1" name="$2"
  if [ ! -x "$p" ]; then
    echo "错误：找不到可执行的 $name（期望在同目录：$p）" >&2
    exit 1
  fi
}

usage() {
  cat <<'EOF'
用法：
  YouTube 视频改名助手.sh <文件或目录>
    [--type video|audio|media]
EOF
}

need_exec "$MEDIA_LIST" "media_list.sh"
need_exec "$YT_RENAME"  "yt_rename_with_id.sh"

# -----------------------------------------------------------------------------
# 参数解析
# -----------------------------------------------------------------------------
[ $# -ge 1 ] || { usage; exit 1; }

TARGET=""
TYPE=""
TYPE_SPECIFIED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --type)
      shift || true
      case "${1:-}" in
        video|audio|media)
          TYPE="$1"
          TYPE_SPECIFIED=1
          ;;
        *)
          echo "错误：--type 需为 video、audio 或 media" >&2
          exit 1
          ;;
      esac
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
      if [ -z "$TARGET" ]; then
        TARGET="$1"
      else
        echo "错误：仅支持一个路径参数，多余的：$1" >&2
        exit 1
      fi
      ;;
  esac
  shift || true
done

if [ -z "$TARGET" ]; then
  echo "错误：未指定文件或目录" >&2
  exit 1
fi
if [ ! -e "$TARGET" ]; then
  echo "错误：找不到路径：$TARGET" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# 单文件处理
# -----------------------------------------------------------------------------
process_one_file() {
  local file="$1"

  if [ ! -f "$file" ]; then
    echo "警告：跳过非文件路径：$file" >&2
    return 0
  fi

  "$YT_RENAME" "$file"
}

# -----------------------------------------------------------------------------
# 目录处理
# -----------------------------------------------------------------------------
process_dir() {
  local dir="$1"

  echo "扫描目录：$dir"
  if [ "$TYPE_SPECIFIED" -eq 1 ]; then
    echo "类型过滤：$TYPE"
  else
    echo "类型过滤：<未指定>（使用 media_list.sh 的默认策略）"
  fi

  local list_cmd=( "$MEDIA_LIST" "$dir" )
  if [ "$TYPE_SPECIFIED" -eq 1 ]; then
    list_cmd+=( --type "$TYPE" )
  fi

  mapfile -t media_files < <("${list_cmd[@]}")

  local total="${#media_files[@]}"
  if [ "$total" -eq 0 ]; then
    echo "没有找到媒体文件"
    return 0
  fi

  local i
  for ((i=0; i<total; i++)); do
    local media="${media_files[$i]}"
    [ -z "${media// }" ] && continue

    echo
    echo "$((i + 1))/$total $media"
    process_one_file "$media"
  done
}

# -----------------------------------------------------------------------------
# 主入口
# -----------------------------------------------------------------------------
if [ -f "$TARGET" ]; then
  echo "1/1 $TARGET"
  process_one_file "$TARGET"
elif [ -d "$TARGET" ]; then
  process_dir "$TARGET"
else
  echo "错误：不支持的路径类型：$TARGET" >&2
  exit 1
fi
