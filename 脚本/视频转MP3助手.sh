#!/usr/bin/env bash
# =============================================================================
# 视频转MP3助手.sh
# -----------------------------------------------------------------------------
# 功能概述
#   一个“批量媒体 → MP3”的编排脚本，用于将视频或音频文件
#   统一转换为 MP3。脚本本身不做实际转码，而是负责：
#     - 列表化输入文件
#     - 生成分段计划
#     - 按分段调用底层转码脚本
#
# 工作模式
#   1) 单文件模式
#      - 输入：单个媒体文件
#      - 行为：
#          a. 调用 media_segment_plan.sh 生成分段计划（JSON 数组）
#          b. 按分段逐一调用 media_to_mp3.sh 输出 MP3
#
#   2) 目录模式
#      - 输入：目录路径
#      - 行为：
#          a. 调用 media_list.sh 列出目录中的媒体文件
#          b. 对每个文件重复“单文件模式”的完整流程
#
# 关于 --type 参数（重要）
#   - --type 是一个“可选透传参数”，仅在用户显式指定时才会传给
#     media_list.sh
#   - 未指定 --type 时：
#       * 本脚本不会向 media_list.sh 传 --type
#       * 实际筛选策略完全由 media_list.sh 的默认行为决定
#   - 指定 --type 时：
#       * 可选值：video | audio | media
#       * 用于限制目录模式下被处理的文件类型
#
# 设计原则
#   - 本脚本不擅自决定“默认类型”，避免与 media_list.sh 的默认策略
#     发生隐性耦合
#   - 所有文件枚举均依赖 media_list.sh 的 stdout：
#       * 要求其输出严格为“一行一个文件路径”
#       * 任何日志或提示信息必须输出到 stderr
#
# 依赖脚本（默认与本脚本位于同一目录）
#   - media_list.sh              （必需：列出媒体文件）
#   - media_segment_plan.sh      （必需：生成分段计划）
#   - media_to_mp3.sh            （必需：执行实际转码）
#   - media_find_tracklist.sh    （可选：自动查找 tracklist）
#   - video_metadata.sh          （可选：自动提取来源 URL 作为 comment）
#
# 用法
#   视频转MP3助手.sh <文件或目录>
#     [--type video|audio|media]   # 仅目录模式生效
#     [--tracklist FILE]
#     [--segment N]
#     [--out DIR]
#     [--artist A]
#     [--album ALB]
#     [--year Y]
#     [--genre G]
#     [--comment C]
#     [--reencode]
#     [--force]
# =============================================================================


set -Eeo pipefail

IFS=$'\n\t'

# -----------------------------------------------------------------------------
# 基础：路径与依赖检查
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MEDIA_LIST="$SCRIPT_DIR/media_list.sh"
MEDIA_SEGMENT_PLAN="$SCRIPT_DIR/media_segment_plan.sh"
MEDIA_TO_MP3="$SCRIPT_DIR/media_to_mp3.sh"

# 可选依赖
MEDIA_FIND_TRACKLIST="$SCRIPT_DIR/media_find_tracklist.sh"
VIDEO_METADATA="$SCRIPT_DIR/video_metadata.sh"

need_exec() {
  local p="$1" name="$2"
  if [ ! -x "$p" ]; then
    echo "错误：找不到可执行的 $name（期望在同目录：$p）" >&2
    exit 1
  fi
}

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "错误：缺少依赖命令：$cmd" >&2
    exit 1
  fi
}

