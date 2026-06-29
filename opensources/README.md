---
tags:
  - 总览
  - MOC
  - opensources
---

# opensourceways 代码组织分析

> 分析时间：2026-06-10
> 最后更新：2026-06-21（新增 integration-tests 集成测试 + APIMagic 数据统计 API 平台分析）
> 组织地址：https://github.com/opensourceways

## 组织定位

`opensourceways` 是 **openEuler 社区基础设施团队** 的 GitHub 代码组织，负责建设与维护社区的基础设施服务、自动化工具、AI 驱动的开发流水线。公开可见 50 个仓库，核心业务仓库为私有。

## 服务分类体系

该组织的服务按业务领域分为七大类别：

| 类别 | 定位 | 代表性仓库 |
|------|------|-----------|
| **平台类** | AI 驱动的全自动软件开发流水线与项目管理 | `backlog`（私有） |
| **机器人类** | 社区自动化问答与事务处理机器人 | `forum-reply-robot`（私有） |
| **中台类** | 共享业务能力中心，为各前台服务提供通用能力 | `APIMagic`（私有） |
| **论坛服务类** | 基于 Discourse 的社区论坛平台 | `discourse`（fork） |
| **会议服务类** | 社区会议管理与直播服务 | `meeting-server`（私有） |
| **搜索服务类** | 社区内容搜索与检索服务 | — |
| **基础设施类** | 服务注册、配置管理、部署底座、开发工具链 | `infrastructure`（私有）、`infra-common`（私有）、`cora`、`agent-skills` |

## 核心串联机制：ai-flow

`backlog` 仓库中的 `.ai-flow` 系统是整个组织的 **"操作系统"** —— 它通过 Issue 驱动的 AI Agent 编排 + K8s 预览部署 + 门禁自动化 + 服务注册，将以上所有类别串成一条完整的 **"需求 → 设计 → 开发 → 测试 → 部署 → 发布"** 自动化流水线。

## 文档结构

```
opensources/
├── README.md                           # 本文件：组织概览
├── 分类概览/                            # 七大业务类别的代表性服务分析
│   ├── 平台类-backlog.md
│   ├── 机器人类-forum-reply-robot.md
│   ├── 中台类.md
│   ├── 中台类-APIMagic.md              # APIMagic 数据统计 API 平台详细分析
│   ├── 论坛服务类-discourse.md
│   ├── 会议服务类-meeting.md
│   └── 搜索服务类.md
├── 基础设施类/                          # 基础设施详细分析
│   ├── 概览.md                         # 基础设施整体架构
│   ├── infrastructure-服务映射表.md     # 服务注册与发现
│   ├── infra-common-部署配置.md        # 部署配置管理
│   ├── cora-统一命令工具.md            # 社区服务 CLI 工具
│   ├── agent-skills-共享技能库.md      # AI Agent 技能库
│   ├── integration-tests-集成测试.md   # 跨仓端到端集成测试详细分析
│   └── 服务间调用关系.md               # 基础设施各组件间的调用关系图
└── ai-flow串联/                        # ai-flow 串联分析
    ├── ai-flow如何串联全组织.md         # 端到端串联机制详解
    └── local-debug-本地调试体系.md       # docs/local-debug 本地调试工具集分析
```

## 关键发现

1. **大部分核心业务仓库为私有**：`backlog`、`forum-reply-robot`、`infrastructure`、`infra-common`、`APIMagic` 等均为私有仓库，通过 `opensourceways` 组织在 GitHub 上管理（仅对团队成员可见）。
2. **公开仓库以 fork 和工具为主**：公开可见的 50 个仓库大部分是上游开源项目的 fork（Discourse、Karmada、LightRAG 等），以及少量自研工具（cora、agent-skills、integration-tests）。
3. **ai-flow 是组织运转的中心**：backlog 仓库不仅是需求管理仓库，更是一套完整的 AI Agent 编排引擎，联动所有服务仓库的开发和部署。
4. **APIMagic 是数据中台核心**：275 个只读 API 端点覆盖 38 个业务分组，基于 MagicAPI 低代码框架，为所有社区看板提供统一的数据统计查询能力。
5. **integration-tests 实现 AI 闭环测试**：通过 AI Agent 自动生成测试用例 → TSE Agent 审查 → 自动修订（最多 3 轮）→ 合并 → 执行，覆盖 17 个微服务的端到端集成测试。

---

## 🔗 相关笔记

- [[平台类-backlog]] — 平台类
- [[机器人类-forum-reply-robot]] — 机器人类
- [[中台类]] — 中台类
- [[论坛服务类-discourse]] — 论坛服务类
- [[会议服务类-meeting]] — 会议服务类
- [[搜索服务类]] — 搜索服务类
- [[ai-flow如何串联全组织]] — ai-flow 串联
- [[概览]] — 基础设施概览
- [[术语解释]] — 术语字典

> 索引：[[服务总览]] · 返回 [[首页]]
