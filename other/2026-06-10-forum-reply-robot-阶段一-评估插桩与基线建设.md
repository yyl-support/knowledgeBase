---
tags:
  - RAG
  - forum-reply-robot
  - issue-621
  - 评估
issue: 621
---

# 阶段一：评估插桩与基线建设

> 关联 Issue: https://github.com/opensourceways/backlog/issues/621  
> 目标工程: `opensourceways/forum-reply-robot`  
> 本地路径: `/Users/gorden/huawei/code/forum-reply-robot`

## 目标

在不改变任何现有业务逻辑的前提下，为 forum-reply-robot 建立 RAG 质量评估的数据采集能力和 LightRAG 质量基线。

**一句话**：给系统装上"数据记录仪"，跑一周，产出第一份 LightRAG 质量报告。

---

## 背景

当前系统所有 RAG 检索委托给外部 LightRAG HTTP 服务（`forum_client.py:165`），内部无本地向量库/嵌入模型/重排序器。运维层面整个 RAG 流程是黑盒 HTTP 调用，无法感知检索失败、延迟、变更原因。

本阶段不改造架构，只用非侵入式方式在关键节点采集数据。

---

## 范围

### 必须完成

| # | 内容 | 说明 |
|---|------|------|
| 1 | 创建 `evaluation_samples` PostgreSQL 表 | 存储每条问答的完整评测数据 |
| 2 | 在检索节点插入数据采集钩子 | `forum_client._get_response_data()` 捕获 `retrieval_context` + 检索延迟 |
| 3 | 在生成节点插入数据采集钩子 | `ai_processor.call_large_model()` 捕获 `actual_output` + token数 + 生成延迟 |
| 4 | 在编排节点组装并持久化样本 | `monitor._process_new_topics()` 中组装 `EvaluationSample` 写入 PG |
| 5 | 暴露 Prometheus metrics 端点 | Flask `/metrics` 端点，包含检索延迟、生成延迟、端到端延迟、空回复率、检索召回量 |
| 6 | 构建评估数据集 | 从采集数据中按问题类型分层抽样，每类 50-100 条 |
| 7 | 运行 LightRAG 质量基线评测 | 使用 deepeval 的 ContextualRelevancy + Faithfulness 指标对评估集打分 |
| 8 | 产出基线报告 | Markdown 格式报告，含分指标得分、分布、典型 case |

### 明确不做

- 不修改 `monitor.py` / `ai_processor.py` / `forum_client.py` / `data_processor.py` 的业务逻辑
- 不引入新的外部服务依赖（Prometheus 仅加 client 库 + 端点）
- 不修改现有配置结构
- 不改变 Flask 现有的 `/health` / `/health/detail` 行为

---

## 技术设计

### 1. EvaluationSample 数据模型

在现有 PostgreSQL 数据库中新建表：

```sql
CREATE TABLE IF NOT EXISTS evaluation_samples (
    id              SERIAL PRIMARY KEY,
    topic_id        INTEGER NOT NULL,
    input           TEXT NOT NULL,                    -- 用户提问原文
    retrieval_context JSONB NOT NULL,                 -- LightRAG /query 返回的 KG + Document Chunks
    actual_output   TEXT NOT NULL,                    -- LLM 生成的最终回答
    retrieval_latency_ms  FLOAT,                      -- 检索 HTTP 请求耗时
    generation_latency_ms FLOAT,                      -- LLM 调用耗时
    token_count     INTEGER,                          -- 本次 LLM 调用 token 总数
    category        VARCHAR(50),                      -- 问题类型（技术/使用/规则/其他）
    created_at      TIMESTAMP DEFAULT NOW(),
    INDEX idx_topic_id (topic_id),
    INDEX idx_created_at (created_at)
);
```

### 2. 数据采集钩子

**方式**：装饰器模式，现有函数签名不变。

**2.1 检索节点** — `@capture_retrieval` 装饰器

