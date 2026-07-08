---
tags:
  - RAG
  - forum-reply-robot
  - issue-621
  - 需求分析
issue: 621
---

# forum-reply-robot Issue #621 — 社区回复机器人rag持续看护

**链接**: https://github.com/opensourceways/backlog/issues/621  
**状态**: open  **创建者**: @yyl-support  **创建时间**: 2026-06-04  
**标签**: accepted, need_design, need_security, sig/infratructure, feature-request, project:forum-reply-robot  
**评论数**: 86

## 需求背景

软件结构层面：项目和LightRAG耦合度过高，不适合技术演进。  
业务场景层面：本质是FAQ召回，LightRAG适合跨文档多跳推理，与当前场景不匹配。  
运维层面：RAG全流程以HTTP接口调用，内部黑盒，无法感知检索失败/延迟/变更原因。

---

## 代码库关键事实（决定方案设计的前提）

当前工程（`forum-reply-robot`，~4000行Python，位于 `/Users/gorden/huawei/code/forum-reply-robot/`）的实际情况：

| 事实 | 对方案的影响 |
|------|------------|
| 项目内**没有本地RAG pipeline**——检索全通过 `forum_client.py:165` 的 `POST /query` 委托给外部LightRAG HTTP服务 | 不存在"可解耦的检索代码"，pgvector管道需要从零新建 |
| 项目已使用PostgreSQL，`data_processor.py` 中通过psycopg2连接 | pgvector只需安装extension，不需要新数据库 |
| `update_lightrag/forum_data_Fetcher.py` 已有完整的论坛FAQ数据抓取链路 | pgvector数据源可直接复用 |
| 生成模型通过 `ai_processor.py:307` 调用SiliconFlow API（OpenAI兼容） | 影子管道生成层可复用同一LLM，确保对比仅反映检索差异 |
| 无依赖注入，无metrics，无可观测性基础设施 | 阶段一必须是非侵入式插桩，不能先重构 |

---

## 完整需求详情（重组）

### 总体目标

构建RAG质量长期评估体系，通过数据驱动决策确定最优检索方案。

**核心原则**：先建尺子再量东西，结论由数据驱动，不预设答案。可能的结论包括：保留LightRAG / 切换pgvector / 两者融合路由。

---

### 阶段一：评估插桩与基线建设（1-2周）

**目标**：在不改变任何业务逻辑的前提下，建立评估数据采集能力和LightRAG质量基线。

#### 1.1 非侵入式数据采集

在现有管道关键节点埋入装饰器，捕获评测所需数据：

```
forum_client._get_response_data()    → 捕获 retrieval_context + retrieval_latency
ai_processor.call_large_model()      → 捕获 actual_output + token_count + generation_latency
monitor._process_new_topics()        → 组装 EvaluationSample 写入 PostgreSQL
```

`EvaluationSample` 表结构：

| 字段 | 来源 | 说明 |
|------|------|------|
| `input` | 用户提问原文 | 评分输入 |
| `retrieval_context` | LightRAG `/query` 返回值 | KG + Document Chunks |
| `actual_output` | LLM生成回答 | 评分输入 |
| `retrieval_latency_ms` | HTTP请求耗时 | 性能指标 |
| `generation_latency_ms` | LLM调用耗时 | 性能指标 |
| `token_count` | API返回 | 成本指标 |
| `topic_id` | monitor上下文 | 溯源 |
| `created_at` | 采集时间戳 | 时间序列 |

#### 1.2 可观测性增强

在插桩点同时暴露Prometheus metrics（不改代码结构，仅加 `@track_metrics` 装饰器）：

| 指标名 | 采集位置 | 用途 |
|--------|---------|------|
| `retrieval_latency_seconds` (p50/p99) | `_get_response_data()` | 监控LightRAG服务健康 |
| `llm_generation_latency_seconds` (p50/p99) | `call_large_model()` | 监控SiliconFlow API健康 |
| `end_to_end_latency_seconds` (p50/p99) | `_process_new_topics()` | 监控整体响应时延 |
| `empty_response_ratio` | `call_large_model()` 返回值 | 监控回答成功率 |
| `retrieval_result_count` | `_get_response_data()` | 监控检索召回量 |

