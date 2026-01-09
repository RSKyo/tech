#!/usr/bin/env bash
# =============================================================================
# SHID: Aa2p1cxL
# DO NOT REMOVE OR MODIFY THIS BLOCK.
# Used for script identity / indexing.
# =============================================================================

IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# files_filter.sh
#
# 配置文件（与本脚本同目录）：files_filter.sh.conf
# 兼容 Bash 3.2；不使用 eval；不使用关联数组；避免 Bash 3.2 + set -u 坑。
#
# 配置契约（唯一真源）：
#   FILE_TYPES=( t1 t2 t3 ... )
#   TYPE_<type>="ext1,ext2,ext3"     # 逗号分隔；ext 可带点；大小写不敏感
#
# 命令行：
#   --type <type>     使用配置中 TYPE_<type> 的扩展名集合；默认 all
#   --ext  a,b,c      自定义扩展名集合（覆盖 --type）
#
# 输入：stdin 每行一个路径
# 输出：通过过滤的路径（每行一个）
# =============================================================================

usage() {
  cat <<EOF
用法：
  <paths> | $(basename "$0") [options]

options:
  --type <type>
      使用配置中的 FILE_TYPES 与 TYPE_<type>
      默认：all（不过滤扩展名，但仍要求是普通文件）

  --ext ext1,ext2,...
      自定义扩展名集合（覆盖 --type），逗号分隔
      - 支持带点或不带点
      - 不区分大小写

  -h, --help
      显示帮助
EOF
}

to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

trim_ws() {
  # 去掉两端空白（不依赖外部命令）
  local s="$1"
  s="${s#"${s%%[!$' \t\r\n']*}"}"
  s="${s%"${s##*[!$' \t\r\n']}"}"
  printf '%s' "$s"
}

# 读取名为 $1 的“标量变量”（形如 NAME="value"）并输出 value。
# 成功 return 0；失败 return 1
# 注意：只支持配置里这种最常见的写法：TYPE_xxx="a,b,c"
get_scalar_var() {
  local name="$1" decl rhs

  decl="$(declare -p "$name" 2>/dev/null)" || return 1

  # 期望：declare -- NAME="value"
  case "$decl" in
    declare\ --\ "$name"=*)
      rhs="${decl#*=}"   # rhs 形如 "value"
      rhs="${rhs#\"}"
      rhs="${rhs%\"}"
      printf '%s' "$rhs"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

type_exists() {
  local t="$1" x
  for x in "${FILE_TYPES[@]}"; do
    [[ "$x" == "$t" ]] && return 0
  done
  return 1
}

# csv -> exts[]（逗号分隔；去点；小写；忽略空项）
parse_csv_exts() {
  local csv="$1" part
  exts=()

  local IFS=','  # 只在本函数内生效
  for part in $csv; do
    part="$(trim_ws "$part")"
    part="${part#.}"
    part="$(to_lower "$part")"
    [ -n "$part" ] && exts+=( "$part" )
  done
}

load_type_exts() {
  local t="$1"
  local var="TYPE_$t"
  local csv=""

  # Bash 3.2 + set -u 下，避免“赋值 + || { ... }”这种写法
  if ! csv="$(get_scalar_var "$var")"; then
    # echo "❌ 配置缺少：${var}（当前 --type ${t} 需要它）" >&2
    echo "❌ 配置缺少：${var}（当前 --type ${t} 需要它）" >&2
    exit 1
  fi

  if [ -z "$csv" ]; then
    echo "❌ 配置为空：${var} （当前 --type ${t} 需要它）" >&2
    exit 1
  fi

  parse_csv_exts "$csv"
}

# -----------------------------------------------------------------------------
# 参数解析
# -----------------------------------------------------------------------------
TYPE="all"
EXT_CSV=""

while [ $# -gt 0 ]; do
  case "$1" in
    --type)
      [ $# -ge 2 ] || { echo "错误：--type 需要参数" >&2; exit 1; }
      TYPE="$2"
      shift 2
      ;;
    --ext)
      [ $# -ge 2 ] || { echo "错误：--ext 需要参数" >&2; exit 1; }
      EXT_CSV="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数：$1" >&2
      exit 1
      ;;
  esac
done

# -----------------------------------------------------------------------------
# 读取配置（同目录，一次性）
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_PATH="$SCRIPT_DIR/files_filter.sh.conf"

if [[ ! -f "$CONF_PATH" ]]; then
  echo "❌ 缺少配置文件：$CONF_PATH" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONF_PATH"

if ! declare -p FILE_TYPES >/dev/null 2>&1; then
  echo "❌ 配置缺少 FILE_TYPES 数组" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# 构造过滤规则（一次性）
# -----------------------------------------------------------------------------
FILTER_MODE="exts"
exts=()

if [ -n "$EXT_CSV" ]; then
  parse_csv_exts "$EXT_CSV"
else
  if [ "$TYPE" = "all" ]; then
    FILTER_MODE="all"
  else
    type_exists "$TYPE" || { echo "❌ 未知类型（FILE_TYPES 未声明）：$TYPE" >&2; exit 1; }
    load_type_exts "$TYPE"
  fi
fi

# -----------------------------------------------------------------------------
# 过滤并输出
# -----------------------------------------------------------------------------
handle_path() {
  local f="$1" ext e
  [ -f "$f" ] || return 0

  if [ "$FILTER_MODE" = "all" ]; then
    printf '%s\n' "$f"
    return 0
  fi

  [[ "$f" == *.* ]] || return 0
  ext="$(to_lower "${f##*.}")"

  for e in "${exts[@]}"; do
    [ "$ext" = "$e" ] && { printf '%s\n' "$f"; return 0; }
  done
  return 0
}

while read -r line; do
  [ -n "$line" ] || continue
  handle_path "$line"
done

exit 0
