#!/usr/bin/env bash
# =========================================================
# 📘 名称：youtube封面提取助手.sh
# 📦 代号：YTEX (YouTube Thumbnail Extract)
#
# 模式逻辑：
#   ✅ 默认：
#      1) 直连 i.ytimg.com 仅试 maxresdefault.webp / .jpg（极速）
#      2) 否则回退 yt-dlp --write-thumbnail（一次）
#      3) 仍失败 → 提示并跳过（不进入精挑）
#   ✅ --best：下载所有缩略图并选择最清晰（较慢）
#   ✅ --translate-en：将视频标题翻译成英文后作为文件名
#
# 特性：
#   - 仅保留最终 .jpg 文件，自动清理中间文件
#   - 兼容 macOS bash 3.2（不使用 mapfile）；处理 CRLF
#   - 进度显示 (i/N)
#   - 默认输出目录：<脚本所在目录>/yt_cover（可用 --out 指定）
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

# --- 参数（默认 OUT_DIR 留空，稍后判定是否用脚本目录/yt_cover） ---
OUT_DIR=""
BEST_MODE=0           # 0=默认；1=精挑
TRANSLATE_EN=0        # 1=把标题翻译为英文
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

说明：
  默认输出目录：<脚本所在目录>/yt_cover
  默认流程：直连 maxres → yt-dlp 回退 → 失败跳过（不进入精挑）
  --best           下载全部缩略图并挑最清晰（较慢）
  --translate-en   将标题翻译成英文后作为文件名
EOF
      exit 0
      ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
