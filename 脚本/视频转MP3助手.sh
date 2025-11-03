#!/usr/bin/env bash
# =============================================================================
# media2mp3.sh — 批量媒体转 MP3（基于 media_list / media_segment_plan / media_to_mp3）
# -----------------------------------------------------------------------------
# 用法：
#   media2mp3.sh <文件或目录>
#       [--type video|audio|media]   # 仅目录时生效，传给 media_list.sh
#       [--segment N]                # 传给 media_segment_plan.sh（清单优先）
#       [--out DIR]                  # 传给 media_to_mp3.sh
#       [--artist A]
#       [--album ALB]
#       [--year Y]
#       [--genre G]
#       [--comment C]
#       [--reencode]                 # 目前 media_to_mp3.sh 可忽略或兼容
#       [--force]
#
# 行为说明：
#   - 如果参数是“文件”：
#       对该媒体调用 media_segment_plan.sh 得到分段列表，
#       然后对每一段调用 media_to_mp3.sh 生成 MP3。
#
#   - 如果参数是“目录”：
#       用 media_list.sh 列出目录下的媒体文件（按 --type 过滤），
#       然后对每个文件重复上述流程。
# =============================================================================

set -Eeo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
用法：
  media2mp3.sh <文件或目录>
    [--type video|audio|media]
    [--segment N]
    [--out DIR]
    [--artist A]
    [--album ALB]
    [--year Y]
    [--genre G]
    [--comment C]
    [--reencode]
    [--force]
EOF
}

[ $# -ge 1 ] || { usage; exit 1; }

TARGET=""
TYPE="media"   # 默认音频 + 视频都处理
SEGMENT_SEC=0

OUT_DIR_OVERRIDE=""
ARTIST_PARAM=""
ALBUM_PARAM=""
YEAR_PARAM=""
GENRE_PARAM=""
COMMENT_PARAM=""
REENCODE=0
FORCE=0

# ---------- 参数解析 ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --type)
      shift || true
      case "${1:-}" in
        video|audio|media) TYPE="$1" ;;
        *) echo "错误：--type 需为 video、audio 或 media" >&2; exit 1 ;;
      esac
      ;;
    --segment)
      shift || true
      if ! [[ "${1:-}" =~ ^[0-9]+$ ]] || [ "${1:-0}" -le 0 ]; then
        echo "错误：--segment 需为 >0 的整数秒" >&2
        exit 1
      fi
      SEGMENT_SEC="$1"
      ;;
    --out)       shift; OUT_DIR_OVERRIDE="${1:-}" ;;
    --artist)    shift; ARTIST_PARAM="${1:-}" ;;
    --album)     shift; ALBUM_PARAM="${1:-}" ;;
    --year)      shift; YEAR_PARAM="${1:-}" ;;
    --genre)     shift; GENRE_PARAM="${1:-}" ;;
    --comment)   shift; COMMENT_PARAM="${1:-}" ;;
    --reencode)  REENCODE=1 ;;
    --force)     FORCE=1 ;;
    -h|--help)   usage; exit 0 ;;
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

# ---------- 定位同目录依赖脚本 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MEDIA_LIST="$SCRIPT_DIR/media_list.sh"
MEDIA_SEGMENT_PLAN="$SCRIPT_DIR/media_segment_plan.sh"
MEDIA_TO_MP3="$SCRIPT_DIR/media_to_mp3.sh"

need_exec() {
  local p="$1" name="$2"
  if [ ! -x "$p" ]; then
    echo "错误：找不到可执行的 $name（期望在同目录：$p）" >&2
    exit 1
  fi
}

need_exec "$MEDIA_LIST"         "media_list.sh"
need_exec "$MEDIA_SEGMENT_PLAN" "media_segment_plan.sh"
need_exec "$MEDIA_TO_MP3"       "media_to_mp3.sh"

# ---------- 单文件处理 ----------
process_one_media() {
  local src="$1"

  if [ ! -f "$src" ]; then
    echo "警告：跳过非文件路径：$src" >&2
    return 0
  fi

  # 构造 media_segment_plan.sh 调用命令
  local plan_cmd=()
  if [ "$SEGMENT_SEC" -gt 0 ]; then
    plan_cmd=( "$MEDIA_SEGMENT_PLAN" "$src" --segment "$SEGMENT_SEC" )
  else
    plan_cmd=( "$MEDIA_SEGMENT_PLAN" "$src" )
  fi

  # 先把所有分段读到数组里，这样就能知道总共有多少段
  mapfile -t segments < <("${plan_cmd[@]}")

  local total_seg="${#segments[@]}"
  if [ "$total_seg" -eq 0 ]; then
    echo "  无有效分段，跳过"
    return 0
  fi

  local idx
  for ((idx=0; idx<total_seg; idx++)); do
    local line="${segments[$idx]}"
    [ -z "${line// }" ] && continue

    local start end title artist
    IFS=$'\t' read -r start end title artist <<< "$line"

    local seg_no=$((idx + 1))
    # 3）seg 行："> seg 当前段/总段 开始s → 结束s"
    echo "  > seg ${seg_no}/${total_seg} ${start}s → ${end}s"

    # 确定这一段的有效 artist：清单里的优先，其次全局 --artist
    local artist_eff="$ARTIST_PARAM"
    if [ -n "$artist" ]; then
      artist_eff="$artist"
    fi

    # 组装 media_to_mp3.sh 命令（使用 --quiet，让下层尽量少说话）
    local cmd=( "$MEDIA_TO_MP3" "$src" --start "$start" --end "$end" --quiet )

    if [ -n "$title" ]; then
      cmd+=( --title "$title" )
    fi
    if [ -n "$artist_eff" ]; then
      cmd+=( --artist "$artist_eff" )
    fi
    if [ -n "$ALBUM_PARAM" ]; then
      cmd+=( --album "$ALBUM_PARAM" )
    fi
    if [ -n "$YEAR_PARAM" ]; then
      cmd+=( --year "$YEAR_PARAM" )
    fi
    if [ -n "$GENRE_PARAM" ]; then
      cmd+=( --genre "$GENRE_PARAM" )
    fi
    if [ -n "$COMMENT_PARAM" ]; then
      cmd+=( --comment "$COMMENT_PARAM" )
    fi
    if [ -n "$OUT_DIR_OVERRIDE" ]; then
      cmd+=( --out "$OUT_DIR_OVERRIDE" )
    fi
    if [ "$REENCODE" -eq 1 ]; then
      cmd+=( --reencode )
    fi
    if [ "$FORCE" -eq 1 ]; then
      cmd+=( --force )
    fi

    if "${cmd[@]}"; then
      echo "    → OK"
    else
      echo "    → 失败（详见上方错误信息）"
    fi
  done
}

# ---------- 目录处理 ----------
process_dir() {
  local dir="$1"
  echo "扫描目录：$dir"
  echo "类型过滤：$TYPE"

  # 先把所有媒体文件读到数组里，这样可以打印 1/4 之类的进度
  mapfile -t media_files < <("$MEDIA_LIST" "$dir" --type "$TYPE")

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
    # 1）文件行： "当前序号/总数 路径"
    echo "$((i + 1))/$total $media"

    process_one_media "$media"
  done
}

# ---------- 主入口 ----------
if [ -f "$TARGET" ]; then
  # 单个媒体文件：就当作“1/1 文件”
  echo "1/1 $TARGET"
  process_one_media "$TARGET"
elif [ -d "$TARGET" ]; then
  process_dir "$TARGET"
else
  echo "错误：不支持的路径类型：$TARGET" >&2
  exit 1
fi
