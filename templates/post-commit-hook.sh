#!/bin/bash
# Git post-commit hook for llm-wiki
# 检测代码变更并提示运行 wiki digest
# 支持排除模式：监控所有代码，排除非代码目录和文件

set -euo pipefail

# 获取项目根目录
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
CONFIG_FILE="$PROJECT_ROOT/.llm-wiki.yaml"

# 默认配置
EXCLUDE_DIRS="wiki/ data/ results/ output/ logs/ __pycache__/ .pytest_cache/ .ruff_cache/ node_modules/"
EXCLUDE_PATTERNS="*.json *.txt *.log *.md"
LINE_THRESHOLD=100

# 读取项目配置（如果存在）
if [ -f "$CONFIG_FILE" ]; then
  # 解析 exclude_dirs
  EXCLUDE_DIRS=$(grep -E "^exclude_dirs:" -A 20 "$CONFIG_FILE" 2>/dev/null | grep -E "^  - " | sed 's/  - //' | tr '\n' ' ' || echo "$EXCLUDE_DIRS")
  # 解析 exclude_patterns（简单处理，去掉 *)
  EXCLUDE_PATTERNS=$(grep -E "^exclude_patterns:" -A 10 "$CONFIG_FILE" 2>/dev/null | grep -E "^  - " | sed 's/  - //' | sed 's/\"//g' | tr '\n' ' ' || echo "$EXCLUDE_PATTERNS")
  LINE_THRESHOLD=$(grep "line_threshold:" "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' || echo "$LINE_THRESHOLD")
fi

# 获取提交范围
if [ -f "$PROJECT_ROOT/.git/COMMIT_EDITMSG" ]; then
  DIFF_RANGE="HEAD~1 HEAD"
else
  DIFF_RANGE="--cached HEAD"
fi

# 构建排除目录的正则（用于 grep -v）
EXCLUDE_DIR_PATTERN=""
for dir in $EXCLUDE_DIRS; do
  dir=$(echo "$dir" | sed 's:/$::')
  if [ -n "$EXCLUDE_DIR_PATTERN" ]; then
    EXCLUDE_DIR_PATTERN="$EXCLUDE_DIR_PATTERN|"
  fi
  EXCLUDE_DIR_PATTERN="$EXCLUDE_DIR_PATTERN^$dir/"
done

# 获取变更文件的增删行数统计，并排除指定目录
# numstat 格式: added\tdeleted\tfilename
if [ -n "$EXCLUDE_DIR_PATTERN" ]; then
  STAT_OUTPUT=$(git diff --numstat $DIFF_RANGE 2>/dev/null | grep -vE "$EXCLUDE_DIR_PATTERN" || true)
else
  STAT_OUTPUT=$(git diff --numstat $DIFF_RANGE 2>/dev/null || true)
fi

if [ -z "$STAT_OUTPUT" ]; then
  exit 0
fi

# 构建 grep 排除参数（排除文件模式）
EXCLUDE_GREP_ARGS=""
for pattern in $EXCLUDE_PATTERNS; do
  # 移除通配符后缀
  base_pattern=$(echo "$pattern" | sed 's/\*\.//g' | sed 's/\*$//g')
  if [ -n "$EXCLUDE_GREP_ARGS" ]; then
    EXCLUDE_GREP_ARGS="$EXCLUDE_GREP_ARGS --ignore=$base_pattern"
  else
    EXCLUDE_GREP_ARGS="--ignore=$base_pattern"
  fi
done

# 如果有排除模式，再次过滤
if [ -n "$EXCLUDE_PATTERNS" ]; then
  FILTERED_OUTPUT=""
  while IFS=$'\t' read -r added deleted filename; do
    skip=false
    for pattern in $EXCLUDE_PATTERNS; do
      # 简单模式匹配（支持 *.ext 格式）
      ext=$(echo "$pattern" | sed 's/\*\.//')
      if [[ "$filename" == *".$ext" ]]; then
        skip=true
        break
      fi
    done
    if [ "$skip" = false ]; then
      printf '%s\t%s\t%s\n' "$added" "$deleted" "$filename"
    fi
  done <<< "$STAT_OUTPUT"
  STAT_OUTPUT="$FILTERED_OUTPUT"
fi

if [ -z "$STAT_OUTPUT" ]; then
  exit 0
fi

# 统计总增删行数
TOTAL_ADDED=0
TOTAL_DELETED=0
FILE_COUNT=0

while IFS=$'\t' read -r added deleted filename; do
  # 跳过二进制文件（显示为 -）
  if [ "$added" = "-" ] || [ "$deleted" = "-" ]; then
    continue
  fi
  TOTAL_ADDED=$((TOTAL_ADDED + added))
  TOTAL_DELETED=$((TOTAL_DELETED + deleted))
  FILE_COUNT=$((FILE_COUNT + 1))
done <<< "$STAT_OUTPUT"

TOTAL_LINES=$((TOTAL_ADDED + TOTAL_DELETED))

# 只在代码行变化 >= 阈值时提示
if [ "$TOTAL_LINES" -ge "$LINE_THRESHOLD" ]; then
  echo ""
  echo "================================================"
  echo "检测到代码变更：+$TOTAL_ADDED / -$TOTAL_DELETED（共 $TOTAL_LINES 行，$FILE_COUNT 个文件）"
  echo ""
  echo "变更文件："
  echo "$STAT_OUTPUT" | head -10 | while IFS=$'\t' read -r added deleted filename; do
    if [ "$added" != "-" ] && [ "$deleted" != "-" ]; then
      echo "  - $filename (+$added/-$deleted)"
    fi
  done
  if [ "$FILE_COUNT" -gt 10 ]; then
    echo "  ... 还有 $((FILE_COUNT - 10)) 个文件"
  fi
  echo ""
  echo "建议: 运行 'wiki digest --code' 更新文档"
  echo "================================================"
  echo ""
fi

exit 0
