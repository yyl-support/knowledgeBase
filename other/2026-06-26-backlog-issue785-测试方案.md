# Issue #785 测试方案 — 阶段一：评估插桩与基线建设

**关联 Issue**: https://github.com/opensourceways/backlog/issues/785
**代码仓库**: https://github.com/opensourceways/forum-reply-robot
**涉及 PR**: #104, #109, #110, #111, #112, #113 (全部已合入 main)

---

## 一、改动概览

### 1.1 新增文件

| 文件 | 用途 | 核心逻辑 |
|------|------|---------|
| `src/ForumBot/evaluation_hooks.py` | 数据采集装饰器 | thread-local 上下文，捕获检索/生成延迟和内容 |
| `src/ForumBot/prometheus_metrics.py` | Prometheus 指标定义 | 6 个指标 (3 Histogram + 1 Gauge + 2 Counter) |
| `src/evaluation/build_dataset.py` | 评估数据集构建 | DB查询→去重→分层抽样→JSON导出 |
| `src/evaluation/run_baseline.py` | 基线评测脚本 | LLM Judge 评分 + Markdown 报告 |
| `src/evaluation/templates.py` | 中文评测 Prompt | 3 个模板（相关性/忠实性/精确率） |
| `src/evaluation/__init__.py` | 包标记 | 空文件 |
| `requirements-eval.txt` | 评测依赖 | deepeval 等离线依赖 |

### 1.2 修改文件

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `main.py` | 新增 `/metrics` 端点 | 使用 `prometheus_client.generate_latest()` |
| `src/ForumBot/forum_client.py` | 装饰器注入 | `_get_response_data()` 加 `@capture_retrieval_metrics` |
| `src/ForumBot/ai_processor.py` | 装饰器注入 | `call_large_model()` 加 `@capture_generation_metrics` |
| `src/ForumBot/data_processor.py` | 新增表+方法 | `evaluation_samples` 表、`save_evaluation_sample()`、`_normalize_retrieval_context()`、JSONB 适配器注册 |
| `src/ForumBot/monitor.py` | 编排节点注入 | 主循环中组装并持久化 `EvaluationSample` |
| `Dockerfile` | Bugfix | 不再删除 `timeit.py`（prometheus_client 依赖） |
| `requirements.txt` | 新增依赖 | `prometheus-client` |

### 1.3 数据流

```
forum_client._get_response_data()  →  [@capture_retrieval_metrics]
         ↓ (捕获 retrieval_context + retrieval_latency)
ai_processor.call_large_model()    →  [@capture_generation_metrics]
         ↓ (捕获 actual_output + generation_latency)
monitor._process_new_topics()      →  组装 EvaluationSample → save_evaluation_sample() → PG
         ↓                                                                   ↓
update_prometheus_metrics()        ←  读取同一批数据                     evaluation_samples 表
         ↓                                                                   ↓
Flask /metrics                     →  prometheus scrape                build_dataset.py
                                                                              ↓
                                                                        run_baseline.py
                                                                              ↓
                                                                      baseline_*.md 报告
```

---

## 二、测试策略总览

```
层级1: 单元测试 (pytest)          → 每个函数/方法的独立行为
层级2: 集成测试                   → 组件间协作（钩子→存储→指标）
层级3: 端到端测试                 → 完整数据流（入库→采集→评测→报告）
层级4: 非功能测试                 → 性能 / 可靠性 / 容错
层级5: 回归测试                   → 确认现有功能不受影响
层级6: 验收测试                   → 对照 Issue 验收标准逐条验证
```

---

## 三、单元测试

### 3.1 evaluation_hooks.py

