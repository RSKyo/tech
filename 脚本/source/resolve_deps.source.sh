#!/usr/bin/env bash
# =============================================================================
# SOURCE-ONLY LIBRARY
#
# resolve_deps.source.sh
#
# Purpose:
#   - Resolve script dependencies via SHID
#   - Derive registry.sh from ROOT_DIR
#   - Validate existence & executability
#   - Assign resolved paths to variables in caller scope
#
# Usage:
#   source resolve_deps.source.sh
#
#   resolve_deps \
#     ROOT_DIR="/path/to/script-root" \
#     VAR1=SHID1 \
#     VAR2=SHID2
#
# Notes:
#   - This file MUST be sourced, not executed.
#   - Variables are assigned into the caller shell.
# =============================================================================

# ---------------------------------------------------------------------------
# execution guard
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "[ERROR] resolve_deps.source.sh must be sourced, not executed." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# resolve_deps
# ---------------------------------------------------------------------------
resolve_deps() {
  local root_dir=""
  local registry=""
  local kv
  local var_name shid resolved

  # -------------------------------------------------------------------------
  # parse ROOT_DIR
  # -------------------------------------------------------------------------
  for kv in "$@"; do
    case "$kv" in
      ROOT_DIR=*)
        root_dir="${kv#*=}"
        ;;
    esac
  done

  if [[ -z "$root_dir" ]]; then
    echo "[ERROR] ROOT_DIR is required." >&2
    return 1
  fi

  registry="$root_dir/registry.sh"

  if [[ ! -x "$registry" ]]; then
    echo "[ERROR] registry not found or not executable: $registry" >&2
    return 1
  fi

  # -------------------------------------------------------------------------
  # resolve dependencies
  # -------------------------------------------------------------------------
  for kv in "$@"; do
    case "$kv" in
      ROOT_DIR=*)
        continue
        ;;
    esac

    var_name="${kv%%=*}"
    shid="${kv#*=}"

    if [[ -z "$var_name" || -z "$shid" ]]; then
      echo "[ERROR] invalid dependency declaration: $kv" >&2
      return 1
    fi

    if ! resolved="$("$registry" "$shid")"; then
      echo "[ERROR] resolve SHID failed: $shid" >&2
      return 1
    fi

    if [[ ! -x "$resolved" ]]; then
      echo "[ERROR] $(basename "$resolved") not found or not executable: $resolved" >&2
      return 1
    fi

    # dynamic assignment in caller scope
    printf -v "$var_name" '%s' "$resolved"
  done
}
