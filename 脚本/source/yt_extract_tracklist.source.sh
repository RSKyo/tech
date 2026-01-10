#!/usr/bin/env bash
# =============================================================================
# yt_extract_tracklist.source.sh
#
# 基于「时间戳前缀结构一致性（ASCII 投影）」提取 tracklist
#
# 核心思想：
#   1. 收集所有包含时间戳的行
#   2. 取“时间戳前缀”，做 ASCII 投影（非 ASCII → #）
#   3. 从最后一行开始向前扫描
#   4. 当前缀结构一致时连续收集
#   5. 若连续块长度 >= (总匹配行数的一半，向上取整)
#      → 认定为 tracklist
#
# 输入：
#   stdin  : YouTube description 原文
#
# 输出：
#   stdout : 规范化 tracklist（TIME + 空格 + TEXT）
#
# 说明：
#   - 本脚本不判断“是否足够多行”
#   - 是否采用输出结果，由上游决定
# =============================================================================

yt_extract_tracklist() {
  local description="$1"
  [[ -z "$description" ]] && return 0

  # ---------------------------------------------------------------------------
  # 时间戳正则（宽松）
  #   支持：
  #     56:20
  #     00:56:20
  #     1:02:33
  # ---------------------------------------------------------------------------
  local TIME_REGEX='([0-9]{1,2}:[0-9]{2}(:[0-9]{2})?)'

  # ---------------------------------------------------------------------------
  # Step 1: 收集所有包含时间戳的行及其前缀（ASCII 投影）
  # ---------------------------------------------------------------------------
  local raw_lines=()
  local prefixes=()

  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ $TIME_REGEX ]]; then
      local time="${BASH_REMATCH[1]}"
      local raw_prefix="${line%%$time*}"

      # ASCII 投影：非 ASCII 可打印字符 → #
      local calc_prefix
      calc_prefix="$(printf '%s' "$raw_prefix" | LC_ALL=C sed 's/[^ -~]/#/g')"

      # 去掉前后空白（不折叠中间空格）
      calc_prefix="${calc_prefix#"${calc_prefix%%[![:space:]]*}"}"
      calc_prefix="${calc_prefix%"${calc_prefix##*[![:space:]]}"}"

      raw_lines+=( "$line" )
      prefixes+=( "$calc_prefix" )
    fi
  done <<< "$description"

  local total="${#raw_lines[@]}"
  (( total == 0 )) && return 0

  # 阈值：匹配总数的一半（向上取整）
  local threshold=$(( (total + 1) / 2 ))

  # ---------------------------------------------------------------------------
  # Step 2: 从后向前扫描，寻找前缀一致的连续块
  #         使用 >=，保证后出现的结构覆盖前面的
  # ---------------------------------------------------------------------------
  local buf=()
  local buf_prefix=""
  local found=0

  for (( i=total-1; i>=0; i-- )); do
    if [[ -z "$buf_prefix" ]]; then
      buf_prefix="${prefixes[$i]}"
      buf=( "${raw_lines[$i]}" )
      continue
    fi

    if [[ "${prefixes[$i]}" == "$buf_prefix" ]]; then
      buf=( "${raw_lines[$i]}" "${buf[@]}" )
    else
      if (( ${#buf[@]} >= threshold )); then
        break
      fi
      buf_prefix="${prefixes[$i]}"
      buf=( "${raw_lines[$i]}" )
    fi
  done

  if (( ${#buf[@]} >= threshold )); then
    found=1
  fi

  (( found == 0 )) && return 0

  # ---------------------------------------------------------------------------
  # Step 3: 规范化输出
  # ---------------------------------------------------------------------------
  for line in "${buf[@]}"; do
    if [[ "$line" =~ $TIME_REGEX ]]; then
      local time="${BASH_REMATCH[1]}"
      local rest="${line#*$time}"

      # 去掉时间戳后正文开头的“非文字符号 + 空白”
      rest="$(printf '%s' "$rest" | LC_ALL=C sed -E 's/^[^[:alnum:]]+[[:space:]]+//')"

      printf '%s %s\n' "$time" "$rest"
    fi
  done
}