usage() {
  cat <<'EOF'
用法：
  media2mp3.sh <文件或目录>
    [--type video|audio|media]
    [--tracklist FILE]
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

need_cmd "jq"
need_exec "$MEDIA_LIST"         "media_list.sh"
need_exec "$MEDIA_SEGMENT_PLAN" "media_segment_plan.sh"
need_exec "$MEDIA_TO_MP3"       "media_to_mp3.sh"

# 可选脚本：不存在则降级
if [ ! -x "$MEDIA_FIND_TRACKLIST" ]; then
  MEDIA_FIND_TRACKLIST=""
fi
if [ ! -x "$VIDEO_METADATA" ]; then
  VIDEO_METADATA=""
fi

# -----------------------------------------------------------------------------
# build_cmd_*（模式 B：local -n）
# -----------------------------------------------------------------------------
build_cmd_media_list() {
  local -n _out="$1"
  local dir="$2"
  local type="${3:-}"

  _out=( "$MEDIA_LIST" "$dir" )

  if [ -n "$type" ]; then
    _out+=( --type "$type" )
  fi
}


build_cmd_media_find_tracklist() {
  local -n _out="$1"
  local src="$2"
  _out=( "$MEDIA_FIND_TRACKLIST" "$src" )
}

build_cmd_video_metadata() {
  local -n _out="$1"
  local src="$2"
  _out=( "$VIDEO_METADATA" "$src" )
}

build_cmd_media_segment_plan() {
  local -n _out="$1"
  local src="$2"
  local tracklist="$3"   # 允许为空
  local segment="$4"     # 允许为 0 或空

  _out=( "$MEDIA_SEGMENT_PLAN" "$src" )

  # --tracklist 与 --segment 完全独立：有就加，没有就不加
  if [ -n "$tracklist" ]; then
    _out+=( --tracklist "$tracklist" )
  fi

  if [ -n "${segment:-}" ] && [ "${segment:-0}" -gt 0 ]; then
    _out+=( --segment "$segment" )
  fi
}

build_cmd_media_to_mp3() {
  local -n _out="$1"; shift

  local src="${1:?}"; shift
  local start="${1:?}"; shift
  local end="${1:?}"; shift

  # 下面这些都是“可选值”，没传就默认为空/0
  local title="${1-}"; shift || true
  local artist="${1-}"; shift || true
  local album="${1-}"; shift || true
  local year="${1-}"; shift || true
  local genre="${1-}"; shift || true
  local comment="${1-}"; shift || true
  local out_dir="${1-}"; shift || true
  local reencode="${1-0}"; shift || true
  local force="${1-0}"; shift || true

  _out=( "$MEDIA_TO_MP3" "$src" --start "$start" --end "$end" --quiet )

  if [ -n "$title" ]; then
    _out+=( --title "$title" )
  fi
  if [ -n "$artist" ]; then
    _out+=( --artist "$artist" )
  fi
  if [ -n "$album" ]; then
    _out+=( --album "$album" )
  fi
  if [ -n "$year" ]; then
    _out+=( --year "$year" )
  fi
  if [ -n "$genre" ]; then
    _out+=( --genre "$genre" )
  fi
  if [ -n "$comment" ]; then
    _out+=( --comment "$comment" )
  fi
  if [ -n "$out_dir" ]; then
    _out+=( --out "$out_dir" )
  fi

  # 避免 set -e 下的 “[ ... ] && ...” 触发提前退出；同时用字符串比较更稳
  if [ "${reencode:-0}" = "1" ]; then
    _out+=( --reencode )
  fi
  if [ "${force:-0}" = "1" ]; then
    _out+=( --force )
  fi
}


# -----------------------------------------------------------------------------
# 参数解析
# -----------------------------------------------------------------------------
[ $# -ge 1 ] || { usage; exit 1; }

TARGET=""
TYPE=""              # 默认不指定：不传 --type，让 media_list.sh 自己决定默认策略
TYPE_SPECIFIED=0     # 用户是否显式传了 --type

SEGMENT_SEC=0
TRACKLIST_FILE=""

OUT_DIR_OVERRIDE=""
ARTIST_PARAM=""
ALBUM_PARAM=""
YEAR_PARAM=""
GENRE_PARAM=""
COMMENT_PARAM=""
REENCODE=0
FORCE=0

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
    --tracklist)
      shift || true
      TRACKLIST_FILE="${1:-}"
      if [ -z "$TRACKLIST_FILE" ]; then
        echo "错误：--tracklist 需要提供文件路径" >&2
        exit 1
      fi
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

# 仅做存在性校验：tracklist 如果传了就必须存在；不再与 segment 互斥
if [ -n "$TRACKLIST_FILE" ] && [ ! -f "$TRACKLIST_FILE" ]; then
  echo "错误：tracklist 文件不存在：$TRACKLIST_FILE" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# 小工具：打印命令（调试用，默认不启用）
# -----------------------------------------------------------------------------
# print_cmd() { printf 'CMD: %q ' "$@"; echo; }

# -----------------------------------------------------------------------------
# 单文件处理
# -----------------------------------------------------------------------------
resolve_tracklist_for_src() {
  local src="$1"

  # 1) 若用户显式传 --tracklist，则优先使用它
  if [ -n "$TRACKLIST_FILE" ]; then
    printf '%s\n' "$TRACKLIST_FILE"
    return 0
  fi

  # 2) 否则尝试自动查找（若脚本存在）
  if [ -n "$MEDIA_FIND_TRACKLIST" ]; then
    local cmd=()
    build_cmd_media_find_tracklist cmd "$src"
    local found=""
    set +e
    found="$("${cmd[@]}" 2>/dev/null)"
    set -e
    # 上层约定：找不到返回空字符串
    printf '%s\n' "${found:-}"
    return 0
  fi

  # 3) 没有查找脚本则返回空
  printf '%s\n' ""
}

resolve_auto_comment_for_src() {
  local src="$1"

  # 若用户显式传 --comment，则完全不自动推断
  if [ -n "$COMMENT_PARAM" ]; then
    printf '%s\n' ""
    return 0
  fi

  # 若 video_metadata.sh 不存在，则无法自动推断
  if [ -z "$VIDEO_METADATA" ]; then
    printf '%s\n' ""
    return 0
  fi

  local cmd=()
  build_cmd_video_metadata cmd "$src"

  local meta_json=""
  set +e
  meta_json="$("${cmd[@]}" 2>/dev/null)"
  set -e

  if [ -z "$meta_json" ]; then
    printf '%s\n' ""
    return 0
  fi

  # 你已要求：缺失字段返回空字符串，而不是 null
  local url=""
  url="$(printf '%s' "$meta_json" | jq -r '.url' 2>/dev/null || true)"

  printf '%s\n' "${url:-}"
}

process_one_media() {
  local src="$1"

  if [ ! -f "$src" ]; then
    echo "警告：跳过非文件路径：$src" >&2
    return 0
  fi

  # 自动 comment（来自 video_metadata.url）
  local auto_comment=""
  auto_comment="$(resolve_auto_comment_for_src "$src")"
  if [ -n "$auto_comment" ]; then
    echo "  自动识别来源URL：$auto_comment"
  fi

  # tracklist（显式优先，否则自动找；找不到则空）
  local tracklist_eff=""
  tracklist_eff="$(resolve_tracklist_for_src "$src")"

  # 构造 media_segment_plan.sh 命令（tracklist/segment 有就传，没有就不传）
  local plan_cmd=()
  build_cmd_media_segment_plan plan_cmd "$src" "$tracklist_eff" "$SEGMENT_SEC"

printf '    CMD:'; printf ' %q' "${plan_cmd[@]}"; echo

  local plan_json=""
  if ! plan_json="$("${plan_cmd[@]}")"; then
    echo "  生成分段计划失败，跳过该文件" >&2
    return 0
  fi

  # 基础校验：必须是数组
  local plan_type
  plan_type="$(printf '%s' "$plan_json" | jq -r 'type' 2>/dev/null || true)"
  if [ "$plan_type" != "array" ]; then
    echo "  分段计划不是 JSON 数组，跳过（type=$plan_type）" >&2
    return 0
  fi

  local total_seg
  total_seg="$(printf '%s' "$plan_json" | jq -r 'length' 2>/dev/null || echo 0)"
  if [ "${total_seg:-0}" -le 0 ]; then
    echo "  无有效分段，跳过"
    return 0
  fi

  local idx
  for ((idx=0; idx<total_seg; idx++)); do
    local seg
    seg="$(printf '%s' "$plan_json" | jq -c ".[$idx]")"

    # seg 内字段：start/end/title/artist（目前 media_segment_plan 已输出 string/number；缺失用 ""）
    local start end title artist
    start="$(printf '%s' "$seg" | jq -r '.start' 2>/dev/null || echo 0)"
    end="$(printf '%s' "$seg" | jq -r '.end' 2>/dev/null || echo 0)"
    title="$(printf '%s' "$seg" | jq -r '.title' 2>/dev/null || echo "")"
    artist="$(printf '%s' "$seg" | jq -r '.artist' 2>/dev/null || echo "")"

    local seg_no=$((idx + 1))
    echo "  > seg ${seg_no}/${total_seg} ${start}s → ${end}s"

    # artist 优先级：seg.artist > 全局 --artist
    local artist_eff="$ARTIST_PARAM"
    [ -n "$artist" ] && artist_eff="$artist"

    # comment 优先级：全局 --comment > auto_comment(来源URL) > 空
    local comment_eff="$COMMENT_PARAM"
    if [ -z "$comment_eff" ] && [ -n "$auto_comment" ]; then
      comment_eff="$auto_comment"
    fi

    local mp3_cmd=()
    build_cmd_media_to_mp3 \
      mp3_cmd \
      "$src" \
      "$start" \
      "$end" \
      "$title" \
      "$artist_eff" \
      "$ALBUM_PARAM" \
      "$YEAR_PARAM" \
      "$GENRE_PARAM" \
      "$comment_eff" \
      "$OUT_DIR_OVERRIDE" \
      "$REENCODE" \
      "$FORCE"

    if "${mp3_cmd[@]}"; then
      echo "    → OK"
    else
      echo "    → 失败（详见上方错误信息）"
    fi
  done
}

# -----------------------------------------------------------------------------
# 目录处理
# -----------------------------------------------------------------------------
process_dir() {
  local dir="$1"
  echo "扫描目录：$dir"
  if [ "${TYPE_SPECIFIED:-0}" -eq 1 ]; then
    echo "类型过滤：$TYPE"
  else
    echo "类型过滤：<未指定>（使用 media_list.sh 的默认策略）"
  fi


  local list_cmd=()
  build_cmd_media_list list_cmd "$dir" "$TYPE"

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
    process_one_media "$media"
  done
}

# -----------------------------------------------------------------------------
# 主入口
# -----------------------------------------------------------------------------
if [ -f "$TARGET" ]; then
  echo "1/1 $TARGET"
  process_one_media "$TARGET"
elif [ -d "$TARGET" ]; then
  process_dir "$TARGET"
else
  echo "错误：不支持的路径类型：$TARGET" >&2
  exit 1
fi
