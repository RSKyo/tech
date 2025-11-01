#!/usr/bin/env bash
# =============================================================================
# media2mp3.sh — 智能媒体转 MP3 + 自动分轨/分段 + 可嵌封面
# -----------------------------------------------------------------------------
# 优先级（单文件）：
#   1) 若存在同名清单 <源文件>.txt → 按清单时间点分轨输出 MP3；
#   2) 若提供 --segment N(>0) → 按 N 秒一段拆分（每段可选封面）；
#   3) 否则 → 直接将源媒体转为 1 个 MP3（可选封面）。
#
# 功能要点
#   - 支持处理单文件或目录（非递归批量）；
#   - 分轨/分段时支持重编码（精确切分）或流复制（快切，源为 MP3 时默认）；
#   - 可从第 N 秒截帧作为封面（源含视频流时有效）；
#   - 同名严格策略：默认跳过已存在文件；只有加 --force 才覆盖；
#   - 尽力抓取“来源 URL/Where froms”等写入 comment。
#
# 依赖
#   - ffmpeg、ffprobe（macOS 可用 Homebrew 安装：brew install ffmpeg）
#   - 可选：mdls / xattr / plutil / jq（用于抽取“Where froms”等元数据）
#
# 使用方法（Usage）
#   media2mp3.sh <文件或目录>
#       [--out DIR]
#       [--thumb-sec N]
#       [--artist A]
#       [--album ALB]
#       [--year Y]
#       [--genre G]
#       [--comment C]
#       [--reencode]
#       [--force]
#       [--segment N]
#
# 说明：
#   优先级：存在同名清单(.txt) → 按清单分轨；
#          否则若提供 --segment N(>0) → 按时长拆分；
#          否则 → 直接整段转 MP3。
#
# 清单（CUE）格式（UTF-8 无 BOM；两种格式可混用；时间支持 mm:ss 或 hh:mm:ss）
#   00:00 标题 / 艺术家
#   03:11 - 标题（可省略艺术家）
#   # 以 # 开头的行为注释
#   # 当标题文本中出现 Repeat 或 Replay 时，视为到此为止（后续行忽略）
#
# 示例
#   media2mp3.sh "concert.m4a"                      # 有清单 → 分轨
#   media2mp3.sh "video.mp4" --segment 300          # 无清单 → 按 300s 分段
#   media2mp3.sh "speech.mov" --thumb-sec 60        # 无清单 → 整段转并封面
#   media2mp3.sh "./Downloads"                      # 批处理目录（非递归）
#   media2mp3.sh "mix.m4a" --reencode               # 精确切分（重编码）
#   media2mp3.sh "mix.m4a" --force                  # 覆盖已存在目标
#
# 退出状态码（常见）
#   0  成功
#   1  参数/环境错误（缺依赖、路径不存在、清单格式错误等）
#   2  分轨分支返回“无清单”，由转换/分段分支继续处理（脚本内部使用）
#
# 版权与许可
#   本脚本按“自行承担风险”原则提供。请确保对源媒体拥有合法的处理与导出权。
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# ---------- 依赖 ----------
need() { command -v "$1" >/dev/null 2>&1 || { echo "错误：需要 $1，请先安装"; exit 1; }; }
need ffmpeg
need ffprobe

# ---------- 全局选项（默认值） ----------
ARTIST_DEFAULT=""
GENRE_DEFAULT=""
OUT_DIR_OVERRIDE=""     # --out DIR
THUMB_SEC=""            # 截帧封面（仅无清单整段/分段时，且源含视频）
REENCODE=0              # 分轨/分段精确切分（重编码）
FORCE=0                 # 同名覆盖
SEGMENT_SEC=0           # 新增：--segment N（秒），>0 时按固定时长拆分