通过Flask新增 `/metrics` 端点暴露，对接现有Prometheus/Grafana基础设施。

#### 1.3 评估数据集构建

- 从 `EvaluationSample` 表中取最近30天数据
- 按问题类型分层抽样：技术问题 / 使用问题 / 社区规则 / 其他，每类50-100条
- 每月从新问题中按同策略补充，防止数据集过时

#### 1.4 LightRAG质量基线

使用deepeval对采样数据集执行首轮评测，产出基线报告：

| 指标 | 用途 | 是否需要expected_output |
|------|------|:---:|
| Contextual Relevancy | 检索到的上下文是否与问题相关 | 否 |
| Faithfulness | 回答是否忠实于检索上下文（不幻觉） | 否 |

基线上报告存入评测系统，作为后续所有对比的参照物。

---

### 阶段二：影子管道建设（3-4周）

**目标**：新建独立的pgvector+混合检索+rerank管道，在离线评测环境中与LightRAG并行运行。

**关键原则**：`src/evaluation/` 是独立包，不import现有业务模块，不与线上代码耦合。

#### 2.1 四层架构设计

这是pgvector影子管道的技术架构——**不是对现有代码的重构，而是新管道的蓝图**。

```
                      ┌─────────────┐
                      │  用户问题    │
                      └──────┬──────┘
                             │
        ┌────────────────────┼────────────────────┐
        │       [接入层] DataIngestion            │
        │  - 问题文本归一化                         │
        │  - 问题类型分类（技术/使用/规则）            │
        │  输入: str                               │
        │  输出: QueryInput(text, category)        │
        └────────────────────┬────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │       [检索层] RetrievalLayer            │
        │  ┌─────────────────┐ ┌────────────────┐ │
        │  │ VectorRetriever  │ │  BM25Retriever │ │
        │  │ (dense/语义)     │ │  (sparse/关键词) │ │
        │  │ Qwen3-Emb-0.6B  │ │  PostgreSQL     │ │
        │  │ + pgvector HNSW │ │  ts_rank        │ │
        │  └────────┬────────┘ └───────┬────────┘ │
        │           └────────┬─────────┘          │
        │  输入: QueryInput                        │
        │  输出: RetrievalCandidates(dense[], sparse[]) │
        └────────────────────┬────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │       [处理层] ProcessingLayer           │
        │  ┌─────────────────┐ ┌────────────────┐ │
        │  │  RRFFusion      │ │   Reranker     │ │
        │  │  (k=60)         │ │   (BGE-Reranker│ │
        │  │  融合dense+     │ │    v2-m3 或    │ │
        │  │  sparse排序      │ │    SiliconFlow │ │
        │  └────────┬────────┘ │   rerank API)  │ │
        │           └──────────┴───────┬────────┘ │
        │  输入: RetrievalCandidates               │
        │  输出: RerankedResults(top_k=5)          │
        └────────────────────┬────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │       [生成层] GenerationLayer            │
        │  - Prompt 组装（复用现有模板）              │
        │  - 调用 SiliconFlow API（与线上同模型）     │
        │  输入: RerankedResults                    │
        │  输出: GeneratedAnswer                    │
        └────────────────────┴────────────────────┘
```

**各层接口契约**（Pydantic model）：

```python
class QueryInput(BaseModel):
    text: str
    category: str | None  # 技术/使用/规则

class RetrievalCandidates(BaseModel):
    dense: list[RetrievalResult]   # VectorRetriever 返回
    sparse: list[RetrievalResult]  # BM25 返回

class RetrievalResult(BaseModel):
    doc_id: str
    content: str
    score: float

class RerankedResults(BaseModel):
    candidates: list[RetrievalResult]  # 重排后 top_k
    latency_ms: float

class GeneratedAnswer(BaseModel):
    text: str
    token_count: int
    latency_ms: float
```

