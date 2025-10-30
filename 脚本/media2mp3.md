```bash
#!/usr/bin/env bash

# =============================================================================

# media2mp3.sh — 智能媒体转 MP3 + 自动分轨工具

# -----------------------------------------------------------------------------

# 功能简介：

# - 若存在同名清单 <源文件>.txt → 按清单分轨输出 MP3；

# - 若不存在清单 → 直接将媒体转 MP3（可选从第 N 秒截帧为封面）；

# - 支持单文件或目录（非递归）批量处理；

# - 同名严格策略：默认跳过，--force 才覆盖，不生成 _2/_3。

#

# 输出规则：

# - 未指定 --out：分轨输出到同名目录（把文件名里的 . 替换为 _）；转换输出到源目录；

# - 指定 --out DIR：所有结果直接输出到 DIR（不再建同名子目录）。

#

# 清单格式（UTF-8 无 BOM；标题中出现 Repeat/Replay 时停止）：

# 00:00 标题 / 艺术家

# 00:00 - 标题 / 艺术家

# （艺术家可省略；两种格式都可混用）

#

# 依赖：ffmpeg、ffprobe （macOS 可：brew install ffmpeg）

#

# 常用示例：

# 单文件（有清单则分轨，无清单则转 MP3）：

# ./media2mp3.sh "/path/a.mp4"

# 转 MP3 并截取第 3 秒为封面：

# ./media2mp3.sh "/path/a.mp4" --thumb-sec 3

# 批量处理目录并统一输出：

# ./media2mp3.sh "/path/media" --out "output" --force

# 分轨使用精确切（重编码）：

# ./media2mp3.sh "/path/a.webm" --reencode

# =============================================================================

  

set -Eeuo pipefail

IFS=$'\n\t'

  

# ---------- 依赖 ----------

need() { command -v "$1" >/dev/null 2>&1 || { echo "错误：需要 $1，请先安装"; exit 1; }; }

need ffmpeg

need ffprobe

  

# ---------- 全局选项（仅作为默认值） ----------

ARTIST_DEFAULT=""

GENRE_DEFAULT=""

OUT_DIR_OVERRIDE="" # --out DIR

THUMB_SEC="" # 仅“无清单转换”时生效；空=不截帧

REENCODE=0 # 分轨时精确切

FORCE=0 # 同名覆盖

  

# ---------- 参数解析 ----------

usage() {

cat <<'EOF'

用法：

media2mp3.sh <文件或目录> [--out DIR] [--thumb-sec N] [--artist A] [--album ALB] [--year Y] [--genre G] [--comment C] [--reencode] [--force]

  

说明：

- 若 <源文件>.txt 存在 → 分轨；否则 → 转为 MP3。

- --out DIR：统一输出目录；未指定时，分轨到同名目录、转换到源目录。

- --thumb-sec N：仅在“无清单转换”时，从第 N 秒截帧作为封面。

- 分轨同名或磁盘已存在同名：默认跳过；--force 才覆盖。

  

示例：

./media2mp3.sh "/path/a.mp4"

./media2mp3.sh "/path/a.mp4" --thumb-sec 3

./media2mp3.sh "/path/media" --out "output" --force

./media2mp3.sh "/path/a.webm" --reencode

EOF

}

  

[ $# -ge 1 ] || { usage; exit 1; }

TARGET="$1"; shift

  

ARTIST_PARAM=""; ALBUM_PARAM=""; YEAR_PARAM=""; GENRE_PARAM=""; COMMENT_PARAM=""

while [ $# -gt 0 ]; do

case "$1" in

--out) shift; OUT_DIR_OVERRIDE="${1:-output}" ;;

--thumb-sec) shift; [[ "${1:-}" =~ ^[0-9]+$ ]] || { echo "错误：--thumb-sec 需整数秒"; exit 1; }; THUMB_SEC="$1" ;;

--artist) shift; ARTIST_PARAM="${1:-}" ;;

--album) shift; ALBUM_PARAM="${1:-}" ;;

--year) shift; YEAR_PARAM="${1:-}" ;;

--genre) shift; GENRE_PARAM="${1:-}" ;;

--comment) shift; COMMENT_PARAM="${1:-}" ;;

--reencode) REENCODE=1 ;;

--force) FORCE=1 ;;

-h|--help) usage; exit 0 ;;

*) echo "未知参数：$1"; exit 1 ;;

esac

shift || true

done

  

[ -e "$TARGET" ] || { echo "错误：找不到路径：$TARGET"; exit 1; }

  

# ---------- 工具函数 ----------

to_seconds() {

local t="$1"; IFS=':' read -r -a a <<< "$t"

if [ "${#a[@]}" -eq 3 ]; then echo $((10#${a[0]}*3600 + 10#${a[1]}*60 + 10#${a[2]}))

elif [ "${#a[@]}" -eq 2 ]; then echo $((10#${a[0]}*60 + 10#${a[1]}))

else echo 0; fi

}

sanitize() {

local s="$1"

s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"

s="${s//\//-}"; s="${s//\\/-}"; s="${s//:/-}"

s="${s//\*/-}"; s="${s//\?/-}"; s="${s//\"/-}"

s="${s//</(}"; s="${s//>/(}"; s="${s//|/-}"

echo "$s"

}

normalize_cue() {

# 归一化清单（去 BOM、CRLF）

local in="$1" out tmp

out="$(mktemp)"

if LC_ALL=C grep -q $'^\xEF\xBB\xBF' "$in"; then

tail -c +4 "$in" > "$out"

else

cat "$in" > "$out"

fi

if LC_ALL=C grep -q $'\r' "$out"; then

tmp="$(mktemp)"; tr -d '\r' < "$out" > "$tmp"; mv "$tmp" "$out"

fi

echo "$out"

}

get_audio_codec() {

ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nk=1:nw=1 "$1" 2>/dev/null || true

}

get_tag() {

# get_tag <key> <src>

local key="$1" src="$2" val=""

val=$(ffprobe -v error -show_entries format_tags="$key" -of default=nk=1:nw=1 "$src" 2>/dev/null || true)

[ -n "$val" ] || val=$(ffprobe -v error -select_streams a:0 -show_entries stream_tags="$key" -of default=nk=1:nw=1 "$src" 2>/dev/null || true)

printf '%s' "$val"

}

first_url() { sed -nE 's/.*((https?:\/\/)[^"'\''[:space:]]+).*/\1/p' | head -n1; }

  

resolve_out_dir() {

# resolve_out_dir <src> <mode: split|convert>

local src="$1" mode="$2"

local src_dir src_name out_basename out

src_dir="$(cd "$(dirname "$src")" && pwd)"

src_name="${src##*/}"

out_basename="${src_name//./_}"

if [ -n "$OUT_DIR_OVERRIDE" ]; then

if [[ "$OUT_DIR_OVERRIDE" = /* ]]; then out="$OUT_DIR_OVERRIDE"; else out="$src_dir/$OUT_DIR_OVERRIDE"; fi

else

if [ "$mode" = "split" ]; then out="$src_dir/$out_basename"; else out="$src_dir"; fi

fi

mkdir -p "$out"

printf '%s' "$out"

}

  

# ---------- 分轨 ----------

split_by_cue() {

# split_by_cue <src>

local src="$1"

local cue="${src}.txt"

[ -f "$cue" ] || return 2 # 无清单 → 交给转换路径

  

# 总时长

local dur_total

dur_total=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src" | awk '{printf("%.0f",$1)}') || true

[[ "$dur_total" =~ ^[0-9]+$ ]] || { echo "错误：无法获取时长：$src"; return 1; }

  

# 源编解码：非 mp3 自动启用重编码

local reenc="$REENCODE" acodec

acodec="$(get_audio_codec "$src")"

case "$acodec" in mp3|mp3float) : ;;

*) [ "$reenc" -eq 0 ] && { echo "提示：检测到 '$acodec'，自动启用重编码输出 MP3"; reenc=1; } ;;

esac

  

# comment 来源合并

local SRC_ORIGIN="" v

for k in purl comment description source; do

v="$(get_tag "$k" "$src")"

[ -n "$v" ] && { SRC_ORIGIN="$v"; break; }

done

if [ -z "$SRC_ORIGIN" ] && command -v mdls >/dev/null 2>&1; then

WF="$(mdls -raw -name kMDItemWhereFroms "$src" 2>/dev/null || true)"

SRC_ORIGIN="$(printf '%s\n' "$WF" | first_url)"

fi

if [ -z "$SRC_ORIGIN" ]; then

local info_json="${src%.*}.info.json"

if [ -f "$info_json" ]; then

if command -v jq >/dev/null 2>&1; then

SRC_ORIGIN="$(jq -r '(.webpage_url // .original_url // .purl // .upload_webpage_url // empty)' "$info_json" 2>/dev/null || true)"

else

SRC_ORIGIN="$(grep -Eo '"webpage_url"[[:space:]]*:[[:space:]]*"[^"]+"' "$info_json" \

| sed -E 's/.*"webpage_url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -n1)"

[ -z "$SRC_ORIGIN" ] && SRC_ORIGIN="$(grep -Eo '"original_url"[[:space:]]*:[[:space:]]*"[^"]+"' "$info_json" \

| sed -E 's/.*"original_url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -n1)"

fi

fi

fi

if [ -z "$SRC_ORIGIN" ]; then

CHAP_JSON="$(ffprobe -v error -print_format json -show_chapters "$src" 2>/dev/null || true)"

SRC_ORIGIN="$(printf '%s' "$CHAP_JSON" | first_url)"

fi

if [ -z "$SRC_ORIGIN" ]; then

DESC="$(get_tag description "$src")"

SRC_ORIGIN="$(printf '%s' "$DESC" | first_url)"

fi

[ -n "$SRC_ORIGIN" ] && SRC_ORIGIN="$(printf '%s' "$SRC_ORIGIN" | awk '{$1=$1; print}')"

  

local COMMENT_EFF="$COMMENT_PARAM"

if [ -z "$COMMENT_EFF" ] && [ -n "$SRC_ORIGIN" ]; then

COMMENT_EFF="$SRC_ORIGIN"

elif [ -n "$COMMENT_EFF" ] && [ -n "$SRC_ORIGIN" ] && [[ "$COMMENT_EFF" != *"$SRC_ORIGIN"* ]]; then

COMMENT_EFF="${COMMENT_EFF} | ${SRC_ORIGIN}"

fi

  

# 读取清单

local cue_norm STARTS_T=() TITLES=() ARTISTS_LINE=() REPEAT_AT="" line_no=0

cue_norm="$(normalize_cue "$cue")"

while IFS= read -r line || [ -n "$line" ]; do

line_no=$((line_no+1))

[[ -z "${line// }" ]] && continue

[[ "$line" =~ ^[[:space:]]*# ]] && continue

  

# 归一化

local ts="" rest="" title="" artist="" line_norm

line_norm="$(printf '%s' "$line" | sed $'s/\xef\xbc\x9a/:/g; s/\xc2\xa0/ /g; s/\xe3\x80\x80/ /g')"

line_norm="${line_norm//$'\t'/ }"

line_norm="${line_norm#"${line_norm%%[![:space:]]*}"}"

line_norm="${line_norm%"${line_norm##*[![:space:]]}"}"

  

if [[ "$line_norm" =~ ^([0-9]{1,2}:[0-9]{2}(:[0-9]{2})?)[[:space:]]+(.+)$ ]]; then

ts="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[3]}"

else

echo "错误：清单格式不符（第 $line_no 行）：$line"

echo "示例：03:11 标题 / 艺术家 或 03:11 - 标题 / 艺术家"

rm -f "$cue_norm"; return 1

fi

  

# 可选连字符 " - "

if [[ "$rest" =~ ^[-–—][[:space:]]*(.+)$ ]]; then

rest="${BASH_REMATCH[1]}"

fi

  

title="$rest"

if [[ "$rest" == *" / "* ]]; then

title="${rest%%" / "*}"

artist="${rest#*" / "}"

fi

  

local ts_sec title_lc

ts_sec="$(to_seconds "$ts")"

title_lc="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')"

if [[ "$title_lc" == *repeat* || "$title_lc" == *replay* ]]; then

REPEAT_AT="$ts_sec"; echo "终止标记：$ts $title"; break

fi

  

STARTS_T+=( "$ts_sec" ); TITLES+=( "$title" ); ARTISTS_LINE+=( "$artist" )

done < "$cue_norm"

rm -f "$cue_norm"

  

local N="${#STARTS_T[@]}"

[ "$N" -gt 0 ] || { echo "错误：清单为空或被终止/注释清空：$cue"; return 1; }

  

# 输出目录

local OUT_DIR; OUT_DIR="$(resolve_out_dir "$src" "split")"

echo "分轨：$src"

echo "输出目录：$OUT_DIR"

echo

  

# 切分

local USED_NAMES=() ok=0 fail=0

local dur_end_total="${REPEAT_AT:-$dur_total}"

  

for ((i=0;i<N;i++)); do

local start="${STARTS_T[$i]}"

local next="${STARTS_T[$((i+1))]:-$dur_end_total}"

[ "$next" -gt "$dur_end_total" ] && next="$dur_end_total"

if [ "$next" -le "$start" ]; then

echo " 时间异常：$start → $next，跳过"; echo; continue

fi

  

local raw_title="${TITLES[$i]}"

local artist_line="${ARTISTS_LINE[$i]}"

  

local artist_eff

if [ -n "$artist_line" ]; then artist_eff="$artist_line"

elif [ -n "$ARTIST_PARAM" ]; then artist_eff="$ARTIST_PARAM"

else artist_eff="$ARTIST_DEFAULT"; fi

  

local base clean out dur

clean="$(sanitize "$raw_title")"

base="${clean:-Track_$((i+1))}"

out="$OUT_DIR/${base}.mp3"

  

echo " [$((i+1))/$N] $raw_title / $artist_eff (${start}s → ${next}s)"

  

# 清单内重复：默认跳过，--force 覆盖上一条（严格不追加 _2/_3）

local seen=0 idx

for ((idx=0; idx<${#USED_NAMES[@]}; idx++)); do [ "$base" = "${USED_NAMES[$idx]}" ] && { seen=1; break; }; done

if [ "$seen" -eq 1 ]; then

if [ "$FORCE" -eq 0 ]; then

echo " 已出现同名（本次清单内），跳过（--force 可覆盖）"; echo; continue

else

echo " --force：覆盖上一条同名"; rm -f "$out" 2>/dev/null || true

fi

fi

USED_NAMES+=( "$base" )

  

# 磁盘已存在：默认跳过；--force 覆盖

if [ -e "$out" ]; then

if [ "$FORCE" -eq 0 ]; then

echo " 目标已存在，跳过：$out"; echo; continue

else

echo " --force：覆盖目标：$out"; rm -f "$out"

fi

fi

  

dur=$(( next - start ))

local seek_opts=() enc=() map_opts=() meta=()

if [ "$reenc" -eq 1 ]; then

seek_opts=(-i "$src" -ss "$start" -to "$next")

enc=(-c:a libmp3lame -q:a 2)

else

seek_opts=(-ss "$start" -t "$dur" -i "$src")

enc=(-c copy)

fi

  

# 是否复制封面（仅无损拷贝有意义；默认关闭）

local KEEP_ART="${KEEP_ART:-0}"

if [ "$KEEP_ART" -eq 1 ] && [ "$reenc" -eq 0 ]; then

map_opts=(-map 0:a -map 0:v? -c:v copy -disposition:v attached_pic)

else

map_opts=(-map a)

fi

  

meta=(-id3v2_version 3 -write_id3v2 1 -metadata "title=$raw_title" -metadata "artist=$artist_eff")

[ -n "$ALBUM_PARAM" ] && meta+=(-metadata "album=$ALBUM_PARAM")

[ -n "$YEAR_PARAM" ] && meta+=(-metadata "date=$YEAR_PARAM")

if [ -n "$GENRE_PARAM" ]; then

meta+=(-metadata "genre=$GENRE_PARAM")

elif [ -n "$GENRE_DEFAULT" ]; then

meta+=(-metadata "genre=$GENRE_DEFAULT")

fi

[ -n "$COMMENT_EFF" ] && meta+=(-metadata "comment=$COMMENT_EFF")

meta+=(-metadata "track=$((i+1))/$N")

[ -n "$ARTIST_PARAM" ] && meta+=(-metadata "album_artist=$ARTIST_PARAM")

  

if ffmpeg -hide_banner -loglevel error -y \

"${seek_opts[@]}" -avoid_negative_ts make_zero \

"${map_opts[@]}" "${enc[@]}" "${meta[@]}" \

"$out"

then

echo " 成功：$out"; ok=$((ok+1))

else

echo " 失败：$out"; fail=$((fail+1))

fi

echo

done

  

echo "分轨完成：成功 $ok，失败 ${fail:-0}"

return 0

}

  

# ---------- 转 MP3（无清单） ----------

convert_to_mp3() {

# convert_to_mp3 <src>

local src="$1"

  

# 若本身是 mp3，默认不再转（避免二次有损）

case "${src##*.}" in mp3|MP3)

echo "源已为 MP3，默认跳过：$src"; echo; return 0 ;;

esac

  

local OUT_DIR; OUT_DIR="$(resolve_out_dir "$src" "convert")"

local src_name base out

src_name="${src##*/}"

base="${src_name%.*}"

out="$OUT_DIR/$(sanitize "$base").mp3"

  

echo "转换为 MP3：$src"

echo "输出目录：$OUT_DIR"

  

if [ -e "$out" ]; then

if [ "$FORCE" -eq 0 ]; then

echo " 目标已存在，跳过：$out"; echo; return 0

else

echo " --force：覆盖目标：$out"; rm -f "$out"

fi

fi

  

# 是否有视频流（只有视频且指定了 --thumb-sec 才截帧）

local has_video=0 cover=""

if ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$src" >/dev/null 2>&1; then

has_video=1

fi

  

if [ -n "$THUMB_SEC" ] && [ "$has_video" -eq 1 ]; then

cover="$(mktemp -t cover_XXXXXX).jpg"

echo " 截取第 ${THUMB_SEC} 秒画面作为封面"

if ! ffmpeg -hide_banner -loglevel error -ss "$THUMB_SEC" -i "$src" -vframes 1 -q:v 2 "$cover"; then

echo " 截图失败，取消封面嵌入"; rm -f "$cover"; cover=""

fi

fi

  

# 元数据

local meta=(-id3v2_version 3 -write_id3v2 1 -metadata "title=$base")

[ -n "$ARTIST_PARAM" ] && meta+=(-metadata "artist=$ARTIST_PARAM")

[ -n "$ALBUM_PARAM" ] && meta+=(-metadata "album=$ALBUM_PARAM")

[ -n "$YEAR_PARAM" ] && meta+=(-metadata "date=$YEAR_PARAM")

if [ -n "$GENRE_PARAM" ]; then

meta+=(-metadata "genre=$GENRE_PARAM")

elif [ -n "$GENRE_DEFAULT" ]; then

meta+=(-metadata "genre=$GENRE_DEFAULT")

fi

[ -n "$COMMENT_PARAM" ] && meta+=(-metadata "comment=$COMMENT_PARAM")

[ -n "$ARTIST_PARAM" ] && meta+=(-metadata "album_artist=$ARTIST_PARAM")

  

if [ -n "$cover" ]; then

if ffmpeg -hide_banner -loglevel error -y \

-i "$src" -i "$cover" \

-map 0:a:0 -map 1:v:0 \

-c:a libmp3lame -q:a 2 \

-c:v mjpeg -frames:v 1 \

-disposition:v attached_pic \

"${meta[@]}" \

"$out"

then

echo " 成功：$out"

else

echo " 失败：$out"

fi

rm -f "$cover"

else

if ffmpeg -hide_banner -loglevel error -y \

-i "$src" \

-map 0:a:0 \

-c:a libmp3lame -q:a 2 \

"${meta[@]}" \

"$out"

then

echo " 成功：$out"

else

echo " 失败：$out"

fi

fi

echo

return 0

}

  

# ---------- 入口：单文件或目录 ----------

shopt -s nullglob nocaseglob

  

process_path() {

local path="$1"

if [ -f "$path" ]; then

# 有清单 → 分轨；无清单 → 转 MP3

if split_by_cue "$path"; then

return 0

else

case $? in

2) convert_to_mp3 "$path" ;; # 无清单

*) return 1 ;;

esac

fi

elif [ -d "$path" ]; then

# 默认不遍历 mp3，避免二次有损；如需可把 mp3 加回扩展列表

local exts=( m4a aac wav flac ogg opus wma mp4 m4v mov webm mkv avi flv ts mpeg mpg ogv )

local files=() ext f

for ext in "${exts[@]}"; do

for f in "$path"/*."$ext"; do

[ -e "$f" ] && files+=( "$f" )

done

done

if [ ${#files[@]} -eq 0 ]; then

echo "提示：目录下没有可处理的媒体文件（支持：${exts[*]}）。"

return 0

fi

  

echo "[共计] 处理 ${#files[@]} 个文件"

echo

local i=0 ok=0 fail=0

for f in "${files[@]}"; do

i=$((i+1)); echo "[$i/${#files[@]}] $f"

if process_path "$f"; then ok=$((ok+1)); else fail=$((fail+1)); fi

done

echo "批量完成：成功 $ok，失败 $fail"

else

echo "警告：不支持的路径类型：$path"

return 1

fi

}

  

process_path "$TARGET"
```