---
tags:
  - 服务
  - forum-reply-robot
  - 机器人类
  - RAG
---

# 机器人类 — forum-reply-robot

> 代表性仓库：`opensourceways/forum-reply-robot`（私有）
> 分析来源：公开文档 + `forum-reply-robot-issue分析.md` + `阶段一/阶段二` 设计文档

## 仓库定位

openEuler 社区论坛的**智能自动回帖机器人**，基于 RAG（检索增强生成）技术对新帖子自动生成回复。当前线上版本委托 LightRAG HTTP 服务进行检索，正在建设中引入独立的 pgvector + 混合检索 + rerank 影子管道。

## 核心架构

```
论坛新帖 → Monitor 监控 → RAG Pipeline → LLM 生成 → 自动回帖
                              │
                    ┌─────────┼─────────┐
                    │  L2 检索层          │
                    │  (向量+BM25+KG)     │
                    └─────────┬─────────┘
                              │
                    ┌─────────┼─────────┐
                    │  L3 处理层          │
                    │  (RRF融合+Rerank)   │
                    └─────────┬─────────┘
                              │
                    ┌─────────┼─────────┐
                    │  L4 生成层          │
                    │  (LLM 生成回答)     │
                    └───────────────────┘
```

## 当前状态（四阶段演进路线）

| 阶段 | 状态 | 内容 |
|------|------|------|
| 阶段一 | ✅ 完成 | 评估插桩 + LightRAG 基线建设（Prometheus metrics、deepeval 评测） |
| 阶段二 | 🔄 进行中 | pgvector 影子管道建设（四层架构新管道，离线对比评测） |
| 阶段三 | ⏳ 待开始 | 持续对比运行（每周定时评测、统计检验） |
| 阶段四 | ⏳ 待开始 | 数据驱动决策（灰度切换或融合路由） |

## 关键依赖

- **检索服务**：LightRAG HTTP（当前）/ pgvector + BM25 + Rerank（影子管道）
- **LLM**：SiliconFlow API（DeepSeek-V3）
- **Embedding**：Qwen3-Embedding-0.6B / BGE-M3
- **Rerank**：BGE-Reranker-v2-m3
- **评测框架**：deepeval
- **基础设施**：PostgreSQL（pgvector extension）、Vault（配置管理）、K8s（部署）

---

## 🔗 相关笔记

- [[2026-06-10-forum-reply-robot-issue分析]] — issue#621 需求分析
- [[openUBMC RAG对外查询接口-架构设计说明书]] — RAG 对外接口
- [[搜索服务类]] — RAG / 检索
- [[README]] — 组织总览

> 索引：[[服务总览]] · [[RAG 体系]] · 返回 [[首页]]