| 用例ID | 测试点 | 输入 | 期望输出 |
|--------|--------|------|---------|
| U-001 | `classify_question` 技术问题识别 | `("配置报错", "error日志")` | `"技术问题"` |
| U-002 | `classify_question` 使用问题识别 | `("怎么安装", "如何部署")` | `"使用问题"` |
| U-003 | `classify_question` 社区规则识别 | `("PR审核", "提交规范")` | `"社区规则"` |
| U-004 | `classify_question` 其他分类 | `("普通问题", "一般内容")` | `"其他"` |
| U-005 | `classify_question` 混合关键词优先级 | `("配置报错怎么解决", "教程")` | `"技术问题"` (先匹配) |
| U-006 | `capture_retrieval_metrics` 正常捕获 | 返回 `(["d1","d2"], {"data":"x"})` | context.retrieval_context = `["d1","d2"]`, latency 为 float |
| U-007 | `capture_retrieval_metrics` 异常捕获 | 函数抛出 `Exception("boom")` | context 字段为 None, 原异常仍抛出 |
| U-008 | `capture_retrieval_metrics` 空列表 | 返回 `([], {})` | context 为空列表, latency 为 float |
| U-009 | `capture_generation_metrics` 正常捕获 | 返回 `"output text"` | actual_output = `"output text"`, latency 为 float |
| U-010 | `capture_generation_metrics` 异常捕获 | 抛出, 重抛 | actual_output=None, latency=None, 异常重抛 |
| U-011 | `capture_generation_metrics` 空字符串 | 返回 `""` | actual_output = `""` |
| U-012 | `get_evaluation_context` 线程隔离 | 3线程并发写入 | 各自独立, 无交叉污染 |
| U-013 | `capture_retrieval_metrics` 带 args/kwargs | `("arg1", kw=1)` | 原函数被正确调用 |
| U-014 | `capture_generation_metrics` 带 args/kwargs | `("prompt", temp=0.1)` | 原函数被正确调用 |

### 3.2 prometheus_metrics.py

| 用例ID | 测试点 | 输入 | 期望输出 |
|--------|--------|------|---------|
| U-020 | 指标正常注册 | 模块首次导入 | 6个指标对象创建成功 |
| U-021 | 指标重复注册容错 | 模块二次导入 (热重载) | 不崩溃, log warning |
| U-022 | `update_prometheus_metrics` 正常数据 | `{retrieval_latency:2.0, generation_latency:10.0, actual_output:"hello", retrieval_context:["d1","d2"]}` | retrieval.observe(2.0), generation.observe(10.0), empty_reply.set(0.0), doc_count.inc(2), topic_count.inc(1), end_to_end.observe(12.0) |
| U-023 | `update_prometheus_metrics` 空回复 | `actual_output = ""` | empty_reply_rate.set(1.0) |
| U-024 | `update_prometheus_metrics` None 延迟 | `retrieval_latency=None, generation_latency=None` | observe 不调用, end_to_end 也不调用 |
| U-025 | `update_prometheus_metrics` 部分 None 延迟 | `retrieval_latency=None, generation_latency=30.0` | retrieval 不调用, generation.observe(30.0), end_to_end.observe(30.0) |
| U-026 | `update_prometheus_metrics` dict 类型 context | `retrieval_context={"k1":"v1","k2":"v2"}` | doc_count.inc(2) |
| U-027 | `update_prometheus_metrics` list 类型 context | `retrieval_context=["d1","d2","d3"]` | doc_count.inc(3) |
| U-028 | `update_prometheus_metrics` str 类型 context | `retrieval_context="single doc"` | doc_count.inc(1) |
| U-029 | `update_prometheus_metrics` None context | `retrieval_context=None` | doc_count 不调用 |
| U-030 | `update_prometheus_metrics` 空 dict context | `retrieval_context={}` | doc_count.inc(0) |
| U-031 | `update_prometheus_metrics` 嵌套 dict context | `retrieval_context={"k1":{"nested":"v"}}` | doc_count.inc(1) |
| U-032 | `update_prometheus_metrics` 异常处理 | 模拟内部异常 | 不崩溃, log warning |

### 3.3 data_processor.py (新增方法)

