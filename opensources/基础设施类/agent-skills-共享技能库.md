---
tags:
  - 基础设施
  - agent-skills
  - AI
---

# agent-skills — AI Agent 共享技能库

> 仓库：`opensourceways/agent-skills`（公开）
> 语言：Python / Markdown
> 分析来源：GitHub README 公开内容

## 定位

`agent-skills` 是一个**集中管理和共享 Claude Code Skills 的部门级仓库**，支持多团队协作。它为整个 opensourceways 组织的 AI Agent（如 backlog 的 design/dev/review/tester）提供可复用的操作技能。

## 仓库结构

```
agent-skills/
├── skills/
│   ├── infrastructure/  # 基础设施团队专属 skills
│   ├── upstream/        # 上游开发贡献团队专属 skills
│   ├── operation/       # 社区运营团队专属 skills
│   └── shared/          # 跨团队共享的 skills
├── templates/           # Skill 模板
└── docs/                # 文档和使用指南
```

## 接入方式

在 Claude Code 中通过 plugin marketplace 机制接入：

```bash
# 添加 marketplace
/plugin marketplace add opensourceways/agent-skills

# 安装 skill（交互式或命令行）
/plugin install <skill-name>@opensourceways-agent-skills
```

## 三团队协作模式

| 团队 | 目录 | 职责范围 |
|------|------|---------|
| **Infrastructure** | `skills/infrastructure/` | 基础设施建设（K8s、数据库、CI/CD、部署） |
| **Upstream** | `skills/upstream/` | 上游开源社区开发贡献 |
| **Operation** | `skills/operation/` | 社区运营（活动、内容、用户管理） |
| **Shared** | `skills/shared/` | 跨团队通用能力 |

## 在基础设施体系中的角色

`agent-skills` 位于**工具链层**，是 AI Agent 的知识底座：

```
agent-skills (技能库)
      │
      ├──→ infrastructure Agent: "如何部署一个服务到 K8s"
      ├──→ upstream Agent:      "如何提交一个上游 PR"
      ├──→ operation Agent:     "如何发布社区公告"
      └──→ shared:              "通用 GitHub/代码操作技能"
               │
               ▼
    backlog 的 .ai-flow Agent (design/dev/review/tester)
    通过 README + Claude Code plugin 使用这些技能
```

与 `cora`（给人用的 CLI）不同，`agent-skills` 是**给 AI Agent 用的知识库**，两者是人工操作与 AI 自动化的互补关系。

---

## 🔗 相关笔记

- [[概览]] — 基础设施总览
- [[服务间调用关系]] — 调用关系

> 索引：[[基础设施]] · [[ai-flow 体系]] · 返回 [[首页]]
