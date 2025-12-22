#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# media_segment_plan.sh
# ------------------------------------------------------------------------------
# 功能说明：
#
#   为指定的本地媒体文件生成「分段计划（Segment Plan）」的 JSON 输出，
#   供后续 ffmpeg 或其他音视频处理流程使用。
#
#   分段计划用于描述“从哪里切到哪里”，
#   不直接执行切割，仅生成可执行的时间区间定义。
#
# ------------------------------------------------------------------------------
# 支持的使用模式（优先级从高到低）：
#
#   1) --tracklist <file>
#
#      使用 tracklist 文件生成分段计划（推荐模式）。
#
#      tracklist 文件需由上游脚本解析生成（如 parse_tracklist.sh），
#      其 JSON 结构至少包含：
#
#        {
#          "time": "MM:SS" | "HH:MM:SS",
#          "text": "<曲目文本>",
#          "raw":  "<原始行文本>"
#        }
#
#      tracklist 规则与约定：
#
#      - 仅检查「最后一行」是否包含显式循环标记：@loop（大小写不敏感）：
#
#          * 如果包含：
#              - 该行被视为“循环起点标记行”
#              - 该行本身不会生成 segment
#              - 该行的 time 作为「上一段的结束时间」
#              - 后续内容一律忽略
#
#          * 如果不包含：
#              - 最后一段自然结束于媒体总时长
#
#      - tracklist 中间行即使包含 @loop，
#        一律视为普通标题文本，不参与循环判断。
#
#      时间约定：
#
#      - 每一段的 end 必须严格大于 start
#      - 若出现非递增时间，脚本会直接报错退出
#
#      输出字段：
#
#        - start / end
#            数值秒（number），用于计算与切割
#
#        - start_raw / end_raw
#            原始时间字符串（MM:SS / HH:MM:SS）
#
#        - title
#            直接使用 tracklist 中的 text 字段，
#            不做拆分、不做语义推断
#
#   2) --segment <N>
#
#      按固定秒数 N 对媒体进行顺序切割。
#
#      - 不使用 tracklist
#      - 每一段长度为 N 秒（最后一段可能不足）
#      - 自动生成标题：Part 1 / Part 2 / ...
#
#      输出字段：
#
#        - start / end
#        - title
#
#   3) 无参数
#
#      输出整段媒体的单一 segment：
#
#        start = 0
#        end   = 媒体总时长
#
# ------------------------------------------------------------------------------
# 媒体时长来源：
#
#   - 使用 ffprobe 从本地媒体文件直接读取真实时长
#   - 不依赖外部元数据或网络服务
#
# ------------------------------------------------------------------------------
# 依赖环境：
#
#   - jq
#       用于解析与构建 JSON
#
#   - bc
#       用于浮点时间计算（segment 模式）
#
#   - ffprobe（来自 ffmpeg）
#       用于获取媒体文件总时长
#
# ------------------------------------------------------------------------------
# 设计目标：
#
#   - 保持与原脚本一致的使用方式与功能覆盖
#   - 规则显式、行为确定，不做隐式推断
#   - 支持多种分段模式，便于复用
#   - 在不影响既有能力的前提下，简化元数据依赖
#
# ==============================================================================


# ------------------------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------------------------
die() {
  echo "Error: $*" >&2
  exit 1
}

require_executables() {
  command -v jq >/dev/null 2>&1 || die "缺少依赖命令: jq"
  command -v bc >/dev/null 2>&1 || die "缺少依赖命令: bc"
  command -v ffprobe >/dev/null 2>&1 || die "缺少依赖命令: ffprobe"
}

