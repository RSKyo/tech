#!/usr/bin/env bash
# =============================================================================
# media_to_mp3.sh — 单文件：媒体转 MP3（整段 / 指定时间段），总是重编码
# -----------------------------------------------------------------------------
# 用法：
#   media_to_mp3.sh <媒体文件>
#       [--out DIR]
#       [--start T]
#       [--end T]
#       [--title TITLE]
#       [--artist ARTIST]
#       [--album ALBUM]
#       [--year YEAR]
#       [--genre GENRE]
#       [--comment COMMENT]
#       [--force]
#
# 说明：
#   - 若未提供 --start / --end，则整个媒体转为 MP3。
#   - 若同时提供 --start 与 --end，则仅导出该时间段。
#   - --start / --end 支持：
#       * 纯秒数：30, 120
#       * 时间码：mm:ss 或 hh:mm:ss
#   - 一律重编码为 MP3（libmp3lame），不再区分源是否为 mp3。
# =============================================================================

# 不用 -u，只保留 e/E/pipefail 避免脚本半吊子执行
set -Eeo pipefail
IFS=$'\n\t'

# ---------- 依赖 ----------
need() { command -v "$1" >/dev/null 2>&1 || { echo "错误：需要 $1，请先安装"; exit 1; }; }
need ffmpeg

# ---------- 全局选项 ----------
OUT_DIR_OVERRIDE=""
START_STR=""
END_STR=""
TITLE_PARAM=""
ARTIST_PARAM=""
ALBUM_PARAM=""
YEAR_PARAM=""
GENRE_PARAM=""
COMMENT_PARAM=""
FORCE=0
QUIET=0

usage() {
  cat <<'EOF'
用法：
  media_to_mp3.sh <媒体文件>
    [--out DIR]
    [--start T]
    [--end T]
    [--title TITLE]
    [--artist ARTIST]
    [--album ALBUM]
    [--year YEAR]
    [--genre GENRE]
    [--comment COMMENT]
    [--force]

说明：
  - 未提供 --start / --end：整段转 MP3。
  - 同时提供 --start 与 --end：只转该时间区间。
  - 时间 T 支持：
      * 纯秒数：30, 120
      * 时间码：mm:ss 或 hh:mm:ss
EOF
}

[ $# -ge 1 ] || { usage; exit 1; }

SRC="$1"; shift || true

while [ $# -gt 0 ]; do
  case "$1" in
    --out)       shift; OUT_DIR_OVERRIDE="${1:-}" ;;
    --start)     shift; START_STR="${1:-}" ;;
    --end)       shift; END_STR="${1:-}" ;;
    --title)     shift; TITLE_PARAM="${1:-}" ;;
    --artist)    shift; ARTIST_PARAM="${1:-}" ;;
    --album)     shift; ALBUM_PARAM="${1:-}" ;;
    --year)      shift; YEAR_PARAM="${1:-}" ;;
    --genre)     shift; GENRE_PARAM="${1:-}" ;;
    --comment)   shift; COMMENT_PARAM="${1:-}" ;;
    --reencode)  ;;  # 为兼容旧调用接口，忽略此参数
    --force)     FORCE=1 ;;
    --quiet)     QUIET=1 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "未知参数：$1"; exit 1 ;;
  esac
  shift || true
done

if [ ! -f "$SRC" ]; then
  echo "错误：找不到文件：$SRC"
  exit 1
fi

# ---------- 工具函数 ----------

sanitize() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  s="${s//\//-}"; s="${s//\\/-}"; s="${s//:/-}"
  s="${s//\*/-}"; s="${s//\?/-}"; s="${s//\"/-}"
  s="${s//</(}"; s="${s//>/)}"; s="${s//|/-}"
  echo "$s"
}

to_seconds() {
  local t="$1"
  t="${t/,/.}"
  awk -F: '{
    if (NF==3) {h=$1; m=$2; s=$3}
    else if (NF==2) {h=0; m=$1; s=$2}
    else {h=0; m=0; s=$1}
    printf("%d", h*3600 + m*60 + s + 0.5)
  }' <<<"$t"
}

