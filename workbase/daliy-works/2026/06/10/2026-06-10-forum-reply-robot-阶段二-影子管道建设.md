---
tags:
  - RAG
  - forum-reply-robot
  - issue-621
  - pgvector
issue: 621
---

# 阶段二：影子管道建设

> 关联 Issue: https://github.com/opensourceways/backlog/issues/621  
> 前置依赖: 阶段一（评估数据集 + LightRAG 基线已产出）  
> 目标工程: `opensourceways/forum-reply-robot`  
> 本地路径: `/Users/gorden/huawei/code/forum-reply-robot`

## 目标

新建一条独立的 pgvector + 混合检索 + rerank 影子管道，在离线评测环境中与 LightRAG 并行运行，产出可对比的评测结果。

**一句话**：用阶段一的评估数据集，对新的 pgvector 管道打分，和 LightRAG 基线做对比。

---

## 背景

当前线上只运行 LightRAG，没有本地检索管道。本阶段不替换线上 LightRAG，而是在项目内新建一个完全独立的 `src/evaluation/` 包，实现另一套检索方案，仅在离线评测流水线中使用。

"四层架构"是本阶段 pgvector 影子管道的技术设计——不是对现有代码的重构，而是新管道的蓝图。

---

## 范围

### 必须完成

| # | 内容 | 说明 |
|---|------|------|
| 1 | pgvector 环境准备 | 在现有 PostgreSQL 安装 pgvector extension，创建向量表 |
| 2 | Embedding 客户端 | 封装 Qwen/Qwen3-Embedding-0.6B 调用（通过 ModelScope API 或本地推理） |
| 3 | VectorRetriever（dense 检索） | 基于 pgvector HNSW 索引的语义向量检索 |
| 4 | BM25Retriever（sparse 检索） | 基于 PostgreSQL `ts_rank` + jieba 分词的全文检索 |
| 5 | RRFFusion（混合融合） | Reciprocal Rank Fusion（k=60）合并 dense + sparse 结果 |
| 6 | Reranker（重排序） | 对融合候选集重排序，输出 top-k=5 |
| 7 | 生成层 | Prompt 组装 + 调用 SiliconFlow API（与线上同模型） |
| 8 | 全量数据回填 | 从 `update_lightrag/forum_data_Fetcher.py` 获取 FAQ 数据，向量化存入 pgvector |
| 9 | 评测对比脚本 | 对阶段一的评估数据集，分别走 pgvector 管道评分，产出对比报告 |
| 10 | 单元测试 | `src/evaluation/` 模块分支覆盖率 ≥90% |

### 明确不做

- 不修改线上 LightRAG 调用链路
- 不替换 `forum_client.py` 的检索逻辑
- 不开代码 PR（影子管道仅内部使用）
- 不部署到生产环境
- pgvector 管道不暴露 HTTP 接口

---

## 技术设计

### 1. 四层架构（新管道的结构）

```
                      ┌─────────────┐
                      │  QueryInput  │
                      │  .text       │
                      │  .category   │
                      └──────┬──────┘
                             │
        ┌────────────────────┼────────────────────┐
        │          DataIngestion                   │
        │  输入: str                                │
        │  输出: QueryInput(text, category)         │
        │  行为: 文本归一化 + 类别标注               │
        └────────────────────┬────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │          RetrievalLayer                  │
        │  ┌───────────────┐  ┌────────────────┐  │
        │  │VectorRetriever│  │ BM25Retriever  │  │
        │  │ (dense)       │  │ (sparse)       │  │
        │  │ pgvector HNSW │  │ pg ts_rank     │  │
        │  └───────┬───────┘  └───────┬────────┘  │
        │          └─────────┬────────┘            │
        │  输出: RetrievalCandidates(dense, sparse) │
        └────────────────────┬────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │          ProcessingLayer                 │
        │  ┌───────────────┐  ┌────────────────┐  │
        │  │  RRFFusion    │  │   Reranker     │  │
        │  │  k=60         │  │   BGE-Reranker │  │
        │  │               │  │   或API rerank  │  │
        │  └───────┬───────┘  └───────┬────────┘  │
        │          └─────────┬────────┘            │
        │  输出: RerankedResults(candidates[:5])    │
        └────────────────────┬────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │          GenerationLayer                 │
        │  - Prompt 组装（复用现有PROMPT_TEMPLATE）  │
        │  - SiliconFlow API 调用（与线上同模型）    │
        │  输出: GeneratedAnswer(text, tokens, ms)  │
        └────────────────────┴────────────────────┘
```

