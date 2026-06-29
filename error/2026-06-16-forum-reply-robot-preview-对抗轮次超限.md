---
tags:
  - error
  - forum-reply-robot
  - 对抗模式
  - issue-921
issue: 921
---

# forum-reply-robot — 开发预览对抗轮次超限 (Issue #921)

**时间**: 2026-06-16  **仓库**: opensourceways/backlog
**Issue**: https://github.com/opensourceways/backlog/issues/921

## 错误概览

| # | 类型 | Run ID | 简要描述 |
|---|------|--------|---------|
| 1 | Runner 超时 | 27599457258 | 部署阶段 self-hosted runner 崩溃 |
| 2 | Runner 超时 | 27604353824 | 部署阶段 self-hosted runner 崩溃 |
| 3 | 对抗轮次超限 | 27605916054 | preview/unknown, 对抗轮次 3/2 |
| 4 | 对抗轮次超限 | 27608733402 | preview/unknown, 对抗轮次 3/2 |
| 5 | 对抗轮次超限 | 27613130251 | preview/unknown, 对抗轮次 3/2 |

## 详细分析

### 错误 1-2: 部署阶段 Runner 超时

**原始日志**:
```
##[error]Executing the custom container implementation failed. 
Please contact your self hosted runner administrator.
```

**原因分析**: forum-reply-robot 需要加载 LightRAG 全量数据初始化（历史耗时约 90min）。若 `readinessProbe.initialDelaySeconds` 过小，Pod 在初始化完成前不断被探伤判死 → CrashLoopBackOff → `kubectl rollout status` 无限等待 → self-hosted runner 超时崩溃。

**影响范围**: 前两次 /ai-develop-preview 完全失败，Preview 环境未成功启动。

### 错误 3-5: 对抗审查轮次超限

**原始日志** (Run 27613130251 tester agent):
```
curl https://work-issue-921.preview.test.osinfra.cn/api/v1/rag/auth/authorize
→ 500 Internal Server Error
kubectl logs → RuntimeError: The session is unavailable because no secret key was set.

curl https://work-issue-921.preview.test.osinfra.cn/api/v1/rag/health
→ 404 Not Found

增量核验未过（第 2/3 轮）→ 回炉 dev 改代码 → 重部署 → 重核验
orchestrate done: phase=preview status=unknown rounds=3
```

**Tester 发现的 Bug（最新的 27613130251）**:
1. `/api/v1/rag/auth/authorize` → 500: Flask `secret_key` 未设置，OIDC 授权端点调用 `session['oidc_state']` 失败
2. `/api/v1/rag/health` → 404: 该端点未注册到 RAG API Blueprint
3. Blueprint 注册顺序问题（本轮已修复）

**每次迭代引入新 Bug**：
| 轮次 | 用户 feedback | tester 发现的新问题 |
|------|-------------|-------------------|
| 第3次 | 修改RAG API路径可达性问题 | Blueprint 注册失败 + 其他可达性问题 |
| 第4次 | 修复Blueprint注册失败问题 | Flask secret_key 未配置 + health 端点缺失 |

**根因**: dev agent 每轮修复某些问题但同时引入新 Bug，tester agent 发现新 Bug 后触发下一轮修复，3 轮超出 `MAX_FIX_ROUNDS=2`，orchestrate.sh 标记为 `unknown`。

## 总结

**当前阻塞点**: AI dev agent 无法在 2 轮修复内通过 tester agent 的全量 e2e 检查。各 endpoints 的测试返回结果：
- `tokenize` / `retrieve` → 401 (TOKEN_MISSING，正确)
- `auth/authorize` → 500 (Flask `secret_key` 缺失)
- `rag/health` → 404 (路由未注册)

**修复建议**:
1. 使用 `/ai-develop-preview --skip-design` 跳过设计阶段（设计已定稿），加速迭代
2. 在 feedback 中明确列出 tester 发现的所有具体问题：Flask `secret_key` 配置 + health 端点注册
3. 如果问题持续，考虑 `--deploy-only` 后手动修代码再 `/ai-develop-preview --skip-design`

---

## 🔗 相关笔记

- [[术语解释]] — 对抗模式概念定义
- [[backlog-architecture]] — 对抗模式在 orchestrate.sh 的实现

> 索引：[[错误库]] · [[Issue 专题]] · 返回 [[首页]]
