---
tags:
  - MOC
  - RAG
---

# 🔍 RAG 体系

> 围绕 forum-reply-robot 的 RAG（检索增强生成）知识看护与对外服务，覆盖需求、评估、管道、重构与对外接口。

## Issue #621 — RAG 持续看护演进

- [[2026-06-10-forum-reply-robot-issue分析]] — 五阶段需求规划
- [[2026-06-10-forum-reply-robot-阶段一-评估插桩与基线建设]] — 数据采集 + LightRAG 基线
- [[2026-06-10-forum-reply-robot-阶段二-影子管道建设]] — pgvector 四层影子管道
- [[2026-06-11-RAG评估方案-轻量替代deepeval]] — 零依赖 LLM judge 轻量评测

## 重构与切换

- [[0519-RAG切换]] — 四层模块化重构设计方案

## 对外服务（Issue #921）

- [[openUBMC RAG对外查询接口-架构设计说明书]] — 对外查询接口架构
- [[RAG对外API使用说明]] — 外部接入文档

## 测试方案

- [[Issue-785-921-联合测试方案]] — #785 + #921 联合测试 (20 项验收)
- [[Issue-921-安全测试方案]] — OIDC / 限流 / 透传安全测试 (27 用例)
- [[2026-06-26-backlog-issue785-测试方案]] — #785 阶段一测试方案 (175 用例)

## LightRAG 参考

- [[LightRAG_API_Documentation]] — LightRAG 原生 API 完整文档（/query vs /query/data 差异溯源）

## 相关服务

- [[机器人类-forum-reply-robot]] — 服务概览
- [[搜索服务类]] — LightRAG / 嵌入式检索

---

> 返回 [[首页]]
