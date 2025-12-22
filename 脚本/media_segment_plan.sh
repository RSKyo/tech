#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# media_segment_plan.sh
# ------------------------------------------------------------------------------
# Purpose:
#   Generate a segmentation plan (JSON array) for a media file, used by ffmpeg.
#
# Modes (priority high -> low):
#   1) --tracklist <file> : Parse a tracklist text file and generate segments.
#      - Only the LAST line is checked for repeat|replay as a loop marker.
#      - If last line contains repeat|replay, its time is treated as the end time
#        of the final segment; anything after it is ignored.
#      - Middle lines are never treated as loop markers.
#      - Output fields include start/end (seconds) + start_raw/end_raw (time string).
#
#   2) --segment <N> : Split into fixed-length segments (seconds).
#   3) default       : Output a single full-length segment.
#
# Dependencies:
#   - jq, bc, ffprobe (via video_metadata.sh)
#   - video_metadata.sh, _json_get.sh, parse_tracklist.sh
# ==============================================================================

# ------------------------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------------------------
require_executables() {
  local scripts=(
    "video_metadata.sh"
    "_json_get.sh"
    "parse_tracklist.sh"
  )

  for s in "${scripts[@]}"; do
    if [[ ! -x "$SCRIPT_DIR/$s" ]]; then
      echo "Error: 依赖脚本不存在或不可执行: $SCRIPT_DIR/$s" >&2
      echo "Hint: 请确认该文件存在，并执行: chmod +x \"$SCRIPT_DIR/$s\"" >&2
      exit 1
    fi
  done
}

die() {
  echo "Error: $*" >&2
  exit 1
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

  read -r duration video_title video_artist < <(
    "$SCRIPT_DIR/_json_get.sh" \
      --json "$meta_json" \
      --key duration \
      --key title \
      --key artist
  )

  if [[ "$video_artist" == "null" ]] || [[ -z "$video_artist" ]]; then
    video_artist=""
  fi
}

# ------------------------------------------------------------------------------
# JSON helpers
# ------------------------------------------------------------------------------
append_plan_entry() {
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

# ------------------------------------------------------------------------------
# Tracklist mode
# ------------------------------------------------------------------------------
tracklist_get_effective_range() {
  # Outputs:
  #   effective_len, has_loop, loop_time
  # Rules:
  #   Only the LAST line is checked for repeat|replay.
  #   If present: that last line is a loop marker and excluded from segment list.
  #              loop_time is used as the end time of the final segment.
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
    if [[ "$loop_time" == "null" || -z "$loop_time" ]]; then
      die "最后一行包含 repeat|replay 但缺少 time（无法确定上一段结束时间）"
    fi
    has_loop=1
    effective_len=$((length - 1))
  fi
}

tracklist_pick_artist() {
  # Choose artist with the following priority:
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

    # End time:
    # - if not last: next entry time
    # - if last:
    #     - has_loop: loop_time
    #     - else: duration
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

    append_plan_entry "$start_sec" "$end_sec" "$start_raw" "$end_raw" "$title" "$final_artist"
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

    # Keep output structure unchanged for segment mode (no start_raw/end_raw).
    local line
    line=$(jq -n \
      --arg start "$start" \
      --arg end "$end" \
      --arg title "$part_title" \
      --arg artist "$video_artist" \
      '{start: ($start|tonumber), end: ($end|tonumber), title: $title, artist: $artist}')

    plan_entries=$(echo "$plan_entries" | jq --argjson item "$line" '. += [$item]')

    start=$end
    idx=$((idx+1))
  done

  echo "$plan_entries"
}

# ------------------------------------------------------------------------------
# Full mode
# ------------------------------------------------------------------------------
full_build_plan() {
  # Keep output structure unchanged for full mode (no start_raw/end_raw).
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

# ==============================================================================
# Main
# ==============================================================================
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
