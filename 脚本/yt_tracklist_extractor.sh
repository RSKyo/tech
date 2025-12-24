#!/usr/bin/env bash
IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# yt_tracklist_extractor.sh
#
# Tracklist 提取器（YouTube 描述 → 时间轴文本）
#
# 角色定位
#   本脚本用于从 YouTube 视频的描述文本中提取“时间轴形式”的
#   Tracklist，仅负责识别与整理文本语义。
#
#   它是一个【只读分析工具】：
#     - 不下载媒体
#     - 不生成文件
#     - 不修改外部状态
#
# 输入
#   - YouTube 视频 URL
#   - 通过 yt-dlp 获取 description 文本
#
# 识别规则
#   - 只要一行中出现合法时间戳，即视为 Track 行
#   - 支持时间格式：
#       mm:ss
#       h:mm:ss
#       hh:mm:ss
#
# 输出
#   - 标准输出：逐行 Track 文本
#   - 每行内容默认保持原始描述中的文本
#
# Loop 语义
#   - 当启用最后一行 loop 时：
#       最后一行将被重写为：
#         "<时间戳> @loop"
#       原行中时间戳之后的文本将被丢弃
#
# 行为约定
#   - 若未识别到任何 Track 行：静默退出（exit 0）
#   - 若 Track 行数 < MIN_TRACK_LINES：静默退出（exit 0）
#   - 除参数或环境错误外，不输出错误信息
#
# 使用示例
#   yt_tracklist_extractor.sh "https://www.youtube.com/watch?v=XXXXXXXXXXX"
#
# =============================================================================

# -----------------------------------------------------------------------------
# Defaults / Globals
# -----------------------------------------------------------------------------
readonly CMD_NAME="$(basename "$0")"

YTDLP_BIN="yt-dlp"

MIN_TRACK_LINES=2
ENABLE_LAST_LINE_LOOP=1

INPUT_URL=""

# 与原脚本一致：
# 捕获组 2 = 时间戳本体
TIME_REGEX='(^|[[:space:]])([0-9]{1,2}:[0-9]{2}(:[0-9]{2})?)([[:space:]]|$)'

# -----------------------------------------------------------------------------
# Utils
# -----------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage:
  $CMD_NAME [options] <youtube_url>

Options:
  --min-lines N        最少需要的 track 行数（默认 2）
  --loop-last          最后一行视为 loop（默认）
  --no-loop-last       不处理最后一行 loop
  -h, --help           显示帮助
EOF
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
while (( $# > 0 )); do
  case "$1" in
    --min-lines)
      [[ $# -lt 2 ]] && die "--min-lines requires a value"
      MIN_TRACK_LINES="$2"
      shift 2
      ;;
    --loop-last)
      ENABLE_LAST_LINE_LOOP=1
      shift
      ;;
    --no-loop-last)
      ENABLE_LAST_LINE_LOOP=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      INPUT_URL="$1"
      shift
      ;;
  esac
done

[[ -z "$INPUT_URL" ]] && {
  usage
  die "Missing YouTube URL"
}

command -v "$YTDLP_BIN" >/dev/null 2>&1 \
  || die "yt-dlp not found in PATH"

# -----------------------------------------------------------------------------
# Extract description
# -----------------------------------------------------------------------------
description="$(
  "$YTDLP_BIN" \
    --print description \
    --no-warnings \
    "$INPUT_URL" \
    2>/dev/null || true
)"

[[ -z "$description" ]] && exit 0

# -----------------------------------------------------------------------------
# Collect track lines (match original behavior)
# -----------------------------------------------------------------------------
tracks=()

while IFS= read -r line; do
  line="${line%$'\r'}"
  [[ -z "$line" ]] && continue

  if [[ "$line" =~ $TIME_REGEX ]]; then
    tracks+=("$line")
  fi
done <<< "$description"

(( ${#tracks[@]} < MIN_TRACK_LINES )) && exit 0

# -----------------------------------------------------------------------------
# Handle last-line loop (STRICT original semantics)
# -----------------------------------------------------------------------------
if (( ENABLE_LAST_LINE_LOOP == 1 )); then
  last_idx=$((${#tracks[@]} - 1))
  if [[ "${tracks[$last_idx]}" =~ $TIME_REGEX ]]; then
    tracks[$last_idx]="${BASH_REMATCH[2]} @loop"
  fi
fi

# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------
printf '%s\n' "${tracks[@]}"