| 用例ID | 测试点 | 输入 | 期望输出 |
|--------|--------|------|---------|
| U-040 | `_normalize_retrieval_context` dict | `{"k1":"v1","k2":"v2"}` | `["v1","v2"]` |
| U-041 | `_normalize_retrieval_context` list | `["d1","d2"]` | `["d1","d2"]` |
| U-042 | `_normalize_retrieval_context` string | `"single doc"` | `["single doc"]` |
| U-043 | `_normalize_retrieval_context` None | `None` | `None` |
| U-044 | `_normalize_retrieval_context` 空 list | `[]` | `None` |
| U-045 | `_normalize_retrieval_context` 空 string | `""` | `None` |
| U-046 | `_normalize_retrieval_context` 嵌套 dict | `{"k1":{"nested":"v"},"k2":123}` | list, `str()` 转换 |
| U-047 | `save_evaluation_sample` 正常写入 | 全部字段有效 | return True, cursor.execute 调用 1 次 |
| U-048 | `save_evaluation_sample` dict 类型 context | `{"k1":"v1"}` | 写入时 `json.dumps(["v1"])` |
| U-049 | `save_evaluation_sample` None 连接 | `_get_db_connection → None` | return False |
| U-050 | `save_evaluation_sample` DB 写入异常 | cursor.execute throw | return False, rollback 调用 |
| U-051 | `save_evaluation_sample` commit 异常 | conn.commit throw | return False, rollback 调用 |
| U-052 | `save_evaluation_sample` close 连接异常 | _close_db_connection throw | 不影响返回值 |
| U-053 | `save_evaluation_sample` 空 list context | `[]` | context 字段写入 None |
| U-054 | `save_evaluation_sample` 所有 category 类型 | 技术/使用/社区/其他 | 全部成功写入 |
| U-055 | `save_token_usage` None 输入 | `token_usage=None` | 各字段为 0 |
| U-056 | `save_token_usage` 空 dict 输入 | `token_usage={}` | 各字段为 0 |
| U-057 | `save_token_usage` ON CONFLICT upsert | 重复 topic_id | 更新而不是插入 |
| U-058 | `save_token_usage` 无连接 | `_get_db_connection → None` | 静默返回 |

### 3.4 build_dataset.py

| 用例ID | 测试点 | 输入 | 期望输出 |
|--------|--------|------|---------|
| U-060 | 正常构建数据集 | DB 返回 3 条记录 | JSON 文件生成, 样本数 >0 |
| U-061 | 去重逻辑 | 2条相同问题 | 只保留 1 条 |
| U-062 | 分层抽样 | 技术 200 条, 使用 30 条 | 技术 ≤100, 使用全部 30 条 |
| U-063 | DB 连接失败 | `psycopg2.connect` throw | return None |
| U-064 | 空结果集 | DB 返回 [] | return None, 打印提示 |
| U-065 | `similar()` 函数 | `("abc","abc")` | 1.0 |
| U-066 | `similar()` 函数 | `("abc","def")` | < 1.0 |
| U-067 | CLI 参数解析 | 自定义参数 | 正确解析并使用 |
| U-068 | 输出目录不存在 | output_dir 新建 | 自动创建目录 |

### 3.5 run_baseline.py

| 用例ID | 测试点 | 输入 | 期望输出 |
|--------|--------|------|---------|
| U-070 | 正常评测运行 | 2 条样本 | Markdown 报告含所有指标章节 |
| U-071 | 数据集文件不存在 | 无效路径 | return None |
| U-072 | 空数据集 | `[]` | 报告生成成功 (无评分) |
| U-073 | string 类型 context | `"doc string"` | 正常处理为 `["doc string"]` |
| U-074 | dict 类型 context | `{"k":"v"}` | 正常处理为 `["v"]` |
| U-075 | 嵌套 dict context | `{"k1":{"n":"v"},"k2":123}` | 全部 str() 转换 |
| U-076 | LLM 调用失败 | API 异常 | 对应指标为 None, 报告仍生成 |
| U-077 | `extract_score` 小数 | `"0.85"` | 0.85 |
| U-078 | `extract_score` 整数 | `"8"` | 0.8 (除以 10) |
| U-079 | `extract_score` 无效输入 | `"invalid"` | 0.5 (默认值) |
| U-080 | `extract_score` 越界 | `"15"` | 1.0 (截断) |
| U-081 | `extract_score` 带文字 | `"评分是 0.9"` | 0.9 |
| U-082 | `normalize_retrieval_context` list | `["a","b"]` | `["a","b"]` |
| U-083 | `normalize_retrieval_context` string | `"text"` | `["text"]` |
| U-084 | `normalize_retrieval_context` dict | `{"k":"v"}` | `["v"]` |
| U-085 | `normalize_retrieval_context` None | `None` | `[]` |
| U-086 | `normalize_retrieval_context` 空 list | `[]` | `[]` |
| U-087 | `normalize_retrieval_context` 空 dict | `{}` | `[]` |
| U-088 | `normalize_retrieval_context` list 含混合类型 | `["str", 123, {}]` | 全部 str() |