### 2. 接口契约（Pydantic model）

所有层之间的数据传递通过以下模型，定义在 `src/evaluation/models.py`：

```python
from pydantic import BaseModel

class QueryInput(BaseModel):
    text: str
    category: str | None = None

class RetrievalResult(BaseModel):
    doc_id: str
    content: str
    score: float

class RetrievalCandidates(BaseModel):
    dense: list[RetrievalResult]    # VectorRetriever 返回 top_k=20
    sparse: list[RetrievalResult]   # BM25Retriever 返回 top_k=20

class RerankedResults(BaseModel):
    candidates: list[RetrievalResult]  # 重排后 top_k=5
    latency_ms: float

class GeneratedAnswer(BaseModel):
    text: str
    token_count: int
    latency_ms: float
```

### 3. pgvector 向量库

**环境**：复用现有 PostgreSQL 实例（`data_processor.py` 已连接），安装 pgvector extension。

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS faq_vectors (
    id          SERIAL PRIMARY KEY,
    doc_id      VARCHAR(255) UNIQUE NOT NULL,  -- 对应 forum topic_id
    content     TEXT NOT NULL,                  -- FAQ 文本
    chunk_index INTEGER DEFAULT 0,              -- 分块序号
    embedding   vector(1024),                   -- Qwen3-Embedding-0.6B 输出维度
    category    VARCHAR(50),                    -- 问题类型
    created_at  TIMESTAMP DEFAULT NOW(),
    updated_at  TIMESTAMP DEFAULT NOW()
);

-- HNSW 索引（用于向量检索）
CREATE INDEX ON faq_vectors USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 200);

-- 全文检索索引（用于 BM25/ts_rank）
CREATE INDEX ON faq_vectors USING gin (
    to_tsvector('simple', content)
);
```

**bm25 检索 SQL**：

```sql
SELECT doc_id, content, ts_rank(
    to_tsvector('simple', content),
    plainto_tsquery('simple', %s)
) AS score
FROM faq_vectors
WHERE to_tsvector('simple', content) @@ plainto_tsquery('simple', %s)
ORDER BY score DESC
LIMIT %s;
```

**中文分词**：使用 jieba 对查询文本做分词后传入 `plainto_tsquery`。

### 4. Embedding 模型

**模型**：`Qwen/Qwen3-Embedding-0.6B`（锁定 commit: `main` 分支最新）

**调用方式**（二选一，按环境决定）：
- **方式 A（推荐）**：通过 ModelScope API 调用（`modelscope` Python SDK），无需 GPU
- **方式 B**：本地部署（需要 GPU，`python:3.9-slim` 基础镜像不适用）

**客户端接口**（`src/evaluation/embedding_client.py`）：

```python
class EmbeddingClient:
    def embed(self, texts: list[str]) -> list[list[float]]: ...
    def embed_query(self, text: str) -> list[float]: ...
    @property
    def dimension(self) -> int: return 1024
```

**注意事项**：
- 单次调用最大 32K tokens（Qwen3-Embedding 上限）
- 批量 embed 时分批，每批不超过 32 条
- 失败重试 3 次，指数退避

### 5. RRF 融合

**公式**：
```
RRF_score(d) = Σ 1/(k + rank_i(d))
```
其中 k=60，i 遍历 dense 和 sparse 两个排序列表。

**实现逻辑**：
1. 收集两个列表中所有 doc_id
2. 对每个 doc_id 计算 RRF 分数
3. 按 RRF 分数降序排列，取 top_k=5 给 reranker

### 6. Reranker

**方案**：使用 BGE-Reranker-v2-m3（通过 SiliconFlow Rerank API 或 ModelScope 调用）

```python
class Reranker:
    def rerank(self, query: str, candidates: list[RetrievalResult]) -> RerankedResults:
        # 调用 rerank API 对 candidates 重排序
        # 输出 top_k=5
        ...
