#!/bin/bash
# llm-wiki 依赖安装脚本
# 安装素材提取所需的配套 skill
set -e

SKILLS_DIR="$HOME/.claude/skills"

# 颜色输出
info()  { echo "\033[36m[信息]\033[0m $1"; }
ok()    { echo "\033[32m[完成]\033[0m $1"; }
warn()  { echo "\033[33m[警告]\033[0m $1"; }
err()   { echo "\033[31m[错误]\033[0m $1"; }

echo ""
echo "================================"
echo "  llm-wiki 依赖安装"
echo "================================"
echo ""

# 检查 npx 是否可用
if ! command -v npx &>/dev/null; then
    err "未找到 npx，请先安装 Node.js"
    echo "  安装方式：brew install node"
    exit 1
fi

# 定义依赖：名称、skill 目录名、安装命令
declare -A DEPS
DEPS=(
    ["baoyu-url-to-markdown"]="网页和公众号文章提取"
    ["x-article-extractor"]="X (Twitter) 内容提取"
    ["youtube-transcript"]="YouTube 字幕提取"
)

MISSING=()
for skill_name in "${!DEPS[@]}"; do
    if [ -d "$SKILLS_DIR/$skill_name" ]; then
        ok "$skill_name 已安装（${DEPS[$skill_name]}）"
    else
        warn "$skill_name 未安装（${DEPS[$skill_name]}）"
        MISSING+=("$skill_name")
    fi
done

if [ ${#MISSING[@]} -eq 0 ]; then
    echo ""
    ok "所有依赖已就绪！可以直接使用 llm-wiki。"
    exit 0
fi

echo ""
echo "需要安装 ${#MISSING[@]} 个依赖："
for skill_name in "${MISSING[@]}"; do
    echo "  - $skill_name（${DEPS[$skill_name]}）"
done
echo ""

# 尝试用 npx skills add 安装
info "正在安装缺失的依赖..."
echo ""

FAILED=()
for skill_name in "${MISSING[@]}"; do
    info "安装 $skill_name..."
    if npx skills add "$skill_name" 2>/dev/null; then
        ok "$skill_name 安装成功"
    else
        warn "$skill_name 自动安装失败"
        FAILED+=("$skill_name")
    fi
done

echo ""
echo "================================"

if [ ${#FAILED[@]} -eq 0 ]; then
    ok "所有依赖安装完成！"
else
    echo ""
    warn "以下 skill 自动安装失败，请手动安装："
    for skill_name in "${FAILED[@]}"; do
        echo "  npx skills add $skill_name"
    done
    echo ""
    echo "手动安装命令："
    for skill_name in "${FAILED[@]}"; do
        echo "  npx skills add $skill_name"
    done
    echo ""
    echo "注意：部分 skill 可能需要在 skills 注册表中搜索对应名称。"
    echo "可以使用 'npx skills find <关键词>' 搜索。"
fi

echo ""
echo "提示：即使部分依赖缺失，llm-wiki 仍可使用："
echo "  - 缺少 baoyu-url-to-markdown → 无法自动提取网页/公众号"
echo "  - 缺少 x-article-extractor → 无法自动提取 X/Twitter 内容"
echo "  - 缺少 youtube-transcript → 无法自动提取 YouTube 字幕"
echo "  - 上述情况可以手动粘贴文本内容作为替代"