# ---------- 参数解析 ----------
usage() {
  cat <<'EOF'
用法：
  media2mp3.sh <文件或目录> [--out DIR] [--thumb-sec N] [--artist A] [--album ALB] [--year Y] [--genre G] [--comment C] [--reencode] [--force] [--segment N]
说明：
  优先级：存在同名清单(.txt) → 按清单分轨；否则若提供 --segment N(>0) → 按时长拆分；否则直接整段转 MP3。
EOF
}

[ $# -ge 1 ] || { usage; exit 1; }
TARGET="$1"; shift

ARTIST_PARAM=""; ALBUM_PARAM=""; YEAR_PARAM=""; GENRE_PARAM=""; COMMENT_PARAM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out)       shift; OUT_DIR_OVERRIDE="${1:-output}" ;;
    --thumb-sec) shift; [[ "${1:-}" =~ ^[0-9]+$ ]] || { echo "错误：--thumb-sec 需整数秒"; exit 1; }; THUMB_SEC="$1" ;;
    --artist)    shift; ARTIST_PARAM="${1:-}" ;;
    --album)     shift; ALBUM_PARAM="${1:-}" ;;
    --year)      shift; YEAR_PARAM="${1:-}" ;;
    --genre)     shift; GENRE_PARAM="${1:-}" ;;
    --comment)   shift; COMMENT_PARAM="${1:-}" ;;
    --reencode)  REENCODE=1 ;;
    --force)     FORCE=1 ;;
    --segment)   shift; [[ "${1:-}" =~ ^[0-9]+$ && "$1" -gt 0 ]] || { echo "错误：--segment 需 >0 的整数秒"; exit 1; }; SEGMENT_SEC="$1" ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "未知参数：$1"; exit 1 ;;
  esac
  shift || true
done

[ -e "$TARGET" ] || { echo "错误：找不到路径：$TARGET"; exit 1; }

# ---------- 工具函数 ----------
to_seconds() {
  # 支持 00:00(.ms) / 00:00:00(.ms)，四舍五入到整数秒
  local t="$1"
  t="${t/,/.}"
  awk -F: '{
    if (NF==3) {h=$1; m=$2; s=$3}
    else if (NF==2) {h=0; m=$1; s=$2}
    else {h=0; m=0; s=0}
    printf("%d", h*3600 + m*60 + s + 0.5)
  }' <<<"$t"
}
sanitize() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"
  s="${s//\//-}"; s="${s//\\/-}"; s="${s//:/-}"
  s="${s//\*/-}"; s="${s//\?/-}"; s="${s//\"/-}"
  s="${s//</(}"; s="${s//>/)}"; s="${s//|/-}"
  echo "$s"
}
normalize_cue() {
  local in="$1" out tmp
  out="$(mktemp "${TMPDIR:-/tmp}/m2m.XXXXXX")"
  if LC_ALL=C grep -q $'^\xEF\xBB\xBF' "$in"; then
    tail -c +4 "$in" > "$out"
  else
    cat "$in" > "$out"
  fi
  if LC_ALL=C grep -q $'\r' "$out"; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/m2m.XXXXXX")"; tr -d '\r' < "$out" > "$tmp"; mv "$tmp" "$out"
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

# 取 Finder “来源/Where froms”（kMDItemWhereFroms）为 URL 列表并用 " | " 拼接。
get_where_froms_joined() {
  local path="$1"
  local urls="" joined="" tmp="" json=""

  # 1) 扩展属性
  if command -v xattr >/dev/null 2>&1 && command -v plutil >/dev/null 2>&1; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/m2m.XXXXXX")"
    if xattr -p "com.apple.metadata:kMDItemWhereFroms" "$path" > "$tmp" 2>/dev/null; then
      json="$(plutil -convert json -o - "$tmp" 2>/dev/null || true)"
      if [ -n "$json" ]; then
        urls="$(printf '%s' "$json" | grep -Eo 'https?://[^"]+')"
      fi
    fi
    rm -f "$tmp"
  fi

  # 2) mdls -plist
  if [ -z "$urls" ] && command -v mdls >/dev/null 2>&1 && command -v plutil >/dev/null 2>&1; then
    json="$(mdls -plist "$path" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || true)"
    if [ -n "$json" ]; then
      urls="$(printf '%s' "$json" | grep -Eo 'https?://[^"]+')"
    fi
  fi

  # 3) mdls -raw
  if [ -z "$urls" ] && command -v mdls >/dev/null 2>&1; then
    urls="$(mdls -raw -name kMDItemWhereFroms "$path" 2>/dev/null | grep -Eo 'https?://[^"<>[:space:]]+')"
  fi

  if [ -n "$urls" ]; then
    joined="$(printf '%s\n' "$urls" | awk '!seen[$0]++' | paste -sd' | ' -)"
    printf '%s' "$joined"
  else
    printf ''
  fi
}

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

