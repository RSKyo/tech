#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

############################################
# yt_rename_with_id.sh
# ---------------------
# 作用：
#   - 传入一个媒体文件路径；
#   - 调用 yt_get_source.sh 获取对应的 YouTube 视频 ID；
#   - 把文件重命名为：
#       原名（去掉 Downie 自动追加的时间戳） + 空格 + [ID].扩展名
#
# 用法：
#   yt_rename_with_id.sh <媒体文件路径>
#
# 说明：
#   - ID 由 yt_get_source.sh 提供（优先 Finder 的“来源”，其次媒体内部元数据）；
#   - 若文件名已以 [11位ID] 结尾，则不会重复添加；
#   - 若无法获取 ID，则该文件不重命名。
#
# 依赖：
#   yt_get_source.sh（需可执行，且在同一目录或 PATH 中）
############################################

# 找到 yt_get_source.sh：优先脚本同目录，其次 PATH
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YT_GET_SOURCE="$SCRIPT_DIR/yt_get_source.sh"

if [ ! -x "$YT_GET_SOURCE" ]; then
  if command -v yt_get_source.sh >/dev/null 2>&1; then
    YT_GET_SOURCE="yt_get_source.sh"
  else
    echo "错误：未找到 yt_get_source.sh，请确保它与本脚本在同一目录或在 PATH 中。" >&2
    exit 1
  fi
fi

usage() {
  cat <<'EOF'
用法：
  yt_rename_with_id.sh <媒体文件>

说明：
  - 调用 yt_get_source.sh 获取该文件的 YouTube 视频 ID；
  - 然后把文件重命名为：<清洗后的原名> [ID].扩展名；
  - 对 Downie 这种自动追加 " -  - 日期时间" 的情况，会把这一段去掉再加 [ID]。
EOF
}

[ $# -ge 1 ] || { usage; exit 1; }

TARGET="$1"

[ -f "$TARGET" ] || { echo "错误：找不到文件：$TARGET" >&2; exit 1; }

# ---------- 工具函数 ----------

# 去掉常见的 Downie 后缀：
#   " -  - 2025-11-05 04-40-50" 这一类
clean_downie_suffix() {
  local name="$1"
  # 如果包含 " -  - "，从这里开始全部裁掉
  if [[ "$name" == *" -  - "* ]]; then
    name="${name%% -  -*}"
  fi
  printf '%s\n' "$name"
}

# 实际处理单个文件
process_file() {
  local path="$1"

  local dir base ext name vid clean_name new_name new_path

  dir="$(dirname "$path")"
  base="${path##*/}"
  ext="${base##*.}"
  name="${base%.*}"

  echo "▶ 处理文件：$path"

  # 已经是 [...].扩展名 的就先简单判断一下，避免重复加
  if [[ "$name" =~ \[[A-Za-z0-9_-]{11}\]$ ]]; then
    echo "  ✓ 文件名已包含 [ID]，跳过重命名。"
    return 0
  fi

  # 调用 yt_get_source.sh 获取 ID
  if ! vid="$("$YT_GET_SOURCE" "$path" --id 2>/dev/null || true)"; then
    vid=""
  fi

  if [ -z "$vid" ]; then
    echo "  ⚠ 无法通过 yt_get_source.sh 获取 YouTube ID，跳过。"
    return 0
  fi

  # 去掉 Downie 特有的 " -  - 时间" 后缀
  clean_name="$(clean_downie_suffix "$name")"

  new_name="${clean_name} [${vid}].${ext}"
  new_path="${dir}/${new_name}"

  # 如果新名字和旧名字一样，就不动
  if [ "$new_path" = "$path" ]; then
    echo "  ✓ 已是目标命名：$new_name"
    return 0
  fi

  # 若目标文件已存在，提示后跳过（默认不覆盖）
  if [ -e "$new_path" ]; then
    echo "  ⚠ 目标文件已存在：$new_path"
    echo "     为避免覆盖，跳过当前文件。"
    return 0
  fi

  echo "  → 重命名为：$new_name"
  mv -- "$path" "$new_path"
}

# ---------- 主逻辑 ----------
process_file "$TARGET"

echo "✅ 处理完成。"
