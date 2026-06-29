---
tags:
  - MOC
  - issue
---

# 📌 Issue 专题

> 按 GitHub Issue 编号聚拢相关文档，串起设计、部署、测试、故障的全过程。

## Issue #921 — openUBMC RAG 对外查询接口

为 `forum-reply-robot` 新增对外 RAG 检索 API，打通对外域名并接入 OneID OIDC 认证。

- [[openUBMC RAG对外查询接口-架构设计说明书]] — 架构设计总纲
- [[issue-921-OIDC认证完整机制]] — OneID 授权码模式完整流程
- [[issue-921-helm改动对比分析]] — helm-charts Service / Ingress 改动
- [[issue-921-RAG对外域名全链路]] — DNS → ELB → Ingress → Service → Pod 全链路
- [[RAG对外API使用说明]] — 外部接入文档与 Python 示例
- [[RAG API 测试环境联调指南]] — 测试环境联调手册
- [[Issue-921-测试命令]] — curl 测试命令速查
- [[2026-06-16-forum-reply-robot-preview-对抗轮次超限]] — 相关故障：开发预览对抗轮次超限
- [[Issue-921-安全测试方案]] — OIDC / 限流 / 透传安全测试 (27 用例)
- [[Issue-785-921-联合测试方案]] — #785 + #921 联合功能测试 (20 项验收)

## Issue #785 — 评估插桩与基线建设

为 forum-reply-robot 新增评估数据采集（Prometheus 指标 + evaluation_samples）+ 离线评测基线。

- [[2026-06-26-backlog-issue785-测试方案]] — 阶段一测试方案 (175 用例)
- [[2026-06-10-forum-reply-robot-阶段一-评估插桩与基线建设]] — 阶段一设计文档
- [[Issue-785-921-联合测试方案]] — #785 + #921 联合测试

## Issue #621 — 社区回复机器人 RAG 持续看护

为社区回复机器人构建 RAG 持续看护能力，分阶段做评估、影子管道与部署落地。

- [[2026-06-10-forum-reply-robot-issue分析]] — 五阶段需求规划
- [[2026-06-10-forum-reply-robot-阶段一-评估插桩与基线建设]] — 数据采集 + 基线
- [[2026-06-10-forum-reply-robot-阶段二-影子管道建设]] — pgvector 影子管道
- [[2026-06-10-backlog-issue621-preview-deploy-failed]] — 预览部署失败故障
- [[2026-06-09-forum-reply-robot-pod启动超时]] — Pod 启动超时故障

---

> 返回 [[首页]]
