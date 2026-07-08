---
tags:
  - error
  - backlog
  - 部署
  - issue-621
  - K8s
issue: 621
---

# backlog #621 — 开发预览部署失败分析

**时间**: 2026-06-10  **仓库**: opensourceways/backlog
**Issue**: [#621 - 社区回复机器人 RAG 持续看护](https://github.com/opensourceways/backlog/issues/621)

---

## 错误概览

| # | 类型 | 位置 | 简要描述 |
|---|------|------|---------|
| 1 | 部署失败 | Run 27251637974 implement job | self-hosted runner 容器崩溃，部署 49 分钟后失败 |
| 2 | 部署失败 | Run 27253596792 implement job | 同上，部署 47 分钟后失败 |
| 3 | heredoc 转义 | sync.sh 第 197 行 | TOK 变量在 bash heredoc 中未转义，`set -u` 下 "unbound variable" |
| 4 | Pod 启动崩溃 | main.py | EvaluationTimer 顶层 import 在依赖缺失时导致 CrashLoopBackOff |
| 5 | 探针配置不当 | sync.sh YAML | readinessProbe 从 tcpSocket 改为 httpGet + initialDelaySeconds 30s 过短 |

---

## 详细分析

### 错误 1: sync.sh heredoc 变量转义被破坏（根本原因）

**原始日志**:
```
-  TOK="$(cat /run/secrets/clone/token 2>/dev/null || true)"
-  在 `set -u` 环境下，`${TOK}` 未定义导致 "unbound variable" 错误，部署中止
```

**原因分析**:
- sync.sh 通过 `cat <<YAML` heredoc 生成 Kubernetes Deployment YAML
- 容器 args 里的 `\$BRANCH` / `\${TOK}` 是容器运行时的字面量，必须保留反斜杠转义
- 某次修改去掉了转义，`TOK="$(cat ..."` 变成直接展开，外层 `set -u` 下 TOK 未定义 → "unbound variable" 崩溃
- YAML 未生成，kubectl apply 直接跳过，部署中止

**修复**:
```
-  TOK="$(cat /run/secrets/clone/token 2>/dev/null || true)"
+  TOK="\$(cat /run/secrets/clone/token 2>/dev/null || true)"
```

Agent 在两轮中都正确识别并修复了此问题。

### 错误 2: 部署阶段 self-hosted runner 崩溃

**原始日志**:
```
── [2026-06-10 12:44:27] 部署预览到 forum-reply-robot ──
... 47 分钟无输出 ...
##[error]Executing the custom container implementation failed. Please contact your self hosted runner administrator.
```

**原因分析**:
- 两轮 run 都在 `kubectl apply` + 等待 rollout 阶段崩溃
- 耗时 47-49 分钟，远小于 progressDeadlineSeconds (7200s = 120 分)
- **可能原因**:
  1. Pod 持续 CrashLoopBackOff，kubectl rollout status 永远等不到 Ready
  2. Self-hosted runner 容器 OOM / 超时（runner 层限制 ~50 分钟）
  3. readinessProbe.initialDelaySeconds 从 5400 改到 30，探针过早触发但服务未就绪

**影响范围**: 预览环境从未成功部署，阻塞开发→测试流程。

### 错误 3: readinessProbe 配置与启动时序不匹配

**原始日志 (diff)**:
```
-          tcpSocket: { port: 5000 }
-          initialDelaySeconds: 5400
+          httpGet: { path: /health, port: 5000 }
+          initialDelaySeconds: 30
-          failureThreshold: 30
+          failureThreshold: 60
+          timeoutSeconds: 5
```

**原因分析**:
- 原始配置: `tcpSocket` 探针 + `initialDelaySeconds: 5400`(90分钟)，匹配 LightRAG 全量数据初始化耗时
- Agent 改为: `httpGet` 探针 + `initialDelaySeconds: 30`(30秒)
- 虽然 main.py 做了异步初始化（Flask 快速启动监听 5000），但 /health 端点需要 `monitor_instance` 已创建
- 如果后台初始化失败或耗时过长，30 秒后探针失败 → `failureThreshold: 60` → 最多 30+60*10=630 秒后 pod 标记为 Unhealthy → CrashLoopBackOff
- `progressDeadlineSeconds: 7200` 虽大，但 pod 持续重启无法 progressing，kubectl rollout status 阻塞

**与 B3 规则的关联**:
- `progressDeadlineSeconds`(7200s)、`readinessProbe.initialDelaySeconds`(30s → 原5400s)、`kubectl rollout status --timeout` 三者严重不匹配
- 这是典型的时间窗口冲突问题

### 错误 4: main.py EvaluationTimer 导入崩溃

**原始日志 (Pod 日志)**:
```
from src.ForumBot.evaluation_timer import EvaluationTimer
# → ModuleNotFoundError / ImportError → Pod CrashLoopBackOff
```

**原因分析**:
- AI Agent 在 main.py 顶部加了 `from src.ForumBot.evaluation_timer import EvaluationTimer`
- 该模块或其依赖链在 import 阶段失败 → Flask 无法启动 → Pod 崩溃
- 已修复为懒加载 + try/except 隔离

---

## 总结

**核心问题**: 部署失败是**多层叠加**的复合故障：

1. **sync.sh heredoc 转义** → YAML 生成失败 → 部署中止（已在两轮 run 中修复）
2. **readinessProbe 配置错位** → initialDelaySeconds 30s 太短，pod 永远无法通过探针 → CrashLoopBackOff
3. **Self-hosted runner 稳定性** → 容器在 ~47 分钟后崩溃（可能受 runner 资源限制）
4. **Pod 应用层启动问题** → EvaluationTimer 导入崩溃（已修复）、LightRAG 初始化失败时 /health 判定逻辑不当

**修复建议**:
1. `readinessProbe.initialDelaySeconds` 应设为足够长（建议 300-600s），等待后台初始化启动
2. `/health` 端点应改为：Flask 存活即返回 200（如用户最新指令所述）
3. `progressDeadlineSeconds` 保持 7200 或降低到 3600（按用户最新指令）
4. 在 sync.sh 的 CI 规则中加入 heredoc 转义完整性检查，防止 agent 误修改
5. 排查 self-hosted runner 的容器资源限制和超时配置

---

## 🔗 相关笔记

- [[backlog-CI-术语解释]] — 探针/heredoc 术语解释
- [[2026-06-10-forum-reply-robot-issue分析]] — issue#621 开发上下文
- [[2026-06-09-forum-reply-robot-pod启动超时]] — 相关 Pod 故障

> 索引：[[错误库]] · [[Issue 专题]] · 返回 [[首页]]