#### 2.2 pgvector向量库建设

**数据源**：从原始FAQ数据库重建向量库（不继承LightRAG已有数据，避免质量损失）。复用 `update_lightrag/forum_data_Fetcher.py` 的抓取链路获取全量topic JSON。

**技术选型**：

| 项目 | 选择 | 原因 |
|------|------|------|
| 嵌入模型 | `Qwen/Qwen3-Embedding-0.6B`（锁定版本） | 本地测试效果优于原嵌入模型 |
| 向量索引 | pgvector HNSW（m=16, ef_construction=200） | 查询性能优于IVFFlat |
| 维度 | 1024 | Qwen3-Embedding-0.6B 输出维度 |
| Chunk大小 | 512-1024 tokens | 平衡语义完整性和检索精度 |
| Chunk重叠 | 15% | 避免边界截断 |
| BM25实现 | PostgreSQL `ts_rank` + jieba分词 | 零额外依赖 |

**增量同步**：通过 PostgreSQL LISTEN/NOTIFY 机制或定时轮询 `update_time`，在FAQ数据更新时自动回填pgvector。

#### 2.3 deepeval评测集成

新建 `src/evaluation/evaluator.py`，封装deepeval评测逻辑：

- 自定义中文化评测模板（覆盖默认英文prompt）
- 评判器LLM使用与线上同系的模型（避免评判器偏差）
- 每条测试用例包含 `input` + `retrieval_context` + `actual_output`
- 评测结果存储：本地JSON报告 + PostgreSQL表（用于趋势分析）

#### 2.4 单元测试补充

- 基于当前覆盖率报告，将分支覆盖率从当前水平提升至 ≥85%
- 新增 `src/evaluation/` 模块覆盖率 ≥90%
- 覆盖口径：`pytest-cov --branch`

---

### 阶段三：持续对比运行（4周）

**每周定时任务**（GitHub Actions CronJob）：

```
每周一 00:00 UTC：
  1. 从最近一周新问题中分层抽样补充评估集（每类+10条）
  2. 对全量评估集并行执行两条管道：
     - LightRAG管道：读取已记录的 retrieval_context + actual_output
     - pgvector管道：运行影子管道产出新的 retrieval_context + actual_output
  3. deepeval分别对两条管道产出的结果打分
  4. 产出对比报告：
     - Contextual Relevancy 趋势图（LightRAG vs pgvector）
     - Faithfulness 趋势图（LightRAG vs pgvector）
     - 配对t检验结果（p < 0.05）
     - 差异最大的 top-10 case（含 reasoning）→ 人工抽检
  5. 报告存储到 PostgreSQL + 生成 Markdown 摘要评论到对应 Issue
```

---

### 阶段四：数据驱动决策

四周评测结束后，基于统计检验结果做出判断：

| 观察结果 | 决策 | 后续行动 |
|---------|------|---------|
| pgvector在两个指标上均**显著优于**LightRAG（p<0.05） | 执行灰度切换 | 10%→50%→100%，熔断指标：`retrieval_latency_p99` + `empty_response_ratio` |
| LightRAG在Contextual Relevancy上**显著优于**pgvector，但pgvector在Faithfulness上更好 | 探索融合路由 | 进入阶段五 |
| 两者**无显著差异** | 保留LightRAG | 优化LightRAG知识库质量/chunk策略 |
| 两者指标**都差** | FAQ数据质量问题 | 先治理FAQ数据，再重新评测 |

**灰度切换设计**（如决定切换）：

```
阶段A（1周）：10%流量 → pgvector
阶段B（1周）：50%流量 → pgvector
阶段C（长期）：100%流量 → pgvector

熔断条件（任意一条触发自动回滚到LightRAG）：
  - empty_response_ratio > 10%
  - retrieval_latency_p99 > 10s
  - Contextual Relevancy 均值相对基线下降 > 0.1
```

---

### 阶段五：融合方案预研（为"各有所长"场景准备）

