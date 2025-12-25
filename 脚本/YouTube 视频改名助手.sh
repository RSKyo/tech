#!/usr/bin/env bash
IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# yt_rename_media.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DIR_FILES="$SCRIPT_DIR/dir_files.sh"
GET_SOURCE="$SCRIPT_DIR/get_source_url.sh"
YT_PARSE_ID="$SCRIPT_DIR/yt_parse_id.sh"
SANITIZER="$SCRIPT_DIR/sanitize_filename.sh"

# -----------------------------------------------------------------------------
# 参数
# -----------------------------------------------------------------------------
INPUT=""
OFFLINE=0
RECURSIVE=0
TYPE="media"

usage() {
  cat <<EOF
用法：
  $0 <file|directory> [options]

选项：
  --offline        不联网获取 title
  --recursive      递归扫描目录
  --type media     dir_files.sh 的 --type（默认 media）
EOF
}

# -----------------------------------------------------------------------------
# 参数解析
# -----------------------------------------------------------------------------
while (( $# > 0 )); do
  case "$1" in
    --offline) OFFLINE=1 ;;
    --recursive) RECURSIVE=1 ;;
    --type) shift; TYPE="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "❌ 未知参数：$1" >&2
      exit 1 ;;
    *)
      [[ -z "$INPUT" ]] || { echo "❌ 只允许一个输入参数" >&2; exit 1; }
      INPUT="$1"
      ;;
  esac
  shift || true
done

[[ -n "$INPUT" ]] || { usage >&2; exit 1; }

# -----------------------------------------------------------------------------
# INPUT_TYPE
# -----------------------------------------------------------------------------
INPUT_FILE=1
INPUT_DIR=2
INPUT_TYPE=0

if [[ -f "$INPUT" ]]; then
  INPUT_TYPE="$INPUT_FILE"
elif [[ -d "$INPUT" ]]; then
  INPUT_TYPE="$INPUT_DIR"
else
  echo "❌ 无法识别的输入：$INPUT" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# 状态定义
# -----------------------------------------------------------------------------
STATE_OK=0
STATE_HAS_ID=1

# -----------------------------------------------------------------------------
# 数据基座
# -----------------------------------------------------------------------------
files=()
filenames=()
exts=()
urls=()
ids=()
states=()

# -----------------------------------------------------------------------------
# 工具函数
# -----------------------------------------------------------------------------
add_file() {
  local file="$1" base name ext dir

  dir="$(cd "$(dirname "$file")" && pwd)"
  base="$(basename "$file")"
  name="${base%.*}"
  ext="${base##*.}"

  files+=( "$dir/$base" )
  filenames+=( "$name" )
  exts+=( "$ext" )
  states+=( "$STATE_OK" )
}

# -----------------------------------------------------------------------------
# 文件枚举
# -----------------------------------------------------------------------------
case "$INPUT_TYPE" in
  "$INPUT_FILE")
    add_file "$INPUT"
    ;;
  "$INPUT_DIR")
    cmd=( "$DIR_FILES" "$INPUT" "--type" "$TYPE" )
    [[ "$RECURSIVE" -eq 1 ]] && cmd+=( "--recursive" )

    while IFS= read -r f; do
      add_file "$f"
    done < <("${cmd[@]}")
    ;;
esac

# -----------------------------------------------------------------------------
# URL / ID 构建 + state 修正
# -----------------------------------------------------------------------------
for ((i=0; i<${#files[@]}; i++)); do
  file="${files[i]}"
  base="$(basename "$file")"
  ext="${exts[i]}"

  url="$("$GET_SOURCE" --youtube "$file" 2>/dev/null || true)"
  urls+=( "$url" )

  id=""
  if [[ -n "$url" ]]; then
    id="$("$YT_PARSE_ID" "$url" 2>/dev/null || true)"
    ids+=( "$id" )
  else
    ids+=( "" )
  fi

  # 仅当文件名明确包含：[id].ext → 标记为已处理
  if [[ -n "$id" && "$base" == *"[$id].$ext" ]]; then
    states[i]="$STATE_HAS_ID"
  fi
done

maybe_fetch_online_title() {
  local idx="$1"
  local url title

  [[ "$OFFLINE" -eq 1 ]] && return
  [[ "${states[idx]}" -ne "$STATE_OK" ]] && return

  url="${urls[idx]}"
  [[ -n "$url" ]] || return

  echo "⏳ 获取在线标题…"
  title="$(yt-dlp --no-playlist --get-title "$url" 2>/dev/null | head -n 1 || true)"

  if [[ -n "$title" ]]; then
    filenames[idx]="$title"
  else
    echo "⚠ 未获取到在线标题，使用本地文件名"
  fi
}

# -----------------------------------------------------------------------------
# rename（仅区分 STATE_HAS_ID，其余一律修改）
# -----------------------------------------------------------------------------
total=${#files[@]}

for ((i=0; i<total; i++)); do
  file="${files[i]}"
  base="$(basename "$file")"
  dir="$(dirname "$file")"
  ext="${exts[i]}"
  id="${ids[i]}"
  state="${states[i]}"

  echo
  echo "===== ($((i+1))/${total}) ====="

  # 已包含 [id].ext → 仅提示，不修改
  if [[ "$state" -eq "$STATE_HAS_ID" ]]; then
    echo "⏭ 跳过：$base"
    echo "ℹ 已包含 [${id}].${ext}"
    continue
  fi

  # 👉 这里：逐条获取在线 title（如果需要）
  maybe_fetch_online_title "$i"
  title="${filenames[i]}"

  # 其余情况：一定执行改名
  title_safe="$("$SANITIZER" "$title")"
  
  if [[ -n "$id" ]]; then
    new_name="${title_safe} [${id}].${ext}"
  else
    new_name="${title_safe}.${ext}"
  fi

  echo "▶ 重命名：$base"
  echo "→ $new_name"

  mv -n "$file" "$dir/$new_name"
done

echo
echo "✔ 重命名完成"
