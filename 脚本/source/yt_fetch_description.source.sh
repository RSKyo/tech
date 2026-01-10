#!/usr/bin/env bash
# =============================================================================
# yt_fetch_description.source.sh
#
# 功能：
#   通过 yt-dlp 获取 YouTube 视频的 description 文本
#
# 行为约定：
#   - 使用 yt-dlp 获取 description
#   - 若系统未安装 yt-dlp：
#       * 不报错、不退出
#       * 返回空字符串
#       * 在 stderr 输出一次安装提示
#
# 用法（source 后）：
#   desc="$(yt_fetch_description "$url")"
#
# yt-dlp --print description --no-playlist --no-warnings "https://youtu.be/P-Iv16c-674?list=RDP-Iv16c-674"
# =============================================================================

# 内部标记：避免重复输出安装提示
__YT_FETCH_DESC_YTDLP_WARNED=0

yt_fetch_description() {
  local url="$1"
  local desc=""

  # yt-dlp 不存在：静默降级 + 提示一次
  if ! command -v yt-dlp >/dev/null 2>&1; then
    if [[ $__YT_FETCH_DESC_YTDLP_WARNED -eq 0 ]]; then
      __YT_FETCH_DESC_YTDLP_WARNED=1
      cat >&2 <<'EOF'
[INFO] yt-dlp 未安装，无法获取 YouTube 描述信息（description）。
       当前流程将继续执行，但不会解析描述内容。

       可通过以下命令安装 yt-dlp：
         macOS (Homebrew):  brew install yt-dlp
         Debian / Ubuntu:   sudo apt install yt-dlp
         Fedora / RHEL:     sudo dnf install yt-dlp
         Arch Linux:        sudo pacman -S yt-dlp
EOF
    fi
    return 0
  fi

  # 获取 description（保持与原脚本语义一致）
  desc="$(
    yt-dlp \
      --print description \
      --no-playlist \
      --no-warnings \
      "$url" \
      2>/dev/null || true
  )"

  [[ -n "$desc" ]] && printf '%s\n' "$desc"
}
