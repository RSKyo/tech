#!/usr/bin/env bash
IFS=$'\n\t'
set -Eeuo pipefail
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# registry.sh — Script Registry Builder / Resolver
#
# 功能：
#   1) 构建 registry（无参数）
#   2) 通过 SHID 查询脚本路径
#
# SHID 约定：
#   # SHID: FB5uMYAc
#
# 以下命令可生成8位随机数
# echo "$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8)"
# =============================================================================

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  local cmd
  cmd="$(basename "$0")"

  cat >&2 <<EOF
Usage:
  $cmd
      Rebuild registry.tsv by scanning scripts.

  $cmd <SHID>
      Resolve SHID to script path and output PATH to stdout.

Description:
  - Without arguments, $cmd scans all .sh files under its directory
    and rebuilds registry.tsv.
  - With a SHID argument, $cmd looks up the corresponding PATH from
    registry.tsv and prints it to stdout.

Notes:
  - registry.tsv is a generated file and can be safely removed.
  - Query mode does NOT rebuild registry.tsv.
EOF
}

# ---------------------------------------------------------------------------
# 基础路径
# ---------------------------------------------------------------------------
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_TSV="$SCRIPT_ROOT/registry.tsv"
SELF_PATH="$SCRIPT_ROOT/$(basename "$0")"

# ---------------------------------------------------------------------------
# 扫描规则
# ---------------------------------------------------------------------------
HEADER_SCAN_LINES=5

# ---------------------------------------------------------------------------
# 参数处理
# ---------------------------------------------------------------------------
if [[ $# -gt 1 ]]; then
  usage
  exit 1
fi

# ---------------------------------------------------------------------------
# 查询模式：registry.sh <SHID>
# ---------------------------------------------------------------------------
if [[ $# -eq 1 ]]; then
  shid="$1"

  if [[ "$shid" == "-h" || "$shid" == "--help" ]]; then
    usage
    exit 0
  fi

  if [[ ! -f "$REGISTRY_TSV" ]]; then
    echo "[ERROR] registry not found: $REGISTRY_TSV" >&2
    exit 1
  fi

  path="$(
    awk -F '\t' -v id="$shid" '
      $1 == id { print $2; found=1 }
      END { if (!found) exit 1 }
    ' "$REGISTRY_TSV"
  )" || {
    echo "[ERROR] SHID not found: $shid" >&2
    exit 1
  }

  # 查询模式：stdout 仅输出 PATH
  printf '%s\n' "$path"
  exit 0
fi

# ---------------------------------------------------------------------------
# 构建模式：registry.sh
# ---------------------------------------------------------------------------
: > "$REGISTRY_TSV"
printf '# SHID\tPATH\n' >> "$REGISTRY_TSV"

find "$SCRIPT_ROOT" -type f -name '*.sh' | while IFS= read -r sh_file; do
  # 排除 registry.sh 自身
  [[ "$sh_file" == "$SELF_PATH" ]] && continue

  # 只读取头部指定行数
  header="$(sed -n "1,${HEADER_SCAN_LINES}p" "$sh_file")"

  shid="$(
    printf '%s\n' "$header" \
    | sed -n 's/^# SHID:[[:space:]]*\([A-Za-z0-9]\{8\}\)$/\1/p'
  )"

  [[ -n "$shid" ]] || continue

  # SHID 冲突检测
  if grep -q "^$shid"$'\t' "$REGISTRY_TSV"; then
    echo "[WARN] duplicate SHID '$shid' ignored: $sh_file" >&2
    continue
  fi

  printf '%s\t%s\n' "$shid" "$sh_file" >> "$REGISTRY_TSV"
done

record_count="$(grep -vc '^#' "$REGISTRY_TSV" || true)"
echo "[OK] registry generated: $REGISTRY_TSV ($record_count entries)" >&2
