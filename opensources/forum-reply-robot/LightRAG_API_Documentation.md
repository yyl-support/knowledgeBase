# LightRAG API 文档

> 基于 `lightrag-cn4.test.osinfra.cn` 的 OpenAPI 规范分析生成。
> 分析日期: 2026-06-25

---

## 目录

1. [认证与通用说明](#认证与通用说明)
2. [文档管理 (documents)](#文档管理-documents)
3. [查询与检索 (query)](#查询与检索-query)
4. [知识图谱 (graph)](#知识图谱-graph)
5. [系统与健康检查](#系统与健康检查)
6. [Ollama 兼容接口](#ollama-兼容接口)

---

## 认证与通用说明

### API Key 认证

大部分接口支持可选的 `api_key_header_value` query 参数进行认证。

### 通用响应格式

所有接口 JSON 响应，标准 HTTP 状态码。错误时返回:

```json
{
  "detail": [{"loc": ["field"], "msg": "error message", "type": "error_type"}]
}
```

---

## 文档管理 (documents)

### 1. GET `/documents` — 获取所有文档状态

获取按状态分组的文档列表。

**请求参数**: 无 (可选 `api_key_header_value` query)

**响应** (`DocsStatusesResponse`):

```json
{
  "statuses": {
    "<status>": [
      {
        "id": "string",
        "content_summary": "string",
        "content_length": 0,
        "status": "PENDING | PROCESSING | COMPLETED | FAILED",
        "created_at": "ISO datetime",
        "updated_at": "ISO datetime",
        "track_id": "string|null",
        "chunks_count": 0,
        "error_msg": "string|null",
        "metadata": {},
        "file_path": "string"
      }
    ]
  }
}
```

---

### 2. GET `/documents/status_counts` — 获取状态统计

获取各状态文档数量的统计。

**请求参数**: 无

**响应** (`StatusCountsResponse`):

```json
{
  "status_counts": {
    "PENDING": 10,
    "PROCESSING": 2,
    "COMPLETED": 150,
    "FAILED": 3
  }
}
```

---

### 3. POST `/documents/paginated` — 分页查询文档

分页获取文档列表，支持状态过滤和排序。

**请求体** (`DocumentsRequest`):

```json
{
  "status_filter": "COMPLETED",
  "page": 1,
  "page_size": 20,
  "sort_field": "created_at",
  "sort_direction": "desc"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `status_filter` | string \| null | 否 | 按状态过滤，null 表示不过滤 |
| `page` | integer | 否 | 页码 (1-based)，默认 1 |
| `page_size` | integer | 否 | 每页条数，范围 10-200 |
| `sort_field` | string | 否 | 排序字段 |
| `sort_direction` | string | 否 | 排序方向 `asc`/`desc` |

**响应** (`PaginatedDocsResponse`):

```json
{
  "documents": [
    {
      "id": "doc_001",
      "content_summary": "BMC firmware upgrade guide...",
      "content_length": 5000,
      "status": "COMPLETED",
      "created_at": "2025-01-01T00:00:00",
      "updated_at": "2025-01-02T00:00:00",
      "track_id": "trk_xxx",
      "chunks_count": 15,
      "error_msg": null,
      "metadata": {},
      "file_path": "/data/doc_001.txt"
    }
  ],
  "pagination": {
    "page": 1,
    "page_size": 20,
    "total_count": 150,
    "total_pages": 8,
    "has_next": true,
    "has_prev": false
  },
  "status_counts": {
    "COMPLETED": 150
  }
}
```

---

### 4. POST `/documents/upload` — 上传文档

上传文件到 LightRAG 的输入目录进行处理。

**请求** (`multipart/form-data`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file` | file | **是** | 要上传的文件 |

**响应** (`InsertResponse`):

```json
{
  "status": "success",
  "message": "File uploaded successfully",
  "track_id": "trk_abc123"
}
```

---

### 5. POST `/documents/text` — 插入文本

直接插入文本内容（无需文件）。

**请求体** (`InsertTextRequest`):

```json
{
  "text": "BMC firmware update via Redfish...",
  "file_source": "manual_input"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `text` | string | **是** | 要插入的文本内容 |
| `file_source` | string | 否 | 文本来源标识 |

**响应** (`InsertResponse`):

```json
{
  "status": "success",
  "message": "Text inserted successfully",
  "track_id": "trk_def456"
}
```

---

### 6. POST `/documents/texts` — 批量插入文本

批量插入多条文本。

**请求体** (`InsertTextsRequest`):

```json
{
  "texts": ["text one...", "text two..."],
  "file_sources": ["source1", "source2"]
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `texts` | string[] | **是** | 文本数组 |
| `file_sources` | string[] | 否 | 对应的来源标识数组 |

**响应** (`InsertResponse`):

```json
{
  "status": "success",
  "message": "Texts inserted successfully",
  "track_id": "trk_ghi789"
}
```

---

### 7. POST `/documents/scan` — 扫描新文档

扫描输入目录中的新文档并加入处理队列。

**请求参数**: 无

**响应** (`ScanResponse`):

```json
{
  "status": "scanned",
  "message": "Found 5 new documents",
  "track_id": "trk_scan001"
}
```

---

### 8. DELETE `/documents` — 清空所有文档

删除全部文档及其关联数据。

**请求参数**: 无

**响应** (`ClearDocumentsResponse`):

```json
{
  "status": "success",
  "message": "All documents cleared"
}
```

---

### 9. DELETE `/documents/delete_document` — 删除指定文档

根据文档 ID 删除文档及其关联数据。

**请求体** (`DeleteDocRequest`):

```json
{
  "doc_ids": ["doc_001", "doc_002"],
  "delete_file": false
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `doc_ids` | string[] | **是** | 要删除的文档 ID 列表 |
| `delete_file` | boolean | 否 | 是否同时删除上传目录中的文件 |

**响应** (`DeleteDocByIdResponse`):

```json
{
  "status": "success",
  "message": "Documents deleted",
  "doc_id": "doc_001"
}
```

---

### 10. DELETE `/documents/delete_entity` — 删除实体

从知识图谱中删除指定实体。

**请求体** (`DeleteEntityRequest`):

```json
{
  "entity_name": "BMC_Firmware"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `entity_name` | string | **是** | 实体名称 |

**响应** (`DeletionResult`):

```json
{
  "status": "success",
  "doc_id": "doc_001",
  "message": "Entity deleted",
  "status_code": 200,
  "file_path": null
}
```

---

### 11. DELETE `/documents/delete_relation` — 删除关系

从知识图谱中删除两个实体间的关系。

**请求体** (`DeleteRelationRequest`):

```json
{
  "source_entity": "BMC_Firmware",
  "target_entity": "Redfish_UpdateService"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `source_entity` | string | **是** | 源实体名称 |
| `target_entity` | string | **是** | 目标实体名称 |

**响应** (`DeletionResult`): 同上。

---

### 12. GET `/documents/track_status/{track_id}` — 查询跟踪状态

根据 track_id 查询文档处理进度。

**路径参数**:

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `track_id` | string | **是** | 上传/扫描时返回的 tracking ID |

**响应** (`TrackStatusResponse`):

```json
{
  "track_id": "trk_abc123",
  "documents": [
    {
      "id": "doc_001",
      "content_summary": "...",
      "status": "COMPLETED",
      "chunks_count": 15,
      "file_path": "/data/file.txt"
    }
  ],
  "total_count": 1,
  "status_summary": {
    "COMPLETED": 1
  }
}
```

---

### 13. GET `/documents/pipeline_status` — 管道状态

获取文档处理管道的当前状态。

**请求参数**: 无

**响应** (`PipelineStatusResponse`):

```json
{
  "autoscanned": false,
  "busy": false,
  "job_name": "default",
  "job_start": "2025-01-01T00:00:00",
  "docs": 100,
  "batchs": 10,
  "cur_batch": 5,
  "request_pending": false,
  "latest_message": "Processing batch 5/10",
  "history_messages": null,
  "update_status": null
}
```

| 字段 | 说明 |
|------|------|
| `autoscanned` | 是否自动扫描模式 |
| `busy` | 管道是否忙碌 (正在处理) |
| `docs` | 待处理文档总数 |
| `batchs` | 批次数 |
| `cur_batch` | 当前处理批次 |

---

### 14. POST `/documents/clear_cache` — 清空缓存

清空系统缓存。

**请求体** (`ClearCacheRequest`): 空对象 `{}`

**响应** (`ClearCacheResponse`):

```json
{
  "status": "success",
  "message": "Cache cleared"
}
```

---

## 查询与检索 (query)

### 15. POST `/query` — 执行查询

执行 RAG 查询，返回 LLM 生成的回答。

**请求体** (`QueryRequest`):

```json
{
  "query": "如何配置BMC网络？",
  "mode": "mix",
  "only_need_context": false,
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
}
```

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `query` | string | **是** | — | 查询文本 |
| `mode` | string | 否 | — | 查询模式 (`local`/`global`/`mix`/`naive`) |
| `only_need_context` | boolean | 否 | false | 仅返回检索上下文，不生成回答 |
| `only_need_prompt` | boolean | 否 | false | 仅返回生成的 prompt，不生成回答 |
| `response_type` | string | 否 | — | 回答格式: `Multiple Paragraphs`, `Single Paragraph`, `Bullet Points` |
| `top_k` | integer | 否 | — | 检索数量: local模式=实体数, global模式=关系数 |
| `chunk_top_k` | integer | 否 | — | 向量检索初始召回+rerank后保留的文本块数 |
| `max_entity_tokens` | integer | 否 | — | 实体上下文的最大 token 数 |
| `max_relation_tokens` | integer | 否 | — | 关系上下文的最大 token 数 |
| `max_total_tokens` | integer | 否 | — | 总 token 预算 (实体+关系+chunks+system prompt) |
| `conversation_history` | array | 否 | [] | 对话历史 `[{"role":"user/assistant","content":"..."}]` |
| `enable_rerank` | boolean | 否 | true | 是否启用 rerank |
| `include_references` | boolean | 否 | false | 是否在回答中包含引用列表 |
| `stream` | boolean | 否 | false | 流式输出 (不影响 `/query` 端点) |

**响应** (`QueryResponse`):

```json
{
  "response": "BMC网络配置可通过以下步骤完成...",
  "references": null
}
```

> **注意**: `/query` 的 `QueryResponse` 仅包含 `response` 和 `references`，**不包含** `context.chunks`。原始检索数据需通过 `/query/data` 获取。

---

### 16. POST `/query/data` — 查询原始数据

执行查询并返回完整的检索数据（实体、关系、chunks、引用），**不生成 LLM 回答**。

**请求体**: 同 `QueryRequest`

**响应** (`QueryDataResponse`):

```json
{
  "status": "success",
  "message": "Query completed",
  "data": {
    "entities": [...],
    "relationships": [...],
    "chunks": [
      {
        "content": "BMC firmware can be updated via...",
        "file_path": "redfish_guide.md_topic_123.json",
        "score": 0.92
      }
    ],
    "references": [...]
  },
  "metadata": {
    "mode": "mix",
    "keywords": ["BMC", "Redfish", "Update"],
    "query_time": 1.5
  }
}
```

> **重要**: 内部链路 (`forum_client.py`) 调用的检索接口正是 `/query/data`，读取结构为 `response['data']['chunks']`。

---

### 17. POST `/query/stream` — 流式查询

与 `/query` 功能相同但以 SSE (Server-Sent Events) 流式返回回答。

**请求体**: 同 `QueryRequest`（`stream` 参数应设为 `true`）。

**响应**: SSE 流，逐 chunk 返回 `{response: "..."}` 片段。

---

## 知识图谱 (graph)

### 18. GET `/graphs` — 获取知识图谱

获取指定标签下的知识图谱数据。

**Query 参数**:

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `label` | string | **是** | 图谱标签 |
| `max_depth` | integer | 否 | 最大深度 |
| `max_nodes` | integer | 否 | 最大节点数 |

**响应**: 包含 ECharts 格式的图谱 JSON 数据。

---

### 19. GET `/graph/label/list` — 获取所有标签

返回知识图谱中的所有标签列表。

**请求参数**: 无

---

### 20. GET `/graph/label/popular` — 获取热门标签

获取最常用的图谱标签。

**Query 参数**:

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | integer | 否 | 返回数量限制 |

---

### 21. GET `/graph/label/search` — 搜索标签

按关键词搜索标签。

**Query 参数**:

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `q` | string | **是** | 搜索关键词 |
| `limit` | integer | 否 | 返回数量限制 |

---

### 22. GET `/graph/entity/exists` — 检查实体存在

检查指定实体是否存在于知识图谱中。

**Query 参数**:

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | **是** | 实体名称 |

---

### 23. POST `/graph/entity/edit` — 编辑实体

更新知识图谱中的实体。

**请求体** (`EntityUpdateRequest`):

```json
{
  "entity_name": "BMC_Controller",
  "updated_data": {
    "description": "Updated description..."
  },
  "allow_rename": false
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `entity_name` | string | **是** | 实体名称 |
| `updated_data` | object | **是** | 更新的数据 |
| `allow_rename` | boolean | 否 | 是否允许重命名 |

---

### 24. POST `/graph/relation/edit` — 编辑关系

更新知识图谱中的关系。

**请求体** (`RelationUpdateRequest`):

```json
{
  "source_id": "BMC_Firmware",
  "target_id": "UpdateService",
  "updated_data": {
    "description": "firmware update relationship"
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `source_id` | string | **是** | 源实体 ID |
| `target_id` | string | **是** | 目标实体 ID |
| `updated_data` | object | **是** | 更新的数据 |

---

## 系统与健康检查

### 25. GET `/health` — 健康检查

服务健康状态检查。

**请求参数**: 无

**响应**: 返回服务运行状态信息。

---

### 26. GET `/**` — 重定向到 WebUI

根路径自动重定向到 `/webui/`。

---

### 27. GET `/auth-status` — 认证状态

获取当前认证状态。

---

### 28. POST `/login` — 登录

表单登录认证。

**请求体** (`application/x-www-form-urlencoded`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `username` | string | **是** | 用户名 |
| `password` | string | **是** | 密码 |
| `grant_type` | string | 否 | 授权类型 |
| `scope` | string | 否 | 权限范围 |
| `client_id` | string | 否 | 客户端 ID |
| `client_secret` | string | 否 | 客户端密钥 |

---

## Ollama 兼容接口

LightRAG 服务包含部分 Ollama API 兼容接口。

### 29. GET `/api/version` — 获取版本

### 30. GET `/api/tags` — 获取模型标签

### 31. GET `/api/ps` — 获取运行中的模型

### 32. POST `/api/generate` — 生成 (Ollama)

### 33. POST `/api/chat` — 对话 (Ollama)

---

## 关键接口对照：LightRAG vs forum-reply-robot RAG API

| LightRAG 原生 | forum-reply-robot (rag_api.py) | 差异 |
|---|---|---|
| `POST /query` | `POST /api/v1/rag/retrieve` | RAG API 返回标准化的 `{results, total}` |
| `POST /query/data` | (内部 `forum_client.py` 使用) | 返回 `data.chunks`，包含完整检索数据 |
| `POST /tokenize` (LightRAG) | `POST /api/v1/rag/tokenize` | 路径不同，RAG API 加了认证 |
| `POST /documents/upload` | `POST /api/v1/rag/knowledge/upload` | RAG API 加了 OIDC + RBAC |
| `GET /health` | `GET /health` | 相同 |
| — | `POST /api/v1/rag/auth/authorize` | RAG API 独有 OIDC 认证 |
| — | `POST /api/v1/rag/auth/refresh` | RAG API 独有 Token 刷新 |

---

## `/query` vs `/query/data` 响应结构差异

这是理解 `rag_api.py` 当前问题最关键的对照：

### `/query` 返回 (`QueryResponse`)

```json
{
  "response": "LLM生成的回答文本..."
}
```

**仅包含生成的回答文本，不包含 chunks/entities/relationships 等原始检索数据。**

### `/query/data` 返回 (`QueryDataResponse`)

```json
{
  "status": "success",
  "message": "Query completed",
  "data": {
    "entities": [...],
    "relationships": [...],
    "chunks": [
      {"content": "...", "file_path": "...", "score": 0.95}
    ]
  },
  "metadata": {...}
}
```

**包含完整的检索数据，从 `data.chunks` 路径访问，这正是 `forum_client.py` 内部使用的路径。**

> **当前 `rag_api.py` 的问题**: `retrieve()` 方法调 `/query` 并从 `response['context']['chunks']` 取数据——但这个路径在 LightRAG 的 `/query` 响应中**根本不存在**。`/query` 不返回 `context` 字段。应改为调 `/query/data` 并从 `response['data']['chunks']` 取数据。