```

**备选**：如果 rerank API 不可用，使用 CrossEncoder 本地推理（需要额外依赖 `sentence-transformers`）。

### 7. 生成层

**复用线上逻辑**：不重新实现 Prompt 模板和 LLM 调用，而是复用 `data_processor.py` 的 `PROMPT_TEMPLATE` 和 `ai_processor.py` 的 `call_large_model()` 的参数配置（但独立调用，不复用 import）。

```python
class GenerationLayer:
    def __init__(self, api_config: dict):
        self.client = OpenAI(base_url=api_config["base_url"], api_key=api_config["api_key"])
        self.model = api_config["model_name"]
        self.prompt_template = PROMPT_TEMPLATE  # 从 data_processor.py 复制或引用

    def generate(self, query: str, context: list[RetrievalResult]) -> GeneratedAnswer:
        prompt = self.prompt_template.format(...)
        response = self.client.chat.completions.create(
            model=self.model,
            messages=[{"role": "system", "content": prompt}, ...],
            timeout=300  # 离线评测可用较长超时
        )
        return GeneratedAnswer(
            text=response.choices[0].message.content,
            token_count=response.usage.total_tokens,
            latency_ms=...
        )
```

### 8. 全量数据回填

**数据源**：复用 `update_lightrag/forum_data_Fetcher.py` 获取全量 forum topic JSON 文件。

**回填流程**（`src/evaluation/data_backfill.py`）：

```
1. 遍历 lightrag_paths.rag_data_dir 下所有 *_topic.json
2. 对每个 topic，提取 title + question + best_answer 组成 content
3. 按 chunk_size=800 tokens, overlap=15% 分块
4. 调用 EmbeddingClient.embed() 向量化每个 chunk
5. INSERT INTO faq_vectors
6. 记录回填时间戳到 evaluation_meta 表
```

**增量同步**：基于 `update_time` 文件（`src/update_lightrag/update_time.py` 已有），定时检查新 topic，对新增内容向量化回填。

### 9. 评测对比脚本

**脚本**：`src/evaluation/run_comparison.py`

**流程**：
```
1. 加载阶段一的评估数据集 JSON
2. 对每条测试用例：
   a. pgvector管道: QueryInput → Retrieval → RRF → Rerank → Generate → deepeval打分
   b. 读取 LightRAG 基线分数（从阶段一的基线报告）
3. 产出对比报告 Markdown：
   - 总分对比表（Contextual Relevancy均值, Faithfulness均值）
   - 按 category 分组对比
   - 差异最大 top-10 case 详情
   - 延迟对比
