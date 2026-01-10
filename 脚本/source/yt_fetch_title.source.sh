#!/usr/bin/env bash
# =============================================================================
# yt_fetch_title.source.sh
#
# 功能：
#   从 YouTube URL 获取视频标题（title）
#
# 行为约定：
#   - 首选使用 jq 解析 YouTube oEmbed 返回的 JSON
#   - 若系统未安装 jq：
#       * 不报错
#       * 不中断主流程
#       * 返回空字符串
#       * 在 stderr 输出一次安装提示
#
# 用法（source 后）：
#   title="$(yt_fetch_title "$url")"
# =============================================================================

# 内部标记：避免重复输出安装提示
__YT_FETCH_TITLE_JQ_WARNED=0

yt_fetch_title() {
  local url="$1"
  local title=""

  # 检查 jq 是否存在
  if ! command -v jq >/dev/null 2>&1; then
    if [[ $__YT_FETCH_TITLE_JQ_WARNED -eq 0 ]]; then
      __YT_FETCH_TITLE_JQ_WARNED=1
      cat >&2 <<'EOF'
[INFO] jq 未安装，无法解析 YouTube 标题（title）。
       当前流程将继续执行，但不会写入标题信息。

       可通过以下命令安装 jq：
         macOS (Homebrew):  brew install jq
         Debian / Ubuntu:   sudo apt install jq
         Fedora / RHEL:     sudo dnf install jq
         Arch Linux:        sudo pacman -S jq
EOF
    fi
    return 0
  fi

  # 使用 oEmbed + jq 获取 title
  local clean_url="${url%%\?*}"

  title="$(curl -sL \
    --connect-timeout 5 \
    --max-time 8 \
    "https://www.youtube.com/oembed?format=json&url=$clean_url" \
    | jq -r '.title // empty' \
    2>/dev/null)"

  # 输出结果（可能为空）
  [[ -n "$title" ]] && printf '%s\n' "$title"
}