# ------------------------------------------------------------------------------
# Time helpers
# ------------------------------------------------------------------------------
to_seconds() {
  local t="$1"
  t="${t//[[:space:]]/}"

  local hh="0" mm="0" ss="0"
  if [[ "$t" =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
    mm="${BASH_REMATCH[1]}"
    ss="${BASH_REMATCH[2]}"
  elif [[ "$t" =~ ^([0-9]{1,2}):([0-9]{2}):([0-9]{2})$ ]]; then
    hh="${BASH_REMATCH[1]}"
    mm="${BASH_REMATCH[2]}"
    ss="${BASH_REMATCH[3]}"
  else
    die "非法时间格式: '$1'"
  fi

  echo $((10#$hh*3600 + 10#$mm*60 + 10#$ss))
}

seconds_to_hms() {
  local s="${1%.*}"
  [[ -z "$s" ]] && s=0

  local h=$(( s / 3600 ))
  local m=$(( (s % 3600) / 60 ))
  local sec=$(( s % 60 ))

  if (( h > 0 )); then
    printf "%d:%02d:%02d" "$h" "$m" "$sec"
  else
    printf "%02d:%02d" "$m" "$sec"
  fi
}

# ------------------------------------------------------------------------------
# CLI parsing & validation
# ------------------------------------------------------------------------------
parse_args() {
  VIDEO_FILE=""
  TRACKLIST_FILE=""
  SEGMENT_SECS=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tracklist)
        TRACKLIST_FILE="${2:-}"
        shift 2
        ;;
      --segment)
        SEGMENT_SECS="${2:-}"
        shift 2
        ;;
      *)
        VIDEO_FILE="$1"
        shift
        ;;
    esac
  done
}

validate_args() {
  [[ -n "$VIDEO_FILE" ]] || die "必须提供媒体文件路径"
  [[ -f "$VIDEO_FILE" ]] || die "媒体文件不存在: $VIDEO_FILE"

  if [[ -n "$TRACKLIST_FILE" ]]; then
    [[ -f "$TRACKLIST_FILE" ]] || die "tracklist 文件不存在: $TRACKLIST_FILE"
  fi

  if [[ -n "$TRACKLIST_FILE" && -n "$SEGMENT_SECS" ]]; then
    die "--tracklist 与 --segment 不能同时使用"
  fi
}

# ------------------------------------------------------------------------------
# Media duration
# ------------------------------------------------------------------------------
load_duration() {
  duration="$(ffprobe -v error \
    -show_entries format=duration \
    -of default=nw=1:nk=1 \
    "$VIDEO_FILE")"

  [[ -n "$duration" ]] || die "无法获取媒体时长"
}

# ------------------------------------------------------------------------------
# Tracklist loop handling
# ------------------------------------------------------------------------------
tracklist_get_effective_range() {
  local tl_json="$1"
  local length="$2"

  has_loop=0
  loop_time=""
  effective_len="$length"

  (( length <= 0 )) && return 0

  local last_raw
  last_raw=$(echo "$tl_json" | jq -r ".[${length}-1].raw // \"\"")

  if echo "$last_raw" | grep -qi '@loop'; then
    loop_time=$(echo "$tl_json" | jq -r ".[${length}-1].time // \"\"")
    [[ -n "$loop_time" ]] || die "最后一行包含 @loop 但缺少 time"
    has_loop=1
    effective_len=$((length - 1))
  fi
}

append_segment() {
  local start="$1"
  local end="$2"
  local start_raw="$3"
  local end_raw="$4"
  local title="$5"

  plan_entries=$(echo "$plan_entries" | jq \
    --arg start "$start" \
    --arg end "$end" \
    --arg start_raw "$start_raw" \
    --arg end_raw "$end_raw" \
    --arg title "$title" \
    '. += [{
      start: ($start|tonumber),
      end: ($end|tonumber),
      start_raw: $start_raw,
      end_raw: $end_raw,
      title: $title
    }]')
}


# ------------------------------------------------------------------------------
# Tracklist plan builder
# ------------------------------------------------------------------------------
tracklist_build_plan() {
  local tl_json="$1"
  local length="$2"

  plan_entries="[]"
  tracklist_get_effective_range "$tl_json" "$length"

  (( effective_len <= 0 )) && { echo "[]"; return 0; }

  for ((i=0; i<effective_len; i++)); do
    local entry start_raw start_sec end_raw end_sec title

    entry=$(echo "$tl_json" | jq -c ".[$i]")
    start_raw=$(echo "$entry" | jq -r '.time')
    start_sec="$(to_seconds "$start_raw")"

    if (( i < effective_len - 1 )); then
      end_raw=$(echo "$tl_json" | jq -r ".[$((i+1))].time")
      end_sec="$(to_seconds "$end_raw")"
    else
      if (( has_loop == 1 )); then
        end_raw="$loop_time"
        end_sec="$(to_seconds "$loop_time")"
      else
        end_raw="$(seconds_to_hms "$duration")"
        end_sec="$duration"
      fi
    fi

    (( end_sec > start_sec )) || die "非递增时间：$start_raw → $end_raw"

    title=$(echo "$entry" | jq -r '.text // ""')

    append_segment \
      "$start_sec" \
      "$end_sec" \
      "$start_raw" \
      "$end_raw" \
      "$title"

  done

  echo "$plan_entries"
}

# ------------------------------------------------------------------------------
# Segment / full modes
# ------------------------------------------------------------------------------
segment_build_plan() {
  local title="$1"
  local n="$2"
  plan_entries="[]"
  local start=0 idx=1

  while (( $(echo "$start < $duration" | bc -l) )); do
    local end=$(echo "$start + $n" | bc -l)
    (( $(echo "$end > $duration" | bc -l) )) && end="$duration"

    local start_raw end_raw
    start_raw="$(seconds_to_hms "$start")"
    end_raw="$(seconds_to_hms "$end")"

    append_segment \
      "$start" \
      "$end" \
      "$start_raw" \
      "$end_raw" \
      "${title} Part ${idx}"

    start="$end"
    idx=$((idx+1))
  done

  echo "$plan_entries"
}

full_build_plan() {
  plan_entries="[]"
  local title="$1"
  local start end start_raw end_raw
  start="0"
  end="$duration"
  start_raw="$(seconds_to_hms "$start")"
  end_raw="$(seconds_to_hms "$end")"

  append_segment \
    "$start" \
    "$end" \
    "$start_raw" \
    "$end_raw" \
    "$title"

  echo "$plan_entries"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
  require_executables
  parse_args "$@"
  validate_args
  load_duration

  base_title="$(basename "$VIDEO_FILE")"
  base_title="${base_title%.*}"

  if [[ -n "$TRACKLIST_FILE" ]]; then
    local tl_json length
    tl_json=$("$SCRIPT_DIR/parse_tracklist.sh" "$TRACKLIST_FILE")
    length=$(echo "$tl_json" | jq -r 'length')
    tracklist_build_plan "$tl_json" "$length"
  elif [[ -n "$SEGMENT_SECS" ]]; then
    segment_build_plan "$base_title" "$SEGMENT_SECS"
  else
    full_build_plan "$base_title"
  fi
}

main "$@"
