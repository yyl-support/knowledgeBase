---
tags:
  - RAG
  - 评估
  - LLM-judge
---

# RAG 评估 — 轻量替代 deepeval

> 目标：不装 deepeval，复用 config.yaml 已有模型做评判，零额外依赖

## 对比

| | deepeval | 轻量方案 |
|---|---|---|
| 新依赖 | 30+ 包 | 0 |
| pip install | 数分钟 | 秒级 |
| 评判模型 | 需单独配置 | 复用 config.yaml |
| Pod 影响 | 击穿 readiness | 无 |

## 指标映射

| deepeval 指标 | 替代方案 | 实现方式 |
|---|---|---|
| ContextualRelevancy | **答案相关性** | LLM judge：问"回答是否直接回应了用户问题"，输出 0-1 |
| Faithfulness | **忠实性** | LLM judge：拆解回答为事实陈述，逐条判断检索上下文是否有依据，0-1 |
| — | **上下文精确率** | LLM 逐条判断每个 chunk 是否有用，计算有用/总数 |

## 评测流程

```
加载数据集 → 逐条构造中文 prompt → 调已有 LLM 打分
    → 解析 JSON → 按类别聚合均值 → 输出 Markdown 报告
```

三个 prompt 各约 15 行，核心代码约 60 行，全在 `run_baseline.py` 和 `templates.py` 中。

## 检索指标（无需 LLM）

检索延迟、chunk 去重率、检索召回量 —— 纯计算，已在 Prometheus 采集。

---

## 🔗 相关笔记

- [[2026-06-10-forum-reply-robot-阶段一-评估插桩与基线建设]] — 阶段一中的 deepeval 被本方案替代
- [[机器人类-forum-reply-robot]] — 服务概览

> 索引：[[RAG 体系]] · 返回 [[首页]]
