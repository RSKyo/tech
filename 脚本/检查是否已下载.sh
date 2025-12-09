#!/bin/sh

# ============================================================
# 检查是否已下载.sh（最终稳定版）
#
# 用法：
#   ./检查是否已下载.sh <mp3目录> <download_list.txt>
#
# list.txt 格式：
#   URL<TAB>标题
# ============================================================

if [ $# -ne 2 ]; then
  echo "Usage: $0 <mp3目录> <download_list.txt>"
  exit 1
fi

MP3_DIR="$1"
LIST_FILE="$2"

LIST_DIR="$(cd "$(dirname "$LIST_FILE")" && pwd)"
DOWNLOADED="$LIST_DIR/downloaded.txt"
MISSING="$LIST_DIR/missing.txt"

TMP_RAW="$(mktemp)"
TMP_KEYS="$(mktemp)"

: > "$DOWNLOADED"
: > "$MISSING"
: > "$TMP_RAW"
: > "$TMP_KEYS"

# ---------- 规范化 ----------
normalize() {
  echo "$1" \
    | tr -d '[:space:]' \
    | sed 's/[[:punct:]]//g'
}

echo "✅ 扫描 mp3 文件（一次性）..."

# ---------- ① 先把 mp3 列表落盘 ----------
find "$MP3_DIR" -maxdepth 1 -type f -iname "*.mp3" ! -name "._*" > "$TMP_RAW"

MP3_COUNT="$(wc -l < "$TMP_RAW" | tr -d ' ')"

if [ "$MP3_COUNT" -eq 0 ]; then
  echo "❌ 未发现 mp3 文件"
  rm -f "$TMP_RAW" "$TMP_KEYS"
  exit 1
fi

echo "✅ 发现 mp3 文件：$MP3_COUNT"

# ---------- ② 构建 mp3“规范化 key 集合” ----------
while read -r f; do
  base="$(basename "$f" .mp3)"
  normalize "$base" >> "$TMP_KEYS"
done < "$TMP_RAW"

# ---------- ③ 比对 list.txt ----------
TOTAL=0
FOUND=0
MISS=0

echo "✅ 开始比对 list.txt（高效模式）..."
echo "--------------------------------"

while IFS=$'\t' read -r url title; do
  [ -z "$url" ] && continue
  TOTAL=$((TOTAL + 1))

  key="$(normalize "$title")"

  if grep -Fq "$key" "$TMP_KEYS"; then
    printf "%s\t%s\n" "$url" "$title" >> "$DOWNLOADED"
    FOUND=$((FOUND + 1))
  else
    printf "%s\t%s\n" "$url" "$title" >> "$MISSING"
    MISS=$((MISS + 1))
  fi

done < "$LIST_FILE"

rm -f "$TMP_RAW" "$TMP_KEYS"

echo "--------------------------------"
echo "✅ list 总数 : $TOTAL"
echo "✅ 已下载   : $FOUND"
echo "✅ 未下载   : $MISS"
echo "输出文件："
echo "  $DOWNLOADED"
echo "  $MISSING"
