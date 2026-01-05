#!/usr/bin/env bash
###############################################################################
# Video Screenshot Tool — Cinema Grade (Educational Edition)
#
# PURPOSE
# -------
# 从电影 / 剧集视频中截取「收藏级」单帧画面：
# - SDR 模式：模拟电影播放器（IINA / mpv）的显示结果
# - HDR 模式：保留原始高动态范围，不做任何映射
#
# 设计原则：
# - 不追求“像 ffmpeg 默认那样快”
# - 只追求：亮部不炸、层次完整、颜色稳定、可长期存档
#
###############################################################################

# ---------------------------------------------------------------------------
# Bash 安全选项
# ---------------------------------------------------------------------------
# -e : 任一命令失败，脚本立即退出
# 目的：避免 ffmpeg 静默失败却生成“坏截图”
set -e


# ===========================================================================
# 1️⃣ 默认参数（可被命令行覆盖）
# ===========================================================================

# 截图模式：
#   sdr = 电影级 SDR（默认，推荐）
#   hdr = 原始 HDR（不给人看，用于调色/对比）
MODE="sdr"

# 输出目录（默认与视频同目录）
OUT_DIR=""

# 是否裁剪到指定宽高比（例如 2.39）
CROP_AR=""

# 像素对齐（16 是视频领域最通用的安全值）
ALIGN=16


# ===========================================================================
# 2️⃣ 使用说明
# ===========================================================================

usage() {
  echo "Usage:"
  echo "  video_shot.sh <video> <time> [options]"
  echo
  echo "Arguments:"
  echo "  <video>    Input video file"
  echo "  <time>     Timestamp (HH:MM:SS or MM:SS)"
  echo
  echo "Options:"
  echo "  --hdr              Output raw HDR frame (no tone mapping)"
  echo "  --crop <ratio>     Force aspect ratio (e.g. 2.39, 1.85)"
  echo "  --out <dir>        Output directory"
  exit 1
}


# ===========================================================================
# 3️⃣ 参数解析（手动解析，便于阅读和维护）
# ===========================================================================

VIDEO=""
TIME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --hdr)
      MODE="hdr"
      shift
      ;;
    --crop)
      CROP_AR="$2"
      shift 2
      ;;
    --out)
      OUT_DIR="$2"
      shift 2
      ;;
    -*)
      usage
      ;;
    *)
      if [ -z "$VIDEO" ]; then
        VIDEO="$1"
      elif [ -z "$TIME" ]; then
        TIME="$1"
      else
        usage
      fi
      shift
      ;;
  esac
done

[ -z "$VIDEO" ] && usage
[ -z "$TIME" ] && usage


# ===========================================================================
# 4️⃣ 路径与输出文件名处理
# ===========================================================================

# 将视频路径转换为绝对路径（避免 ffmpeg 相对路径坑）
VIDEO_PATH="$(cd "$(dirname "$VIDEO")" && pwd)/$(basename "$VIDEO")"

[ ! -f "$VIDEO_PATH" ] && {
  echo "Video not found: $VIDEO_PATH"
  exit 1
}

# 输出目录
if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$(dirname "$VIDEO_PATH")"
else
  OUT_DIR="${OUT_DIR/#\~/$HOME}"
  mkdir -p "$OUT_DIR"
fi

# 文件名组成：
#   原视频名 + 时间点 + SDR/HDR 标识
BASE="$(basename "$VIDEO_PATH")"
BASE="${BASE%.*}"
SAFE_TIME="$(echo "$TIME" | tr ':' '-')"

SUFFIX="_SDR"
[ "$MODE" = "hdr" ] && SUFFIX="_HDR"

OUT_FILE="$OUT_DIR/${BASE}_${SAFE_TIME}${SUFFIX}.png"


# ===========================================================================
# 5️⃣ 获取视频分辨率（用于裁剪计算）
# ===========================================================================

# 使用 ffprobe 精确读取视频流参数
read VW VH < <(
  ffprobe -v error \
    -select_streams v:0 \
    -show_entries stream=width,height \
    -of csv=p=0:s=x "$VIDEO_PATH" | tr 'x' ' '
)


# ===========================================================================
# 6️⃣ 裁剪逻辑（仅当指定 --crop）
# ===========================================================================

# 默认不裁剪
CROP_FILTER=""

if [ -n "$CROP_AR" ]; then
  # 目标高度 = 宽度 / 宽高比
  # 同时向下取整到 ALIGN 的倍数（视频友好）
  TARGET_H=$(awk -v w="$VW" -v ar="$CROP_AR" -v a="$ALIGN" '
    BEGIN {
      h = int(w / ar);
      h = h - (h % a);
      print h
    }')

  # 合法性检查
  if [ "$TARGET_H" -le 0 ] || [ "$TARGET_H" -gt "$VH" ]; then
    echo "Invalid crop ratio: $CROP_AR"
    exit 1
  fi

  # 垂直居中裁剪
  OFFSET_Y=$(( (VH - TARGET_H) / 2 ))
  CROP_FILTER="crop=${VW}:${TARGET_H}:0:${OFFSET_Y}"
fi


# ===========================================================================
# 7️⃣ 核心：电影级滤镜链
# ===========================================================================

VF="$CROP_FILTER"

if [ "$MODE" = "sdr" ]; then
  ###########################################################################
  # SDR 路径（最重要）
  #
  # 思路：
  #   解码 → 线性光 → 电影级 tone mapping → 回到 BT.709 → RGB 输出
  #
  # 为什么要这么复杂？
  #   因为 ffmpeg 默认路径：
  #     YUV → RGB → 保存
  #   会直接压扁高光（火焰 / 爆炸 / 日光）
  ###########################################################################

  TONEMAP_FILTER="
zscale=t=linear:npl=100,            \
tonemap=tonemap=hable:desat=0,      \
zscale=t=bt709:m=bt709:r=tv,        \
format=rgb24
"

  VF="${VF:+$VF,}${TONEMAP_FILTER}"

else
  ###########################################################################
  # HDR 路径
  #
  # 不做 tone mapping
  # 用于：
  #   - 对比编码
  #   - 调色参考
  #   - HDR 显示器观看
  ###########################################################################

  VF="${VF:+$VF,}format=rgb48le"
fi


# ===========================================================================
# 8️⃣ 执行截图
# ===========================================================================

ffmpeg -loglevel error \
  -ss "$TIME" \
  -i "$VIDEO_PATH" \
  ${VF:+-vf "$VF"} \
  -frames:v 1 \
  "$OUT_FILE"


# ===========================================================================
# 9️⃣ 输出结果说明
# ===========================================================================

echo "Saved: $OUT_FILE"
[ -n "$CROP_FILTER" ] && echo "Crop applied: $CROP_FILTER" || echo "Crop: none"
echo "Mode: ${MODE^^}"
