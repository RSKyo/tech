#!/usr/bin/env bash
set -euo pipefail

############################################
# get_yt_source.sh
# -----------------
# 用途：
#   - 传入一个媒体文件：
#       默认：输出来源链接（优先 Finder 的“来源”，其次媒体内部 metadata）
#       --id：只输出其中的 YouTube 视频 ID（11 位）
#
# 优先级：
#   1) macOS 扩展属性 kMDItemWhereFroms（Finder 中的“来源”）
#   2) ffprobe 读取的 format_tags 元数据
#   3) 都没有 → 输出提示，退出
#
# 用法：
#   ./get_yt_source.sh <媒体文件>
#   ./get_yt_source.sh <媒体文件> --id
#
# 依赖：
#   macOS（有 mdls）、ffprobe（随 ffmpeg）
############################################

need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ 需要 $1，请先安装"; exit 1; }; }

need mdls
need ffprobe

if [ $# -lt 1 ]; then
  echo "用法：$0 <媒体文件> [--id]" >&2
  exit 1
fi

FILE="$1"
MODE="${2:-url}"   # 默认输出 URL，传 --id 时输出 ID

[ -f "$FILE" ] || { echo "❌ 找不到文件：$FILE" >&2; exit 1; }

############################################
# 小工具函数
############################################

# 在给定文本中找 YouTube 链接（优先 youtube.com/watch?v=，其次 youtu.be）
extract_url_from_text() {
  grep -Eo 'https?://(www\.)?(youtube\.com/watch\?v=|youtu\.be/)[A-Za-z0-9_-]{11}' \
    | head -n1
}

# 在文本中直接抠出 11 位 ID（兼容 v=ID 或 /ID）
extract_id_from_text() {
  sed -n '
    s/.*v=\([A-Za-z0-9_-]\{11\}\).*/\1/p
    s#.*/\([A-Za-z0-9_-]\{11\}\).*#\1#p
  ' | head -n1
}

# 1) 从 kMDItemWhereFroms 里取到“第一个 YouTube URL”
get_url_from_wherefroms() {
  local raw
  raw="$(mdls -name kMDItemWhereFroms -raw "$FILE" 2>/dev/null || echo "")"

  if [ -z "$raw" ] || [ "$raw" = "(null)" ]; then
    return 1
  fi

  # 不再管括号格式，直接在整段文本里 grep 出第一个 YouTube 链接
  printf '%s\n' "$raw" | extract_url_from_text || return 1
}

# 2) 从 ffprobe 的 format_tags 里拿到所有 value 文本
get_ffprobe_tags_text() {
  ffprobe -v error \
    -show_entries format_tags \
    -of default=noprint_wrappers=1:nokey=1 \
    "$FILE" 2>/dev/null || true
}

############################################
# 1) 先尝试从 kMDItemWhereFroms 里拿 URL
############################################

url_from_where=""
if url_from_where="$(get_url_from_wherefroms)"; then
  : # 有就用它
else
  url_from_where=""
fi

############################################
# 2) 再尝试从 ffprobe 元数据里拿 URL / ID
############################################

tags_text="$(get_ffprobe_tags_text)"

url_from_tags=""
if [ -n "$tags_text" ]; then
  url_from_tags="$(printf '%s\n' "$tags_text" | extract_url_from_text || true)"
fi

############################################
# 3) 统一决定 URL / ID
############################################

# 优先级：wherefroms 的 URL > ffprobe 的 URL
final_url=""
if [ -n "$url_from_where" ]; then
  final_url="$url_from_where"
elif [ -n "$url_from_tags" ]; then
  final_url="$url_from_tags"
fi

# ID 的来源可以是 URL，也可以是所有文本
final_id=""

if [ -n "$final_url" ]; then
  final_id="$(printf '%s\n' "$final_url" | extract_id_from_text || true)"
fi

# 如果 URL 里没提取出 ID，再从所有文本里兜底找一次
if [ -z "$final_id" ]; then
  all_text="$url_from_where
$tags_text"
  final_id="$(printf '%s\n' "$all_text" | extract_id_from_text || true)"
fi

############################################
# 4) 根据模式输出
############################################

if [ "$MODE" = "--id" ]; then
  if [ -n "$final_id" ]; then
    echo "$final_id"
    exit 0
  else
    echo "⚠️ 未能从 kMDItemWhereFroms 或元数据中解析出 YouTube 视频 ID。" >&2
    exit 1
  fi
else
  # URL 模式
  if [ -n "$final_url" ]; then
    echo "$final_url"
    exit 0
  fi

  # 没有 URL，但有 ID → 拼一个标准 URL
  if [ -n "$final_id" ]; then
    echo "https://www.youtube.com/watch?v=${final_id}"
    exit 0
  fi

  echo "⚠️ 未能从 kMDItemWhereFroms 或元数据中找到来源 URL 或视频 ID。" >&2
  exit 1
fi