resolve_out_dir() {
  local src="$1"
  local src_dir out
  src_dir="$(cd "$(dirname "$src")" && pwd)"
  if [ -n "$OUT_DIR_OVERRIDE" ]; then
    if [[ "$OUT_DIR_OVERRIDE" = /* ]]; then
      out="$OUT_DIR_OVERRIDE"
    else
      out="$src_dir/$OUT_DIR_OVERRIDE"
    fi
  else
    out="$src_dir"
  fi
  mkdir -p "$out"
  printf '%s' "$out"
}

# ---------- 时间参数解析 ----------
START_SEC=""
END_SEC=""
WHOLE=1

if [ -n "$START_STR" ] || [ -n "$END_STR" ]; then
  if [ -z "$START_STR" ] || [ -z "$END_STR" ]; then
    echo "错误：--start 与 --end 必须同时提供" >&2
    exit 1
  fi

  START_SEC="$(to_seconds "$START_STR")"
  END_SEC="$(to_seconds "$END_STR")"

  if ! [[ "$START_SEC" =~ ^[0-9]+$ ]]; then
    echo "错误：无法解析开始时间：$START_STR" >&2
    exit 1
  fi
  if ! [[ "$END_SEC" =~ ^[0-9]+$ ]]; then
    echo "错误：无法解析结束时间：$END_STR" >&2
    exit 1
  fi
  if [ "$END_SEC" -le "$START_SEC" ]; then
    echo "错误：结束时间必须大于开始时间" >&2
    exit 1
  fi

  WHOLE=0
fi

# ---------- 输出路径和文件名 ----------
OUT_DIR="$(resolve_out_dir "$SRC")"
SRC_NAME="${SRC##*/}"
SRC_BASENAME="${SRC_NAME%.*}"

if [ -n "$TITLE_PARAM" ]; then
  base_name="$(sanitize "$TITLE_PARAM")"
else
  base_name="$(sanitize "$SRC_BASENAME")"
  if [ "$WHOLE" -eq 0 ]; then
    base_name="${base_name}_$(printf '%d-%d' "$START_SEC" "$END_SEC")"
  fi
fi

OUT_PATH="$OUT_DIR/${base_name}.mp3"

if [ -e "$OUT_PATH" ] && [ "$FORCE" -eq 0 ]; then
  echo "目标已存在，跳过（使用 --force 可覆盖）：$OUT_PATH"
  exit 0
fi

if [ "$FORCE" -eq 1 ] && [ -e "$OUT_PATH" ]; then
  rm -f "$OUT_PATH"
fi

# ---------- 组装 ffmpeg 参数（统一重编码） ----------
seek_opts=()
meta_opts=()

if [ "$WHOLE" -eq 1 ]; then
  seek_opts=(-i "$SRC")
else
  DUR=$(( END_SEC - START_SEC ))
  # -i 后 -ss -t，保证精确度
  seek_opts=(-i "$SRC" -ss "$START_SEC" -t "$DUR")
fi

meta_opts=(-id3v2_version 3 -write_id3v2 1)
if [ -n "$TITLE_PARAM" ]; then
  meta_opts+=(-metadata "title=$TITLE_PARAM")
else
  meta_opts+=(-metadata "title=$base_name")
fi
if [ -n "$ARTIST_PARAM" ]; then
  meta_opts+=(-metadata "artist=$ARTIST_PARAM" -metadata "album_artist=$ARTIST_PARAM")
fi
[ -n "$ALBUM_PARAM" ]   && meta_opts+=(-metadata "album=$ALBUM_PARAM")
[ -n "$YEAR_PARAM" ]    && meta_opts+=(-metadata "date=$YEAR_PARAM" -metadata "year=$YEAR_PARAM")
[ -n "$GENRE_PARAM" ]   && meta_opts+=(-metadata "genre=$GENRE_PARAM")
[ -n "$COMMENT_PARAM" ] && meta_opts+=(-metadata "comment=$COMMENT_PARAM")

# ---------- 执行 ----------
if [ "$QUIET" -eq 0 ]; then
  echo "源文件：$SRC"
  if [ "$WHOLE" -eq 1 ]; then
    echo "模式：整段转 MP3"
  else
    echo "模式：截取区间 ${START_SEC}s → ${END_SEC}s"
  fi
  echo "输出：$OUT_PATH"
  echo
fi


if ffmpeg -nostdin -hide_banner -loglevel error -y \
     "${seek_opts[@]}" -map_metadata -1 -vn -map 0:a:0 \
     -c:a libmp3lame -q:a 2 \
     "${meta_opts[@]}" \
     "$OUT_PATH"
then
  if [ "$QUIET" -eq 0 ]; then
    echo "完成：$OUT_PATH"
  fi
else
  echo "错误：ffmpeg 转换失败" >&2
  exit 1
fi
