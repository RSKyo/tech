#!/usr/bin/env bash
# =============================================================================
# segment_plan.sh — 媒体分段规划器：接收一个媒体文件（音频/视频），输出分段列表
# -----------------------------------------------------------------------------
# 用法：
#   segment_plan.sh <媒体文件> [--segment N]
#
# 优先级：
#   1) 若存在清单文件 <媒体文件>.split.txt → 按清单分段；
#   2) 否则若提供 --segment N(>0) → 按 N 秒一段拆分；
#   3) 否则 → 将整个媒体视为一个段。
#
# 清单文件命名：
#   a.mp4   → a.mp4.split.txt
#   a.flac  → a.flac.split.txt
#   a.m4a   → a.m4a.split.txt
#
# 清单格式（沿用原“视频转MP3助手.sh”的规则）：
#   - UTF-8 文本；
#   - 支持 mm:ss 或 hh:mm:ss(.ms)；
#   - 行格式示例：
#       00:00 标题 / 艺术家
#       03:11 - 标题
#   - 以 # 开头的行为注释；
#   - 当标题中包含 Repeat 或 Replay 时，视为终止标记，之后的行忽略。
#
# 输出格式（stdout）：
#   每行一个分段，字段以 TAB 分隔：
#     start_sec<TAB>end_sec<TAB>title<TAB>artist
#
# 依赖：
#   ffprobe（通常随 ffmpeg 一起安装）
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# ---------- 依赖 ----------
need() { command -v "$1" >/dev/null 2>&1 || { echo "错误：需要 $1，请先安装"; exit 1; }; }
need ffprobe

# ---------- 参数解析 ----------
usage() {
  cat <<'EOF'
用法：
  segment_plan.sh <媒体文件> [--segment N]

说明：
  优先级：
    1) 若存在清单文件 <媒体文件>.split.txt → 按清单分段；
    2) 否则若提供 --segment N(>0) → 按 N 秒一段拆分；
    3) 否则 → 将整个媒体视为一个段。

输出：
  每行一个分段：
    start_sec<TAB>end_sec<TAB>title<TAB>artist
EOF
}

[ $# -ge 1 ] || { usage; exit 1; }

SRC=""
SEGMENT_SEC=0

while [ $# -gt 0 ]; do
  case "$1" in
    --segment)
      shift || true
      [[ "${1:-}" =~ ^[0-9]+$ && "$1" -gt 0 ]] || { echo "错误：--segment 需 >0 的整数秒"; exit 1; }
      SEGMENT_SEC="$1"
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
      if [ -z "$SRC" ]; then
        SRC="$1"
      else
        echo "错误：仅支持单个媒体文件参数，多余的：$1" >&2
        exit 1
      fi
      ;;
  esac
  shift || true
done

[ -n "$SRC" ] || { echo "错误：未提供媒体文件"; exit 1; }
[ -f "$SRC" ] || { echo "错误：找不到文件：$SRC"; exit 1; }

# ---------- 工具函数 ----------

# 总时长（秒，四舍五入为整数秒）
duration_seconds() {
  # 如果不是合法媒体或没有 duration，会返回空
  ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$1" 2>/dev/null \
    | awk 'NF {printf "%.0f\n",$1+0}' 2>/dev/null
}

# 时间字符串转秒数：支持 00:00(.ms) / 00:00:00(.ms)
to_seconds() {
  local t="$1"
  t="${t/,/.}"
  awk -F: '{
    if (NF==3) {h=$1; m=$2; s=$3}
    else if (NF==2) {h=0; m=$1; s=$2}
    else {h=0; m=0; s=0}
    printf("%d", h*3600 + m*60 + s + 0.5)
  }' <<<"$t"
}

# 去除 UTF-8 BOM + CRLF → LF
normalize_cue() {
  local in="$1" out tmp
  out="$(mktemp "${TMPDIR:-/tmp}/segcue.XXXXXX")"
  # 去 BOM
  if LC_ALL=C grep -q $'^\xEF\xBB\xBF' "$in"; then
    tail -c +4 "$in" > "$out"
  else
    cat "$in" > "$out"
  fi
  # CRLF → LF
  if LC_ALL=C grep -q $'\r' "$out"; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/segcue.XXXXXX")"
    tr -d '\r' < "$out" > "$tmp"
    mv "$tmp" "$out"
  fi
  printf '%s\n' "$out"
}

# ---------- 构造分段列表：三种来源统一输出 ----------
# 统一约定：输出到 stdout，每行：
#   start_sec<TAB>end_sec<TAB>title<TAB>artist

