#!/usr/bin/env bash
IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# YouTube 在线音乐列表提取助手.sh
#
# 功能：
#   从 YouTube URL（单个 / URL 文件 / 目录反查）中提取在线音乐 Tracklist，
#   并输出为：
#     "<sanitize(title)> [id].tracklist.txt"
#
# 输入形式：
#   1) 单个 YouTube URL
#   2) URL 文件（每行一个 URL）
#   3) 目录（通过 dir_files.sh + get_source_url.sh 反查 YouTube URL）
#
# 输出目录规则：
#   - 若指定 --out DIR → 直接输出到 DIR
#   - 否则：
#       * 单 URL      → $(pwd)/yt_tracklist/
#       * URL 文件    → <urls.txt 同级>/yt_tracklist/
#       * 目录        → <目录>/yt_tracklist/
#
# 覆盖规则：
#   - 默认：若输出文件已存在 → 跳过
#   - --force：强制覆盖
#
# 依赖：
#   - yt-dlp
#   - yt_tracklist_extractor.sh
#   - sanitize_filename.sh
#   - dir_files.sh（目录模式）
#   - get_source_url.sh（用于从单个媒体文件中提取来源 URL）
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EXTRACTOR="$SCRIPT_DIR/yt_tracklist_extractor.sh"
SANITIZER="$SCRIPT_DIR/sanitize_filename.sh"
DIR_FILES="$SCRIPT_DIR/dir_files.sh"
GET_SOURCE="$SCRIPT_DIR/get_source_url.sh"
YT_PARSE_ID="$SCRIPT_DIR/yt_parse_id.sh"

# -----------------------------------------------------------------------------
# 参数
# -----------------------------------------------------------------------------
OUT_DIR=""
FORCE_OVERWRITE=0
INPUT=""

# 要转发给 yt_tracklist_extractor.sh 的参数
EXTRACTOR_OPTS=()

# -----------------------------------------------------------------------------
# usage
# -----------------------------------------------------------------------------
usage() {
  cat <<EOF
用法：
  单 URL：
    $0 "<YouTube URL>"

  URL 文件：
    $0 urls.txt

  目录：
    $0 <directory>

参数：
  --out DIR     指定输出目录（直接使用 DIR）
  --force       若输出文件已存在，强制覆盖
  -h, --help    显示帮助

Tracklist 提取参数（将转发给 yt_tracklist_extractor.sh）：
  --min-lines N        最少需要的 track 行数（默认 2）
  --loop-last          最后一行视为 loop（默认）
  --no-loop-last       不处理最后一行 loop
EOF
}

# -----------------------------------------------------------------------------
# 参数解析
# -----------------------------------------------------------------------------
while (( $# > 0 )); do
  case "$1" in
    --out)
      shift
      [[ -n "${1:-}" ]] || {
        echo "❌ --out 需要一个目录参数" >&2
        exit 1
      }
      OUT_DIR="$1"
      ;;
    --force)
      FORCE_OVERWRITE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --min-lines)
      [[ -n "${2:-}" ]] || {
        echo "❌ --min-lines 需要一个参数" >&2
        exit 1
      }
      EXTRACTOR_OPTS+=( "$1" "$2" )
      shift 2
      continue
      ;;
    --loop-last|--no-loop-last)
      EXTRACTOR_OPTS+=( "$1" )
      shift
      continue
      ;;
    *)
      [[ -z "$INPUT" ]] || {
        echo "❌ 只允许一个输入参数" >&2
        exit 1
      }
      INPUT="$1"
      ;;
  esac
  shift || true
done

[[ -n "${INPUT:-}" ]] || { usage >&2; exit 1; }

# -----------------------------------------------------------------------------
# 依赖检查
# -----------------------------------------------------------------------------
command -v yt-dlp >/dev/null 2>&1 || {
  echo "❌ 缺少 yt-dlp" >&2
  exit 1
}

for f in "$EXTRACTOR" "$SANITIZER" "$YT_PARSE_ID"; do
  [[ -x "$f" ]] || {
    echo "❌ 缺少依赖脚本或无执行权限：$f" >&2
    exit 1
  }
done

# -----------------------------------------------------------------------------
# 定义变量
# -----------------------------------------------------------------------------
STATE_OK=0
STATE_NO_ID=1
STATE_EXISTS=2

INPUT_URL=1
INPUT_FILE=2
INPUT_DIR=3

INPUT_TYPE=0