[[ ${#ARGS[@]} -lt 1 ]] && die "缺少输入参数。用法：$0 [--out <目录>] [--translate-en] [--best] <链接或txt>"

INPUT="${ARGS[0]}"

# 计算脚本所在目录；决定最终输出目录
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$SCRIPT_DIR/yt_cover"
elif [[ "$OUT_DIR" != /* ]]; then
  # 将相对路径视为相对脚本目录
  OUT_DIR="$SCRIPT_DIR/$OUT_DIR"
fi
mkdir -p "$OUT_DIR"

command -v curl >/dev/null 2>&1 || die "需要 curl，请先安装。"
# yt-dlp 非强制（默认直连即可）；API 回退/取标题时会用到
if ! command -v yt-dlp >/dev/null 2>&1; then
  warn "未检测到 yt-dlp，API 回退与标题获取将受限（将以 ID 命名）。可通过：brew install yt-dlp 或 pip3 install -U yt-dlp 安装。"
fi

# --- 工具函数 ---
sanitize_title() {
  # 去非法字符、压缩空格、去首尾空白，移除 CR/LF
  tr -d '\r' | sed 's#[/\\:*?"<>|]#_#g; s/  \+/ /g; s/^[[:space:]]\+//; s/[[:space:]]\+$//' | tr -d '\n'
}

cleanup_temp() {
  # 删除中间文件（thumb.* 以及非最终格式）
  find "$OUT_DIR" -type f \( -name "thumb.*" -o -name "*.webp" -o -name "*.png" \) -delete 2>/dev/null || true
}

# 统一的“转成 jpg”助手：in → out.jpg
convert_to_jpg() {
  local in="$1" out="$2"
  # 若已经是 jpg 直接复制
  if [[ "$in" =~ \.jpe?g$ ]]; then
    cp -f "$in" "$out"
    return 0
  fi
  # 依次尝试 ffmpeg / sips / mogrify
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -i "$in" "$out" >/dev/null 2>&1 || true
  elif command -v sips >/dev/null 2>&1; then
    sips -s format jpeg "$in" --out "$out" >/dev/null 2>&1 || true
  elif command -v mogrify >/dev/null 2>&1; then
    cp -f "$in" "$out"
    mogrify -format jpg "$out" >/dev/null 2>&1 || true
  fi
  [[ -f "$out" ]]
}

# URL 编码（尽量使用 python3/ruby；没有则简化）
urlencode() {
  local s="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$s" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1]))
PY
  elif command -v ruby >/dev/null 2>&1; then
    ruby -r uri -e 'print URI.encode_www_form_component(ARGV[0])' "$s"
  else
    local out="${s// /%20}"
    printf "%s" "$out"
  fi
}

# 翻译到英文（Google 免费接口；失败则返回原文）
translate_to_en() {
  local text="$1"
  local q; q="$(urlencode "$text")"
  local url="https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=en&dt=t&q=${q}"
  local resp
  resp="$(curl -s "$url" || true)"
  [[ -z "$resp" ]] && { echo "$text"; return; }
  if command -v python3 >/dev/null 2>&1; then
    local out
    out="$(python3 - "$resp" <<'PY'
import sys, json
try:
    data=json.loads(sys.argv[1])
    print(''.join(seg[0] for seg in data[0] if seg and seg[0]))
except Exception:
    print('')
PY
)"
    [[ -n "$out" ]] && { echo "$out"; return; }
  fi
  local first
  first="$(printf "%s" "$resp" | awk -F'"' '{print $2}')"
  echo "${first:-$text}"
}

# 选最大缩略图（有 identify 用分辨率，否则用文件大小）
pick_largest_thumb() {
  local pattern="$1" chosen=""
  if command -v identify >/dev/null 2>&1; then
    chosen="$(ls $pattern 2>/dev/null | xargs -I{} identify -format "%[fx:w*h] %i\n" "{}" 2>/dev/null | sort -nr | head -1 | awk '{print $2}')"
  else
    if stat -f%z / >/dev/null 2>&1; then
      chosen="$(ls -1 $pattern 2>/dev/null | xargs -I{} sh -c 'echo $(stat -f%z "{}") "{}"' | sort -nr | head -1 | cut -d" " -f2- )"
    else
      chosen="$(ls -1 $pattern 2>/dev/null | xargs -I{} sh -c 'echo $(stat -c%s "{}") "{}"' | sort -nr | head -1 | cut -d" " -f2- )"
    fi
  fi
  echo "${chosen:-}"
}

# 提取视频 ID（支持 youtu.be / v=）
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

# 1) 直连 maxres（webp/jpg），并转成 jpg 保存
direct_thumbnail() {
  local id="$1" outfile="$2"
  local base="https://i.ytimg.com/vi/${id}"
  # 用临时文件按源后缀保存，随后统一转 jpg
  for f in maxresdefault.webp maxresdefault.jpg; do
    local url="${base}/${f}"
    local tmp="${OUT_DIR}/.tmp_${id}_${f}"
    if curl -fs -o "$tmp" "$url" >/dev/null 2>&1; then
      if convert_to_jpg "$tmp" "$outfile"; then
        rm -f "$tmp" 2>/dev/null || true
        ok "直连封面：$f"
        return 0
      fi
      rm -f "$tmp" 2>/dev/null || true
    fi
  done
  return 1
}

# 2) yt-dlp 回退：拿到任意缩略图并转成 jpg
api_thumbnail() {
  local url="$1" title="$2" outfile="$3"
  command -v yt-dlp >/dev/null 2>&1 || return 1
  info "调用 yt-dlp API 回退..."
  # 清理潜在残留
  rm -f "${OUT_DIR}/${title}."{jpg,jpeg,png,webp} 2>/dev/null || true
  yt-dlp --skip-download --write-thumbnail --convert-thumbnails jpg \
         -o "${OUT_DIR}/${title}.%(ext)s" "$url" >/dev/null 2>&1 || true
  local got=""
  for ext in jpg jpeg png webp; do
    if [[ -f "${OUT_DIR}/${title}.${ext}" ]]; then
      got="${OUT_DIR}/${title}.${ext}"
      break
    fi
  done
  [[ -z "$got" ]] && return 1
  if convert_to_jpg "$got" "$outfile"; then
    rm -f "$got" 2>/dev/null || true
    return 0
  fi
  return 1
}

# 3) 精挑：下载全部缩略图选最大（仅 --best 才使用）
best_thumbnail() {
  local url="$1" outfile="$2"
  command -v yt-dlp >/dev/null 2>&1 || return 1
  warn "进入精挑模式（下载全部缩略图）..."
  rm -f "${OUT_DIR}/thumb."*.jpg 2>/dev/null || true
  yt-dlp --skip-download --write-all-thumbnails --convert-thumbnails jpg \
         -o "${OUT_DIR}/thumb.%(ext)s" "$url" >/dev/null 2>&1 || true
  local largest
  largest="$(pick_largest_thumb "${OUT_DIR}/thumb.*.jpg")"
  if [[ -n "$largest" && -f "$largest" ]]; then
    cp -f "$largest" "$outfile"
    cleanup_temp
    return 0
  fi
  cleanup_temp
  return 1
}

# 从 txt 读取链接（兼容 CRLF / 空行 / 注释）
read_links_file() {
  local file="$1" arr=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    local trimmed="${line#"${line%%[![:space:]]*}"}"
    [[ -z "${trimmed//[[:space:]]/}" || "$trimmed" == \#* ]] && continue
    arr+=("$line")
  done < "$file"
  (IFS=$'\n'; printf "%s\0" "${arr[@]}")
}

# --- 单个视频处理 ---
process_one() {
  local URL="$1" index="$2" total="$3"
  local percent=$(( total ? index * 100 / total : 0 ))
  echo -e "\n${BOLD}==============================${RESET}"
  info "处理视频（${index}/${total}，约 ${percent}%）：$URL"

  # 标题（没有 yt-dlp 就用 ID 代替）
  local raw_title title out_file video_id
  if command -v yt-dlp >/dev/null 2>&1; then
    raw_title="$(yt-dlp --get-title "$URL" 2>/dev/null || echo "background")"
  else
    raw_title="background"
  fi

  # 可选：翻译成英文
  if [[ "$TRANSLATE_EN" -eq 1 ]]; then
    info "翻译标题 → 英文..."
    local t_en
    t_en="$(translate_to_en "$raw_title")"
    [[ -n "$t_en" ]] && raw_title="$t_en"
  fi

  title="$(echo "$raw_title" | sanitize_title)"
  [[ -z "$title" || "$title" == "background" ]] && {
    # 如果取不到标题，尝试用视频 ID 兜底命名
    video_id="$(extract_id "$URL")"
    [[ -n "$video_id" ]] && title="$video_id" || title="background"
  }
  out_file="${OUT_DIR}/${title}.jpg"
  info "文件名：$title.jpg"

  # 提取视频 ID（直连步骤需要）
  [[ -z "${video_id:-}" ]] && video_id="$(extract_id "$URL")"
  if [[ -z "$video_id" ]]; then
    warn "无法解析视频 ID，跳过。"
    return
  fi

  # 顺序：直连 → API → （可选）精挑
  if direct_thumbnail "$video_id" "$out_file"; then
    ok "保存封面：$out_file"
  elif api_thumbnail "$URL" "$title" "$out_file"; then
    ok "API 获取封面：$out_file"
  elif [[ "$BEST_MODE" -eq 1 ]]; then
    if best_thumbnail "$URL" "$out_file"; then
      ok "保存最清晰封面：$out_file"
    else
      warn "精挑模式也失败。"
    fi
  else
    warn "未找到高清封面，已跳过。"
  fi

  cleanup_temp
}

# --- 入口 ---
echo -e "${BOLD}📁 输出目录：${OUT_DIR}${RESET}"
if [[ -f "$INPUT" ]]; then
  info "检测到链接文件：$INPUT"
  LINKS=()
  while IFS= read -r -d '' one; do LINKS+=("$one"); done < <(read_links_file "$INPUT")
  TOTAL=${#LINKS[@]}
  [[ "$TOTAL" -eq 0 ]] && die "文件中没有有效链接。"
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
