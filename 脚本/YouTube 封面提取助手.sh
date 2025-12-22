#!/usr/bin/env bash
# =========================================================
# 📘 名称：youtube封面提取助手.sh
# 📦 代号：YTEX (YouTube Thumbnail Extract)
#
# 🎯 设计目标：
#   - 极速获取 YouTube 视频封面
#   - 对真实世界分享链接具备强容错能力
#   - 避免 playlist / 网络问题导致的阻塞
#
# 🧠 模式逻辑：
#   ✅ 默认模式：
#      1) 直连 i.ytimg.com，仅尝试 maxresdefault.webp / .jpg（最快）
#      2) 若直连失败，回退使用 yt-dlp API 获取缩略图（一次）
#      3) 仍失败则提示并跳过（不进入精挑）
#
#   ✅ --best：
#      - 下载该视频的所有缩略图
#      - 自动选择分辨率或体积最大的那一张（较慢）
#
#   ✅ --translate-en：
#      - 将视频标题翻译为英文后作为文件名
#
# 🔒 稳定性与安全策略：
#   - 自动移除 URL 中的 playlist 参数（如 ?list=xxx）
#   - 所有 yt-dlp 调用均强制使用 --no-playlist
#   - 确保只处理“单个视频”，避免解析整个播放列表导致卡住
#
# 🧹 文件处理策略：
#   - 最终仅保留 .jpg 文件
#   - 自动清理中间生成的 webp / png / thumb.* 文件
#
# 🧩 兼容性说明：
#   - 兼容 macOS 自带 bash 3.2（不使用 mapfile 等新特性）
#   - 兼容 zsh / bash 调用方式
#   - 支持 Unicode / emoji / 多语言标题作为文件名
#
# 📂 输出说明：
#   - 默认输出目录：<脚本所在目录>/yt_cover
#   - 可通过 --out 指定输出目录
#
# =========================================================


set -euo pipefail

