#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# media_segment_plan.sh
# ------------------------------------------------------------------------------
# 功能说明：
#   为指定媒体文件生成「分段计划（Segment Plan）」的 JSON 输出，
#   供后续 ffmpeg 或其他处理流程使用。
#
#   输出结果是一个 JSON 数组，每一项描述一个分段：
#     - start / end       : 数值秒（用于计算与切割）
#     - start_raw / end_raw（仅 tracklist 模式）:
#                           原始时间字符串（用于展示、回写、调试）
#     - title / artist    : 曲目信息
#
# ------------------------------------------------------------------------------
# 使用模式（优先级从高到低）：
#
#   1) --tracklist <file>
#      使用 tracklist 文本文件生成分段计划（推荐模式）。
#
#      tracklist 解析规则（重要约定）：
#      - 只检查「最后一行」是否包含 repeat 或 replay（大小写不敏感）：
#          * 如果包含：
#              - 该行被视为“循环起点标记行”
#              - 该行的 time 作为「上一段的结束时间」
#              - 该行本身不会生成 segment
#              - 后续内容一律忽略
#          * 如果不包含：
#              - 最后一段自然结束于视频总时长
#      - tracklist 中间行即使包含 repeat / replay，
#        一律视为普通标题文本，不参与循环判断。
#
#      时间规则：
#      - 每一段的 end 必须严格大于 start；
#        若出现非递增时间，脚本会直接报错退出。
#
#      输出字段：
#      - start / end       : 秒（number）
#      - start_raw / end_raw : 原始时间字符串（MM:SS / HH:MM:SS）
#      - title / artist
#
#   2) --segment <N>
#      按固定秒数 N 对视频进行切割。
#      - 不使用 tracklist
#      - 不输出 start_raw / end_raw（保持原有结构）
#
#   3) 无参数
#      输出整段视频（0 → duration）的单一 segment。
#
# ------------------------------------------------------------------------------
# 元信息来源：
#   - video_metadata.sh
#       * 输出 JSON，至少包含：
#           - duration : 视频总时长（秒，可能带小数）
#           - title    : 视频标题
#           - artist   : 视频作者/艺术家（可选）
#
# ------------------------------------------------------------------------------
# 依赖环境：
#   - bash（支持 set -euo pipefail）
#   - jq
#   - bc
#   - ffprobe（由 video_metadata.sh 内部使用）
#
# 依赖脚本：
#   - video_metadata.sh
#   - parse_tracklist.sh
#
# ------------------------------------------------------------------------------
# 设计目标：
#   - 逻辑清晰、规则显式
#   - 数值时间与原始字符串时间分离
#   - repeat/replay 语义只在最后一行生效，避免误判
#   - 便于长期维护与二次扩展
# ==============================================================================


# ------------------------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------------------------
die() {
  echo "Error: $*" >&2
  exit 1
}

require_executables() {
  local scripts=(
    "video_metadata.sh"
    "parse_tracklist.sh"
  )

  for s in "${scripts[@]}"; do
    if [[ ! -x "$SCRIPT_DIR/$s" ]]; then
      echo "Error: 依赖脚本不存在或不可执行: $SCRIPT_DIR/$s" >&2
      echo "Hint: 请确认该文件存在，并执行: chmod +x \"$SCRIPT_DIR/$s\"" >&2
      exit 1
    fi
  done

  command -v jq >/dev/null 2>&1 || die "缺少依赖命令: jq"
  command -v bc >/dev/null 2>&1 || die "缺少依赖命令: bc"
}

