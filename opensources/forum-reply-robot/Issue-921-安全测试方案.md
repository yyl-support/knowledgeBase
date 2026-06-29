---
tags:
  - issue-921
  - 安全
  - 测试
  - RAG
  - forum-reply-robot
issue: 921
---

# Issue #921 openUBMC RAG API — 安全测试方案

> 测试环境：`https://lightrag-cn4.test.osinfra.cn`（根据实际部署调整）
> 测试范围：OIDC 认证、限流、输入校验、API 透传、并发安全

---

## 一、接口清单

| 方法 | 路径 | 功能 | 认证 |
|------|------|------|------|
| GET | `/api/v1/rag/auth/authorize` | OIDC 授权入口 | 否 |
| GET | `/api/v1/rag/auth/callback` | OIDC 回调 | 否 |
| POST | `/api/v1/rag/auth/refresh` | 刷新 token | 否（带 refresh_token） |
| GET | `/health` | 健康检查 | 否 |
| POST | `/api/v1/rag/retrieve` | RAG 检索（透传 /query） | 是 |
| GET | `/api/v1/rag/documents/status_counts` | 文档状态统计（透传） | 是 |
| GET | `/api/v1/rag/documents/pipeline_status` | 管道状态（透传） | 是 |
| POST | `/api/v1/rag/documents/paginated` | 分页文档列表（透传） | 是 |

---

## 二、认证测试（OIDC）

### 2.1 无 token 访问受保护接口

```bash
# /retrieve
curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/v1/rag/retrieve \
  -H "Content-Type: application/json" -d '{"query":"test"}'
# 预期: 401

# /documents/status_counts
curl -s -o /dev/null -w "%{http_code}" $BASE/api/v1/rag/documents/status_counts
# 预期: 401

# /documents/pipeline_status
curl -s -o /dev/null -w "%{http_code}" $BASE/api/v1/rag/documents/pipeline_status
# 预期: 401

# /documents/paginated
curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/v1/rag/documents/paginated \
  -H "Content-Type: application/json" -d '{}'
# 预期: 401
```

### 2.2 伪造 / 空 / 过期 token 被拒绝

```bash
# 假 token
curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/v1/rag/retrieve \
  -H "Authorization: Bearer fake123" \
  -H "Content-Type: application/json" -d '{"query":"test"}'
# 预期: 401

# 空 token
curl -s -o /dev/null -w "%{http_code}" $BASE/api/v1/rag/documents/status_counts \
  -H "Authorization: Bearer "
# 预期: 401

# 过期 token
curl -s -o /dev/null -w "%{http_code}" $BASE/api/v1/rag/retrieve \
  -H "Authorization: Bearer $EXPIRED_TOKEN" \
  -H "Content-Type: application/json" -d '{"query":"test"}'
# 预期: 401
```

### 2.3 不同格式 Authorization 头

```bash
# 无 Bearer 前缀
curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/v1/rag/retrieve \
  -H "Authorization: $VALID_TOKEN" -d '{"query":"test"}'
# 预期: 401

# Basic 而非 Bearer
curl -s -o /dev/null -w "%{http_code}" $BASE/api/v1/rag/documents/status_counts \
  -H "Authorization: Basic dGVzdDp0ZXN0"
# 预期: 401
```

### 2.4 OIDC 回调安全

```bash
# 无 code
curl -s "$BASE/api/v1/rag/auth/callback?state=test"
# 预期: 400

# 无 state
curl -s "$BASE/api/v1/rag/auth/callback?code=fake"
# 预期: 400

# 伪造 state
curl -s "$BASE/api/v1/rag/auth/callback?code=fake&state=fake"
# 预期: 400（state 不匹配）

# 重复使用 code
curl -s "$BASE/api/v1/rag/auth/callback?code=USED_CODE&state=VALID_STATE"
# 预期: 400 或 500
```

---

## 三、限流测试

### 3.1 连续请求触发限流

```bash
for i in $(seq 1 105); do
  code=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/v1/rag/retrieve \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" -d '{"query":"test"}')
  echo "$i: $code"
done
# 第 101 次起预期: 429
```

### 3.2 限流后下一窗口恢复

等待 1 小时后重新调用，预期 200。

### 3.3 不同用户限流独立

用户 A 超限后，用户 B 正常返回 200。

### 3.4 新接口同样受限流保护

```bash
for i in $(seq 1 105); do
  code=$(curl -s -o /dev/null -w "%{http_code}" $BASE/api/v1/rag/documents/status_counts \
    -H "Authorization: Bearer $TOKEN")
  echo "$i: $code"
done
# 第 101 次起预期: 429
```

---

## 四、新接口功能测试

### 4.1 status_counts 透传

```bash
curl -s $BASE/api/v1/rag/documents/status_counts \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
# 预期: 返回 LightRAG 原始响应，包含 status_counts 对象
```

### 4.2 pipeline_status 透传

```bash
curl -s $BASE/api/v1/rag/documents/pipeline_status \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
# 预期: 返回 LightRAG 原始响应
```

