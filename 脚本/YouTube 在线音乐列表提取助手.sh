#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# YouTube 曲目列表提取助手.sh
# ==============================================================================
#
# 用途：
#   输入一个 YouTube 地址或 urls.txt 批量文件，
#   对每个地址调用 yt_tracklist_extractor.sh 提取曲目列表，
#   并输出成 "<标题> [id].tracklist.txt" 文件。
#
# 输出目录规则：
#   - 单 URL：输出目录默认为当前 bash 目录下的 ./yt_tracklist/
#   - 批量模式：目录为 urls.txt 所在路径下的 ./yt_tracklist/
#   - 可通过 --out DIR 指定输出目录
#
# 依赖：
#   - yt-dlp
#   - yt_tracklist_extractor.sh（必须与本脚本在同一目录）
#
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACTOR="$SCRIPT_DIR/yt_tracklist_extractor.sh"

if [[ ! -x "$EXTRACTOR" ]]; then
  echo "❌ 找不到 yt_tracklist_extractor.sh 或没有执行权限" >&2
  exit 1
fi

usage() {
  cat <<EOF
用法：
  单条 URL:
      ./YouTube 曲目列表提取助手.sh "<YouTube URL>"

  批量 URL 文件:
      ./YouTube 曲目列表提取助手.sh urls.txt

可选参数：
  --out DIR     指定输出目录
EOF
}

# ---------------- 参数解析 ----------------
OUT_DIR=""
INPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage; exit 0 ;;
    --out)
      shift
      OUT_DIR="$1"
      ;;
    *)
      INPUT="$1"
      ;;
  esac
  shift || true
done

if [[ -z "${INPUT:-}" ]]; then
  echo "❌ 需要提供 URL 或 urls.txt" >&2
  usage
  exit 1
fi

# ---------------- 工具检查 ----------------
if ! command -v yt-dlp >/dev/null 2>&1; then
  echo "❌ 缺少 yt-dlp，请先安装：brew install yt-dlp" >&2
  exit 1
fi

# ---------------- 工具函数 ----------------
sanitize_filename() {
  local s="$1"
  # 去除开头结尾空格
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  # 替换不合法字符
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

# ---------------- 单个 URL 处理 ----------------
process_one_url() {
  local url="$1"
  local real_out_dir="$2"

  echo "▶ 正在处理：$url"

  # 获取标题与ID
  local title video_id
  title=$(yt-dlp --no-playlist --get-title "$url" 2>/dev/null | head -n 1 || echo "video")
  video_id=$(yt-dlp --no-playlist -O "%(id)s" "$url" 2>/dev/null | head -n 1 || echo "id")

  title_clean=$(sanitize_filename "$title")
  outfile="$real_out_dir/${title_clean} [${video_id}].tracklist.txt"

  mkdir -p "$real_out_dir"

  # 调用 extractor
  tracklist=$("$EXTRACTOR" "$url" || true)

  # tracklist 可能为空
  if [[ -z "$tracklist" ]]; then
    echo "⚠ 未提取到曲目列表：$url" >&2
    return
  fi

  printf "%s" "$tracklist" > "$outfile"

  echo "✅ 已保存：$outfile"
}

# ---------------- 主逻辑 ----------------

# 输入是文件？ → 批量模式
if [[ -f "$INPUT" ]]; then
  urls_file="$INPUT"

  # 输出目录默认与 urls.txt 同级
  if [[ -z "$OUT_DIR" ]]; then
    OUT_DIR="$(cd "$(dirname "$urls_file")" && pwd)/yt_tracklist"
  fi

  mkdir -p "$OUT_DIR"
  echo "📁 输出目录：$OUT_DIR"

  total=$(grep -v '^[[:space:]]*$' "$urls_file" | grep -v '^#' | wc -l | tr -d ' ')
  index=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    url="${line#"${line%%[![:space:]]*}"}"
    url="${url%"${url##*[![:space:]]}"}"

    [[ -z "$url" || "$url" =~ ^# ]] && continue

    index=$((index + 1))
    echo
    echo "===== (${index}/${total}) ====="
    process_one_url "$url" "$OUT_DIR"

  done < "$urls_file"

else
  # 单 URL 模式
  url="$INPUT"
  OUT_DIR="${OUT_DIR:-$(pwd)/yt_tracklist}"
  echo "📁 输出目录：$OUT_DIR"
  mkdir -p "$OUT_DIR"
  process_one_url "$url" "$OUT_DIR"
fi

echo
echo "🎵 全部完成！"
exit 0
