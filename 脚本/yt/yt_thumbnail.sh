#!/usr/bin/env bash
# =============================================================================
# SHID: R0BCnzp6
# DO NOT REMOVE OR MODIFY THIS BLOCK.
# Used for script identity / indexing.
# =============================================================================

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
#   - 使用 yt_extract_id 提取 videoId
#   - 可选 --with-title，标题通过 sanitize_string 清洗
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
# 路径
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)"

# ---------------------------------------------------------------------------
# source 能力模块（函数级依赖）
# ---------------------------------------------------------------------------
source "$ROOT_DIR/source/yt_extract_id.source.sh"
source "$ROOT_DIR/source/sanitize_string.source.sh"

# ---------------------------------------------------------------------------
# 业务常量
# ---------------------------------------------------------------------------
SIZES=(maxresdefault sddefault hqdefault)
EXTS=(jpg webp)

# ---------------------------------------------------------------------------
# optional dependency: jq（仅 --with-title 使用）
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
# 获取 title（仅在 --with-title 且 jq 可用时）
# ---------------------------------------------------------------------------
fetch_title() {
  local url="$1"

  [[ $HAS_JQ -eq 1 ]] || return 1

  curl -sL \
    "https://www.youtube.com/oembed?format=json&url=$url" \
  | jq -r '.title // empty'
}

# ---------------------------------------------------------------------------
# 下载单个 videoId 的封面
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
      safe_title="$(sanitize_string "$title")"
    else
      echo "[WARN] title fetch failed, fallback to id: $id" >&2
    fi
  fi

  # --- 文件名前缀 ---
  if [[ -n "$safe_title" ]]; then
    outfile_base="$OUT_DIR/$safe_title [$id]"
  else
    outfile_base="$OUT_DIR/[$id]"
  fi

  # --- 已存在检查 ---
  if [[ $FORCE -eq 0 ]]; then
    for ext in "${EXTS[@]}"; do
      if [[ -f "$outfile_base.$ext" ]]; then
        echo "[SKIP] $id -> $outfile_base.$ext" >&2
        return 0
      fi
    done
  fi

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

    if ! id="$(yt_extract_id "$url")"; then
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

    if ! id="$(yt_extract_id "$url")"; then
      echo "[WARN] invalid url: $url" >&2
      continue
    fi

    if ! download_thumbnail "$id" "$url"; then
      echo "[WARN] thumbnail not found: $id" >&2
    fi
  done
fi

[[ $had_input -eq 1 ]] || usage
