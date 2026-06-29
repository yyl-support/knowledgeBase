---
tags:
  - 服务
  - backlog
  - 平台类
---

# 平台类 — backlog

> 代表性仓库：`opensourceways/backlog`（私有）
> 分析来源：公开文档 + `backlog-architecture.md` + `backlog-ai-flow-commands.md`

## 仓库定位

`backlog` 是 openEuler 社区基础设施团队的**需求与交付管理仓库**，同时也是一个 **AI 驱动的全自动软件开发流水线控制中心**。

## 核心能力

- **需求全生命周期管理**：需求分析 → 架构设计 → 开发预览 → 测试发布 → 正式上线
- **AI Agent 多角色协作**：design / dev / review / tester 四个 AI Agent 协同完成开发任务
- **K8s 预览部署**：每个 Issue 自动在 K8s 集群中起预览环境（runtime-clone 模式）
- **门禁自动化**：7 项检查（敏感信息/设计文档/漏洞扫描/安全编码/License/镜像漏洞/UT 覆盖率）
- **服务注册**：19 个 YAML 配置文件管理所有业务服务的接入

## 架构亮点 — 引擎不动 + YAML 驱动

```
接新服务 = 加一个 services/<id>.yaml
            ↓
    不改引擎   不改 workflow   不写脚本
```

这是 `.ai-flow` 最核心的哲学：通过 YAML 配置驱动，零代码接入新服务。

## 三段式工作流

| 阶段 | 命令 | 职责 |
|------|------|------|
| Phase A | `/ai-requirement-analysis` | AI 产出需求分析说明书，自动评估标签 |
| Phase B1 | `/ai-develop-preview` | 设计 → 开发 → 部署 → 冒烟，出预览版本 |
| Phase B2 | `/ai-develop-submit` | 门禁 → review → 测试 → security-gate → 开 PR |
| Phase C | `/ai-deploy-test` | 构建镜像 → 推 SWR → 改 GitOps → ArgoCD → 集成测试 |

## 技术栈

- **编排引擎**：`orchestrate.sh`（1458 行 Shell 脚本）
- **AI CLI**：OpenCode / Claude Code
- **部署**：Kubernetes（runtime-clone Pod 模式）+ PostgreSQL 底座 + Vault 配置管理
- **路由**：`resolve_service.py`（按 Issue label 匹配服务 YAML）

---

## 🔗 相关笔记

- [[backlog-architecture]] — 架构详解
- [[backlog-ai-flow-commands]] — 命令系统
- [[ai-flow如何串联全组织]] — ai-flow 串联
- [[README]] — 组织总览

> 索引：[[服务总览]] · [[ai-flow 体系]] · 返回 [[首页]]
