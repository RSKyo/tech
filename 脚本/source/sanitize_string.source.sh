#!/usr/bin/env bash
# =============================================================================
# SOURCE-ONLY LIBRARY
#
# sanitize_string.source.sh
#
# Purpose:
#   - Sanitize arbitrary strings for safe filesystem usage
#
# Design principles:
#   - Rule-driven (rules as data)
#   - No truncation
#   - No case conversion
#   - No semantic transformation
#   - Only remove / replace filesystem-unsafe characters
#
# Provides:
#   - sanitize_string <string>
#
# Notes:
#   - This file MUST be sourced, not executed.
#   - No I/O handling (no argv / stdin).
#   - No global shell state modification.
# =============================================================================

# ---------------------------------------------------------------------------
# execution guard
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "[ERROR] sanitize_string.source.sh must be sourced, not executed." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# rules (data only)
#
# SANITIZE_RULES:
#   Every 3 items form a rule:
#     [from] [to] [description]
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
# sanitize_string
#
# Input:
#   $1 - arbitrary string
#
# Output:
#   - echo sanitized string
#
# Return:
#   0 - always (pure transformation)
# ---------------------------------------------------------------------------
sanitize_string() {
  local input="$1"
  local s

  s="$input"

  # trim leading / trailing whitespace
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"

  # apply rules
  for ((i = 0; i < ${#SANITIZE_RULES[@]}; i += 3)); do
    local from="${SANITIZE_RULES[i]}"
    local to="${SANITIZE_RULES[i+1]}"
    s="${s//"$from"/"$to"}"
  done

  # collapse repeated spaces
  s="$(printf '%s\n' "$s" | tr -s ' ')"

  printf '%s\n' "$s"
}
