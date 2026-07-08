---
tags:
  - 服务
  - meeting
  - 会议类
---

# 会议服务类 — meeting-server

> 代表性仓库：`opensourceways/meeting-server`（私有，推测）
> 分析来源：`integration-tests` 仓库公开信息 + `backlog-architecture.md` + `infra-service-mapping-fields.md`

## 仓库定位

openEuler 社区的**会议管理与直播服务平台**，为社区 SIG 组会议提供创建、管理、直播、录制、回放等能力。

## 已知信息

### 从 integration-tests 仓库获取的测试结构

```
integration-tests/services/meeting-server/
├── base_community/          # 所有社区共用的公共测试用例
└── openeuler_community/      # openEuler 社区专属测试用例
```

meeting-server 是唯一一个有独立集成测试的服务，说明它在整个组织中的**重要性**和**稳定性要求**较高。

### 从 backlog 架构文档获取的信息

- 在 `.ai-flow/services/` 中有 `meeting-server.yaml` 作为**最完整的全栈服务配置示例**（128 行），是其他服务接入的参考模板。
- 在 `infrastructure/service.md` 中有 `meeting-center` 等会议相关服务的部署记录。

### 服务分类猜测

| 服务名 | 推测用途 |
|--------|---------|
| `meeting-server` | 会议核心后端服务 |
| `meeting-center` | 会议管理前端/中台 |
| `meeting-mcp`（已归档） | 会议 MCP 协议工具 |

## 技术栈推测

- **CI/CD**：通过 `.ai-flow` 的 AI Agent 自动开发
- **部署**：K8s + ArgoCD（GitOps）
- **测试**：`integration-tests/services/meeting-server/`

---

## 🔗 相关笔记

- [[integration-tests-集成测试]] — 集成测试涉及 meeting
- [[README]] — 组织总览

> 索引：[[服务总览]] · 返回 [[首页]]
