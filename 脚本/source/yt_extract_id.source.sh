#!/usr/bin/env bash
# =============================================================================
# SOURCE-ONLY LIBRARY
#
# yt_extract_id.source.sh
#
# Purpose:
#   - Extract YouTube videoId (11 chars) from various URL forms
#
# Provides:
#   - yt_extract_id <url>
#
# Notes:
#   - This file MUST be sourced, not executed.
#   - No network access.
#   - No side effects.
# =============================================================================

# ---------------------------------------------------------------------------
# execution guard
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "[ERROR] yt_extract_id.source.sh must be sourced, not executed." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# constants
# ---------------------------------------------------------------------------
YT_VIDEO_ID_RE='[A-Za-z0-9_-]{11}'

# ---------------------------------------------------------------------------
# yt_extract_id
#
# Input:
#   $1 - YouTube URL
#
# Output:
#   - echo videoId on success
#
# Return:
#   0 - success
#   1 - not matched / invalid
# ---------------------------------------------------------------------------
yt_extract_id() {
  local url="$1"
  local query param id

  [[ -n "$url" ]] || return 1

  # -------------------------------------------------------------------------
  # 1) https://youtu.be/VIDEO_ID
  # -------------------------------------------------------------------------
  if [[ "$url" =~ youtu\.be/($YT_VIDEO_ID_RE) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  # -------------------------------------------------------------------------
  # 2) https://www.youtube.com/watch?v=VIDEO_ID
  # -------------------------------------------------------------------------
  if [[ "$url" == *"youtube.com/watch"* && "$url" == *"v="* ]]; then
    query="${url#*\?}"
    query="${query%%#*}"

    IFS='&' read -r -a params <<< "$query"
    for param in "${params[@]}"; do
      if [[ "$param" == v=* ]]; then
        id="${param#v=}"
        [[ "$id" =~ ^$YT_VIDEO_ID_RE$ ]] || return 1
        echo "$id"
        return 0
      fi
    done
  fi

  # -------------------------------------------------------------------------
  # 3) https://www.youtube.com/embed/VIDEO_ID
  # -------------------------------------------------------------------------
  if [[ "$url" =~ /embed/($YT_VIDEO_ID_RE) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  # -------------------------------------------------------------------------
  # 4) https://www.youtube.com/shorts/VIDEO_ID
  # -------------------------------------------------------------------------
  if [[ "$url" =~ /shorts/($YT_VIDEO_ID_RE) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}
