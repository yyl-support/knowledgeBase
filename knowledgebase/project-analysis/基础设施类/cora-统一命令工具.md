---
tags:
  - 基础设施
  - cora
  - CLI
  - 工具
---

# cora — 统一社区服务命令行工具

> 仓库：`opensourceways/cora`（公开）
> 语言：Go
> 分析来源：GitHub README 公开内容

## 定位

**Cora**（Community Collaboration）是面向开源开发者的**统一命令行工具**。通过单一二进制文件访问论坛、邮件列表、会议、Issue CICD 等社区服务，命令由各后端服务发布的 OpenAPI 3.0 Spec 动态驱动生成。

## 核心设计理念

- **零代码扩展**：接入新后端服务只需在配置文件加一条记录
- **OpenAPI 驱动**：命令在运行时根据各服务的 OpenAPI 3.0 Spec 动态生成
- **Spec 本地缓存**：缓存到本地（默认 24h），冷启动无需网络，延迟 < 200ms
- **脚本友好**：stdout/stderr 分离、语义化退出码、`--format json` 输出

## 已支持服务

| 服务 | 命令名 | Spec 来源 | 鉴权方式 |
|------|--------|----------|---------|
| GitCode | `gitcode` | 内置嵌入 | PAT token |
| GitHub | `github` | 内置嵌入 | PAT / Fine-grained Token |
| Etherpad | `etherpad` | 内置嵌入 | API Key |
| Jenkins | `jenkins` | 内置嵌入 | HTTP Basic Auth |
| Forum (Discourse) | `forum` | spec_url | API Key + 用户名 |
| EUR | `eur` | 内置嵌入 | HTTP Basic Auth |

## 命令结构

```
cora <服务> <资源> <操作> [参数]
```

三层结构：`<服务>` 来自 OpenAPI、`<资源>` 来自 OpenAPI `tags[0]`、`<操作>` 来自 `operationId`。

## 在基础设施体系中的角色

Cora 处于**工具链层**，是所有基础设施开发者的**日常操作入口**：

```
开发者 → cora CLI → 各社区服务 API
                      ├── Forum (Discourse)
                      ├── GitCode
                      ├── GitHub
                      ├── Etherpad
                      └── Jenkins
```

它不直接参与 ai-flow 的自动化流水线，但作为开发者与各服务的**统一交互界面**，降低了跨多个社区服务的操作复杂度。

---

## 🔗 相关笔记

- [[概览]] — 基础设施总览
- [[服务间调用关系]] — 调用关系

> 索引：[[基础设施]] · 返回 [[首页]]
