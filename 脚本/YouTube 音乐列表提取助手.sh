#!/usr/bin/env bash
set -euo pipefail

############################################
# YouTube 音乐列表提取助手
# ------------------------------------------
# 功能：
#   - 支持单个 YouTube 地址或包含多个地址的文件
#   - 提取视频描述中的“时间戳+曲名列表”
#   - 默认输出到脚本所在目录下的 yt_musiclist/
#   - 可用 --out 指定自定义输出目录
#   - 可用 --basename 指定未来对应的“媒体文件名”（含扩展名），
#     输出文件名为：<basename>.split.txt
#
# 依赖：
#   - yt-dlp
#
# 用法：
#   ./yt_musiclist.sh <YouTube地址 或 txt文件>
#       [--out 输出目录]
#       [--basename 媒体文件名]
#
# 示例：
#   单个视频：
#       ./yt_musiclist.sh "https://www.youtube.com/watch?v=2t85i8MewwM"
#   批量：
#       ./yt_musiclist.sh urls.txt
#   自定义输出目录：
#       ./yt_musiclist.sh urls.txt --out ~/Desktop/output
#   指定将来对应的媒体文件名：
#       ./yt_musiclist.sh "URL" --basename "a.mp4"
#       # 输出：a.mp4.split.txt，可供 media_segment_plan.sh 使用
############################################

if [ $# -lt 1 ]; then
  echo "用法：$0 <YouTube地址 或 地址列表.txt> [--out 输出目录] [--basename 媒体文件名]" >&2
  exit 1
fi

if ! command -v yt-dlp >/dev/null 2>&1; then
  echo "错误：未检测到 yt-dlp，请先安装：brew install yt-dlp" >&2
  exit 1
fi

# ---------- 解析参数 ----------
OUT_DIR=""
INPUT=""
BASENAME=""   # 新增：指定输出文件的“基名”（含扩展名），用于生成 <basename>.split.txt

while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      shift
      OUT_DIR="${1:-}"
      ;;
    --basename)
      shift
      BASENAME="${1:-}"
      ;;
    *)
      if [ -z "$INPUT" ]; then
        INPUT="$1"
      else
        echo "⚠️ 忽略多余参数：$1" >&2
      fi
      ;;
  esac
  shift || true
done

if [ -z "$INPUT" ]; then
  echo "错误：缺少输入参数（地址或txt文件）" >&2
  exit 1
fi

# ---------- 确定输出目录 ----------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$SCRIPT_DIR/yt_musiclist"
fi
mkdir -p "$OUT_DIR"

echo "📁 输出目录：$OUT_DIR"
echo

# ---------- 辅助：清理不合法文件名字符 ----------
sanitize_filename() {
  local s="$1"
  # 去掉前后空白
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  # 替换不适合作为文件名的字符
  s="${s//\//_}"
  s="${s//\\/_}"
  s="${s//:/_}"
  s="${s//\*/_}"
  s="${s//\?/_}"
  s="${s//\"/_}"
  s="${s//</_}"
  s="${s//>/_}"
  s="${s//|/_}"
  echo "$s"
}

# ---------- 核心函数 ----------
process_url() {
  local url="$1"

  echo "▶ 正在处理：$url"

  local title outfile desc base

  # 1) 先拿到视频标题，作为默认基名
  echo "  [DEBUG] 调用 yt-dlp --get-title ..."
  title=$(yt-dlp --no-playlist --get-title "$url" 2>/dev/null | head -n1 || true)
  echo "  [DEBUG] --get-title 完成，title=$title"
  [ -n "$title" ] || title="youtube_video"
  title="$(sanitize_filename "$title")"

  # 2) 确定输出文件的“基名”（含扩展名与否都随你）：
  #    - 若提供了 --basename，则优先用它；
  #    - 否则用 <title>.mp4 当作未来的媒体文件名。
  if [ -n "$BASENAME" ]; then
    base="$BASENAME"
  else
    base="${title}.mp4"
  fi

  # 与 media_segment_plan.sh 对齐：<媒体文件名>.split.txt
  outfile="$OUT_DIR/${base}.split.txt"

  echo "▶ 正在获取视频描述..."
  echo "  [DEBUG] 调用 yt-dlp -O '%(description)s' ..."
  desc=$(yt-dlp --no-playlist -O "%(description)s" "$url" 2>/dev/null || true)
  echo "  [DEBUG] description 获取完成，长度：${#desc}"
  if [ -z "$desc" ]; then
    echo "⚠️ 无法获取描述，跳过：$url"
    echo
    return
  fi

  echo "▶ 正在提取音乐列表..."
  # 仅保留“以时间戳开头”的行，前后去空白
  echo "$desc" \
    | grep -E "^[[:space:]]*[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?" \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    > "$outfile"

  if [ ! -s "$outfile" ]; then
    echo "⚠️ 未找到时间标记的行，可能无曲目列表。"
    rm -f "$outfile"
  else
    echo "✅ 已保存到：$outfile"
    wc -l < "$outfile" | awk '{print "共提取 "$1" 行。"}'
  fi

  echo
}

# ---------- 主逻辑 ----------
if [ -f "$INPUT" ]; then
  echo "📃 批量模式：读取文件 $INPUT"
  while IFS= read -r line || [ -n "$line" ]; do
    url="${line#"${line%%[![:space:]]*}"}"
    url="${url%"${url##*[![:space:]]}"}"
    [[ -z "$url" || "$url" =~ ^# ]] && continue
    process_url "$url"
  done < "$INPUT"
else
  process_url "$INPUT"
fi

echo "🎵 全部完成！"
