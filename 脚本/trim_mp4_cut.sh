#!/bin/bash
#
# 批量截断 mp4：
#   - 截掉「开头 N 秒」或「末尾 N 秒」
#   - 输出到 目标目录/output 下，文件名与原文件一致
#
# 用法：
#   ./trim_mp4_cut.sh [目录] [mode] [seconds]
#
# 示例：
#   1) 截掉末尾 3 秒：
#      ./trim_mp4_cut.sh /path/to/dir end 3
#
#   2) 截掉开头 5 秒：
#      ./trim_mp4_cut.sh /path/to/dir start 5
#
# mode 可选：
#   start / head  → 截掉开头 N 秒
#   end   / tail  → 截掉末尾 N 秒

set -e

# ------- 参数解析 -------

DIR="${1:-.}"
MODE="$2"
CUT_SEC="$3"

usage() {
  echo "用法：$0 [目录] [mode] [seconds]"
  echo
  echo "  目录   ：要处理的目录（默认当前目录 .）"
  echo "  mode  ：start/head = 截掉开头 N 秒；end/tail = 截掉末尾 N 秒"
  echo "  seconds：要截断的秒数（可带小数）"
  echo
  echo "示例："
  echo "  截掉末尾 3 秒：   $0 /path/to/dir end 3"
  echo "  截掉开头 5 秒：   $0 /path/to/dir start 5"
}

if [ -z "$MODE" ] || [ -z "$CUT_SEC" ]; then
  usage
  exit 1
fi

case "$MODE" in
  start|head)
    MODE="start"
    ;;
  end|tail)
    MODE="end"
    ;;
  *)
    echo "错误：未知 mode：$MODE"
    usage
    exit 1
    ;;
esac

# seconds > 0 ?
if ! awk "BEGIN { exit !($CUT_SEC > 0) }"; then
  echo "错误：seconds 必须是 > 0 的数字：$CUT_SEC"
  exit 1
fi

# ------- 环境检查 -------

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "错误：未找到 ffmpeg，请先安装（例如：brew install ffmpeg）"
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "错误：未找到 ffprobe，请先安装（通常跟 ffmpeg 一起装）"
  exit 1
fi

if [ ! -d "$DIR" ]; then
  echo "错误：目录不存在：$DIR"
  exit 1
fi

OUT_DIR="$DIR/output"
mkdir -p "$OUT_DIR"

echo "目标目录：$DIR"
echo "输出目录：$OUT_DIR"
echo "截断模式：$MODE"
echo "截断秒数：$CUT_SEC"
echo

# ------- 主循环：遍历 mp4 文件（不递归子目录） -------

find "$DIR" -maxdepth 1 -type f \( -iname '*.mp4' \) -print0 | \
while IFS= read -r -d '' file; do
  echo "处理文件：$file"

  duration=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$file") || {
      echo "  无法获取时长，跳过。"
      echo
      continue
    }

  if ! awk "BEGIN { exit !($duration > 0) }"; then
    echo "  时长异常（$duration），跳过。"
    echo
    continue
  fi

  filename="$(basename "$file")"
  out="${OUT_DIR}/${filename}"

  echo "  原始时长：$duration 秒"

  if [ "$MODE" = "end" ]; then
    # 截掉末尾 N 秒
    new_duration=$(awk -v d="$duration" -v c="$CUT_SEC" 'BEGIN {
      t = d - c;
      if (t < 0.1) t = 0.1;
      printf "%.3f\n", t;
    }')

    echo "  保留时长：$new_duration 秒（从 0 开始到这里）"
    echo "  输出文件：$out"

    ffmpeg -y -i "$file" -t "$new_duration" -c copy "$out"

  else
    # 截掉开头 N 秒
    start_time=$(awk -v d="$duration" -v c="$CUT_SEC" 'BEGIN {
      s = c;
      if (s >= d) s = d - 0.1;
      if (s < 0) s = 0;
      printf "%.3f\n", s;
    }')

    remain=$(awk -v d="$duration" -v s="$start_time" 'BEGIN {
      t = d - s;
      if (t < 0.1) t = 0.1;
      printf "%.3f\n", t;
    }')

    echo "  从 ${start_time} 秒开始保留，时长约：$remain 秒"
    echo "  输出文件：$out"

    ffmpeg -y -ss "$start_time" -i "$file" -c copy "$out"
  fi

  echo "  ✅ 完成"
  echo
done

echo "全部处理完成。"
