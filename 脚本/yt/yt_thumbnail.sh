#!/usr/bin/env bash
IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# yt_thumbnail.sh
#
# 从 YouTube URL 获取官方封面缩略图（thumbnail）
#
# 特性：
#   - 仅直连 i.ytimg.com
#   - 不使用 yt-dlp
#   - 不抽帧（不使用 1/2/3）
#   - 支持 argv / stdin（管道）
#   - 通过 yt_id.sh 本地解析 videoId
#   - 可选 --with-title，标题通过 sanitize_string.sh 清洗
#
# 尝试顺序：
#   尺寸：maxresdefault → sddefault → hqdefault
#   格式：jpg → webp
#
# 输出：
#   - 目录：
#       * 指定 --out <DIR> → 使用该目录
#       * 未指定 → $SCRIPT_DIR/thumbnail/（自动创建）
#   - 文件名：
#       * 默认：[<videoId>].<ext>
#       * --with-title：<safe_title> [<videoId>].<ext>
# =============================================================================

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YT_ID_CMD="$SCRIPT_DIR/yt_id.sh"
SANITIZE_CMD="$SCRIPT_DIR/sanitize_string.sh"

SIZES=(maxresdefault sddefault hqdefault)
EXTS=(jpg webp)

# ---------------------------------------------------------------------------
# dependency check
# ---------------------------------------------------------------------------
for dep in "$YT_ID_CMD" "$SANITIZE_CMD"; do
  if [[ ! -x "$dep" ]]; then
    echo "[ERROR] dependency not found or not executable: $dep" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# optional dependency check (jq for --with-title)
# ---------------------------------------------------------------------------
HAS_JQ=0
if command -v jq >/dev/null 2>&1; then
  HAS_JQ=1
fi

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  cat >&2 <<'EOF'
Usage:
  yt_thumbnail.sh [--out DIR] [--with-title] [--force] [URL ...]
  yt_thumbnail.sh [--out DIR] [--with-title] [--force] < urls.txt

Options:
  --out DIR       Output directory (absolute path).
  --with-title    Include sanitized video title in output filename.
  --force         Overwrite existing file.
EOF
}

# ---------------------------------------------------------------------------
# 参数解析
# ---------------------------------------------------------------------------
OUT_DIR=""
WITH_TITLE=0
FORCE=0
URL_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      OUT_DIR="$2"
      shift 2
      ;;
    --with-title)
      WITH_TITLE=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      usage
      exit 1
      ;;
    *)
      URL_ARGS+=("$1")
      shift
      ;;
  esac
done

[[ -z "$OUT_DIR" ]] && OUT_DIR="$SCRIPT_DIR/thumbnail"
mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------------------
# 获取 title
# ---------------------------------------------------------------------------
fetch_title() {
  local url="$1"

  if [[ $HAS_JQ -ne 1 ]]; then
    return 1
  fi

  curl -sL \
    "https://www.youtube.com/oembed?format=json&url=$url" \
  | jq -r '.title // empty'
}

# ---------------------------------------------------------------------------
# 下载单个 videoId 的封面（修正版）
# ---------------------------------------------------------------------------
download_thumbnail() {
  local id="$1"
  local url="$2"
  local title="" safe_title=""
  local outfile_base outfile
  local size ext img_url

  # --- title 处理 ---
  if [[ $WITH_TITLE -eq 1 ]]; then
    title="$(fetch_title "$url" || true)"
    if [[ -n "$title" ]]; then
      safe_title="$(printf '%s\n' "$title" | "$SANITIZE_CMD")"
    else
      echo "[WARN] title fetch failed, fallback to id: $id" >&2
    fi
  fi

  # --- 最终文件名前缀（关键修复点） ---
  if [[ -n "$safe_title" ]]; then
    outfile_base="$OUT_DIR/$safe_title [$id]"
  else
    outfile_base="$OUT_DIR/[$id]"
  fi

  # --- 已存在检查（只做一次） ---
  for ext in "${EXTS[@]}"; do
    outfile="$outfile_base.$ext"
    if [[ -f "$outfile" && $FORCE -eq 0 ]]; then
      echo "[SKIP] $id -> $outfile" >&2
      return 0
    fi
  done

  # --- 下载循环 ---
  for size in "${SIZES[@]}"; do
    for ext in "${EXTS[@]}"; do
      img_url="https://i.ytimg.com/vi/$id/$size.$ext"
      outfile="$outfile_base.$ext"

      if curl -fsL --connect-timeout 5 --max-time 15 "$img_url" -o "$outfile"; then
        echo "[OK] $id $size.$ext -> $outfile" >&2
        return 0
      fi
    done
  done

  return 1
}

# ---------------------------------------------------------------------------
# main: argv / stdin unified
# ---------------------------------------------------------------------------
had_input=0

if [[ ${#URL_ARGS[@]} -gt 0 ]]; then
  for url in "${URL_ARGS[@]}"; do
    [[ -z "$url" ]] && continue
    had_input=1

    if ! id="$("$YT_ID_CMD" "$url" 2>/dev/null)"; then
      echo "[WARN] invalid url: $url" >&2
      continue
    fi

    if ! download_thumbnail "$id" "$url"; then
      echo "[WARN] thumbnail not found: $id" >&2
    fi
  done
else
  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    had_input=1

    if ! id="$("$YT_ID_CMD" "$url" 2>/dev/null)"; then
      echo "[WARN] invalid url: $url" >&2
      continue
    fi

    if ! download_thumbnail "$id" "$url"; then
      echo "[WARN] thumbnail not found: $id" >&2
    fi
  done
fi

[[ $had_input -eq 1 ]] || usage