```

**输出**：`evaluation_reports/comparison_2026-xx-xx.md`

### 10. 模块结构

```
src/evaluation/
├── __init__.py
├── models.py               # Pydantic 接口契约（QueryInput, RetrievalResult 等）
├── embedding_client.py     # Qwen3-Embedding-0.6B 客户端
├── pgvector_store.py       # faq_vectors 表 CRUD + HNSW 查询
├── bm25_retriever.py       # PostgreSQL ts_rank 检索器
├── vector_retriever.py     # pgvector HNSW dense 检索器
├── hybrid_fusion.py        # RRF 融合
├── reranker.py             # BGE-Reranker 重排序
├── generation_layer.py     # LLM 生成（复用线上同模型）
├── shadow_pipeline.py      # 四层管道串联编排（主入口）
├── data_backfill.py        # 全量数据回填脚本
├── run_comparison.py       # 评测对比脚本
└── templates.py            # deepeval 中文化模板（阶段一已建，本阶段补充）
```

---

## 验收标准

| # | 标准 | 验证方式 |
|---|------|---------|
| 1 | pgvector extension 安装成功 | `SELECT * FROM pg_extension WHERE extname='vector'` 返回行 |
| 2 | `faq_vectors` 表有数据 | `SELECT count(*) FROM faq_vectors` > 1000 |
| 3 | HNSW 索引可用 | `EXPLAIN SELECT * FROM faq_vectors ORDER BY embedding <-> '[...]' LIMIT 5` 显示 Index Scan |
| 4 | 四层管道端到端可运行 | `python -m src.evaluation.shadow_pipeline --query "测试问题"` 返回 GeneratedAnswer |
| 5 | 对比评测脚本可执行 | `python -m src.evaluation.run_comparison` 产出 `comparison_*.md` |
| 6 | `src/evaluation/` 模块分支覆盖率 ≥90% | `pytest --cov=src.evaluation --cov-report=term --cov-branch` |
| 7 | 影子管道不 import 线上业务模块 | `grep -r "from src.ForumBot" src/evaluation/` 无结果 |
| 8 | 对阶段一评估数据集的结果合理 | 人工抽查 top-10 差异 case，评判分数与直觉一致 |
| 9 | 评测对比报告包含 latency 对比 | 报告中有检索延迟 + 端到端延迟对比表格 |
| 10 | 增量同步机制可运行 | 新增 topic 后 `data_backfill.py --incremental` 正确回填 |

---

## 产出物

| 文件 | 说明 |
|------|------|
| `src/evaluation/models.py` | 接口契约 |
| `src/evaluation/embedding_client.py` | Embedding 客户端 |
| `src/evaluation/pgvector_store.py` | pgvector CRUD |
| `src/evaluation/bm25_retriever.py` | BM25 检索器 |
| `src/evaluation/vector_retriever.py` | Dense 向量检索器 |
| `src/evaluation/hybrid_fusion.py` | RRF 融合 |
| `src/evaluation/reranker.py` | BGE-Reranker |
| `src/evaluation/generation_layer.py` | LLM 生成层 |
| `src/evaluation/shadow_pipeline.py` | 管道编排主入口 |
| `src/evaluation/data_backfill.py` | 数据回填脚本 |
| `src/evaluation/run_comparison.py` | 评测对比脚本 |
| `tests/evaluation/` | 单元测试（不低于 10 个 test 函数） |
| `evaluation_reports/comparison_2026-xx-xx.md` | 对比报告 |
| `requirements.txt` | +pgvector, +jieba, +modelscope（如用方式A）, +pydantic |
| `migrations/add_faq_vectors.sql` | DDL 迁移脚本 |

## 文件变更清单（仅限 forum-reply-robot 仓）

```
新增:
  src/evaluation/models.py
  src/evaluation/embedding_client.py
  src/evaluation/pgvector_store.py
  src/evaluation/bm25_retriever.py
  src/evaluation/vector_retriever.py
  src/evaluation/hybrid_fusion.py
  src/evaluation/reranker.py
  src/evaluation/generation_layer.py
  src/evaluation/shadow_pipeline.py
  src/evaluation/data_backfill.py
  src/evaluation/run_comparison.py
  migrations/add_faq_vectors.sql
  tests/evaluation/__init__.py
  tests/evaluation/test_embedding_client.py
  tests/evaluation/test_vector_retriever.py
  tests/evaluation/test_bm25_retriever.py
  tests/evaluation/test_hybrid_fusion.py
  tests/evaluation/test_reranker.py
  tests/evaluation/test_shadow_pipeline.py
  evaluation_reports/comparison_2026-xx-xx.md

修改:
  requirements.txt  — +pgvector, +jieba, +modelscope, +pydantic
```

---

## 阶段三前置依赖

本阶段完成后，产出以下供阶段三（持续对比运行）使用的资产：

- 可独立运行的 pgvector 影子管道（`shadow_pipeline.py`）
- 对比评测脚本（`run_comparison.py`）
- 与 LightRAG 基线的首次对比报告
- 完整的单元测试覆盖
- pgvector 向量库中有全量数据且支持增量更新

---

## 🔗 相关笔记

- [[2026-06-10-forum-reply-robot-阶段一-评估插桩与基线建设]] — 前置阶段
- [[2026-06-10-forum-reply-robot-issue分析]] — 总体需求
- [[0519-RAG切换]] — 模块化重构方案（同技术方向）

> 索引：[[RAG 体系]] · [[Issue 专题]] · 返回 [[首页]]