# ------------------------------------------------------------------------------
# Time helpers
# ------------------------------------------------------------------------------
to_seconds() {
  local t="$1"
  t="${t//[[:space:]]/}"  # remove all whitespace

  local hh="0" mm="0" ss="0"
  if [[ "$t" =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
    mm="${BASH_REMATCH[1]}"
    ss="${BASH_REMATCH[2]}"
  elif [[ "$t" =~ ^([0-9]{1,2}):([0-9]{2}):([0-9]{2})$ ]]; then
    hh="${BASH_REMATCH[1]}"
    mm="${BASH_REMATCH[2]}"
    ss="${BASH_REMATCH[3]}"
  else
    die "非法时间格式: '$1'（期望 MM:SS 或 HH:MM:SS）"
  fi

  echo $((10#$hh*3600 + 10#$mm*60 + 10#$ss))
}

seconds_to_hms() {
  # For display only. Floor decimals to avoid showing a longer-than-real duration.
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
  [[ -n "$VIDEO_FILE" ]] || die "必须提供视频文件路径"
  [[ -f "$VIDEO_FILE" ]] || die "视频文件不存在: $VIDEO_FILE"

  if [[ -n "$TRACKLIST_FILE" ]]; then
    [[ -f "$TRACKLIST_FILE" ]] || die "tracklist 文件不存在: $TRACKLIST_FILE"
  fi

  if [[ -n "$TRACKLIST_FILE" && -n "$SEGMENT_SECS" ]]; then
    die "--tracklist 与 --segment 不能同时使用"
  fi
}

# ------------------------------------------------------------------------------
# Metadata
# ------------------------------------------------------------------------------
load_video_meta() {
  local meta_json
  meta_json=$("$SCRIPT_DIR/video_metadata.sh" "$VIDEO_FILE")

  # Extract multiple fields in a single jq call; output as TSV for stable read.
  read -r duration video_title video_artist < <(
    jq -r '[.duration, .title, .artist] | @tsv' <<<"$meta_json"
  )

  [[ -n "$duration" && "$duration" != "null" ]] || die "无法从 video_metadata 中获取 duration"

  if [[ "$video_title" == "null" ]]; then
    video_title=""
  fi
  if [[ "$video_artist" == "null" ]]; then
    video_artist=""
  fi
}

# ------------------------------------------------------------------------------
# JSON plan helpers
# ------------------------------------------------------------------------------
append_plan_entry_with_raw() {
  local start_sec="$1"
  local end_sec="$2"
  local start_raw="$3"
  local end_raw="$4"
  local title="$5"
  local artist="$6"

  local line
  line=$(jq -n \
    --arg start "$start_sec" \
    --arg end "$end_sec" \
    --arg start_raw "$start_raw" \
    --arg end_raw "$end_raw" \
    --arg title "$title" \
    --arg artist "$artist" \
    '{
      start: ($start|tonumber),
      end: ($end|tonumber),
      start_raw: $start_raw,
      end_raw: $end_raw,
      title: $title,
      artist: $artist
    }')

  plan_entries=$(echo "$plan_entries" | jq --argjson item "$line" '. += [$item]')
}

append_plan_entry_basic() {
  local start="$1"
  local end="$2"
  local title="$3"
  local artist="$4"

  local line
  line=$(jq -n \
    --arg start "$start" \
    --arg end "$end" \
    --arg title "$title" \
    --arg artist "$artist" \
    '{start: ($start|tonumber), end: ($end|tonumber), title: $title, artist: $artist}')

  plan_entries=$(echo "$plan_entries" | jq --argjson item "$line" '. += [$item]')
}

# ------------------------------------------------------------------------------
# Tracklist mode
# ------------------------------------------------------------------------------
tracklist_get_effective_range() {
  # Outputs (globals):
  #   effective_len, has_loop, loop_time
  # Rule:
  #   Only LAST line is checked for repeat|replay; middle lines are ignored.
  local tl_json="$1"
  local length="$2"

  has_loop=0
  loop_time=""
  effective_len="$length"

  if (( length <= 0 )); then
    return 0
  fi

  local last loop_raw
  last=$(echo "$tl_json" | jq -c ".[${length}-1]")
  loop_raw=$(echo "$last" | jq -r '.raw // ""')

  if echo "$loop_raw" | grep -qiE 'repeat|replay'; then
    loop_time=$(echo "$last" | jq -r '.time // "null"')
    [[ "$loop_time" != "null" && -n "$loop_time" ]] || die "最后一行包含 repeat|replay 但缺少 time（无法确定上一段结束时间）"
    has_loop=1
    effective_len=$((length - 1))
  fi
}

tracklist_pick_artist() {
  # Priority:
  #   1) artists[] joined by ", "
  #   2) artist
  #   3) fallback video_artist
  local entry="$1"

  local artists_arr artist
  artists_arr=$(echo "$entry" | jq -r '.artists // [] | join(", ")')
  artist=$(echo "$entry" | jq -r '.artist // ""')

  if [[ -n "$artists_arr" ]]; then
    echo "$artists_arr"
  elif [[ -n "$artist" && "$artist" != "null" ]]; then
    echo "$artist"
  else
    echo "$video_artist"
  fi
}

tracklist_build_plan() {
  local tl_json="$1"
  local length="$2"

  plan_entries="[]"

  tracklist_get_effective_range "$tl_json" "$length"

  if (( effective_len <= 0 )); then
    echo "[]"
    return 0
  fi

  local i entry
  for ((i=0; i<effective_len; i++)); do
    entry=$(echo "$tl_json" | jq -c ".[$i]")

    # Start time
    local start_raw start_sec
    start_raw=$(echo "$entry" | jq -r '.time // "null"')
    [[ "$start_raw" != "null" && -n "$start_raw" ]] || die "tracklist 中发现 time=null（无法确定开始时间）"
    start_sec="$(to_seconds "$start_raw")"

    # End time
    local end_raw end_sec
    if (( i < effective_len - 1 )); then
      local next next_t
      next=$(echo "$tl_json" | jq -c ".[$((i+1))]")
      next_t=$(echo "$next" | jq -r '.time // "null"')
      [[ "$next_t" != "null" && -n "$next_t" ]] || die "下一条 tracklist time=null（无法确定结束时间）"
      end_raw="$next_t"
      end_sec="$(to_seconds "$next_t")"
    else
      if (( has_loop == 1 )); then
        end_raw="$loop_time"
        end_sec="$(to_seconds "$loop_time")"
      else
        end_raw="$(seconds_to_hms "$duration")"
        end_sec="$duration"
      fi
    fi

    # Monotonicity check
    if (( $(printf "%.0f" "$end_sec") <= start_sec )); then
      die "非递增时间：start=$start_raw end=$end_raw（end 必须大于 start）"
    fi

    # Title + Artist
    local title final_artist
    title=$(echo "$entry" | jq -r '.title // .name // ""')
    final_artist="$(tracklist_pick_artist "$entry")"

    append_plan_entry_with_raw "$start_sec" "$end_sec" "$start_raw" "$end_raw" "$title" "$final_artist"
  done

  echo "$plan_entries"
}

# ------------------------------------------------------------------------------
# Segment mode
# ------------------------------------------------------------------------------
segment_build_plan() {
  local n="$1"

  plan_entries="[]"
  local idx=1
  local start=0

  while (( $(echo "$start < $duration" | bc -l) )); do
    local end
    end=$(echo "$start + $n" | bc -l)

    local cmp
    cmp=$(echo "$end > $duration" | bc -l)
    if (( cmp == 1 )); then
      end=$duration
    fi

    local part_title="${video_title} (Part ${idx})"
    append_plan_entry_basic "$start" "$end" "$part_title" "$video_artist"

    start=$end
    idx=$((idx+1))
  done

  echo "$plan_entries"
}

# ------------------------------------------------------------------------------
# Full mode
# ------------------------------------------------------------------------------
full_build_plan() {
  jq -n \
    --arg start "0" \
    --arg end "$duration" \
    --arg title "$video_title" \
    --arg artist "$video_artist" \
  '[{
    start: ($start|tonumber),
    end: ($end|tonumber),
    title: $title,
    artist: $artist
  }]'
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
  require_executables
  parse_args "$@"
  validate_args
  load_video_meta

  if [[ -n "$TRACKLIST_FILE" ]]; then
    local tl_json length
    tl_json=$("$SCRIPT_DIR/parse_tracklist.sh" "$TRACKLIST_FILE")
    length=$(echo "$tl_json" | jq -r 'length')
    tracklist_build_plan "$tl_json" "$length"
    exit 0
  fi

  if [[ -n "$SEGMENT_SECS" ]]; then
    segment_build_plan "$SEGMENT_SECS"
    exit 0
  fi

  full_build_plan
}

main "$@"
