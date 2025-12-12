#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# media_segment_plan.sh
# ------------------------------------------------------------------------------
# 作用：
#   为指定视频生成分割计划（JSON），供后续 ffmpeg 分割使用。
#
# 输入模式（优先级从高到低）：
#
#   1) --tracklist file
#        使用 parse_tracklist.sh 解析 tracklist 文本 → 自动生成分割计划。
#
#   2) --segment N
#        按固定秒数切割视频。
#
#   3) 无参数：
#        输出整段（0 → duration）。
#
# 依赖：
#   - ffprobe（用于视频元信息）
#   - jq
#   - parse_tracklist.sh
#   - _json_get.sh
#   - video_metadata.sh
#
# 输出结构（数组）：
# [
#   { "start": <sec>, "end": <sec>, "title": "...", "artist": "..." },
#   ...
# ]
#
# ==============================================================================

# ------- 参数解析 -------
VIDEO_FILE=""
TRACKLIST_FILE=""
SEGMENT_SECS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tracklist)
      TRACKLIST_FILE="$2"
      shift 2
      ;;
    --segment)
      SEGMENT_SECS="$2"
      shift 2
      ;;
    *)
      VIDEO_FILE="$1"
      shift
      ;;
  esac
done

if [[ -z "$VIDEO_FILE" ]]; then
  echo "Error: 必须提供视频文件路径" >&2
  exit 1
fi
if [[ ! -f "$VIDEO_FILE" ]]; then
  echo "Error: 视频文件不存在: $VIDEO_FILE" >&2
  exit 1
fi

if [[ -n "$TRACKLIST_FILE" && ! -f "$TRACKLIST_FILE" ]]; then
  echo "Error: tracklist 文件不存在: $TRACKLIST_FILE" >&2
  exit 1
fi

if [[ -n "$TRACKLIST_FILE" && -n "$SEGMENT_SECS" ]]; then
  echo "Error: --tracklist 与 --segment 不能同时使用" >&2
  exit 1
fi


# ------- 获取视频元信息 -------
META_JSON=$(./video_metadata.sh "$VIDEO_FILE")

# （唯一修改处）一次调用获取三个 key
read -r duration video_title video_artist < <(
  ./_json_get.sh \
    --json "$META_JSON" \
    --key duration \
    --key title \
    --key artist
)

# video_artist = null → 设为 ""
if [[ "$video_artist" == "null" ]] || [[ -z "$video_artist" ]]; then
  video_artist=""
fi


# ==============================================================================
# 模式 1：使用 tracklist
# ==============================================================================
if [[ -n "$TRACKLIST_FILE" ]]; then

  TL_JSON=$(./parse_tracklist.sh "$TRACKLIST_FILE")

  length=$(./_json_get.sh --json "$TL_JSON" --key length)

  plan_entries="[]"

  for ((i=1; i<=length; i++)); do
    entry=$(./_json_get.sh --json "$TL_JSON" --key . --nth "$i")

    raw=$(echo "$entry" | jq -r '.raw')
    if echo "$raw" | grep -qiE 'repeat|replay'; then
      break
    fi

    tstr=$(echo "$entry" | jq -r '.time')
    if [[ "$tstr" == "null" ]]; then
      echo "Error: tracklist 中发现 time=null（无法确定开始时间）" >&2
      exit 1
    fi
    IFS=':' read -r hh mm ss <<< "$tstr"
    start_sec=$((10#$hh*3600 + 10#$mm*60 + 10#$ss))

    if (( i < length )); then
      next=$(./_json_get.sh --json "$TL_JSON" --key . --nth $((i+1)))
      next_t=$(echo "$next" | jq -r '.time')
      IFS=':' read -r nh nm ns <<< "$next_t"
      end_sec=$((10#$nh*3600 + 10#$nm*60 + 10#$ns))
    else
      end_sec=$duration
    fi

    name=$(echo "$entry" | jq -r '.name')
    artists_arr=$(echo "$entry" | jq -r '.artists | join(", ")')
    artist=$(echo "$entry" | jq -r '.artist')

    if [[ -n "$artists_arr" ]]; then
      final_artist="$artists_arr"
    elif [[ "$artist" != "null" && -n "$artist" ]]; then
      final_artist="$artist"
    else
      final_artist="$video_artist"
    fi

    line=$(jq -n \
      --arg start "$start_sec" \
      --arg end "$end_sec" \
      --arg title "$name" \
      --arg artist "$final_artist" \
      '{start: ($start|tonumber), end: ($end|tonumber), title: $title, artist: $artist}')

    plan_entries=$(echo "$plan_entries" | jq --argjson item "$line" '. += [$item]')
  done

  echo "$plan_entries"
  exit 0
fi


# ==============================================================================
# 模式 2：固定时长切割
# ==============================================================================
if [[ -n "$SEGMENT_SECS" ]]; then
  N="$SEGMENT_SECS"

  plan_entries="[]"

  idx=1
  start=0

  while (( $(echo "$start < $duration" | bc -l) )); do
    end=$(echo "$start + $N" | bc -l)
    cmp=$(echo "$end > $duration" | bc -l)
    if (( cmp == 1 )); then
      end=$duration
    fi

    part_title="${video_title} (Part ${idx})"

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
  exit 0
fi


# ==============================================================================
# 模式 3：整段输出
# ==============================================================================
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
