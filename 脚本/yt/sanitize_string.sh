#!/usr/bin/env bash
IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# sanitize_string.sh
#
# 将任意字符串转换为“文件系统安全”的字符串
#
# 设计原则：
#   - 规则即数据（统一规则表）
#   - 不截断、不改大小写、不做语义加工
#   - 仅处理跨平台不安全字符
#   - 适用于 title、文件名片段、标签等场景
#
# 支持：
#   - argv
#   - stdin（管道，多行）
#
# 用法：
#   sanitize_string.sh "<string>"
#   echo "<string>" | sanitize_string.sh
#   cat file.txt | sanitize_string.sh
# =============================================================================

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  cat >&2 <<'EOF'
Usage:
  sanitize_string.sh <string>
  sanitize_string.sh < strings.txt

Description:
  Sanitize arbitrary strings for safe filesystem usage.
  Works with argv or stdin (pipe).
EOF
}

# ---------------------------------------------------------------------------
# 规则定义区（核心）
#
# SANITIZE_RULES：
#   每 3 项为一组：
#     [原字符] [替换为] [说明]
# ---------------------------------------------------------------------------
SANITIZE_RULES=(
  "/"  " - "  "路径分隔符"
  "\\" " - "  "Windows 路径分隔符"
  ":"  " - "  "标题分隔符"
  "|"  " - "  "管道符"

  "*"  "_"    "非法通配符"
  "?"  "_"    "非法问号"
  "\"" "'"    "双引号 → 单引号"

  "<"  "("    "左尖括号"
  ">"  ")"    "右尖括号"
)

# ---------------------------------------------------------------------------
# 核心处理函数
# ---------------------------------------------------------------------------
sanitize() {
  local input="$1"
  local s="$input"

  # 去除首尾空白
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"

  # 按规则表遍历替换
  for ((i = 0; i < ${#SANITIZE_RULES[@]}; i += 3)); do
    local from="${SANITIZE_RULES[i]}"
    local to="${SANITIZE_RULES[i+1]}"
    s="${s//"$from"/"$to"}"
  done

  # 压缩多余空格
  s="$(printf '%s\n' "$s" | tr -s ' ')"

  printf '%s\n' "$s"
}

# ---------------------------------------------------------------------------
# main: argv / stdin unified
# ---------------------------------------------------------------------------
had_input=0

if [[ $# -gt 0 ]]; then
  # argv mode（将所有参数合并为一个字符串）
  had_input=1
  sanitize "$*"
else
  # stdin mode（逐行处理）
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    had_input=1
    sanitize "$line"
  done
fi

[[ $had_input -eq 1 ]] || usage
