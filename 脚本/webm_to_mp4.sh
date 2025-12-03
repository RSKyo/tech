#!/usr/bin/env bash
# 用法：
#   webm2mp4.sh <input.webm>
#
# 把指定的 webm 文件转成同名 mp4（不覆盖已有 mp4）

# 1. 参数检查
if [ "$#" -ne 1 ]; then
  echo "用法：$0 <input.webm>"
  exit 1
fi

input="$1"

# 2. 检查文件是否存在
if [ ! -f "$input" ]; then
  echo "找不到文件：$input"
  exit 1
fi

# 3. 简单检查扩展名（只是提醒，不强制）
ext="${input##*.}"
if [ "$ext" != "webm" ]; then
  echo "警告：传入的文件扩展名不是 .webm（实际是 .$ext），继续尝试转换……"
fi

# 4. 生成输出文件名：同路径同名，扩展名改为 .mp4
output="${input%.*}.mp4"

# 若目标已存在，为安全起见不覆盖
if [ -e "$output" ]; then
  echo "目标文件已存在：$output"
  echo "为了安全，脚本不会覆盖已有文件。"
  exit 1
fi

# 5. 检查 ffmpeg
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "未找到 ffmpeg，请先安装 ffmpeg 再运行。"
  exit 1
fi

echo "开始转换："
echo "  输入：$input"
echo "  输出：$output"

# 6. 转码：H.264 + AAC，兼容性比较好
ffmpeg -i "$input" \
  -c:v libx264 -preset medium -crf 20 \
  -c:a aac -b:a 192k \
  -movflags +faststart \
  "$output"

if [ "$?" -eq 0 ]; then
  echo "✅ 转换完成：$output"
else
  echo "❌ 转换失败。"
  exit 1
fi