如果阶段四数据显示按问题类型呈现不同最优方案，则设计融合路由：

```
输入问题
  → [意图分类器]（复用阶段一采集的category标签或新增分类模型）
    ├─ 精确FAQ匹配型 → 路由到 pgvector 管道
    ├─ 多概念/跨文档推理型 → 路由到 LightRAG 管道
    └─ 不确定类型 → 两路并发，由Reranker统一打分选top-k
```

融合路由的实现前提是两条管道实现了**相同的接口契约**（2.1中定义的Pydantic model）。

---

## 验收标准（修正后）

| # | 验收标准 | 说明 |
|---|---------|------|
| 1 | 不改变现有业务逻辑 | 阶段一/二期间仅加装饰器，不修改 `monitor.py`/`ai_processor.py`/`forum_client.py` 业务代码 |
| 2 | `src/evaluation/` 模块可独立运行 | `python -m src.evaluation.shadow_pipeline` 不依赖Flask服务 |
| 3 | 评测指标可解释 | deepeval产出包含 `reason` 字段的评分报告 |
| 4 | 趋势可追踪 | 四周评测结果以时序折线图呈现 |
| 5 | 超时保护 | 离线评测管道单条300s；在线链路维持现有600s不变 |
| 6 | 分支覆盖率 ≥85% | `pytest-cov --branch`，新增代码覆盖率 ≥90% |
| 7 | 数据安全 | 评测数据集脱敏用户ID/IP；评估LLM使用私有化部署模型 |
| 8 | 增量评测可持续 | 每月自动补充评估集，不需要人工维护 |

---

## deepeval选型可行性分析（摘要）

| 维度 | 评估 |
|------|------|
| **技术成熟度** | ⭐⭐⭐⭐⭐ GitHub 15k+ stars，专为RAG设计，支持组件级+端到端评测 |
| **指标适配** | ⭐⭐⭐⭐ 选了两个reference-less指标（Contextual Relevancy + Faithfulness），恰好绕开"无标注数据"约束 |
| **中文场景** | ⭐⭐⭐ 默认英文prompt，需自定义中文化模板；评判器LLM可选私有化部署 |
| **成本** | ⭐⭐⭐ LLM-as-judge模式，分层抽样后可控制在可接受范围 |
| **风险** | 评判器偏差、中文FAQ场景准确性待验证、指标覆盖度可后续扩充（Contextual Recall + Answer Relevancy） |

---

## 从原始需求到修正需求的对照

| 原始内容 | 问题 | 修正后 |
|---------|------|--------|
| "拆解成检索层/处理层/生成层"写在需求开头 | 这是pgvector管道的技术设计，不是前置工作 | 移到阶段二 2.1，作为影子管道的架构蓝图 |
| pgvector方案作为唯一候选 | 预设了答案 | 改为待验证假设，结论由阶段四数据决定 |
| 缺少可观测性设计 | 和自己提出的黑盒痛点矛盾 | 阶段一 1.2 加入Prometheus metrics |
| 评测数据集范围模糊 | "全量"不可控 | 阶段一 1.3 明确分层抽样策略 |
| 评测频率仅"每周" | 缺少趋势分析框架 | 阶段三明确每周任务流程+统计检验 |
| 缺少决策框架 | 无法落地 | 阶段四给出四象限决策矩阵+灰度切换方案 |
| 缺少融合路径 | 只考虑替换 | 阶段五预研融合路由 |
| 300s超时用于在线链路 | 违背改善时延目标 | 验收标准区分在线(600s不变)和离线(300s) |

---

## 🔗 相关笔记

- [[2026-06-10-forum-reply-robot-阶段一-评估插桩与基线建设]] — 阶段一实现
- [[2026-06-10-forum-reply-robot-阶段二-影子管道建设]] — 阶段二实现
- [[机器人类-forum-reply-robot]] — 服务概览
- [[2026-06-10-backlog-issue621-preview-deploy-failed]] — 相关部署故障

> 索引：[[RAG 体系]] · [[Issue 专题]] · 返回 [[首页]]
