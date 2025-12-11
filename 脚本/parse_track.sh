#!/usr/bin/env bash
# --------------------------------------------
# parse_track.sh
# --------------------------------------------
# 用途：
#   - 接收一行（或两行）tracklist 文本：
#       1) 仅一行：  "00:00 Airshade - Eternal Sleep"
#       2) 两行：    "00:00 Airshade - Eternal Sleep\n/ some-slug-or-url"
#   - 第一行是曲目信息，第二行若以 "/" 开头，则视为 slug（例如源链接、路径）
#
#   - 自动根据 track_types.json 中定义的正则匹配类型（g / c / b / a / z 等）
#   - 解析出时间、曲目号、艺术家、标题、副标题、专辑等字段
#   - 输出统一 JSON，便于下一步 shell / jq / JS 处理
#
# 依赖：
#   - jq
#   - track_types.json （与本脚本位于同一目录）
#
# 使用示例：
#   ./parse_track.sh "00:00 Airshade - Eternal Sleep"
#   ./parse_track.sh $'00:00 Airshade - Eternal Sleep\n/ airshade-eternal-sleep'
#
# 输出 JSON 示例（字段视类型而定）：
#   {
#     "type": "a",
#     "name": "single_artist_title",
#     "raw": "00:00 Airshade - Eternal Sleep",
#     "time": "00:00",
#     "track_no": null,
#     "artist": "Airshade",
#     "artists": ["Airshade"],
#     "title": "Eternal Sleep",
#     "subtitle": null,
#     "album": null,
#     "slug": "airshade-eternal-sleep"
#   }
# --------------------------------------------

set -euo pipefail

# ---------- check dependency ----------
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 1
fi

# ---------- locate track_types.json ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TYPES_FILE="$SCRIPT_DIR/track_types.json"

if [[ ! -f "$TYPES_FILE" ]]; then
  echo "Error: track_types.json not found in $SCRIPT_DIR" >&2
  exit 1
fi

# ---------- input ----------
if [ $# -lt 1 ]; then
  echo "Usage: $0 \"track line\"  (can contain optional second line starting with / as slug)" >&2
  exit 1
fi

INPUT="$1"
LINE="$INPUT"
SLUG='null'   # jq literal

# ---------- two-line (slug) handling ----------
# 如果 INPUT 中包含换行：
#   第一行视为 track line
#   第二行若以 "/" 开头，则视为 slug
if [[ "$INPUT" == *$'\n'* ]]; then
  first="${INPUT%%$'\n'*}"
  rest="${INPUT#*$'\n'}"

  # 检测 slug 行，如："/ some-slug" 或 "   /slug"
  if [[ "$rest" =~ ^[[:space:]]*/[[:space:]]*(.+)$ ]]; then
    slug_value="${BASH_REMATCH[1]}"
    # 用 jq 封装为 JSON 字符串
    SLUG=$(jq -n --arg v "$slug_value" '$v')
  fi

  LINE="$first"
fi

# 去掉首尾空白
LINE="$(printf '%s' "$LINE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

# ---------- helper: build unknown JSON ----------
emit_unknown() {
  local raw="$1"
  jq -n --arg raw "$raw" --argjson slug "$SLUG" '{
    type: "unknown",
    name: "unknown",
    raw: $raw,
    time: null,
    track_no: null,
    artist: null,
    artists: [],
    title: null,
    subtitle: null,
    album: null,
    slug: $slug
  }'
}

# ---------- detect type ----------
MATCH=""

# 遍历 track_types.json 中的各个类型，按顺序匹配
MATCH="$(
  jq -c '.[]' "$TYPES_FILE" | while read -r obj; do
    regex=$(echo "$obj" | jq -r '.regex')
    if [[ "$LINE" =~ $regex ]]; then
      echo "$obj"
      break
    fi
  done || true
)"

# 未匹配到任何类型 → 输出 unknown
if [[ -z "$MATCH" ]]; then
  emit_unknown "$LINE"
  exit 0
fi

# 读取匹配到的类型 id / name / regex
id=$(echo "$MATCH" | jq -r '.id')
name=$(echo "$MATCH" | jq -r '.name')
regex=$(echo "$MATCH" | jq -r '.regex')

# 再次应用 regex，确保 BASH_REMATCH 中有捕获内容
if ! [[ "$LINE" =~ $regex ]]; then
  # 正常情况下这里不应该走到，保险兜底
  emit_unknown "$LINE"
  exit 0
fi

