---
tags:
  - error
  - CI
  - pytest
  - codearts
---

# codearts-ci-config — pytest 启动崩溃导致 coverage.xml 未生成（pytest_asyncio 与 pytest 7.4.4 不兼容）

**时间**: 2026-06-23T07:34:10Z  **仓库**: opensourceways/codearts-ci-config
**Run ID**: 28009938371  **Job ID**: 82900641138  **原始链接**: https://github.com/opensourceways/codearts-ci-config/actions/runs/28009938371/job/82900641138
**Workflow**: 安全扫描门禁 (Security Gate) / event: repository_dispatch (security-gate) / branch: main

## 错误概览
| # | 类型 | 位置 | 简要描述 |
|---|------|------|---------|
| 1 | 依赖版本不兼容（根因） | `codearts-scripts/ut_scan.sh:429` pytest 启动 | 自动加载的 `pytest_asyncio` 插件 `from pytest import FixtureDef` 失败，pytest 启动即崩溃 |
| 2 | 级联失败 | `ut_scan.sh:434` | `coverage.xml` 未生成（pytest 崩溃，没跑任何用例） |
| 3 | 级联失败 | diff-cover | `FileNotFoundError: coverage.xml` → `Python(Inc) N/A ERROR` → 门禁 exit 1 |

## 详细分析

### 错误 1: pytest_asyncio 插件 import 崩溃（根因）
**原始日志**:
```
File ".../pytest_asyncio/plugin.py", line 42, in <module>
    from pytest import (
ImportError: cannot import name 'FixtureDef' from 'pytest'
    (/opt/cached_resources/sast/python/lib/python3.13/site-packages/pytest/__init__.py)
```
环境版本：`pytest 7.4.4`、`pytest-cov 7.0.0`、`python 3.13`。

**原因分析**：
- 缓存的 SAST Python 环境里 pytest 被钉死在 **7.4.4**；`ut_scan.sh` 里 `pip3 install pytest`（无版本号）不会升级它。
- 该环境里全局预装了**较新的 `pytest_asyncio`**（≥0.24，要求 pytest≥8.2）。pytest 启动时通过 `pytest11` setuptools entrypoint **自动加载**所有插件，`pytest_asyncio/plugin.py` 顶层执行 `from pytest import FixtureDef`。
- `FixtureDef` 在 pytest 8.x 才提升为顶层公共符号；pytest 7.4.4 的 `pytest` 命名空间没有它 → `ImportError` → 插件加载失败 → pytest 在收集用例前直接退出。

**影响范围**：pytest 在 collection 之前就崩溃，**所有** Python 仓库的 UT/覆盖率门禁都受影响（与被测仓库代码无关），coverage.xml 永远不会生成。

### 错误 2/3: 级联
coverage.xml 缺失 → `tail pytest_result.log` 打出上面的 traceback → diff-cover `etree.parse('coverage.xml')` 抛 `FileNotFoundError` → 最终报告 `Python(Inc) | N/A | ERROR` → `❌ [FAILURE]` → exit 1。

## 是否与已知模式匹配
不属于探针时序/heredoc 转义/Runner 超时/artifact 配额。属于新模式：**缓存环境插件版本漂移**——pytest 被钉旧版，全局 pytest 插件被升新版，autoload 时 ABI/符号不兼容导致 pytest 启动崩溃。

## 修复建议（在 codearts-ci-config 侧）
在 `codearts-scripts/ut_scan.sh` 的 `run_analysis_Python()` 内，pytest 调用前钉一个与 pytest 7.x 兼容的 pytest-asyncio：
```bash
pip3 install pytest-cov
pip3 install 'pytest-asyncio<0.24'      # 新增：0.23.x 兼容 pytest>=7；0.24+ 需 pytest>=8.2 才有 FixtureDef
python3 -m pytest --ignore-glob='test_*.py' --continue-on-collection-errors \
  --cov=./ --cov-report=term-missing --cov-report=xml:coverage.xml >pytest_result.log 2>&1
```
- 用户级安装会在 `user_packages` 覆盖系统站点里那份过新的 pytest_asyncio，保证 autoload 成功。
- 同时保留 async 用例支持，比 `-p no:asyncio` 更不破坏功能。
- 备选（更激进、风险更高）：把 pytest 升到 ≥8.2（`pip3 install -U pytest`），但会改变共享门禁里所有仓库的 pytest 大版本行为，不推荐。

## 总结
门禁失败的唯一根因是缓存 SAST 环境里 `pytest_asyncio`(≥0.24) 与被钉死的 `pytest 7.4.4` 不兼容，pytest 启动即崩溃，coverage.xml 无法生成，进而 diff-cover 报错、门禁判 FAILURE。修复点在 `codearts-scripts/ut_scan.sh`，在 pytest 调用前加 `pip3 install 'pytest-asyncio<0.24'` 即可。

---

## 🔗 相关笔记

- [[backlog-CI-术语解释]] — CI 术语背景
- [[2026-06-16-forum-reply-robot-pr113-unit-test-fail]] — 同类单测/CI 故障

> 索引：[[错误库]] · 返回 [[首页]]