# 总时长（秒，四舍五入）
duration_seconds() {
  ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$1" | awk '{printf "%.0f\n",$1+0}'
}

# ---------- 分轨（清单） ----------
split_by_cue() {
  # split_by_cue <src>
  local src="$1"
  local cue="${src}.txt"
  [ -f "$cue" ] || return 2   # 无清单 → 交给分段/整段处理

  local dur_total
  dur_total=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src" | awk '{printf("%.0f",$1)}') || true
  [[ "$dur_total" =~ ^[0-9]+$ ]] || { echo "错误：无法获取时长：$src"; return 1; }

  local reenc="$REENCODE" acodec
  acodec="$(get_audio_codec "$src")"
  case "$acodec" in mp3|mp3float) : ;;
    *) [ "$reenc" -eq 0 ] && { echo "提示：检测到 '$acodec'，自动启用重编码输出 MP3"; reenc=1; } ;;
  esac

  # comment 来源合并
  local SRC_ORIGIN="" v WF="" CHAP_JSON="" DESC="" WHEREF=""
  for k in purl comment description source; do
    v="$(get_tag "$k" "$src")"
    [ -n "$v" ] && { SRC_ORIGIN="$v"; break; }
  done
  if [ -z "$SRC_ORIGIN" ]; then
    WHEREF="$(get_where_froms_joined "$src")"
    [ -n "$WHEREF" ] && SRC_ORIGIN="$WHEREF"
  fi
  if [ -z "$SRC_ORIGIN" ] && command -v mdls >/dev/null 2>&1; then
    WF="$(mdls -raw -name kMDItemWhereFroms "$src" 2>/dev/null || true)"
    SRC_ORIGIN="$(printf '%s\n' "$WF" | first_url)"
  fi
  if [ -z "$SRC_ORIGIN" ]; then
    local info_json="${src%.*}.info.json"
    if [ -f "$info_json" ]; then
      if command -v jq >/dev/null 2>&1; then
        SRC_ORIGIN="$(jq -r '([.webpage_url, .original_url, .purl, .upload_webpage_url] | map(select(.!=null)) | unique | join(" | ")) // empty' "$info_json" 2>/dev/null || true)"
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

    local ts="" rest="" title="" artist="" line_norm
    line_norm="$(printf '%s' "$line" | sed $'s/\xef\xbc\x9a/:/g; s/\xc2\xa0/ /g; s/\xe3\x80\x80/ /g')"
    line_norm="${line_norm//$'\t'/ }"
    line_norm="${line_norm#"${line_norm%%[![:space:]]*}"}"
    line_norm="${line_norm%"${line_norm##*[![:space:]]}"}"

    if [[ "$line_norm" =~ ^([0-9]{1,2}:[0-9]{2}(:[0-9]{2})?([.,][0-9]{1,3})?)[[:space:]]+(.+)$ ]]; then
      ts="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[4]}"
    else
      echo "错误：清单格式不符（第 $line_no 行）：$line"
      echo "示例：03:11 标题 / 艺术家   或   03:11 - 标题 / 艺术家"
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
      REPEAT_AT="$ts_sec"; echo "终止标记：$ts  $title"; break
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

  local i
  for ((i=0;i<N;i++)); do
    local t_start=0 t_next=0 raw_title="" artist_line="" artist_eff="" clean="" base="" out="" dur=0 seen=0 idx=0
    t_start="${STARTS_T[$i]}"

    if [ "$i" -lt $((N-1)) ]; then
      t_next="${STARTS_T[$((i+1))]}"
      if [ "$t_next" -gt "$dur_end_total" ]; then
        t_next="$dur_end_total"
      fi
    else
      t_next="$dur_end_total"
    fi

    if [ "$t_next" -le "$t_start" ]; then
      echo "  时间异常：$t_start → $t_next，跳过"; echo; continue
    fi

    raw_title="${TITLES[$i]}"
    artist_line="${ARTISTS_LINE[$i]}"

    if   [ -n "$artist_line" ]; then artist_eff="$artist_line"
    elif [ -n "$ARTIST_PARAM" ]; then artist_eff="$ARTIST_PARAM"
    else artist_eff="$ARTIST_DEFAULT"; fi

    clean="$(sanitize "$raw_title")"
    base="${clean:-Track_$((i+1))}"
    out="$OUT_DIR/${base}.mp3"

    echo "  [$((i+1))/$N] $raw_title / $artist_eff  (${t_start}s → ${t_next}s)"

    # 清单内重复：默认跳过，--force 覆盖上一条
    seen=0
    for ((idx=0; idx<${#USED_NAMES[@]}; idx++)); do
      [ "$base" = "${USED_NAMES[$idx]}" ] && { seen=1; break; }
    done
    if [ "$seen" -eq 1 ]; then
      if [ "$FORCE" -eq 0 ]; then
        echo "    已出现同名（本次清单内），跳过（--force 可覆盖）"; echo; continue
      else
        echo "    --force：覆盖上一条同名"; rm -f "$out" 2>/dev/null || true
      fi
    fi
    USED_NAMES+=( "$base" )

    # 磁盘已存在：默认跳过；--force 覆盖
    if [ -e "$out" ]; then
      if [ "$FORCE" -eq 0 ]; then
        echo "    目标已存在，跳过：$out"; echo; continue
      else
        echo "    --force：覆盖目标：$out"; rm -f "$out"
      fi
    fi

    dur=$(( t_next - t_start ))
    local seek_opts=() enc=() map_opts=() meta=()
    if [ "$reenc" -eq 1 ]; then
      # 精确切：-i 后加 -ss；统一用 -t（时长）更稳
      seek_opts=(-i "$src" -ss "$t_start" -t "$dur")
      enc=(-c:a libmp3lame -q:a 2)
    else
      # 流复制快切
      seek_opts=(-ss "$t_start" -t "$dur" -i "$src")
      enc=(-c copy)
    fi

    local KEEP_ART="${KEEP_ART:-0}"
    if [ "$KEEP_ART" -eq 1 ] && [ "$reenc" -eq 0 ]; then
      map_opts=(-map 0:a:0 -map 0:v? -c:v copy -disposition:v attached_pic)
    else
      map_opts=(-map 0:a:0)
    fi

    meta=(-id3v2_version 3 -write_id3v2 1 -metadata "title=$raw_title" -metadata "artist=$artist_eff")
    [ -n "$ALBUM_PARAM" ] && meta+=(-metadata "album=$ALBUM_PARAM")
    [ -n "$YEAR_PARAM" ]  && meta+=(-metadata "date=$YEAR_PARAM" -metadata "year=$YEAR_PARAM")
    if [ -n "$GENRE_PARAM" ]; then
      meta+=(-metadata "genre=$GENRE_PARAM")
    elif [ -n "$GENRE_DEFAULT" ]; then
      meta+=(-metadata "genre=$GENRE_DEFAULT")
    fi
    [ -n "$COMMENT_EFF" ] && meta+=(-metadata "comment=$COMMENT_EFF")
    meta+=(-metadata "track=$((i+1))/$N")
    [ -n "$ARTIST_PARAM" ] && meta+=(-metadata "album_artist=$ARTIST_PARAM")

    if ffmpeg -nostdin -hide_banner -loglevel fatal -y \
         "${seek_opts[@]}" -avoid_negative_ts make_zero \
         "${map_opts[@]}" "${enc[@]}" "${meta[@]}" \
         "$out"
    then
      echo "    成功：$out"; ok=$((ok+1))
    else
      echo "    失败：$out"; fail=$((fail+1))
    fi
    echo
  done

  echo "分轨完成：成功 ${ok:-0}，失败 ${fail:-0}"
  return 0
}

# ---------- 分段（固定时长） ----------
split_by_segment() {
  # split_by_segment <src> <seg_seconds>
  local src="$1" seg="$2"
  local total dur_end t_start t_end idx=0
  total="$(duration_seconds "$src")"
  [[ "$total" =~ ^[0-9]+$ && "$total" -gt 0 ]] || { echo "错误：无法获取时长：$src"; return 1; }
  (( seg > 0 )) || { echo "错误：--segment 需 >0"; return 1; }

  # 选择编码策略（与 split_by_cue 相同）
  local reenc="$REENCODE" acodec
  acodec="$(get_audio_codec "$src")"
  case "$acodec" in mp3|mp3float) : ;;
    *) [ "$reenc" -eq 0 ] && { echo "提示：检测到 '$acodec'，按时长拆分将自动启用重编码输出 MP3"; reenc=1; } ;;
  esac

  local OUT_DIR; OUT_DIR="$(resolve_out_dir "$src" "split")"
  echo "按时长拆分：$src"
  echo "输出目录：$OUT_DIR"
  echo

  # 是否有视频流；用于封面截取
  local has_video=0
  if ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$src" >/dev/null 2>&1; then
    has_video=1
  fi

  local base_name clean_name
  base_name="${src##*/}"
  base_name="${base_name%.*}"
  clean_name="$(sanitize "$base_name")"

  local ok=0 fail=0 parts_total=$(( (total + seg - 1) / seg ))
  local USED_NAMES=()

  while (( idx*seg < total )); do
    t_start=$(( idx*seg ))
    t_end=$(( (idx+1)*seg )); (( t_end > total )) && t_end="$total"
    dur_end=$(( t_end - t_start ))
    (( dur_end > 0 )) || { idx=$((idx+1)); continue; }

    local part="$(printf '%03d' "$idx")"
    local raw_title="${clean_name}_part${part}"
    local out="$OUT_DIR/${raw_title}.mp3"

    echo "  [$((idx+1))/${parts_total}] ${raw_title}  (${t_start}s → ${t_end}s)"

    # 同名检查
    local seen=0 k
    for k in "${USED_NAMES[@]}"; do
      [ "$raw_title" = "$k" ] && { seen=1; break; }
    done
    if [ "$seen" -eq 1 ]; then
      if [ "$FORCE" -eq 0 ]; then
        echo "    已出现同名（本段命名），跳过（--force 可覆盖）"; echo; idx=$((idx+1)); continue
      else
        echo "    --force：覆盖上一条同名"; rm -f "$out" 2>/dev/null || true
      fi
    fi
    USED_NAMES+=( "$raw_title" )

    # 目标已存在
    if [ -e "$out" ]; then
      if [ "$FORCE" -eq 0 ]; then
        echo "    目标已存在，跳过：$out"; echo; idx=$((idx+1)); continue
      else
        echo "    --force：覆盖目标：$out"; rm -f "$out"
      fi
    fi

    # 生成封面（可选）
    local jpg=""
    if [ -n "$THUMB_SEC" ] && [ "$has_video" -eq 1 ]; then
      jpg="$(mktemp "${TMPDIR:-/tmp}/m2m.XXXXXX").jpg"
      if ! ffmpeg -nostdin -hide_banner -loglevel fatal -ss "$(( t_start + THUMB_SEC ))" -i "$src" -vframes 1 -q:v 2 "$jpg"; then
        echo "    封面截帧失败，跳过封面"; rm -f "$jpg"; jpg=""
      fi
    fi

    # 编码/复制与元数据
    local seek_opts=() enc=() map_opts=() meta=()
    if [ "$reenc" -eq 1 ]; then
      # 精确切
      seek_opts=(-i "$src" -ss "$t_start" -t "$dur_end")
      enc=(-c:a libmp3lame -q:a 2)
    else
      # 流复制快切
      seek_opts=(-ss "$t_start" -t "$dur_end" -i "$src")
      enc=(-c copy)
    fi
    map_opts=(-map 0:a:0)

    meta=(-id3v2_version 3 -write_id3v2 1 -metadata "title=$raw_title")
    [ -n "$ARTIST_PARAM" ] && meta+=(-metadata "artist=$ARTIST_PARAM" -metadata "album_artist=$ARTIST_PARAM")
    [ -n "$ALBUM_PARAM" ]  && meta+=(-metadata "album=$ALBUM_PARAM")
    [ -n "$YEAR_PARAM" ]   && meta+=(-metadata "date=$YEAR_PARAM" -metadata "year=$YEAR_PARAM")
    if [ -n "$GENRE_PARAM" ]; then
      meta+=(-metadata "genre=$GENRE_PARAM")
    elif [ -n "$GENRE_DEFAULT" ]; then
      meta+=(-metadata "genre=$GENRE_DEFAULT")
    fi
    [ -n "$COMMENT_PARAM" ] && meta+=(-metadata "comment=$COMMENT_PARAM")
    meta+=(-metadata "track=$((idx+1))/$parts_total")

    # 有封面就嵌封面
    if [ -n "$jpg" ]; then
      if ffmpeg -nostdin -hide_banner -loglevel fatal -y \
           "${seek_opts[@]}" -avoid_negative_ts make_zero \
           -i "$jpg" \
           "${map_opts[@]}" -map 1:v:0 \
           "${enc[@]}" -c:v mjpeg -frames:v 1 -disposition:v attached_pic \
           "${meta[@]}" \
           "$out"
      then
        echo "    成功：$out"; ok=$((ok+1))
      else
        echo "    失败：$out"; fail=$((fail+1))
      fi
      rm -f "$jpg"
    else
      if ffmpeg -nostdin -hide_banner -loglevel fatal -y \
           "${seek_opts[@]}" -avoid_negative_ts make_zero \
           "${map_opts[@]}" "${enc[@]}" \
           "${meta[@]}" \
           "$out"
      then
        echo "    成功：$out"; ok=$((ok+1))
      else
        echo "    失败：$out"; fail=$((fail+1))
      fi
    fi

    echo
    idx=$((idx+1))
  done

  echo "按时长拆分完成：成功 ${ok:-0}，失败 ${fail:-0}"
  return 0
}

# ---------- 直接转 MP3（无清单且无分段） ----------
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
      echo "  目标已存在，跳过：$out"; echo; return 0
    else
      echo "  --force：覆盖目标：$out"; rm -f "$out"
    fi
  fi

  local has_video=0 cover=""
  if ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$src" >/dev/null 2>&1; then
    has_video=1
  fi

  if [ -z "$COMMENT_PARAM" ]; then
    # 无清单转换时也尝试抓来源（Finder "更多信息" 的来自网址/下载地址）
    local WF_COMBINED; WF_COMBINED="$(get_where_froms_joined "$src")"
    if [ -n "$WF_COMBINED" ]; then
      COMMENT_PARAM="$WF_COMBINED"
    else
      # 兜底：从已存在的描述字段里抓第一个 URL
      local DESC=""; DESC="$(get_tag description "$src")"
      COMMENT_PARAM="$(printf '%s' "$DESC" | first_url)"
    fi
  fi

  if [ -n "$THUMB_SEC" ] && [ "$has_video" -eq 1 ]; then
    cover="$(mktemp "${TMPDIR:-/tmp}/m2m.XXXXXX").jpg"
    echo "  截取第 ${THUMB_SEC} 秒画面作为封面"
    if ! ffmpeg -nostdin -hide_banner -loglevel fatal -ss "$THUMB_SEC" -i "$src" -vframes 1 -q:v 2 "$cover"; then
      echo "  截图失败，取消封面嵌入"; rm -f "$cover"; cover=""
    fi
  fi

  local meta=(-id3v2_version 3 -write_id3v2 1 -metadata "title=$base")
  [ -n "$ARTIST_PARAM" ] && meta+=(-metadata "artist=$ARTIST_PARAM")
  [ -n "$ALBUM_PARAM" ]  && meta+=(-metadata "album=$ALBUM_PARAM")
  [ -n "$YEAR_PARAM" ]   && meta+=(-metadata "date=$YEAR_PARAM" -metadata "year=$YEAR_PARAM")
  if [ -n "$GENRE_PARAM" ]; then
    meta+=(-metadata "genre=$GENRE_PARAM")
  elif [ -n "$GENRE_DEFAULT" ] ; then
    meta+=(-metadata "genre=$GENRE_DEFAULT")
  fi
  [ -n "$COMMENT_PARAM" ] && meta+=(-metadata "comment=$COMMENT_PARAM")
  [ -n "$ARTIST_PARAM" ]  && meta+=(-metadata "album_artist=$ARTIST_PARAM")

  if [ -n "$cover" ]; then
    if ffmpeg -nostdin -hide_banner -loglevel fatal -y \
         -i "$src" -i "$cover" \
         -map 0:a:0 -map 1:v:0 \
         -c:a libmp3lame -q:a 2 \
         -c:v mjpeg -frames:v 1 \
         -disposition:v attached_pic \
         "${meta[@]}" \
         "$out"
    then
      echo "  成功：$out"
    else
      echo "  失败：$out"
    fi
    rm -f "$cover"
  else
    if ffmpeg -nostdin -hide_banner -loglevel fatal -y \
         -i "$src" \
         -map 0:a:0 \
         -c:a libmp3lame -q:a 2 \
         "${meta[@]}" \
         "$out"
    then
      echo "  成功：$out"
    else
      echo "  失败：$out"
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
    if split_by_cue "$path"; then
      return 0
    else
      case $? in
        2)
          if [ "$SEGMENT_SEC" -gt 0 ]; then
            if split_by_segment "$path" "$SEGMENT_SEC"; then
              return 0
            else
              return 1
            fi
          else
            convert_to_mp3 "$path"
          fi
          ;;
        *) return 1 ;;
      esac
    fi
  elif [ -d "$path" ]; then
    # 支持的扩展（不区分大小写；已启用 nocaseglob）
    local exts=( m4a aac wav flac ogg opus wma mp4 m4v mov webm mkv avi flv ts mpeg mpg ogv 3gp mts m2ts )
    local files=() f
    for f in "$path"/*; do
      [ -f "$f" ] || continue
      case "${f##*.}" in
        m4a|aac|wav|flac|ogg|opus|wma|mp4|m4v|mov|webm|mkv|avi|flv|ts|mpeg|mpg|ogv|3gp|mts|m2ts)
          files+=( "$f" )
          ;;
      esac
    done
    if [ ${#files[@]} -gt 0 ]; then
      IFS=$'\n' files=($(printf '%s\n' "${files[@]}" | LC_ALL=C sort)); IFS=$'\n\t'
    fi

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
    echo "批量完成：成功 ${ok:-0}，失败 ${fail:-0}"
  else
    echo "警告：不支持的路径类型：$path"
    return 1
  fi
}

process_path "$TARGET"
