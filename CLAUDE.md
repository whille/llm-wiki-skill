# CLAUDE.md

先看这三个文件：

- [README.md](README.md)：多平台总说明
- [platforms/claude/CLAUDE.md](platforms/claude/CLAUDE.md)：Claude 专属入口提示
- [SKILL.md](SKILL.md)：核心能力和工作流

---

## Git 流程规则

### 代码变更后更新 Wiki

**触发条件**：
- 用户说 "commit"、"提交"、"完成"、"push"
- 且项目根目录存在 `.wiki-schema.md` 或 `wiki/index.md`

**执行流程**：

1. **检测变更规模**：
   ```bash
   git diff --stat HEAD~1 HEAD
   ```

2. **判断是否需要更新 Wiki**：
   - 代码变更行数 >= 阈值（默认 100 行，读取 `.llm-wiki.yaml` 的 `line_threshold`）
   - 排除 `wiki/`、`*.md`、`data/`、`results/` 等非代码目录

3. **提示用户**：
   - 变更较小：静默跳过
   - 变更较大：提示 "检测到代码变更较大，是否运行 /llm-wiki-skill digest --code？"

**示例对话**：
```
用户: "commit these changes"
Agent: [检测到代码变更 +229/-104 行]
       检测到代码变更较大，是否运行 /llm-wiki-skill digest --code 更新文档？
用户: 是
Agent: [执行 /llm-wiki-skill digest --code]
```

---

## Claude 安装动作

如果当前任务是安装这个 skill，优先执行：

```bash
bash install.sh --platform claude
```

> `setup.sh` 是 `install.sh --platform claude` 的兼容包装，老用户可以继续用。

默认只准备知识库核心主线。如果这次要自动提取网页 / X / 微信公众号 / YouTube / 知乎，再执行：

```bash
bash install.sh --platform claude --with-optional-adapters
```

如果你希望 Claude Code 在会话开始时自动感知当前知识库上下文，可以执行：

```bash
# 配置 Claude Code hooks
mkdir -p ~/.claude/hooks
cat > ~/.claude/hooks/hooks.json << 'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/skills/llm-wiki/scripts/detect-wiki.sh" }]
      }
    ]
  }
}
EOF
```

## 原理篇：从 git hook 观察 Claude Code hooks 设计

> Claude Code hooks 和 git hooks 完全不同。git hooks 响应 git 命令；Claude hooks 响应 Claude Code 工具调用。
>
> 一个 Claude hook = 一个 JSON 文件，声明匹配的 Tool + 触发的脚本。
>
> 吞吐角色（hooks vs rules）：hooks 改变行为，rules 改变认知（prompt）。

### Claude Code hooks 实战（3 例）

| 场景 | Hook 类型 | 行为 |
|------|-----------|------|
| Edit 前强制 Read | PreToolUse | 拦截 Edit，要求必须先 Read |
| Bash 前安全检查 | PreToolUse | 拦截 rm -rf，需二次确认 |
| 记录交互历史 | PostToolUse | 每次对话后追加记录 |

### Claude hooks vs Git hooks

| 维度 | Claude hooks | Git hooks |
|------|-------------|-----------|
| 触发源 | Claude Code 工具调用 | git 命令 |
| 运行环境 | Claude CLI 进程内 | 独立 shell 进程 |
| 能否阻塞父进程 | ✅ 可以阻塞 Claude | ✅ 可以阻塞 git |
| 能否调用 Claude API | ❌ 不行（死锁） | ❌ 不行（环境隔离） |

**结论**：Git hooks 和 Claude hooks 都是无法直接调用 Agent 的。要触发 Agent 行为，唯一可行的方式是：**写入 Rule（如 CLAUDE.md），让 Agent 理意图后执行。**

### Claude hooks 最佳实践（设计思路）

- **拦截验证型**：用钩子检查工具参数合法性（如 Edit 前强制 Read）
- **审计记录型**：用钩子记录关键操作（如记录每次 Bash 命令）
- **纯 shell 脚本**：不要尝试在钩子里调用 Claude API（会死锁）
- **复杂逻辑放 rules**：触发 Agent 行为的逻辑，应写在 CLAUDE.md 而非 hooks

---

## 和原项目 的区别

原项目 Nutlope/llm-wiki 是 Claude Code 知识库技能的原始实现。

本项目 whille/llm-wiki-skill 的区别：

1. **添加 Git 流程规则**：代码变更后自动提示更新 Wiki
2. **移除无用 Git hooks**：git hook 无法触发 Agent 动作，改用 CLAUDE.md rule

详见 [CHANGELOG.md](CHANGELOG.md)。
