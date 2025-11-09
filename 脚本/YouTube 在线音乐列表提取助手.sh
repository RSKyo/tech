#!/usr/bin/env bash
set -euo pipefail

############################################
# YouTube 音乐列表提取助手
# ------------------------------------------
# 功能：
#   从 YouTube 视频的「简介」中自动提取音乐列表（含时间戳），
#   根据一定的结构规则，生成一份「分轨计划」文本文件。
#
# 支持输入：
#   1）单个 YouTube 地址，例如：
#        ./YouTube\ 音乐列表提取助手.sh "https://www.youtube.com/watch?v=XXXX"
#
#   2）批量地址文件：文本文件，每行一个链接，例如：
#        ./YouTube\ 音乐列表提取助手.sh urls.txt
#
#      - 空行会被忽略；
#      - 以 # 开头的行视为注释，会被忽略。
#
# 输出：
#   - 每个视频会生成一个列表文件，命名为：
#       <标题> [<video_id>].list.txt
#     例如：
#       老上海黃金爵士時代 [tFzqDiS46xs0].list.txt
#
#   - 文件内容：每行一首歌，格式为：
#       时间 标题 / 艺术家
#     例如：
#       00:00:00 月光下的舞 / 王小明
#
#     后续脚本（如 media_segment_plan.sh）可以按 "标题 / 艺术家" 来拆分。
#
# 结构识别规则（--struct）：
#   根据你在视频简介中写的列表格式，选择不同模式：
#     0：自动模式（宽松识别）
#     1：00:00 / 00:00:00 - 标题
#     2：00:00 / 00:00:00 标题
#     3：[00:00] / 【00:00】 标题
#     4：1、00:00 标题
#
# 依赖：
#   - yt-dlp（例如：brew install yt-dlp）
#
# 小技巧：
#   - 如果你把这个脚本拖到终端里直接回车（不带任何参数），
#     会自动显示用法说明，不会干别的。
############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
用法：
  1）单个链接：
       YouTube 音乐列表提取助手.sh [--out 输出目录] [--struct N] "<YouTube链接>"

  2）批量链接文件：
       YouTube 音乐列表提取助手.sh [--out 输出目录] [--struct N] <链接列表文件>

参数：
  --out DIR     指定输出目录（默认：脚本目录下的 yt_musiclist/）
  --struct N    指定曲目结构模式（默认 0）
                  0：自动模式（宽松识别）
                  1：00:00 / 00:00:00 - 标题
                  2：00:00 / 00:00:00 标题
                  3：[00:00] / 【00:00】 标题
                  4：1、00:00 标题

输入说明：
  - 若最后一个参数是以 "http" 开头的字符串，则视为单一链接；
  - 若最后一个参数是一个存在的文件路径，则视为「批量地址文件」，
    文件内每行一个链接，空行和以 # 开头的行会被忽略。

输出说明：
  - 每个视频生成：
        <标题> [<video_id>].list.txt
    例如：
        老上海黃金爵士時代 [tFzqDiS46xs0].list.txt

  - 文件内容每行格式：
        时间 标题 / 艺术家
    例如：
        00:00:00 月光下的舞 / 王小明

提示：
  - 如果不带任何参数运行本脚本（例如直接拖到终端回车），
    会显示本用法说明，然后退出。
EOF
}

# 如果完全没有参数（例如直接拖进终端回车），打印用法
if [ $# -eq 0 ]; then
  usage
  exit 1
fi

# 参数解析
OUT_DIR=""
INPUT=""
STRUCT=0   # 0=自动模式

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage; exit 0 ;;
    --out)
      shift || true
      OUT_DIR="${1:-}" ;;
    --struct|-s)
      shift || true
      STRUCT="${1:-0}" ;;
    *)
      if [ -z "${INPUT:-}" ]; then
        INPUT="$1"
      else
        echo "⚠️ 忽略多余参数：$1" >&2
      fi
      ;;
  esac
  shift || true
done

# 必须要有一个最终输入（链接或文件）
if [ -z "${INPUT:-}" ]; then
  echo "❌ 缺少输入链接或链接列表文件。" >&2
  usage
  exit 1
fi

# 检查 yt-dlp
if ! command -v yt-dlp >/dev/null 2>&1; then
  echo "❌ 未检测到 yt-dlp，请先安装（例如：brew install yt-dlp）。" >&2
  exit 1
fi

# 输出目录
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/yt_musiclist}"
mkdir -p "$OUT_DIR"

echo "📁 输出目录：$OUT_DIR"
echo "🔧 列表结构：$STRUCT"
echo

sanitize_filename() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"   # 去前空白
  s="${s%"${s##*[![:space:]]}"}"   # 去后空白
  s="${s//\//_}"
  s="${s//\\/_}"
  s="${s//:/_}"
  s="${s//\*/_}"
  s="${s//\?/_}"
  s="${s//\"/_}"
  s="${s//</_}"
  s="${s//>/_}"
  s="${s//|/_}"
  echo "$s"
}