### 3.6 main.py / Flask 端点

| 用例ID | 测试点 | 输入 | 期望输出 |
|--------|--------|------|---------|
| U-090 | `/metrics` 端点可访问 | GET /metrics | 200, Content-Type: text/plain, 含 Prometheus 指标文本 |
| U-091 | `/health` 端点不受影响 | GET /health | 200 (服务正常时) |
| U-092 | `/health/detail` 不受影响 | GET /health/detail | 返回详细状态 |
| U-093 | `/startup` 不受影响 | GET /startup | 按已有逻辑返回 |
| U-094 | `/metrics` 未初始化时 | 服务未完全启动 | 仍返回指标(部分为 0) |

### 3.7 JSONB/psycopg2 适配 (来自 PR #112, #113)

| 用例ID | 测试点 | 输入 | 期望输出 |
|--------|--------|------|---------|
| U-100 | `register_default_jsonb` 注册 | 模块导入 | 成功调用, 不抛异常 |
| U-101 | `register_adapter(dict, Json)` | 模块导入 | 成功调用 |
| U-102 | `append_to_db` replies list | `[{"id":1}]` | JSON 字符串写入 DB |
| U-103 | `append_to_db` replies 空 list | `[]` | `"[]"` 写入 DB |
| U-104 | `append_to_db` replies JSON 字符串 | `'[{"id":1}]'` | 原样传入 |
| U-105 | `append_to_db` replies None/缺失 | 无 replies key | `"[]"` 写入 DB |
| U-106 | `append_to_db` replies 混合类型 | `["str", {"k":"v"}, 123, None]` | 正确序列化 |
| U-107 | `save_search_results_to_db` 含 dict | `[{"topic_id":1}]` | dict 被 Json 适配后存入 |

---

## 四、集成测试

### 4.1 钩子→存储管道

| 用例ID | 测试点 | 测试方法 | 验证点 |
|--------|--------|---------|--------|
| I-001 | 检索钩子捕获→evaluation_hooks→存储 | 模拟 forum_client 返回, 走完整 _process_new_topics | evaluation_samples 表有新记录 |
| I-002 | 生成钩子捕获→存储 | 模拟 ai_processor 返回 | actual_output + generation_latency 写入正确 |
| I-003 | 钩子装饰器不影响原始返回值 | 直接调用被装饰函数 | 原返回值不变 |
| I-004 | 钩子异常兜底 | 模拟 context 获取异常 | 主流程正常完成, 不崩溃 |
| I-005 | 一条完整 topic 的数据组装 | 模拟 topic 处理全链路 | 所有 9 个字段写入 evaluation_samples |

### 4.2 存储→Prometheus 指标

| 用例ID | 测试点 | 测试方法 | 验证点 |
|--------|--------|---------|--------|
| I-010 | 数据写入后指标更新 | 写入 sample 后调用 update_prometheus_metrics | Counter/Gauge 数值变化 |
| I-011 | 多次写入后指标累积 | 连续写入 5 条 | topic_count = 5, doc_count 累加 |
| I-012 | 空回复指标翻转 | 写入有内容→无内容 交替 | Gauge 在 0.0/1.0 间切换 |
| I-013 | `/metrics` 端点输出完整性 | GET /metrics | 包含所有 6 个指标的 # HELP 和 # TYPE |

### 4.3 PostgreSQL 表与约束