```
位置: forum_client._get_response_data()
采集: 返回值（retrieval_context）、HTTP 请求耗时
副作用: 将数据暂存到 threading.local() 或 contextvars
```

**2.2 生成节点** — `@capture_generation` 装饰器

```
位置: ai_processor.call_large_model()
采集: 返回值（actual_output）、API 耗时、response.usage 中的 token 数
副作用: 将数据暂存到与检索节点共享的上下文中
```

**2.3 编排节点** — `@persist_sample`

```
位置: monitor._process_new_topics() 中生成回答后
行为: 从上下文读取检索数据 + 生成数据，组装 EvaluationSample，写入 PG
```

**关键约束**：钩子函数内部必须 try/except 包裹，任何采集失败不得影响主流程。

### 3. Prometheus Metrics

Flask 新增 `/metrics` 端点，暴露以下指标：

| 指标名 | 类型 | 标签 | 说明 |
|--------|------|------|------|
| `forum_retrieval_latency_seconds` | Histogram | `status` | 检索延迟分布 |
| `forum_generation_latency_seconds` | Histogram | `status` | LLM调用延迟分布 |
| `forum_end_to_end_latency_seconds` | Histogram | `status` | 端到端延迟分布 |
| `forum_empty_response_total` | Counter | - | 空回复计数 |
| `forum_retrieval_result_count` | Histogram | - | 检索召回文档数分布 |

依赖：`prometheus-client`（需添加至 `requirements.txt`）

### 4. 评估数据集构建

**采集期**：至少运行 7 天，积累足够样本。

**构建策略**：
1. 从 `evaluation_samples` 表查询最近 30 天记录
2. 对 `input` 字段做去重（相似度 > 0.9 的只保留一条）
3. 按 `category` 分层：技术问题 / 使用问题 / 社区规则 / 未分类
4. 每层随机抽样 50-100 条（总规模 200-400 条）
5. 导出为 JSON 文件，格式：

```json
[
  {
    "input": "用户问题",
    "retrieval_context": ["chunk1", "chunk2"],
    "actual_output": "机器人回答",
    "category": "技术问题",
    "topic_id": 12345
  }
]
```

**category 分类逻辑**（简易规则，不需要 LLM）：
- 含"报错/error/日志/配置/参数/接口/API/代码" → `技术问题`
- 含"怎么/如何/教程/文档/安装/部署/下载" → `使用问题`
- 含"规范/规则/要求/审核/PR/提交" → `社区规则`
- 其他 → `其他`

### 5. LightRAG 基线评测

**工具**：deepeval（Python 库）

**安装**：`pip install deepeval`（添加至 requirements.txt）

**评测脚本**：`src/evaluation/run_baseline.py`

```python
from deepeval import evaluate
from deepeval.test_case import LLMTestCase
from deepeval.metrics import ContextualRelevancyMetric, FaithfulnessMetric

# 1. 加载评估数据集 JSON
# 2. 对每条构造 LLMTestCase(input, actual_output, retrieval_context)
# 3. 用 ContextualRelevancyMetric + FaithfulnessMetric 打分
# 4. 输出 Markdown 报告到 evaluation_reports/baseline_2026-xx-xx.md
```

**评判器 LLM**：使用与线上同系的模型（从 `config.yaml` 的 `api` 段读取 model_name 和 base_url）

**自定义模板**：覆盖 deepeval 默认英文 prompt 为中文版本（在 `src/evaluation/templates.py` 中定义）

**注意事项**：
- 评测是离线行为，在开发环境执行，不触碰线上服务
- 需要能从 `config.yaml` 读取 API 配置
- 基线结果存入 `evaluation_reports/` 目录（gitignore 该目录的 JSON 中间文件，但提交 Markdown 报告）

---

## 验收标准

