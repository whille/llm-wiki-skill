#!/bin/bash
# Git post-commit hook for llm-wiki
# 检测代码变更并提示运行 wiki digest

set -euo pipefail

# 获取项目根目录
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
CONFIG_FILE="$PROJECT_ROOT/.llm-wiki.yaml"

# 默认配置
WATCH_DIRS="src/ lib/ scripts/"
DIGEST_THRESHOLD=5

# 读取项目配置（如果存在）
if [ -f "$CONFIG_FILE" ]; then
  # 解析 YAML（简单实现，不依赖 yq）
  WATCH_DIRS=$(grep -E "^watch_dirs:" -A 10 "$CONFIG_FILE" 2>/dev/null | grep -E "^  - " | sed 's/  - //' | tr '\n' ' ' || echo "$WATCH_DIRS")
  DIGEST_THRESHOLD=$(grep "digest_threshold:" "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' || echo "$DIGEST_THRESHOLD")
fi

# 构建 grep 正则匹配监视目录
WATCH_PATTERN=""
for dir in $WATCH_DIRS; do
  if [ -n "$WATCH_PATTERN" ]; then
    WATCH_PATTERN="$WATCH_PATTERN|"
  fi
  WATCH_PATTERN="$WATCH_PATTERN^$dir"
done

# 获取本次提交变更的文件
if [ -f "$PROJECT_ROOT/.git/COMMIT_EDITMSG" ]; then
  # 正常提交
  CHANGE_FILES=$(git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -E "$WATCH_PATTERN" | head -20 || true)
else
  # 首次提交或无父提交
  CHANGE_FILES=$(git diff --name-only --cached HEAD 2>/dev/null | grep -E "$WATCH_PATTERN" | head -20 || true)
fi

# 统计变更文件数
if [ -n "$CHANGE_FILES" ]; then
  COUNT=$(echo "$CHANGE_FILES" | wc -l | tr -d ' ')

  # 只在变更文件数 >= 阈值时提示
  if [ "$COUNT" -ge "$DIGEST_THRESHOLD" ]; then
    echo ""
    echo "================================================"
    echo "检测到 $COUNT 个代码文件变更"
    echo ""
    echo "变更文件："
    echo "$CHANGE_FILES" | head -10 | while read -r file; do
      echo "  - $file"
    done
    if [ "$COUNT" -gt 10 ]; then
      echo "  ... 还有 $((COUNT - 10)) 个文件"
    fi
    echo ""
    echo "建议: 运行 'wiki digest --code' 更新文档"
    echo "================================================"
    echo ""
  fi
fi

exit 0