# -----------------------------------------------------------------------------
# 判断输入类型（INPUT_TYPE）
# -----------------------------------------------------------------------------
is_url() {
  [[ "$1" =~ ^https?:// ]]
}

if is_url "$INPUT"; then
  INPUT_TYPE="$INPUT_URL"
elif [[ -f "$INPUT" ]]; then
  INPUT_TYPE="$INPUT_FILE"
elif [[ -d "$INPUT" ]]; then
  INPUT_TYPE="$INPUT_DIR"
else
  echo "❌ 无法识别的输入：$INPUT" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# 输出目录确定（基于 INPUT_TYPE）
# -----------------------------------------------------------------------------
if [[ -n "$OUT_DIR" ]]; then
  :
else
  case "$INPUT_TYPE" in
    "$INPUT_URL")
      OUT_DIR="$(pwd)/yt_tracklist"
      ;;
    "$INPUT_FILE")
      OUT_DIR="$(cd "$(dirname "$INPUT")" && pwd)/yt_tracklist"
      ;;
    "$INPUT_DIR")
      OUT_DIR="$(cd "$INPUT" && pwd)/yt_tracklist"
      ;;
  esac
fi

mkdir -p "$OUT_DIR"

# -----------------------------------------------------------------------------
# URL 列表构建
# -----------------------------------------------------------------------------
url_list=()

case "$INPUT_TYPE" in
  "$INPUT_URL")
    url_list+=( "$INPUT" )
    ;;
  "$INPUT_FILE")
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      url_list+=( "$line" )
    done < "$INPUT"
    ;;
  "$INPUT_DIR")
    while IFS= read -r media_file; do
      url="$("$GET_SOURCE" --youtube "$media_file" 2>/dev/null || true)"
      [[ -n "$url" ]] && url_list+=( "$url" )
    done < <("$DIR_FILES" "$INPUT" --type video)
    ;;
esac

# -----------------------------------------------------------------------------
# URL ID STATE 列表构建
# -----------------------------------------------------------------------------
url_ids=()
url_state=()

for url in "${url_list[@]}"; do
  if video_id="$("$YT_PARSE_ID" "$url")"; then
    url_ids+=( "$video_id" )
    url_state+=( "$STATE_OK" )
  else
    url_ids+=( "" )
    url_state+=( "$STATE_NO_ID" )
  fi
done

# -----------------------------------------------------------------------------
# tracklist 存在检查（非强制覆盖时，已存在则跳过）
# -----------------------------------------------------------------------------
if [[ "$FORCE_OVERWRITE" -eq 0 ]]; then
  for ((i=0; i<${#url_list[@]}; i++)); do
    [[ "${url_state[i]}" -eq "$STATE_OK" ]] || continue

    shopt -s nullglob
    matches=( "$OUT_DIR"/*\["${url_ids[i]}"\].tracklist.txt )
    shopt -u nullglob

    (( ${#matches[@]} > 0 )) && url_state[i]="$STATE_EXISTS"
  done
fi

# -----------------------------------------------------------------------------
# 主处理流程
# -----------------------------------------------------------------------------
total=${#url_list[@]}

for ((i=0; i<total; i++)); do
  url="${url_list[i]}"
  state="${url_state[i]}"
  video_id="${url_ids[i]}"

  echo
  echo "===== ($((i+1))/${total}) ====="
  
  case "$state" in
    "$STATE_NO_ID")
      echo "⚠ 跳过：$url"
      echo "⚠ 无法解析 YouTube video_id"
      continue
      ;;
    "$STATE_EXISTS")
      echo "⏭ 跳过：$url"
      echo "ℹ tracklist 已存在：[${video_id}]"
      continue
      ;;
    "$STATE_OK")
      echo "▶ 处理：$url"
      ;;
  esac

  title="$(yt-dlp --no-playlist --get-title "$url" 2>/dev/null | head -n 1 || echo "video")"
  title_safe="$("$SANITIZER" "$title")"
  outfile="$OUT_DIR/${title_safe} [${video_id}].tracklist.txt"

  tracklist="$("$EXTRACTOR" "${EXTRACTOR_OPTS[@]}" "$url" || true)"
  [[ -n "$tracklist" ]] || {
    echo "⚠ 未提取到 tracklist"
    continue
  }

  printf '%s\n' "$tracklist" > "$outfile"

  echo "✅ 已生成：$outfile"
done

echo
echo "✔ 操作完成"


