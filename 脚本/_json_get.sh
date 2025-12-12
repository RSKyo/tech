#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# _json_get.sh
# ------------------------------------------------------------------------------
# 用途：
#   从 JSON 对象或数组中获取指定 key 的值。
#   支持嵌套 key（dot notation），支持数组的第 N 个元素（1-based）。
#   支持一次性获取多个 key（逐行输出）。
#
# 新特性：
#   ✔ 多个 --key 按顺序逐行输出
#   ✔ 保留全部旧版严格行为
#   ✔ 当 JSON 是数组且没有指定 --nth 时，禁止多 key（避免不明确的行为）
#
# 参数：
#   --json "<json>"       输入 JSON 字符串（必需）
#   --key "a.b.c"         获取字段名，可重复多次
#   --nth N               对数组取第 N 个元素（从 1 开始）
#
# 行为规则：
#   JSON 为对象：
#       无 --nth：输出每个 key 的值（逐行）
#       有 --nth：报错（对象不能 nth）
#
#   JSON 为数组：
#       无 --nth：
#           仅允许单 key → 输出每个元素的 key 值（逐行输出）
#           多 key → 报错（避免歧义）
#       有 --nth：
#           可使用多 key，逐行输出
#
# 输出：
#   每个 key 对应一个输出行。
# ==============================================================================

JSON_INPUT=""
NTH=""
KEYS=()

# -------------------- Parse arguments --------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_INPUT="$2"
      shift 2
      ;;
    --key)
      KEYS+=("$2")
      shift 2
      ;;
    --nth)
      NTH="$2"
      shift 2
      ;;
    *)
      echo "Error: unknown option $1" >&2
      exit 1
      ;;
  esac
done

# -------------------- Validate --------------------
if [[ -z "$JSON_INPUT" ]]; then
  echo "Error: --json is required" >&2
  exit 1
fi

if [[ ${#KEYS[@]} -eq 0 ]]; then
  echo "Error: at least one --key is required" >&2
  exit 1
fi

# JSON 类型检测
JSON_TYPE=$(printf '%s' "$JSON_INPUT" | jq -r '
  if type=="array" then "array" else "object" end
')

# -------------------- If array + no nth + multiple keys → forbidden --------------------
if [[ "$JSON_TYPE" == "array" && -z "$NTH" && ${#KEYS[@]} -gt 1 ]]; then
  echo "Error: multiple --key not allowed when JSON is array without --nth" >&2
  exit 1
fi

# -------------------- Handle nth if provided --------------------
if [[ -n "$NTH" ]]; then
  if ! [[ "$NTH" =~ ^[0-9]+$ ]]; then
    echo "Error: --nth must be a positive integer" >&2
    exit 1
  fi

  if [[ "$JSON_TYPE" == "object" ]]; then
    echo "Error: --nth cannot be used on JSON object" >&2
    exit 1
  fi

  LENGTH=$(printf '%s' "$JSON_INPUT" | jq 'length')
  INDEX=$((NTH - 1))

  if (( INDEX < 0 || INDEX >= LENGTH )); then
    echo "Error: index $NTH out of range (array length = $LENGTH)" >&2
    exit 1
  fi

  # 提取数组某一项（作为新 JSON_INPUT）
  JSON_INPUT=$(printf '%s' "$JSON_INPUT" | jq -c ".[$INDEX]")
  JSON_TYPE="object"   # 被挑出来的必定是对象或基本类型（当作对象处理）
fi

# -------------------- JSON object path checking function --------------------
check_key_exists() {
  local json="$1"
  local key="$2"
  local jq_path=".$key"

  printf '%s' "$json" | jq -e "$jq_path" >/dev/null 2>&1
}

# -------------------- Processing for OBJECT --------------------
if [[ "$JSON_TYPE" == "object" ]]; then
  for KEY in "${KEYS[@]}"; do
    JQ_PATH=".$KEY"

    if ! check_key_exists "$JSON_INPUT" "$KEY"; then
      echo "Error: key '$KEY' does not exist in object" >&2
      exit 1
    fi

    printf '%s\n' "$(printf '%s' "$JSON_INPUT" | jq -r "$JQ_PATH")"
  done

  exit 0
fi

# -------------------- Processing for ARRAY (no nth) --------------------
if [[ "$JSON_TYPE" == "array" ]]; then
  # 此时必然只有一个 key（多 key 在前面已阻止）
  KEY="${KEYS[0]}"
  JQ_PATH=".$KEY"

  # 检查每个元素是否有此 key
  LENGTH=$(printf '%s' "$JSON_INPUT" | jq 'length')
  for i in $(seq 0 $((LENGTH - 1))); do
    if ! printf '%s' "$JSON_INPUT" | jq -e ".[$i]$JQ_PATH" >/dev/null 2>&1; then
      echo "Error: key '$KEY' does not exist in some array elements" >&2
      exit 1
    fi
  done

  # 输出所有元素的此 key 的值
  printf '%s' "$(printf '%s' "$JSON_INPUT" | jq -r ".[]$JQ_PATH")"
  exit 0
fi

echo "Error: unknown JSON type" >&2
exit 1