| # | 标准 | 验证方式 |
|---|------|---------|
| 1 | 线上机器人功能不受影响 | 部署后 `/health` 返回 200，机器人正常回复 |
| 2 | `evaluation_samples` 表有持续写入 | `SELECT count(*) FROM evaluation_samples WHERE created_at > now() - interval '1 hour'` > 0 |
| 3 | `/metrics` 端点可访问且数据正确 | curl `/metrics` 返回包含 `forum_retrieval_latency_seconds` 等指标 |
| 4 | 钩子异常不影响主流程 | 模拟 PG 不可用时机器人仍正常回复 |
| 5 | 评估数据集 JSON 可生成 | 脚本执行成功，输出 200-400 条样本 |
| 6 | 基线评测可执行 | `python -m src.evaluation.run_baseline` 成功，产出报告含两个指标的分数分布 |
| 7 | 不修改现有业务函数签名 | diff 中 `forum_client.py` / `ai_processor.py` / `monitor.py` 仅增加装饰器和 imports |
| 8 | 新增依赖在 requirements.txt 中 | `prometheus-client` 和 `deepeval` 条目存在 |

---

## 产出物

| 文件 | 说明 |
|------|------|
| `src/evaluation/__init__.py` | 包初始化 |
| `src/evaluation/capture.py` | 数据采集装饰器 (`@capture_retrieval`, `@capture_generation`, `@persist_sample`) |
| `src/evaluation/db.py` | EvaluationSample 表的 CRUD 操作 |
| `src/evaluation/metrics.py` | Prometheus metrics 定义 + Flask `/metrics` 端点注册 |
| `src/evaluation/dataset_builder.py` | 评估数据集构建脚本（从 PG 查询 → 去重 → 分层抽样 → JSON） |
| `src/evaluation/run_baseline.py` | LightRAG 基线评测脚本 |
| `src/evaluation/templates.py` | deepeval 自定义中文化 prompt |
| `evaluation_reports/baseline_2026-xx-xx.md` | 基线评测报告（提交到仓库） |
| `requirements.txt` | 添加 `prometheus-client`, `deepeval` |
| 对 `forum_client.py` 的修改 | 仅加 `@capture_retrieval` 装饰器 + 1 行 import |
| 对 `ai_processor.py` 的修改 | 仅加 `@capture_generation` 装饰器 + 1 行 import |
| 对 `monitor.py` 的修改 | 仅加 `@persist_sample` 装饰器 + 1 行 import |
| 对 `main.py` 的修改 | 注册 `/metrics` 端点 |

---

## 文件变更清单（仅限 forum-reply-robot 仓）

```
新增:
  src/evaluation/__init__.py
  src/evaluation/capture.py
  src/evaluation/db.py
  src/evaluation/metrics.py
  src/evaluation/dataset_builder.py
  src/evaluation/run_baseline.py
  src/evaluation/templates.py
  evaluation_reports/baseline_2026-xx-xx.md

修改（仅装饰器和 imports）:
  src/ForumBot/forum_client.py     — +1 decorator +1 import
  src/ForumBot/ai_processor.py     — +1 decorator +1 import
  src/ForumBot/monitor.py          — +1 decorator +1 import
  main.py                          — 注册 /metrics 端点
  requirements.txt                 — +prometheus-client, +deepeval
```

---

## 阶段二前置依赖

本阶段完成后，产出以下供阶段二使用的资产：

- `evaluation_samples` 表中有持续积累的问答数据
- 评估数据集 JSON（`evaluation_reports/dataset.json`）
- LightRAG 基线指标分数（作为阶段二 pgvector 管道对比的参照）
- deepeval 中文化模板（阶段二复用）
- Prometheus metrics 在线运行（阶段二可追加剧评相关的指标）

---

## 🔗 相关笔记

- [[2026-06-10-forum-reply-robot-issue分析]] — 总体需求分析
- [[2026-06-10-forum-reply-robot-阶段二-影子管道建设]] — 下一阶段
- [[2026-06-11-RAG评估方案-轻量替代deepeval]] — 轻量评测替代 deepeval

> 索引：[[RAG 体系]] · [[Issue 专题]] · 返回 [[首页]]