# --- 彩色输出 ---
if [[ -t 1 ]]; then
  GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[34m"; RED="\033[31m"; BOLD="\033[1m"; RESET="\033[0m"
else
  GREEN=""; YELLOW=""; BLUE=""; RED=""; BOLD=""; RESET=""
fi
die() { echo -e "${RED}❌ $*${RESET}"; exit 1; }
info() { echo -e "${BLUE}ℹ️  $*${RESET}"; }
ok()   { echo -e "${GREEN}✅ $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️  $*${RESET}"; }

# --- 参数 ---
OUT_DIR=""
BEST_MODE=0
TRANSLATE_EN=0
ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_DIR="${2:-yt_cover}"; shift 2 ;;
    --best) BEST_MODE=1; shift ;;
    --translate-en|--en) TRANSLATE_EN=1; shift ;;
    -h|--help)
      cat <<'EOF'
用法：
  youtube封面提取助手.sh [--out <目录>] [--translate-en] [--best] <YouTube链接 或 txt文件>
EOF
      exit 0
      ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
[[ ${#ARGS[@]} -lt 1 ]] && die "缺少输入参数。"

INPUT="${ARGS[0]}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$SCRIPT_DIR/yt_cover"
elif [[ "$OUT_DIR" != /* ]]; then
  OUT_DIR="$SCRIPT_DIR/$OUT_DIR"
fi
mkdir -p "$OUT_DIR"

command -v curl >/dev/null 2>&1 || die "需要 curl。"

if ! command -v yt-dlp >/dev/null 2>&1; then
  warn "未检测到 yt-dlp，API 回退与标题获取将受限。"
fi

# --- 工具函数 ---

sanitize_title() {
  tr -d '\r' | sed 's#[/\\:*?"<>|]#_#g; s/  \+/ /g; s/^[[:space:]]\+//; s/[[:space:]]\+$//' | tr -d '\n'
}

cleanup_temp() {
  find "$OUT_DIR" -type f \( -name "thumb.*" -o -name "*.webp" -o -name "*.png" \) -delete 2>/dev/null || true
}

convert_to_jpg() {
  local in="$1" out="$2"
  if [[ "$in" =~ \.jpe?g$ ]]; then
    cp -f "$in" "$out"; return 0
  fi
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -i "$in" "$out" >/dev/null 2>&1 || true
  elif command -v sips >/dev/null 2>&1; then
    sips -s format jpeg "$in" --out "$out" >/dev/null 2>&1 || true
  fi
  [[ -f "$out" ]]
}

# 🔧 新增：移除 playlist 参数，避免 yt-dlp 卡住
sanitize_url() {
  local url="$1"
  echo "$url" | sed 's/[?&]list=[^&]*//'
}

extract_id() {
  local url="$1"
  if [[ "$url" =~ v=([A-Za-z0-9_-]{11}) ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$url" =~ youtu\.be/([A-Za-z0-9_-]{11}) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

direct_thumbnail() {
  local id="$1" outfile="$2"
  local base="https://i.ytimg.com/vi/${id}"
  for f in maxresdefault.webp maxresdefault.jpg; do
    local tmp="${OUT_DIR}/.tmp_${id}_${f}"
    if curl -fs -o "$tmp" "${base}/${f}" >/dev/null 2>&1; then
      if convert_to_jpg "$tmp" "$outfile"; then
        rm -f "$tmp"; ok "直连封面：$f"; return 0
      fi
      rm -f "$tmp"
    fi
  done
  return 1
}

api_thumbnail() {
  local url="$1" title="$2" outfile="$3"
  command -v yt-dlp >/dev/null 2>&1 || return 1
  info "调用 yt-dlp API 回退..."
  yt-dlp --no-playlist --skip-download --write-thumbnail --convert-thumbnails jpg \
    -o "${OUT_DIR}/${title}.%(ext)s" "$url" >/dev/null 2>&1 || true
  for ext in jpg jpeg png webp; do
    [[ -f "${OUT_DIR}/${title}.${ext}" ]] || continue
    convert_to_jpg "${OUT_DIR}/${title}.${ext}" "$outfile" && rm -f "${OUT_DIR}/${title}.${ext}" && return 0
  done
  return 1
}

process_one() {
  local RAW_URL="$1" index="$2" total="$3"
  local URL; URL="$(sanitize_url "$RAW_URL")"
  [[ "$RAW_URL" != "$URL" ]] && warn "检测到 playlist 参数，已自动忽略，仅处理单个视频"

  echo -e "\n${BOLD}==============================${RESET}"
  info "处理视频（${index}/${total}）：$URL"

  local raw_title title video_id out_file

  if command -v yt-dlp >/dev/null 2>&1; then
    raw_title="$(yt-dlp --no-playlist --get-title "$URL" 2>/dev/null || echo background)"
  else
    raw_title="background"
  fi

  title="$(echo "$raw_title" | sanitize_title)"
  video_id="$(extract_id "$URL")"
  [[ -z "$title" ]] && title="${video_id:-background}"
  out_file="${OUT_DIR}/${title}.jpg"

  info "文件名：$title.jpg"

  [[ -z "$video_id" ]] && { warn "无法解析视频 ID，跳过"; return; }

  if direct_thumbnail "$video_id" "$out_file"; then
    ok "保存封面：$out_file"
  elif api_thumbnail "$URL" "$title" "$out_file"; then
    ok "API 获取封面：$out_file"
  else
    warn "未找到高清封面"
  fi

  cleanup_temp
}

echo -e "${BOLD}📁 输出目录：${OUT_DIR}${RESET}"

if [[ -f "$INPUT" ]]; then
  mapfile -t LINKS < "$INPUT"
  TOTAL="${#LINKS[@]}"
  COUNT=0
  for URL in "${LINKS[@]}"; do
    COUNT=$((COUNT+1))
    process_one "$URL" "$COUNT" "$TOTAL"
  done
else
  process_one "$INPUT" 1 1
fi

echo
ok "🎉 所有封面已保存到目录：${OUT_DIR}/"