# ---------- helper: 构造 artists 数组 ----------
build_artists_json() {
  local artist="$1"
  if [[ -z "$artist" ]]; then
    echo '[]'
    return
  fi

  # 使用 , 和 & 拆分多个艺术家，并去空白
  printf '%s\n' "$artist" \
    | tr '&,' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | sed '/^$/d' \
    | jq -R . \
    | jq -s .
}

# ---------- parse by type id ----------
case "$id" in
  g)
    # album_track
    # regex: .*([hh:mm:ss]) + track_no + title (+ optional subtitle)
    time="${BASH_REMATCH[1]}"
    track_no="${BASH_REMATCH[2]}"
    title="$(echo "${BASH_REMATCH[3]}" | sed 's/[[:space:]]*$//')"
    subtitle="${BASH_REMATCH[5]:-}"

    jq -n \
      --arg type "$id" \
      --arg name "$name" \
      --arg raw "$LINE" \
      --arg time "$time" \
      --arg track_no "$track_no" \
      --arg title "$title" \
      --arg subtitle "$subtitle" \
      --argjson slug "$SLUG" \
      '{
        type: $type,
        name: $name,
        raw: $raw,
        time: $time,
        track_no: $track_no,
        artist: null,
        artists: [],
        title: $title,
        subtitle: (
          if ($subtitle | length) > 0
          then $subtitle
          else null
          end
        ),
        album: null,
        slug: $slug
      }'
    ;;

  c)
    # artist_project_title
    # time artist - album - title
    time="${BASH_REMATCH[1]}"
    artist="${BASH_REMATCH[2]}"
    album="${BASH_REMATCH[3]}"
    title="${BASH_REMATCH[4]}"

    artists_json=$(build_artists_json "$artist")

    jq -n \
      --arg type "$id" \
      --arg name "$name" \
      --arg raw "$LINE" \
      --arg time "$time" \
      --arg artist "$artist" \
      --arg album "$album" \
      --arg title "$title" \
      --argjson artists "$artists_json" \
      --argjson slug "$SLUG" \
      '{
        type: $type,
        name: $name,
        raw: $raw,
        time: $time,
        track_no: null,
        artist: $artist,
        artists: $artists,
        title: $title,
        subtitle: null,
        album: $album,
        slug: $slug
      }'
    ;;

  b)
    # multi_artist_title
    # time artist_list - title
    time="${BASH_REMATCH[1]}"
    artist="${BASH_REMATCH[2]}"
    title="${BASH_REMATCH[3]}"

    artists_json=$(build_artists_json "$artist")

    jq -n \
      --arg type "$id" \
      --arg name "$name" \
      --arg raw "$LINE" \
      --arg time "$time" \
      --arg artist "$artist" \
      --arg title "$title" \
      --argjson artists "$artists_json" \
      --argjson slug "$SLUG" \
      '{
        type: $type,
        name: $name,
        raw: $raw,
        time: $time,
        track_no: null,
        artist: $artist,
        artists: $artists,
        title: $title,
        subtitle: null,
        album: null,
        slug: $slug
      }'
    ;;

  a)
    # single_artist_title
    # time artist - title
    time="${BASH_REMATCH[1]}"
    artist="${BASH_REMATCH[2]}"
    title="${BASH_REMATCH[3]}"

    artists_json=$(build_artists_json "$artist")

    jq -n \
      --arg type "$id" \
      --arg name "$name" \
      --arg raw "$LINE" \
      --arg time "$time" \
      --arg artist "$artist" \
      --arg title "$title" \
      --argjson artists "$artists_json" \
      --argjson slug "$SLUG" \
      '{
        type: $type,
        name: $name,
        raw: $raw,
        time: $time,
        track_no: null,
        artist: $artist,
        artists: $artists,
        title: $title,
        subtitle: null,
        album: null,
        slug: $slug
      }'
    ;;

  z)
    # loose_time_title（兜底：时间 + 内容）
    # 只保证 time，剩下当成 title
    time="${BASH_REMATCH[1]}"
    # 从时间后面截取剩余文本作为 title
    rest="${LINE#*$time}"
    rest="$(echo "$rest" | sed 's/^[[:space:]]*//')"
    title="$rest"

    jq -n \
      --arg type "$id" \
      --arg name "$name" \
      --arg raw "$LINE" \
      --arg time "$time" \
      --arg title "$title" \
      --argjson slug "$SLUG" \
      '{
        type: $type,
        name: $name,
        raw: $raw,
        time: $time,
        track_no: null,
        artist: null,
        artists: [],
        title: $title,
        subtitle: null,
        album: null,
        slug: $slug
      }'
    ;;

  *)
    # 未专门处理的 id → 按 unknown 处理
    emit_unknown "$LINE"
    ;;
esac
