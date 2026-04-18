#!/bin/bash
# Install Git Hook for project-level wiki digest
# 用法: bash install-git-hook.sh [--uninstall]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="$(dirname "$SCRIPT_DIR")/templates"

# 查找项目根目录
find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

PROJECT_ROOT=$(find_project_root) || {
  echo "错误: 当前目录不在 Git 仓库中"
  exit 1
}

HOOKS_DIR="$PROJECT_ROOT/.git/hooks"
POST_COMMIT_HOOK="$HOOKS_DIR/post-commit"
HOOK_TEMPLATE="$TEMPLATES_DIR/post-commit-hook.sh"
CONFIG_TEMPLATE="$TEMPLATES_DIR/project-config.yaml"
CONFIG_FILE="$PROJECT_ROOT/.llm-wiki.yaml"

info()  { printf '\033[36m[信息]\033[0m %s\n' "$1"; }
ok()    { printf '\033[32m[完成]\033[0m %s\n' "$1"; }
warn()  { printf '\033[33m[警告]\033[0m %s\n' "$1"; }

install_hook() {
  # 确保_hooks 目录存在
  mkdir -p "$HOOKS_DIR"

  # 检查是否已有 post-commit hook
  if [ -f "$POST_COMMIT_HOOK" ]; then
    # 检查是否已经是我们安装的
    if grep -q "llm-wiki" "$POST_COMMIT_HOOK" 2>/dev/null; then
      info "Git Hook 已存在，跳过安装"
      return 0
    fi

    # 备份现有 hook
    cp "$POST_COMMIT_HOOK" "$POST_COMMIT_HOOK.bak.$(date +%Y%m%d%H%M%S)"
    warn "已备份现有 post-commit hook"
  fi

  # 安装新 hook
  cp "$HOOK_TEMPLATE" "$POST_COMMIT_HOOK"
  chmod +x "$POST_COMMIT_HOOK"

  ok "Git Hook 已安装到: $POST_COMMIT_HOOK"
}

install_config() {
  if [ -f "$CONFIG_FILE" ]; then
    info "配置文件已存在: $CONFIG_FILE"
    return 0
  fi

  cp "$CONFIG_TEMPLATE" "$CONFIG_FILE"
  ok "配置文件已创建: $CONFIG_FILE"
  echo ""
  echo "请根据项目需要编辑配置文件:"
  echo "  - watch_dirs: 监控的代码目录"
  echo "  - digest_threshold: 触发提示的最小变更文件数"
}

uninstall_hook() {
  if [ -f "$POST_COMMIT_HOOK" ]; then
    if grep -q "llm-wiki" "$POST_COMMIT_HOOK" 2>/dev/null; then
      # 恢复备份（如果存在）
      BACKUP=$(ls -t "$POST_COMMIT_HOOK".bak.* 2>/dev/null | head -1)
      if [ -n "$BACKUP" ]; then
        mv "$BACKUP" "$POST_COMMIT_HOOK"
        ok "已恢复备份的 post-commit hook"
      else
        rm "$POST_COMMIT_HOOK"
        ok "已删除 Git Hook"
      fi
    else
      info "post-commit hook 不是由 llm-wiki 安装，跳过"
    fi
  else
    info "未找到 post-commit hook"
  fi

  # 询问是否删除配置文件
  if [ -f "$CONFIG_FILE" ]; then
    echo ""
    read -p "是否删除配置文件 $CONFIG_FILE？[y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      rm "$CONFIG_FILE"
      ok "已删除配置文件"
    fi
  fi
}

# 主逻辑
if [ "${1:-}" = "--uninstall" ]; then
  uninstall_hook
else
  echo ""
  echo "================================"
  echo "  LLM-Wiki Git Hook 安装"
  echo "================================"
  echo ""
  echo "项目根目录: $PROJECT_ROOT"
  echo ""

  install_hook
  install_config

  echo ""
  echo "使用方式:"
  echo "  1. 编辑 .llm-wiki.yaml 配置监控目录"
  echo "  2. 正常 git commit 提交代码"
  echo "  3. 变更文件数 >= 阈值时自动提示"
  echo ""
  echo "卸载: bash $0 --uninstall"
fi