# 1) 整段：只有一条
build_segments_whole() {
  local src="$1"
  local dur base title
  dur="$(duration_seconds "$src")"
  [[ "$dur" =~ ^[0-9]+$ ]] || {
    echo "错误：无法获取时长（可能不是有效的音频/视频文件）：$src" >&2
    return 1
  }

  base="${src##*/}"
  title="${base%.*}"

  printf '%s\t%s\t%s\t%s\n' 0 "$dur" "$title" ""
}

# 2) 固定时长切分
build_segments_fixed() {
  local src="$1" seg="$2"
  local total base start end idx=0
  total="$(duration_seconds "$src")"
  [[ "$total" =~ ^[0-9]+$ && "$total" -gt 0 ]] || {
    echo "错误：无法获取时长（可能不是有效的音频/视频文件）：$src" >&2
    return 1
  }

  base="${src##*/}"; base="${base%.*}"

  start=0
  while [ "$start" -lt "$total" ]; do
    end=$(( start + seg ))
    [ "$end" -gt "$total" ] && end="$total"
    idx=$((idx+1))
    # 标题先用简单命名：原文件名_partXXX
    printf '%s\t%s\t%s\t%s\n' \
      "$start" "$end" "${base}_part$(printf '%03d' "$idx")" ""
    start="$end"
  done
}

# 3) 按清单切分：<媒体文件>.split.txt
build_segments_cue() {
  local src="$1" cue="$2"

  local dur_total
  dur_total="$(duration_seconds "$src")"
  [[ "$dur_total" =~ ^[0-9]+$ ]] || {
    echo "错误：无法获取时长（可能不是有效的音频/视频文件）：$src" >&2
    return 1
  }

  local cue_norm
  cue_norm="$(normalize_cue "$cue")"

  local starts=() titles=() artists=()
  local REPEAT_AT=""
  local line line_no=0

  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no+1))
    [[ -z "${line// }" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    local ts rest title artist line_norm
    line_norm="$(printf '%s' "$line" | sed $'s/\xef\xbc\x9a/:/g; s/\xc2\xa0/ /g; s/\xe3\x80\x80/ /g')"
    line_norm="${line_norm//$'\t'/ }"
    line_norm="${line_norm#"${line_norm%%[![:space:]]*}"}"
    line_norm="${line_norm%"${line_norm##*[![:space:]]}"}"

    if [[ "$line_norm" =~ ^([0-9]{1,2}:[0-9]{2}(:[0-9]{2})?([.,][0-9]{1,3})?)[[:space:]]+(.+)$ ]]; then
      ts="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[4]}"
    else
      echo "错误：清单格式不符（第 $line_no 行）：$line" >&2
      echo "示例：03:11 标题 / 艺术家   或   03:11 - 标题 / 艺术家" >&2
      rm -f "$cue_norm"
      return 1
    fi

    # 可选连字符 " - "
    if [[ "$rest" =~ ^[-–—][[:space:]]*(.+)$ ]]; then
      rest="${BASH_REMATCH[1]}"
    fi

    title="$rest"; artist=""
    if [[ "$rest" == *" / "* ]]; then
      title="${rest%%" / "*}"
      artist="${rest#*" / "}"
    fi

    local ts_sec title_lc
    ts_sec="$(to_seconds "$ts")"
    title_lc="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')"

    # “Repeat/Replay” 作为终止点
    if [[ "$title_lc" == *repeat* || "$title_lc" == *replay* ]]; then
      REPEAT_AT="$ts_sec"
      break
    fi

    starts+=( "$ts_sec" )
    titles+=( "$title" )
    artists+=( "$artist" )
  done < "$cue_norm"

  rm -f "$cue_norm"

  local N="${#starts[@]}"
  [ "$N" -gt 0 ] || {
    echo "错误：清单为空或仅有终止标记/注释：$cue" >&2
    return 1
  }

  local end_total="${REPEAT_AT:-$dur_total}"

  local i
  for ((i=0;i<N;i++)); do
    local s e t a
    s="${starts[$i]}"

    if [ "$i" -lt $((N-1)) ]; then
      e="${starts[$((i+1))]}"
      [ "$e" -gt "$end_total" ] && e="$end_total"
    else
      e="$end_total"
    fi

    [ "$e" -le "$s" ] && continue

    t="${titles[$i]}"
    a="${artists[$i]}"

    printf '%s\t%s\t%s\t%s\n' "$s" "$e" "$t" "$a"
  done
}

# ---------- 主逻辑：按优先级选择 ----------
main() {
  local cue="${SRC}.split.txt"

  if [ -f "$cue" ]; then
    # 情况 1：有清单文件
    build_segments_cue "$SRC" "$cue"
  elif [ "$SEGMENT_SEC" -gt 0 ]; then
    # 情况 2：有 --segment
    build_segments_fixed "$SRC" "$SEGMENT_SEC"
  else
    # 情况 3：整段
    build_segments_whole "$SRC"
  fi
}

main
