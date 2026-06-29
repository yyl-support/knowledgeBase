# Issue #921 RAG API 测试命令

> 替换 `<域名>` 为实际地址，`<token>` 从 OIDC 授权获取

```bash
BASE="https://<域名>"
TOKEN="<access_token>"
```

---

## 获取 token

浏览器访问：
```
$BASE/api/v1/rag/auth/authorize
```
→ OneID 登录 → 授权 → 回调返回 JSON → 复制 access_token 和 refresh_token

---

## 1. 检索（POST，透传 LightRAG `/query`）

```bash
curl -s -X POST $BASE/api/v1/rag/retrieve \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "BMC 固件升级流程",
    "mode": "mix",
    "only_need_context": true,
    "only_need_prompt": false,
    "response_type": "Multiple Paragraphs",
    "top_k": 5,
    "chunk_top_k": 10,
    "max_entity_tokens": 2000,
    "max_relation_tokens": 2000,
    "max_total_tokens": 8000,
    "conversation_history": [],
    "enable_rerank": true,
    "include_references": false,
    "stream": false
  }'
```

超时时间：60s。所有参数原样转发给 LightRAG `/query`，响应原样返回。

---

## 2. 文档状态统计（GET，透传 LightRAG `/documents/status_counts`）

```bash
curl -s $BASE/api/v1/rag/documents/status_counts \
  -H "Authorization: Bearer $TOKEN"
```

无请求体，超时 30s。返回 LightRAG 原始 JSON。

---

## 3. 管道状态（GET，透传 LightRAG `/documents/pipeline_status`）

```bash
curl -s $BASE/api/v1/rag/documents/pipeline_status \
  -H "Authorization: Bearer $TOKEN"
```

无请求体，超时 30s。

---

## 4. 分页文档列表（POST，透传 LightRAG `/documents/paginated`）

```bash
curl -s -X POST $BASE/api/v1/rag/documents/paginated \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "status_filter": "COMPLETED",
    "page": 1,
    "page_size": 20,
    "sort_field": "created_at",
    "sort_direction": "desc"
  }'
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `status_filter` | string\|null | 状态过滤：PENDING / PROCESSING / COMPLETED / FAILED，null=不过滤 |
| `page` | int | 页码，默认 1 |
| `page_size` | int | 每页条数，范围 10-200 |
| `sort_field` | string | 排序字段 |
| `sort_direction` | string | asc / desc |

所有参数原样转发给 LightRAG，超时 30s。

---

## 5. 刷新 token

```bash
curl -s -X POST $BASE/api/v1/rag/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token":"<refresh_token>"}'
```

---

## 6. 错误码验证

| 场景 | 命令 | 预期 |
|------|------|------|
| 无 token | `curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/v1/rag/retrieve -H "Content-Type: application/json" -d '{"query":"test"}'` | 401 `TOKEN_MISSING` |
| 假 token | `curl -s -o /dev/null -w "%{http_code}" $BASE/api/v1/rag/documents/status_counts -H "Authorization: Bearer fake"` | 401 `TOKEN_INVALID` |
| 限流 | 连续 105 次 `documents/status_counts` → `grep '429'` | `> 0` |
