---
tags:
  - 基础设施
  - 部署
  - helm
  - kustomize
---

# infra-common — 部署配置管理

> 仓库：`opensourceways/infra-common`（私有）
> 关联文档：`doc/forum-reply-robot-ai-flow-vault.md` + `knowledge/infra-service-mapping-fields.md`

## 定位

`infra-common` 是 openEuler 社区基础设施团队的 **部署配置统一管理仓库**，存放所有微服务的 K8s Deployment/Service/Ingress 等 YAML 描述文件。

## 两种管理方式

| 方式 | 说明 | 镜像版本改写方式 |
|------|------|----------------|
| **kustomize** | 基于 base + overlay 的 patch 叠加 | 用 script 直接 sed/jq 改写 YAML 字段 |
| **helm** | 模板 + values.yaml 参数化 | 改 values.yaml 的对应字段 |

对应仓库：`infra-common`（kustomize）和 `Open-Infra-Ops/helm-chart-value`（Helm）。

## 部署归档子路径

路径按 `<项目>/<服务>/<环境>` 层级组织：
```
ascend/meeting/prod
ascend/robot/test
boostkit-meeting/prod
```

## 在 ai-flow 预览部署中的角色

`infra-common/service.md` 是 `.ai-flow` 预览部署链条的起点之一：

```
infra-common/service.md  ──→  被 sync.sh 拉取  ──→  匹配 Vault Path
                                                                   │
                                                                   ▼
                                                          Vault 拉取真实配置
                                                                   │
                                                                   ▼
                                                       改写 + 烘 k8s Secret
                                                                   │
                                                                   ▼
                                                     挂载到预览 Pod 启动
```

## 与 infrastructure 仓库的关系

- **infrastructure**：服务档案总表 + Vault 配置路径
- **infra-common**：部署配置的实际 YAML 文件 + CI 部署脚本

两者通过 `service.md` 中的"部署归档仓库"字段关联。`infra-common` 的 service.md 是 infrastructure 的**镜像或子集**，服务 `sync.sh` 时根据实际需要选择读取哪个仓库的 service.md。

### forum-reply-robot 中的差异

forum-reply-robot 的 `sync.sh` 读取的是 `opensourceways/infrastructure` 的 service.md，而 backlog 通用模板读取的是 `opensourceways/infra-common` 的 service.md。这是因为 forum-reply-robot 的 Vault 配置在 infrastructure 仓库中管理。

---

## 🔗 相关笔记

- [[概览]] — 基础设施总览
- [[infrastructure-服务映射表]] — 服务映射表
- [[服务间调用关系]] — 调用关系

> 索引：[[基础设施]] · 返回 [[首页]]
