#!/usr/bin/env bash
# =============================================================================
# SHID: 71Dp6FlP
# DO NOT REMOVE OR MODIFY THIS BLOCK.
# Used for script identity / indexing.
# =============================================================================

IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# -----------------------------------------------------------------------------
# 默认参数
# -----------------------------------------------------------------------------
OUT_DIR=""
WITH_TITLE=0
FORCE=0

MIN_TRACK_LINES=5
ENABLE_LAST_LINE_LOOP=1

# -----------------------------------------------------------------------------
# 解析参数
# -----------------------------------------------------------------------------
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
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
    -*)
      echo "[ERROR] unknown option: $1" >&2
      exit 1
      ;;
    *)
      ARGS+=( "$1" )
      shift
      ;;
  esac
done

[[ ${#ARGS[@]} -eq 0 ]] && exit 0

# -----------------------------------------------------------------------------
# 路径与依赖
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." >/dev/null && pwd)"

source "$ROOT_DIR/source/resolve_deps.source.sh"

resolve_deps \
  ROOT_DIR="$ROOT_DIR" \
  YT_URLS_CMD=Yjd7EHuw

# -----------------------------------------------------------------------------
# source 能力模块
# -----------------------------------------------------------------------------
source "$ROOT_DIR/source/yt_extract_id.source.sh"
source "$ROOT_DIR/source/yt_fetch_title.source.sh"
source "$ROOT_DIR/source/yt_fetch_description.source.sh"
source "$ROOT_DIR/source/sanitize_string.source.sh"
source "$ROOT_DIR/source/yt_extract_tracklist.source.sh"

# -----------------------------------------------------------------------------
# 输出目录
# -----------------------------------------------------------------------------
if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$SCRIPT_DIR/tracklist"
fi
mkdir -p "$OUT_DIR"

# -----------------------------------------------------------------------------
# 主处理逻辑
# -----------------------------------------------------------------------------
process_url() {
  local url="$1"
  local id title outfile
  local description
  local tracks=()

  id="$(yt_extract_id "$url")"
  [[ -z "$id" ]] && return 0

  # ---------------------------------------------------------------------------
  # title + outfile 计算（尽量提前）
  # ---------------------------------------------------------------------------
  title=""
  if (( WITH_TITLE == 1 )); then
    title="$(yt_fetch_title "$url" || true)"
    if [[ -n "$title" ]]; then
      title="$(sanitize_string "$title")"
    fi
  fi

  outfile="$OUT_DIR"
  if [[ -n "$title" ]]; then
    outfile="$outfile/$title [$id].txt"
  else
    outfile="$outfile/[$id].txt"
  fi

  # ---------------------------------------------------------------------------
  # 已存在检查（提前短路）
  # ---------------------------------------------------------------------------
  if (( FORCE == 0 )) && [[ -f "$outfile" ]]; then
    echo "[SKIP] $id -> $outfile" >&2
    return 0
  fi

  # ---------------------------------------------------------------------------
  # description → tracklist（仅在必要时）
  # ---------------------------------------------------------------------------
  description="$(yt_fetch_description "$url")"
  [[ -z "$description" ]] && return 0

  mapfile -t tracks < <(
    yt_extract_tracklist "$description"
  )

  (( ${#tracks[@]} < MIN_TRACK_LINES )) && return 0

  # ---------------------------------------------------------------------------
  # 最后一行 loop（固定开启）
  # ---------------------------------------------------------------------------
  if (( ENABLE_LAST_LINE_LOOP == 1 )); then
    local last_idx=$((${#tracks[@]} - 1))
    if [[ "${tracks[$last_idx]}" =~ ([0-9]{1,2}:[0-9]{2}(:[0-9]{2})?) ]]; then
      tracks[$last_idx]="${BASH_REMATCH[1]} @loop"
    fi
  fi

  printf '%s\n' "${tracks[@]}" >"$outfile"
  echo "[OK] $id -> $outfile" >&2
}

# -----------------------------------------------------------------------------
# 执行
# -----------------------------------------------------------------------------
while IFS= read -r url; do
  process_url "$url"
done < <("$YT_URLS_CMD" "${ARGS[@]}")