| 用例ID | 测试点 | 测试方法 | 验证点 |
|--------|--------|---------|--------|
| I-020 | `evaluation_samples` 表创建 | 调用 `create_tables()` | 表存在, 包含 topic_id, input, retrieval_context(JSONB), actual_output 等列 |
| I-021 | `consume_tokens_topic` UNIQUE 约束迁移 | 旧表无约束 → 调用 create_tables | 约束添加, 重复数据已清理 |
| I-022 | `consume_tokens_topic` 约束已存在时跳过 | 再次调用 create_tables | 不报错, 不重复添加 |
| I-023 | `consume_tokens_topic` ON CONFLICT upsert | 相同 topic_id 两次写入 | 数据更新而非冗余插入 |

### 4.4 评测管线 (离线)

| 用例ID | 测试点 | 测试方法 | 验证点 |
|--------|--------|---------|--------|
| I-030 | 数据集构建→评测报告 全链路 | build_dataset.py + run_baseline.py 串联 | 报告含三个指标的分数分布 |
| I-031 | 分类别统计正确性 | 含多种 category 的数据集 | 每类独立统计 |
| I-032 | config.yaml 读取 | 实际读取项目配置 | model_name, base_url 正确读取 |

---

## 五、端到端测试

### 5.1 完整数据流

| 用例ID | 测试点 | 前置条件 | 验证点 |
|--------|--------|---------|--------|
| E-001 | 用户提问 → 检索 → 生成 → 存储 → 指标 | 服务运行中, 真实或模拟论坛帖子 | 1) PG 有新 sample 记录 2) /metrics 指标更新 3) 日志无异常 |
| E-002 | 无检索上下文的帖子 | forum 返回空搜索结果 | retrieval_context=None, 仍正常存储 |
| E-003 | 大模型生成失败的帖子 | ai_processor 调用失败 | 不崩溃, sample 写入时 actual_output=None |
| E-004 | 批量帖子处理 | 10个新帖子 | 所有 sample 正确写入, topic_count=10 |
| E-005 | 7天采集后构建数据集 | evaluation_samples 积累足够 | build_dataset 产出 JSON, run_baseline 产出报告 |

### 5.2 Docker 镜像验证

| 用例ID | 测试点 | 验证方法 |
|--------|--------|---------|
| E-010 | prometheus_client 可正常导入 | `docker run <image> python -c "from prometheus_client import generate_latest; print(generate_latest().decode())"` |
| E-011 | timeit.py 未被删除 | `docker run <image> python -c "import timeit"` (不报 ModuleNotFoundError) |
| E-012 | /metrics 端点可访问 | 容器启动后 `curl localhost:5000/metrics` 返回 200 |

---

## 六、非功能测试

### 6.1 性能测试

| 用例ID | 测试点 | 测试方法 | 通过标准 |
|--------|--------|---------|---------|
| P-001 | 钩子装饰器延迟开销 | 对比装饰前后函数执行时间 | 增加 < 5ms (p99) |
| P-002 | 线程局部变量操作 | 1000 并发读取 thread.local | p99 < 0.1ms |
| P-003 | save_evaluation_sample 写入耗时 | 单次写入计时 | p99 < 100ms |
| P-004 | /metrics 端点响应时间 | ab/wrk 压测 100 req/s | p99 < 50ms |
| P-005 | 大批量数据去重性能 | 10,000 条样本去重 | < 5s 完成 |
| P-006 | 基线评测 LLM Judge 耗时 | 200 条样本 (600 次 API 调用) | 超时控制 + 进度提示 |

### 6.2 可靠性 / 容错测试

