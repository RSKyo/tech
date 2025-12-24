#!/usr/bin/env bash
IFS=$'\n\t'
set -Eeuo pipefail

[[ $# -eq 1 ]] || exit 1

url="$1"

# -----------------------------------------
# 1) youtu.be/VIDEO_ID
# -----------------------------------------
if [[ "$url" =~ youtu\.be/([A-Za-z0-9_-]{11}) ]]; then
  echo "${BASH_REMATCH[1]}"
  exit 0
fi

# -----------------------------------------
# 2) youtube.com/watch?v=VIDEO_ID
#    先拆 query，再解析 v=
# -----------------------------------------
if [[ "$url" == *"youtube.com/watch"* && "$url" == *"v="* ]]; then
  query="${url#*\?}"      # v=xxx&list=yyy
  query="${query%%#*}"    # 去掉 fragment

  IFS='&' read -r -a params <<< "$query"
  for p in "${params[@]}"; do
    if [[ "$p" == v=* ]]; then
      id="${p#v=}"
      [[ "$id" =~ ^[A-Za-z0-9_-]{11}$ ]] || exit 1
      echo "$id"
      exit 0
    fi
  done
fi

# -----------------------------------------
# 3) /embed/VIDEO_ID
# -----------------------------------------
if [[ "$url" =~ /embed/([A-Za-z0-9_-]{11}) ]]; then
  echo "${BASH_REMATCH[1]}"
  exit 0
fi

# -----------------------------------------
# 4) /shorts/VIDEO_ID
# -----------------------------------------
if [[ "$url" =~ /shorts/([A-Za-z0-9_-]{11}) ]]; then
  echo "${BASH_REMATCH[1]}"
  exit 0
fi

exit 1
