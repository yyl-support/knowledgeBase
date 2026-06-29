---
tags:
  - error
  - forum-reply-robot
  - 测试
  - CI
  - PR113
---

# forum-reply-robot — PR #113 单元测试门禁失败分析

**时间**: 2026-06-16  **仓库**: opensourceways/forum-reply-robot
**PR**: #113  **Run ID**: 27618980192  **Job ID**: 81662434023
**原始链接**: https://github.com/opensourceways/forum-reply-robot/pull/113
**Run 链接**: https://github.com/opensourceways/codearts-ci-config/actions/runs/27618980192

## 错误概览

| # | 类型 | 位置 | 简要描述 |
|---|------|------|---------|
| 1-4 | KeyError: 'api' | test_jsonb_registration.py | DataProcessor 创建在 patch 上下文外部 |
| 5 | inc coverage 49% | conftest.py | 格式化/空白行导致全文件标记为 diff |
| 6 | Exception: Close failed | test_evaluation_data_processor.py | Mock 替换了带 try/except 的真实方法 |

## 详细分析

### 错误 1-4: KeyError: 'api' (4 个新测试)

**原始日志**:
```
processor = DataProcessor(config={'database': {...}})
    → ImageProcessor.__init__ → config['api']['base_url']
KeyError: 'api'
```

**原因分析**: 4 个新增测试在 `test_jsonb_registration.py` 中将 `DataProcessor(config=...)` 放在 `with patch('ImageProcessor')` 块**外部**。退出 with 块后 patch 被撤销，真实的 `ImageProcessor` 构造函数尝试访问 `config['api']['base_url']`，触发 KeyError。

**根因**: 缩进错误——`DataProcessor` 创建代码与 `from import DataProcessor` 不在同一缩进层级。

**影响范围**: `test_jsonb_registration.py` 中 4 个新测试：
- `test_append_to_db_replies_with_nested_list`
- `test_append_to_db_replies_with_dict_tags`
- `test_append_to_db_replies_string_tags`
- `test_save_evaluation_sample_with_complex_jsonb`

### 错误 5: 增量覆盖率 49% < 80%

**原始日志**:
```
Diff Coverage
-------------
src/ForumBot/data_processor.py (100%)
tests/conftest.py (48.2%): Missing lines 63,65-69,77-78,80-84,...
-------------
Python 增量覆盖率未达标 (49% < 80.0%)
```

**原因分析**: `conftest.py` 的 diff 显示 +245/-234 行，但实际只有 8 行真正新增（`psycopg2.extensions` mock + `Json` adapter mock）。其余行被标记为变更是由于格式化差异（可能换行符 CRLF→LF 或缩进微调）。conftest.py 中已有的条件 mock 代码（`langchain_core`, `openai`, `flask`, `git` 等）在仅导入 `data_processor` 时不会被执行，这些"未覆盖行"被错误计入 diff 覆盖率。

### 错误 6: test_save_evaluation_sample_close_connection_error

**原因分析**: 测试将 `_close_db_connection` 替换为 `Mock(side_effect=Exception("Close failed"))`，但真实方法内部有 `try: conn.close() except Exception: logger.error(...)` 包裹。Mock 直接抛出异常无内部捕获，导致异常传播出 `finally` 块。

## 修复建议

### 修复 1 (KeyError)
将 4 个测试中 `processor = DataProcessor(config=...)` 移入 `with patch('ImageProcessor')` 块内部：

```python
with patch('src.ForumBot.data_processor.ImageProcessor'):
    from src.ForumBot.data_processor import DataProcessor
    processor = DataProcessor(config={...})  # ← 移入此缩进
    # ... rest of test
```

### 修复 2 (增量覆盖率)
检查 conftest.py 的 EOL 和缩进风格，用 `git diff --ignore-all-space` 验证实际变化量。需要确保增量实质性变化行能达标。

### 修复 3 (close connection)
修改 `test_save_evaluation_sample_close_connection_error`: 不替换 `_close_db_connection` 的 Mock side_effect，改为让 mock 的 conn.close() 抛异常，同时保留真实的 `_close_db_connection` 方法（不替换它）。

## 总结

| 维度 | 评估 |
|------|------|
| 根因 | test_jsonb_registration.py 中 4 个新测试缩进错误 + conftest.py 格式化 diff 污染增量覆盖率 |
| 是否已知模式 | 否，属于测试代码质量问题 |
| 核心修复 | 调整 4 个测试的缩进使 DataProcessor 创建保持在 patch 上下文内 |

---

## 🔗 相关笔记

- [[integration-tests-集成测试]] — 单测门禁属于测试体系
- [[backlog-CI-术语解释]] — CI 术语

> 索引：[[错误库]] · 返回 [[首页]]
