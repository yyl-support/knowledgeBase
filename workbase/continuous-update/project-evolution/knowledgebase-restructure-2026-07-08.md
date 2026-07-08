---
tags:
  - project-evolution
  - 知识库重构
date: 2026-07-08
---

# 知识库结构重构设计（2026-07-08）

> 本文档记录本知识库从「按来源分目录」到「knowledgebase + workbase 双层结构」的一次结构重构设计与迁移映射，作为工程演进记录长期保留。

## 一、目标

将知识库一级结构划分为两大区：

- **knowledgebase/**：存储已有的、相对稳定的知识
- **workbase/**：存储每日流动的工作内容

## 二、目标结构

```
knowledgeBase/
├── 首页.md  欢迎.md            # 保留在根，作为全局导航入口
├── MOC/                        # 保留主题地图导航
├── knowledgebase/              # 【已有知识】
│   ├── project-analysis/       # 开源库中的工程结构分析
│   ├── soft-knowledge/         # 软件工程 / 计算机方面的知识
│   ├── paper-interpretation/   # 论文
│   ├── industry-insight/       # 业界文章 / 论坛分享
│   └── other/                  # 其他暂未分类
└── workbase/                   # 【每日工作】
    ├── todo-list/              # 每日工作项，按 年/月/日；可接入 day-planner 插件并关联日历
    ├── daliy-works/            # 当天的问题分析 / 工作分析，按 年/月/日
    ├── continuous-update/      # 会持续覆写更新的工作，按任务类型归类
    │   ├── issue-analysis/     #   针对某 issue 的分析
    │   └── project-evolution/  #   某工程的持续性演进 / 设计方案
    └── temp-space/             # 临时空间：一天之内所有持久化知识，按 年/月/日
```

## 三、命名与归类原则

- `knowledgebase/` 下文件名直接使用内容摘要名称，再按内容放入 5 个二级目录。
- `workbase/` 下按 **年/月/日** 三层目录归类（`todo-list`、`daliy-works`、`temp-space`）。
- `continuous-update/` 按任务类型归类（`issue-analysis`、`project-evolution` …）。
- `temp-space` 是一天之内交互最频繁的工作区；日终再统一归档到其他目录。

## 四、本次迁移映射

### → knowledgebase/project-analysis/
- `opensources/` 根：clowder-ai-analysis、codearts-workflow-analysis、pipelineascode-ecosystem-overview、README
- `opensources/ai-flow串联/`、`opensources/分类概览/`、`opensources/基础设施类/`（整目录）
- `opensources/forum-reply-robot/` 知识类文档 → `project-analysis/forum-reply-robot/`：LightRAG_API_Documentation、openUBMC RAG对外查询接口-架构设计说明书、RAG API 测试环境联调指南、RAG对外API使用说明、vault-config-新增段.yaml
- `doc/2026-06-09/`：backlog-architecture、backlog-ai-flow-commands、forum-reply-robot-ai-flow-vault
- `knowledge/pipeline-example/`（整目录）

### → knowledgebase/soft-knowledge/
- `knowledge/`：git-setup-notes、OIDC认证与常见认证手段、密钥与凭据管理、名词解释
- `knowledge/2026-06-09/infra-service-mapping-fields`
- `opensources/术语解释`、`other/backlog-CI-术语解释`

### → knowledgebase/other/
- `other/RAG重构规范` 之外的杂项：产品责任田.xlsx

### → workbase/daliy-works/（年/月/日）
- `error/` 全部 5 篇（06-09 / 06-10 / 06-16 ×2 / 06-23）
- `other/2026-06-10-*`（3 篇）、`other/2026-06-11-RAG评估方案-轻量替代deepeval`

### → workbase/continuous-update/issue-analysis/
- `opensources/issue-921-*`（3 篇）
- `opensources/forum-reply-robot/Issue-785-921-联合测试方案`、`Issue-921-安全测试方案`、`Issue-921-测试命令`
- `doc/2026-06-17/backlog-issue-3-release-architecture`
- `other/2026-06-26-backlog-issue785-测试方案`

### → workbase/continuous-update/project-evolution/
- `plan/wukong-design`、`plan/yyl-agents-design`、`plan/0519/0519-RAG切换`
- `other/RAG重构规范`
- 本设计文档

## 五、导航与链接处理

- `首页.md`、`欢迎.md` 保留在根，更新其中「目录结构」描述指向新结构。
- `MOC/` 保留；Obsidian 的 `[[wikilink]]` 按文件名解析，迁移不改文件名，双向链接不受影响。
- 迁移一律使用 `git mv` 保留历史。

## 六、todo-list 接入 day-planner（说明）

1. **Day Planner** 插件已安装并启用（v0.31.0，https://github.com/ivan-lednev/obsidian-day-planner）。
2. 核心「Daily Notes」插件已配置（`.obsidian/daily-notes.json`）：文件夹 `workbase/todo-list`、日期格式 `YYYY/MM/DD/YYYY-MM-DD`，即每日笔记落在 `workbase/todo-list/年/月/日/年-月-日.md`。Day Planner 直接读取该设置。
3. 每天在当日 todo 文件中用 `- HH:MM - HH:MM 任务` 的格式记录，插件会自动关联时间轴/日历。
