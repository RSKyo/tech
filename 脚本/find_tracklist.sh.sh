#!/usr/bin/env bash
# ==============================================================================
# find_tracklist.sh
# ------------------------------------------------------------------------------
# 接收一个媒体文件路径，在其同级目录（或递归子目录）查找对应的 tracklist 文件。
#
# 规则：
#   1) 默认（未指定 --id）：
#      查找：<媒体文件同名(不含扩展名)>.tracklist.txt
#      例：/a/b/video.webm -> /a/b/video.tracklist.txt
#
#   2) 指定 --id XXXX：
#      查找：任意文件名，只要以 "[XXXX].tracklist.txt" 结尾即算命中
#      例：xxx [LS7vyhX74Uk].tracklist.txt
#
# 查找范围：
#   - 默认：仅媒体文件同级目录（不递归）
#   - --recursive：包含所有子目录
#
# 输出：
#   - 找到：输出匹配文件的路径（一行），并退出 0
#   - 找不到：无任何输出，退出 0
#
# 用法：
#   find_tracklist.sh <media_file> [--recursive] [--id XXXX]
# ==============================================================================

IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

usage() {
  cat <<EOF >&2
用法:
  $(basename "$0") <media_file> [--recursive] [--id XXXX]

参数:
  --recursive        递归搜索同级目录下的所有子目录
  --id XXXX          按 "[XXXX].tracklist.txt" 结尾模式搜索

输出:
  找到则输出路径；找不到不输出任何内容（exit 0）
EOF
}

abs_path() {
  local p="$1"
  if [[ -e "$p" ]]; then
    (cd "$(dirname "$p")" && printf '%s/%s\n' "$(pwd)" "$(basename "$p")")
  else
    (cd "$(dirname "$p")" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$(basename "$p")") || printf '%s\n' "$p"
  fi
}

main() {
  local media=""
  local recursive="0"
  local id=""

  # parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --recursive) recursive="1"; shift ;;
      --id)
        shift
        id="${1:-}"
        shift || true
        ;;
      -*)
        echo "[WARN] Unknown arg: $1" >&2
        shift
        ;;
      *)
        if [[ -z "$media" ]]; then
          media="$1"
        fi
        shift
        ;;
    esac
  done

  [[ -z "$media" ]] && { usage; exit 2; }

  media="$(abs_path "$media")"
  local dir base stem
  dir="$(cd "$(dirname "$media")" 2>/dev/null && pwd || true)"
  [[ -z "$dir" ]] && exit 0

  base="$(basename "$media")"
  stem="${base%.*}"  # 去掉最后一个扩展名

  local maxdepth_opt
  if [[ "$recursive" == "1" ]]; then
    maxdepth_opt=()         # 不限制深度
  else
    maxdepth_opt=(-maxdepth 1)
  fi

  # 模式 A：同名 tracklist
  if [[ -z "$id" ]]; then
    local target="$dir/${stem}.tracklist.txt"
    if [[ -f "$target" ]]; then
      printf '%s\n' "$target"
    fi
    exit 0
  fi

  # 模式 B：按 [id].tracklist.txt 结尾匹配
  # 说明：你要求“只要后面是[xxxx].tracklist.txt 就算找到了”
  # 这里用 find 的 -name "*[ID].tracklist.txt"（需要转义方括号）
  local pattern="*\\[$id\\].tracklist.txt"

  local found=""
  # 找到第一个就返回（按 find 的遍历顺序）
  found="$(find "$dir" "${maxdepth_opt[@]}" -type f -name "$pattern" -print -quit 2>/dev/null || true)"
  [[ -n "$found" ]] && printf '%s\n' "$found"
}

main "$@"