### 4.3 paginated 透传

```bash
curl -s -X POST $BASE/api/v1/rag/documents/paginated \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"page":1,"page_size":10,"status_filter":"COMPLETED"}' | python3 -m json.tool
# 预期: 返回 LightRAG 原始分页响应
```

### 4.4 paginated 参数校验

```bash
# 空 body
curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/v1/rag/documents/paginated \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
# 预期: 透传空 body，由 LightRAG 决定拒绝或默认返回
```

---

## 五、输入校验测试

### 5.1 SQL 注入

```bash
curl -s -X POST $BASE/api/v1/rag/retrieve \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"'\''; DROP TABLE users; --"}'
# 预期: 200（透传，LightRAG 处理）
```

### 5.2 XSS 注入

```bash
curl -s -X POST $BASE/api/v1/rag/retrieve \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"<script>alert(1)</script>"}'
# 预期: 200，响应中不应包含可执行 script
```

### 5.3 超长输入

```bash
BIG=$(python3 -c "print('A'*10240)")
curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/v1/rag/retrieve \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"$BIG\"}"
# 预期: 透传，LightRAG 决定处理或拒绝
```

### 5.4 畸形请求

```bash
# 非 JSON
curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/v1/rag/retrieve \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "not json"
# 预期: 400

# XML
curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/v1/rag/retrieve \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/xml" -d "<query>test</query>"
# 预期: 415
```

---

## 六、HTTP 安全测试

### 6.1 TLS 强制

```bash
curl -s -o /dev/null -w "%{http_code}" "http://$BASE/health"
# 预期: 拒绝连接或重定向 HTTPS
```

### 6.2 方法限制

```bash
# health 仅 GET
curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/health
# 预期: 405

# status_counts 仅 GET
curl -s -o /dev/null -w "%{http_code}" -X DELETE $BASE/api/v1/rag/documents/status_counts \
  -H "Authorization: Bearer $TOKEN"
# 预期: 405
```

### 6.3 路径遍历

```bash
curl -s -o /dev/null -w "%{http_code}" "$BASE/api/v1/rag/../../../etc/passwd"
curl -s -o /dev/null -w "%{http_code}" "$BASE/api/v1/rag/..%2f..%2f..%2fetc%2fpasswd"
# 预期: 404
```

---

## 七、并发与性能测试

### 7.1 并发请求

```bash
# 100 并发 retrieve
seq 100 | xargs -P100 -I{} curl -s -o /dev/null -w "{}: %{http_code}\n" \
  -X POST $BASE/api/v1/rag/retrieve \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"query":"test"}'
# 预期: 全部 200（未超限流），无 500

# 50 并发 status_counts
seq 50 | xargs -P50 -I{} curl -s -o /dev/null -w "{}: %{http_code}\n" \
  $BASE/api/v1/rag/documents/status_counts \
  -H "Authorization: Bearer $TOKEN"
# 预期: 全部 200
```

### 7.2 持续压力

```bash
for i in $(seq 1 60); do
  for j in $(seq 1 10); do
    curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/v1/rag/retrieve \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" -d '{"query":"test"}' &
  done
  sleep 1
done
# 预期: 无服务崩溃
```

---

## 八、日志与监控

### 8.1 敏感信息不泄露

检查服务日志，确保 `access_token` / `refresh_token` / `client_secret` 不以明文出现。

### 8.2 错误不泄露堆栈

500 响应不含 Python traceback、文件路径、代码行号。

### 8.3 健康检查

```bash
curl -s $BASE/health | python3 -m json.tool
# 预期: {"status":"healthy","service":"openubmc-rag-api"}
# 不暴露内部 IP、数据库配置
```

---

## 九、测试汇总

| 测试类型 | 用例数 | 关键项 |
|------|------|------|
| 认证 | 6 | 无 token / 假 token / 过期 / 格式变体 / OIDC 回调 |
| 限流 | 4 | 触发 / 恢复 / 隔离 / 新接口覆盖 |
| 新接口 | 4 | status_counts / pipeline_status / paginated / 参数校验 |
| 输入校验 | 5 | SQL注入 / XSS / 超长 / 畸形 / 路径遍历 |
| HTTP 安全 | 3 | TLS / 方法限制 / 路径遍历 |
| 并发 | 2 | 100并发 / 持续压力 |
| 日志 | 3 | 敏感信息 / 错误堆栈 / 健康检查 |
| **合计** | **27** | |

---

> 更新日期: 2026-06-25 | 修改说明: 删除 RBAC 及 upload 测试，新增 3 个透传接口测试

---

## 🔗 相关笔记

- [[Issue-785-921-联合测试方案]] — 功能测试方案（互补）
- [[issue-921-OIDC认证完整机制]] — OIDC 认证机制（安全测试基础）
- [[Issue-921-测试命令]] — curl 测试命令
- [[openUBMC RAG对外查询接口-架构设计说明书]] — 架构设计中包含安全设计清单

> 索引：[[RAG 体系]] · [[Issue 专题]] · 返回 [[首页]]
