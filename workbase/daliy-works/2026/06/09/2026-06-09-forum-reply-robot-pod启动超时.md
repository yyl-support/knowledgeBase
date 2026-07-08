---
tags:
  - error
  - forum-reply-robot
  - K8s
  - 部署
  - issue-621
---

# forum-reply-robot — AI 开发管线修改代码导致 Pod 启动失败

**时间**: 2026-06-09 13:55 UTC
**仓库**: opensourceways/backlog
**Run ID**: 27209922254
**Job ID**: 80335955671
**原始链接**: https://github.com/opensourceways/backlog/actions/runs/27209922254/job/80335955671

## 错误概览

| # | 类型 | 位置 | 简要描述 |
|---|------|------|---------|
| 1 | Deployment Deadline Exceeded | ~L1994 | `work-issue-621` 超过 rollout 进度截止时间 |
| 2 | pytest 缺失 | L1370, L1592 | AI Agent 无法运行测试，`pytest: command not found` |
| 3 | pip 安装受限 | L1608 | 预览环境禁止 pip 安装, `externally-managed-environment` |

## 详细分析

### 错误 1: Pod 启动超时，Deployment 超过进度截止时间

**原始日志**:
```
deployment.apps/work-issue-621 configured
deployment.apps/work-issue-621 restarted
Waiting for deployment "work-issue-621" rollout to finish: 0 out of 1 new replicas have been updated...
Waiting for deployment "work-issue-621" rollout to finish: 0 out of 1 new replicas have been updated...
Waiting for deployment "work-issue-621" rollout to finish: 0 out of 1 new replicas have been updated...
Waiting for deployment "work-issue-621" rollout to finish: 0 of 1 updated replicas are available...
error: deployment "work-issue-621" exceeded its progress deadline
```

**原因分析**:

AI 开发管线 (agent dev) 对 `main.py` 和 `evaluation_timer.py` 做了以下修改：

1. **main.py 新增导入**:
   ```python
   from src.ForumBot.evaluation_timer import EvaluationTimer  # 新增顶级导入
   ```
   如果 `evaluation_timer.py` 或其依赖链中任何模块在 import 阶段有运行时依赖（如连接数据库、读取配置文件、缺失第三方包），会导致 `main.py` 在 Flask 启动前就崩溃。

2. **main.py 新增启动逻辑**:
   ```python
   evaluation_timer_instance = EvaluationTimer(config=config)  # __init__ 可能抛异常
   evaluation_timer_instance.start()                           # start 可能阻塞或抛异常
   ```
   虽然外层有 `try/except` 捕获，但如果 `EvaluationTimer.__init__` 尝试连接 pgvector/外部 API 且超时**极长**（预览环境网络到这些内部服务可能不通），会导致启动阶段阻塞，readiness probe 持续失败。

3. **Agent 无法验证代码正确性**: 预览环境中 pytest 未安装 (`command not found`)，pip 被 PEP 668 限制 (`externally-managed-environment`)。Agent 只能做语法检查 (`py_compile`)，无法运行任何实际测试，提交的代码完全未经运行时验证。

4. **历史重演**: git log 显示这是**同类问题的第三次出现**:
   ```
   fa05698 fix: 预览Pod启动超时及readiness探针调整
   5206497 chore: 预览Pod超时从600s改为6000s，readiness initialDelay从60s改为5400s
   ```
   即使将超时从 600s 提高到 6000s，Pod 仍然没能在截止时间内就绪，说明 Pod 进入了 CrashLoopBackOff（启动即崩溃）而非慢启动。

**影响范围**:
- PR #621 的预览环境不可用
- 阻塞该 Issue 的后续开发/验收流程
- 部署阶段可见 `discourse.test.osinfra.cn` 返回 200（存量 Pod 仍然存活），但新代码未生效

---

### 错误 2: pytest 缺失 → 代码零测试覆盖变更

**原始日志**:
```
/usr/bin/bash: line 1: pytest: command not found
/usr/bin/bash: line 1: python: command not found
error: externally-managed-environment
```

**原因分析**: 预览环境的 Docker 镜像中未预装 pytest、pytest-cov，Agent 在 `pip3 install` 时被 PEP 668 机制阻断。Agent 只能降级为 `python3 -m py_compile` 做语法校验，完全跳过单元测试。

**影响范围**: 对 `main.py` 和 `evaluation_timer.py` 的修改未经任何自动化测试验证，直接进入部署。

## 总结

**根本原因**: AI Agent 在无法运行测试的环境下，向 `main.py` 注入了 `EvaluationTimer` 的启动代码。`EvaluationTimer` 在预览环境的网络/服务条件下启动失败（或阻塞超长），导致新 Pod 持续崩溃，Deployment rollout 超时。

**关键证据**:
- 同类问题已发生至少 3 次（前两次 commit 都在修 Pod 启动超时）
- Agent 在日志中明确写了 `pytest: command not found` 和 `error: externally-managed-environment`，但仍继续部署
- 修改的代码未经任何运行时验证（仅 `py_compile` 语法检查通过）

**建议修复方向**:
1. **短期**: 在 AI 管线中加入"预览环境无测试能力"的防护 —— 当检测到无 pytest/pip 环境时，禁止 Agent 修改可能影响启动路径的代码（如 main.py 导入、全局初始化）
2. **中期**: 在 `shadow_evaluation_timer()` 中增加超时保护和异步启动机制，避免 EvaluationTimer 初始化阻塞主进程
3. **长期**: 为预览环境 Docker 镜像预装 pytest/pytest-cov，或使用 venv 隔离 pip 安装，确保 Agent 的代码变更可以通过测试

---

## 🔗 相关笔记

- [[forum-reply-robot-ai-flow-vault]] — Pod 启动与部署机制
- [[backlog-CI-术语解释]] — K8s 探针术语
- [[2026-06-10-backlog-issue621-preview-deploy-failed]] — 同 issue#621 部署故障

> 索引：[[错误库]] · [[Issue 专题]] · 返回 [[首页]]