| 用例ID | 测试点 | 模拟故障 | 期望行为 |
|--------|--------|---------|---------|
| F-001 | PG 连接断开时机器人继续服务 | kill PG 连接 | 机器人正常回复, 日志警告, 无崩溃 |
| F-002 | PG 连接断开时 /metrics 不变 | kill PG | /metrics 返回上一个已知值或 0 |
| F-003 | PG 恢复后自动恢复 | 重连 PG | 后续 sample 正常写入 |
| F-004 | Prometheus metric 重复注册 (热重载) | Flask debug 模式重启 | 不抛异常, 日志 warning |
| F-005 | 钩子函数内部异常 | 装饰器内 time.time() 异常 | 原始函数仍被调用, context 置 None |
| F-006 | 多线程并发写入 PG | 10 线程同时写 evaluation_samples | 无死锁, 无数据丢失, 无重复 |
| F-007 | OOM/内存泄漏 | 长时间运行 (24h) 监控内存 | 内存稳定, 无持续增长 |
| F-008 | JSONB 序列化异常 | 不可序列化对象传入 | 明确错误信息, 不静默丢失 |
| F-009 | 数据库迁移幂等性 | 多次调用 create_tables() | 不报错, 约束状态正确 |

### 6.3 安全测试

| 用例ID | 测试点 | 验证方法 |
|--------|--------|---------|
| S-001 | /metrics 端点不暴露敏感信息 | curl /metrics 检查无 API key/password/token |
| S-002 | evaluation_samples 表示不记录鉴权凭证 | 检查表结构和实际写入内容 |
| S-003 | 评测脚本不从 config.yaml 泄露到报告 | 检查生成的 Markdown 报告 |

---

## 七、回归测试

### 7.1 现有功能不受影响

| 用例ID | 测试点 | 验证方法 |
|--------|--------|---------|
| R-001 | 论坛帖子正常采集 | 与 baseline 对比采集结果 |
| R-002 | 机器人正常回复 | 验证回复质量与上游一致 |
| R-003 | /health 端点正常 | GET /health → 200 |
| R-004 | LightRAG HTTP 调用正常 | forum_client 检索功能完整 |
| R-005 | 预审 (pre-audit) 功能正常 | pre_audit_topics 读写无误 |
| R-006 | Token 消耗统计正常 | consume_tokens_topic upsert 正确 |
| R-007 | 搜索结果保存正常 | save_search_results_to_db 无 JSONB 报错 |
| R-008 | Docker 镜像构建成功 | CI 构建通过 |
| R-009 | 现有 pytest 用例全部通过 | `pytest tests/` 0 失败 |
| R-010 | forum_client.py / ai_processor.py 函数签名不变 | 仅增加装饰器, 调用方无感 |

### 7.2 关键回归点 (来自 PR #110, #111, #112, #113 修复的 Bug)

| 用例ID | 复现条件 | Bug 描述 | 验证 |
|--------|---------|---------|------|
| R-020 | `timeit.py` 已删除的旧镜像 | prometheus 启动抛 `ModuleNotFoundError` | 新镜像 `import timeit` 成功 |
| R-021 | 重复 topic_id 写入 consume_tokens_topic | 旧版无 UNIQUE 约束, 产生重复行 | 迁移后约束存在, upsert 工作 |
| R-022 | save_token_usage 传入 `None` | 旧版抛 AttributeError | 新版本各字段默认 0 |
| R-023 | retrieval_context 为 dict 时 prometheus 处理 | 旧版 `isinstance(dict)` 未处理导致逻辑错误 | 新版本 len(.values()) |
| R-024 | retrieval_context 为 dict 时 save_evaluation_sample | 旧版直接存 dict 导致 `can't adapt type 'dict'` | 新版本 json.dumps(normalized) |
| R-025 | append_to_db 中 replies 为 list 时 JSONB 适配 | 旧版 `psycopg2` 无法自动适配 list→JSONB | 新版本 register_adapter(dict, Json) |

---

## 八、验收测试 (对照 Issue 验收标准)

| # | Issue 标准 | 对应测试 | 状态 |
|---|-----------|---------|------|
| 1 | 线上机器人功能不受影响 | E-001~E-003, R-001~R-002 | 待测 |
| 2 | `/health` 返回 200 | R-003 | 待测 |
| 3 | `evaluation_samples` 表有持续写入 | I-001~I-005, E-001 | 待测 |
| 4 | `/metrics` 端点可访问且数据正确 | I-010~I-013, U-090 | 待测 |
| 5 | 钩子异常不影响主流程 | F-005, I-004 | 待测 |
| 6 | 模拟 PG 不可用时机器人仍正常回复 | F-001, F-002 | 待测 |
| 7 | 评估数据集 JSON 可生成 (200-400 条) | U-060~U-062, E-005 | 待测 |
| 8 | 基线评测可执行, 产出报告含分指标得分 | U-070, I-030 | 待测 |
| 9 | 不修改现有业务函数签名 | R-010 | 待测 |
| 10 | 新增依赖在 requirements.txt 中 | 检查 requirements.txt 含 prometheus-client | 待测 |