# ---------- 处理单个视频 ----------
process_url() {
  local url="$1"
  echo "  > 获取标题和ID..."

  local title video_id desc outfile playlist_raw playlist_norm line_count

  title=$(yt-dlp --no-playlist --get-title "$url" 2>/dev/null | head -n1 || true)
  video_id=$(yt-dlp --no-playlist -O "%(id)s" "$url" 2>/dev/null | head -n1 || true)

  [ -n "$title" ] || title="youtube_video"
  [ -n "$video_id" ] || video_id="unknown_id"

  # 标题用于显示和文件命名
  local pretty_title
  pretty_title="$(sanitize_filename "$title")"
  echo "  > 标题：$pretty_title"
  echo "  > ID ：$video_id"

  # 输出文件名：<标题> [<video_id>].list.txt
  outfile="$OUT_DIR/${pretty_title} [${video_id}].list.txt"
  echo "  > 输出文件：$outfile"

  echo "  > 获取视频描述..."
  desc=$(yt-dlp --no-playlist -O "%(description)s" "$url" 2>/dev/null || true)
  [ -n "$desc" ] || { echo "  ⚠️ 无描述内容，跳过。"; echo; return 0; }

  # 抽取连续时间戳块
  playlist_raw=$(
    printf '%s\n' "$desc" | awk -v style="$STRUCT" '
      function trim(s){ sub(/^[ \t\r\n]+/,"",s); sub(/[ \t\r\n]+$/,"",s); return s }
      function is_list_line(line,style,l){
        l=trim(line); if(l=="") return 0
        if(style==1) return (l ~ /^[[:space:]]*[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?[[:space:]]*[-–—:][[:space:]]+[^[:space:]]/)
        else if(style==2) return (l ~ /^[[:space:]]*[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?[[:space:]]+[^[:space:]]/)
        else if(style==3) return (l ~ /^[[:space:]]*[\[\【]?[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?[\]\】]?[[:space:]]+[^[:space:]]/)
        else if(style==4) return (l ~ /^[[:space:]]*[0-9]+[、．.][[:space:]]*[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?[[:space:]]+[^[:space:]]/)
        else return (l ~ /[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?[[:space:][:punct:]]+[^[:space:]]/)
      }
      BEGIN{in_block=0;block_idx=0;max_len=0;max_block=-1}
      {
        if(is_list_line($0,style)){
          line=trim($0)
          if(!in_block){
            in_block=1
            block_idx++
            block_len[block_idx]=0
            block_lines[block_idx]=""
          }
          block_len[block_idx]++
          block_lines[block_idx]=(block_lines[block_idx]=="" ? line : block_lines[block_idx] ORS line)
        } else {
          in_block=0
        }
      }
      END{
        for(i=1;i<=block_idx;i++)
          if(block_len[i]>max_len){max_len=block_len[i];max_block=i}
        if(max_len>=2 && max_block!=-1)
          print block_lines[max_block]
      }'
  )

  if [ -z "$playlist_raw" ]; then
    echo "  ⚠️ 未检测到歌曲列表。"; echo; return 0
  fi

  # 标准化为 “时间 + 空格 + 文本”
  # 文本部分你可以在简介里写成 “标题 / 艺术家”
  playlist_norm=$(
    printf '%s\n' "$playlist_raw" | awk '
      function trim(s){sub(/^[ \t\r\n]+/,"",s);sub(/[ \t\r\n]+$/,"",s);return s}
      {
        if(match($0,/([0-9]{1,2}:[0-9]{2}(:[0-9]{2})?)/)){
          t=substr($0,RSTART,RLENGTH)
          rest=substr($0,RSTART+RLENGTH)
          gsub(/^[[:space:][:punct:]]+/,"",rest)
          rest=trim(rest)
          if(rest!="") print t" "rest
        }
      }' | sed -E '/^[[:space:]]*$/d'
  )

  [ -n "$playlist_norm" ] || { echo "  ⚠️ 格式化失败。"; echo; return 0; }

  printf '%s\n' "$playlist_norm" > "$outfile"
  line_count=$(printf '%s\n' "$playlist_norm" | wc -l | tr -d ' ')
  echo "  ✅ 已保存到：$outfile"
  echo "  共提取 $line_count 行。"
  echo
}

# ---------- 主逻辑 ----------
if [ -f "$INPUT" ]; then
  # 如果 INPUT 本身是一个文本文件 → 批量模式
  # 判断方式：不是以 "http" 开头 且 确实是一个普通文件
  if [[ "$INPUT" != http* ]] && file "$INPUT" >/dev/null 2>&1; then
    echo "📃 批量模式：读取链接列表文件：$INPUT"
    total=$(awk '{line=$0;sub(/^[[:space:]]+/,"",line);sub(/[[:space:]]+$/,"",line);if(line==""||line~"^#")next;n++}END{print n}' "$INPUT")
    index=0
    while IFS= read -r line || [ -n "$line" ]; do
      local_url="${line#"${line%%[![:space:]]*}"}"
      local_url="${local_url%"${local_url##*[![:space:]]}"}"
      [[ -z "$local_url" || "$local_url" =~ ^# ]] && continue
      index=$((index+1))
      echo "▶ ${index}/${total} 正在处理：$local_url"
      process_url "$local_url"
    done < "$INPUT"
  else
    # 否则视为单个链接
    echo "▶ 1/1 正在处理：$INPUT"
    process_url "$INPUT"
  fi
else
  # INPUT 不是现有文件 → 视为单个链接
  echo "▶ 1/1 正在处理：$INPUT"
  process_url "$INPUT"
fi

echo "🎵 全部完成！"
