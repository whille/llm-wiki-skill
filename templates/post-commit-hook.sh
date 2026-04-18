#!/bin/bash
# Git post-commit hook for llm-wiki
# 检测代码变更并提示运行 wiki digest
# 支持排除模式：监控所有代码，排除非代码目录和文件

set -euo pipefail

# 获取项目根目录
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
CONFIG_FILE="$PROJECT_ROOT/.llm-wiki.yaml"

# 默认配置
EXCLUDE_DIRS="wiki/ data/ results/ output/ logs/"
EXCLUDE_PATTERNS="*.md"
LINE_THRESHOLD=100

# 读取项目配置（如果存在）
if [ -f "$CONFIG_FILE" ]; then
  EXCLUDE_DIRS=$(grep -E "^exclude_dirs:" -A 20 "$CONFIG_FILE" 2>/dev/null | grep -E "^  - " | sed 's/  - //' | sed 's/"//g' | tr '\n' ' ' || echo "$EXCLUDE_DIRS")
  EXCLUDE_PATTERNS=$(grep -E "^exclude_patterns:" -A 10 "$CONFIG_FILE" 2>/dev/null | grep -E "^  - " | sed 's/  - //' | sed 's/"//g' | tr '\n' ' ' || echo "$EXCLUDE_PATTERNS")
  LINE_THRESHOLD=$(grep "line_threshold:" "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' || echo "$LINE_THRESHOLD")
fi

# 获取提交范围
if [ -f "$PROJECT_ROOT/.git/COMMIT_EDITMSG" ]; then
  DIFF_RANGE="HEAD~1 HEAD"
else
  DIFF_RANGE="--cached HEAD"
fi

# 构建排除目录的正则
EXCLUDE_DIR_PATTERN=""
for dir in $EXCLUDE_DIRS; do
  dir=$(echo "$dir" | sed 's:/$::')
  if [ -n "$EXCLUDE_DIR_PATTERN" ]; then
    EXCLUDE_DIR_PATTERN="$EXCLUDE_DIR_PATTERN|"
  fi
  EXCLUDE_DIR_PATTERN="$EXCLUDE_DIR_PATTERN^$dir/"
done

# 获取变更文件统计，排除指定目录
if [ -n "$EXCLUDE_DIR_PATTERN" ]; then
  STAT_OUTPUT=$(git diff --numstat $DIFF_RANGE 2>/dev/null | grep -vE "$EXCLUDE_DIR_PATTERN" || true)
else
  STAT_OUTPUT=$(git diff --numstat $DIFF_RANGE 2>/dev/null || true)
fi

if [ -z "$STAT_OUTPUT" ]; then
  exit 0
fi

# 过滤排除文件模式
FILTERED=""
while IFS=$'\t' read -r added deleted filename; do
  skip=0
  # 遍历所有排除模式
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    ext=$(echo "$pattern" | sed 's/\*\.//' | tr -d ' ')
    if [[ "$filename" == *".$ext" ]]; then
      skip=1
      break
    fi
  done < <(grep -E "^exclude_patterns:" -A 10 "$CONFIG_FILE" 2>/dev/null | grep -E "^  - " | sed 's/  - //' | sed 's/"//g')
  if [ "$skip" -eq 0 ]; then
    if [ -n "$FILTERED" ]; then
      FILTERED="${FILTERED}"$'\n'"${added}"$'\t'"${deleted}"$'\t'"${filename}"
    else
      FILTERED="${added}"$'\t'"${deleted}"$'\t'"${filename}"
    fi
  fi
done <<< "$STAT_OUTPUT"

if [ -z "$FILTERED" ]; then
  exit 0
fi

# 统计总增删行数
TOTAL_ADDED=0
TOTAL_DELETED=0
FILE_COUNT=0

while IFS=$'\t' read -r added deleted filename; do
  if [ "$added" = "-" ] || [ "$deleted" = "-" ]; then
    continue
  fi
  TOTAL_ADDED=$((TOTAL_ADDED + added))
  TOTAL_DELETED=$((TOTAL_DELETED + deleted))
  FILE_COUNT=$((FILE_COUNT + 1))
done <<< "$FILTERED"

TOTAL_LINES=$((TOTAL_ADDED + TOTAL_DELETED))

# 只在代码行变化 >= 阈值时提示
if [ "$TOTAL_LINES" -ge "$LINE_THRESHOLD" ]; then
  echo ""
  echo "================================================"
  echo "检测到代码变更：+${TOTAL_ADDED} / -${TOTAL_DELETED}（共 ${TOTAL_LINES} 行，${FILE_COUNT} 个文件）"
  echo ""
  echo "变更文件："
  echo "$FILTERED" | head -10 | while IFS=$'\t' read -r added deleted filename; do
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
