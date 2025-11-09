#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

############################################
# YouTube 视频改名助手
# --------------------
# 用途：
#   - 传入一个视频文件或目录；
#   - 使用 media_list.sh 列出其中所有「视频文件」；
#   - 对每个视频调用 yt_rename_with_id.sh：
#       将文件重命名为：
#         原名（去掉 Downie 自动追加的时间戳） + 空格 + [ID].扩展名
#
# 前置脚本（需已存在且可执行）：
#   - media_list.sh         列出视频/音频文件（仅视频即可）
#   - yt_rename_with_id.sh  对单个文件添加 [ID] 的重命名脚本
#
# 用法：
#   "YouTube 视频改名助手.sh" <文件或目录>
#
# 说明：
#   - 若传入的是单个视频文件，也会通过 media_list.sh 统一处理；
#   - 若目录中包含多种类型文件，只会对视频扩展名的文件进行重命名；
#   - 若某个文件本身已带 [ID]，yt_rename_with_id.sh 会跳过，不重复添加。
############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
用法：
  YouTube 视频改名助手.sh <视频文件或目录>

说明：
  - 使用 media_list.sh 列出目标中的所有视频文件；
  - 对每个视频调用 yt_rename_with_id.sh，根据 YouTube ID 改名；
  - 若已经包含 [ID]，则不会重复改名。
EOF
}

[ $# -ge 1 ] || { usage; exit 1; }

TARGET="$1"

# ---------- 找到 media_list.sh ----------
MEDIA_LIST="$SCRIPT_DIR/media_list.sh"
if [ ! -x "$MEDIA_LIST" ]; then
  if command -v media_list.sh >/dev/null 2>&1; then
    MEDIA_LIST="media_list.sh"
  else
    echo "错误：未找到 media_list.sh，请确认它与本脚本在同一目录或已加入 PATH。" >&2
    exit 1
  fi
fi

# ---------- 找到 yt_rename_with_id.sh ----------
YT_RENAME="$SCRIPT_DIR/yt_rename_with_id.sh"
if [ ! -x "$YT_RENAME" ]; then
  if command -v yt_rename_with_id.sh >/dev/null 2>&1; then
    YT_RENAME="yt_rename_with_id.sh"
  else
    echo "错误：未找到 yt_rename_with_id.sh，请确认它与本脚本在同一目录或已加入 PATH。" >&2
    exit 1
  fi
fi

# ---------- 检查目标 ----------
if [ ! -e "$TARGET" ]; then
  echo "错误：找不到路径：$TARGET" >&2
  exit 1
fi

echo "📂 目标：$TARGET"
echo "🔎 使用：$MEDIA_LIST 列出视频文件"
echo "✏️  使用：$YT_RENAME 为每个视频添加 [ID]"
echo

# ---------- 列出所有视频文件 ----------
# media_list.sh 默认 --type video
mapfile -t FILES < <("$MEDIA_LIST" "$TARGET" --type video 2>/dev/null || true)

TOTAL=${#FILES[@]}
if [ "$TOTAL" -eq 0 ]; then
  echo "⚠️ 未在目标中找到任何视频文件。"
  exit 0
fi

echo "共找到 $TOTAL 个视频文件。"
echo

# ---------- 逐个重命名 ----------
idx=0
for f in "${FILES[@]}"; do
  idx=$((idx+1))
  echo "▶ ${idx}/${TOTAL} 正在处理：$f"
  # 调用单文件改名助手，内部会判断是否已带 [ID]
  "$YT_RENAME" "$f"
  echo
done

echo "✅ 全部处理完成。"
