#!/bin/bash
# Git post-commit hook for llm-wiki
# 检测代码变更并提示运行 wiki digest

set -euo pipefail

# 获取项目根目录
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
CONFIG_FILE="$PROJECT_ROOT/.llm-wiki.yaml"

# 默认配置
WATCH_DIRS="src/ lib/ scripts/"
LINE_THRESHOLD=100

# 读取项目配置（如果存在）
if [ -f "$CONFIG_FILE" ]; then
  # 解析 YAML（简单实现，不依赖 yq）
  WATCH_DIRS=$(grep -E "^watch_dirs:" -A 10 "$CONFIG_FILE" 2>/dev/null | grep -E "^  - " | sed 's/  - //' | tr '\n' ' ' || echo "$WATCH_DIRS")
  LINE_THRESHOLD=$(grep "line_threshold:" "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' || echo "$LINE_THRESHOLD")
fi

# 构建 grep 正则匹配监视目录
WATCH_PATTERN=""
for dir in $WATCH_DIRS; do
  if [ -n "$WATCH_PATTERN" ]; then
    WATCH_PATTERN="$WATCH_PATTERN|"
  fi
  WATCH_PATTERN="$WATCH_PATTERN^$dir"
done

# 获取提交范围
if [ -f "$PROJECT_ROOT/.git/COMMIT_EDITMSG" ]; then
  DIFF_RANGE="HEAD~1 HEAD"
else
  DIFF_RANGE="--cached HEAD"
fi

# 获取变更文件的增删行数统计
# numstat 格式: added\tdeleted\tfilename
STAT_OUTPUT=$(git diff --numstat $DIFF_RANGE 2>/dev/null | grep -E "$WATCH_PATTERN" || true)

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
