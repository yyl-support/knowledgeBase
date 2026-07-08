---
tags:
  - 基础设施
  - 服务映射
  - 部署
---

# infrastructure — 服务映射表（service.md）

> 仓库：`opensourceways/infrastructure`（私有）
> 关联文档：`knowledge/infra-service-mapping-fields.md`

## 定位

`infrastructure/service.md` 是 openEuler 社区基础设施团队的 **"服务部署档案总表"**。它回答以下问题：

> 某个微服务的某个环境，源码在哪、配置在哪、部署在哪集群的哪个命名空间。

## 表结构（字段全解）

| 字段 | 含义 | 示例 |
|------|------|------|
| **微服务** | 服务唯一标识名 | `meeting-center`、`robot-hook-dispatcher` |
| **环境** | `prod` / `test` / `staging` | 同一个服务可有多个环境多行 |
| **域名** | 对外暴露的公网地址（空=仅集群内访问） | `meeting.ascend.osinfra.cn` |
| **镜像名** | Docker 完整地址 | `swr.cn-north-4.myhuaweicloud.com/opensourceway/meeting/meeting-center` |
| **镜像构建源码仓** | 构建镜像的 GitHub 源码地址 | — |
| **Vault Path** | 敏感配置在 Vault 中的路径 | `internal/data/infra-test/ascend-backend-robot` |
| **Vault Key** | 从 Vault Path 取哪些 key | `token`、`ServerCrt, ServerKey`、`dbConfig` |
| **部署归档仓库** | 部署 YAML 存放仓库 | `opensourceways/infra-common`（kustomize）或 `Open-Infra-Ops/helm-chart-value`（Helm） |
| **部署归档子路径** | 在上述仓库中的目录路径 | `ascend/meeting/prod` |
| **部署集群** | K8s 集群名 | `infra-hk-test-cluster-001` |
| **命名空间** | K8s ns | `ascend`、`ascend-robot` |
| **ArgoCD 域名** | GitOps 管理界面地址 | `https://build-01.test.osinfra.cn` |
| **ArgoCD 应用名** | ArgoCD 中注册的应用名 | — |
| **构建脚本路径** | Jenkins 构建任务配置 | `pipeline/helm-charts-ascend-robot-prod.txt` |
| **镜像版本路径** | 镜像 tag 在部署配置中的字段位置 | `.image.tag`（Helm）或 `.spec.template.spec.containers[0].image`（kustomize） |
| **归档方式** | `kustomize` 或 `helm` | 决定 CI 如何改部署配置文件 |

## 在 ai-flow 中的角色

`.ai-flow` 预览部署的关键步骤中，`sync.sh` 会：

1. **curl 拉取** `infrastructure/service.md`（或 `infra-common/service.md`）
2. **按 `(微服务名, "test", 社区名)` 三元组匹配行**
3. **取出 Vault Path + Vault Key** → 登录 Vault → 拉取真实配置
4. **改写为预览形态** → 烘成 k8s Secret → 挂载到预览 Pod

### 实际匹配逻辑差异

| 对比项 | backlog 通用模板 | forum-reply-robot 实际 |
|--------|-----------------|----------------------|
| service.md 源 | `opensourceways/infra-common` | `opensourceways/infrastructure` |
| 匹配方式 | 按 `(微服务名, "test", 社区)` 三列精确匹配 | 按 `(REPO 完整仓库名, "test")` 在 `cols[4]` URL 中模糊包含匹配 |
| 匹配列 | `cols[0]` = 微服务名 | `cols[4]` = 镜像构建源码仓 |

## 多仓库协作关系

```
infrastructure/service.md
        │
        ├──→ 被 backlog 的 .ai-flow/deploy 读取（预览部署）
        │
        ├──→ 被 CI/CD 流水线读取（生产部署时查找镜像版本路径）
        │
        ├──→ 指向 infra-common（kustomize 部署配置）
        │         或 helm-chart-value（Helm 部署配置）
        │
        └──→ 指向 Vault（敏感配置，含 DB 密码、API Key、证书）
```

---

## 🔗 相关笔记

- [[infra-service-mapping-fields]] — service.md 字段逐一详解
- [[概览]] — 基础设施总览
- [[forum-reply-robot-ai-flow-vault]] — Vault 链路用到 service.md
- [[backlog-issue-3-release-architecture]] — 发布依赖 service.md

> 索引：[[基础设施]] · 返回 [[首页]]