---

## 九、测试环境与工具

### 9.1 环境要求

| 层级 | 环境 | 说明 |
|------|------|------|
| 单元测试 | 本地开发 + CI | `pytest` 运行, mock psycopg2/prometheus_client |
| 集成测试 | 本地 PostgreSQL + Flask 测试实例 | 需要真实 PG 实例 |
| 端到端测试 | 预览环境 (K8s) | 通过 `/ai-develop-preview` 部署 |
| 性能测试 | 预览环境 | 使用 `ab` / `wrk` / `locust` |

### 9.2 测试数据准备

- **单元测试**: 使用 `unittest.mock` / `pytest.fixture` 构造 mock 数据
- **集成测试**: 使用测试专用 PostgreSQL 数据库, 预置 schema
- **端到端**: 等待至少 1 小时的论坛帖子处理, 积累 >= 10 条 evaluation_samples
- **评测数据集**: 采集期至少 7 天积累, 或使用历史 mock 数据导入

### 9.3 运行命令

```bash
# 单元测试 (含覆盖率)
pytest tests/ -v --cov=src --cov-report=term --cov-report=html

# 仅评估相关测试
pytest tests/test_evaluation*.py tests/test_prometheus*.py tests/test_jsonb*.py tests/test_main*.py tests/test_health*.py -v

# 运行基线评测 (离线)
python -m src.evaluation.build_dataset --days 30 --output_dir evaluation_datasets
python -m src.evaluation.run_baseline evaluation_datasets/evaluation_dataset_*.json

# 检查 /metrics 端点
curl http://localhost:5000/metrics

# 检查健康状态
curl http://localhost:5000/health
```

---

## 十、风险与建议

### 10.1 已知风险

1. **JSONB 序列化边界**: dict 类型 retrieval_context 在多个节点被处理 (evaluation_hooks, prometheus_metrics, data_processor), 不一致的处理方式可能导致数据差异
2. **Thread-local 的 Flask 兼容性**: Flask 开发模式下多进程/多线程混合可能导致 context 丢失
3. **PSQL 连接池耗尽**: save_evaluation_sample 每次新建连接, 高并发场景可能耗尽连接
4. **Prometheus Counter 重启归零**: 服务重启后 forum_processed_topic_count 归零, 需在 Prometheus 侧用 `rate()` 处理

### 10.2 测试优先级建议

| 优先级 | 测试集 | 原因 |
|--------|--------|------|
| **P0** | 回归测试 R-001~R-025 | 确保不引入回归 |
| **P0** | 单元测试 U-001~U-106 | 基础功能正确性 |
| **P1** | 集成测试 I-001~I-030 | 组件协作正确性 |
| **P1** | 验收测试 E-001~E-012 | 对照 Issue 标准 |
| **P2** | 非功能测试 P-001~P-006, F-001~F-009 | 性能和可靠性 |
| **P2** | 端到端测试 E-001~E-012 | 完整链路验证 |
| **P3** | 安全测试 S-001~S-003 | 安全基线 |

---

## 十一、测试用例总数统计

| 类别 | 数量 |
|------|------|
| 单元测试 (evaluation_hooks) | 14 |
| 单元测试 (prometheus_metrics) | 13 |
| 单元测试 (data_processor) | 19 |
| 单元测试 (build_dataset) | 9 |
| 单元测试 (run_baseline) | 19 |
| 单元测试 (Flask 端点) | 5 |
| 单元测试 (JSONB 适配) | 8 |
| 集成测试 | 23 |
| 端到端测试 | 12 |
| 非功能测试 | 18 |
| 回归测试 | 25 |
| 验收测试 | 10 |
| **合计** | **175** |
