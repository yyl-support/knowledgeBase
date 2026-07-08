---
tags:
  - issue-921
  - 测试
  - API文档
  - RAG
  - forum-reply-robot
issue: 921
service: forum-reply-robot
---

# openUBMC RAG API 测试环境联调指南

> 基于 Issue [#921](https://github.com/opensourceways/backlog/issues/921) 最新代码。

---

## 一、前置条件（调用方准备）

| 项 | 说明 |
|----|------|
| openUBMC 社区账号 | 已注册并登录过 |
| 浏览器 | 首次 OIDC 授权必须浏览器参与 |
| HTTP 客户端 | curl / Python / 你的程序 |

## 二、前置条件（基础设施）

以下需在你联调前由基础设施侧配好：

- [ ] OneID 注册 OIDC 应用，拿到 `client_id` / `client_secret`，回调地址登记为 `https://lightrag-cn4.test.osinfra.cn/api/v1/rag/auth/callback`
- [ ] Vault config 新增段填入（用前面的 `vault-config-新增段.yaml`，填入 client_id / client_secret / redirect_uri）
- [ ] `lightrag-cn4.test.osinfra.cn` Ingress 追加路径规则：`/api/v1/rag/*` → forum-reply-robot Service
- [ ] `/ai-deploy-test` 执行，代码部署到测试集群

---

## 三、测试环境地址

```
https://lightrag-cn4.test.osinfra.cn
```

**注**：复用 LightRAG 已有域名，Ingress 按路径分流。接口路径不变：

| 接口 | 方法 | 路径 | 认证 |
|------|------|------|------|
| OIDC 授权入口 | GET | `/api/v1/rag/auth/authorize` | 否 |
| OIDC 回调 | GET | `/api/v1/rag/auth/callback` | 否 |
| 刷新 token | POST | `/api/v1/rag/auth/refresh` | refresh_token |
| 文本分词 | POST | `/api/v1/rag/tokenize` | access_token |
| 知识库检索 | POST | `/api/v1/rag/retrieve` | access_token |
| 健康检查 | GET | `/api/v1/rag/health` | 否 |
| 知识上传 | POST | `/api/v1/rag/knowledge/upload` | access_token + RBAC |

---

## 四、认证流程

### Step 1：浏览器获取 token

访问：
```
https://lightrag-cn4.test.osinfra.cn/api/v1/rag/auth/authorize
```

→ OneID 登录 → 授权 → 回调返回 JSON：

```json
{
  "access_token": "xxx",
  "refresh_token": "xxx",
  "expires_in": 1800
}
```

### Step 2：调用接口

```bash
TOKEN="<上一步的 access_token>"
BASE="https://lightrag-cn4.test.osinfra.cn"

# 检索
curl -X POST $BASE/api/v1/rag/retrieve \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "BMC 固件升级流程"}'

# 分词
curl -X POST $BASE/api/v1/rag/tokenize \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text": "鲲鹏服务器 BMC"}'

# 健康检查（无需 token）
curl $BASE/api/v1/rag/health

# 无 token 应返回 401
curl -X POST $BASE/api/v1/rag/retrieve \
  -H "Content-Type: application/json" \
  -d '{"query": "test"}'
```

### Step 3：刷新 token

```bash
curl -X POST $BASE/api/v1/rag/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "<refresh_token>"}'
```

### Step 4：知识上传（仅 huawei_maintainer / robot_service）

```bash
curl -X POST $BASE/api/v1/rag/knowledge/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@document.pdf"
```

普通用户返回 403。

---

## 五、状态码

| 状态码 | 含义 |
|--------|------|
| 200 | 成功 |
| 401 | 未认证 |
| 403 | 无权限（知识上传） |
| 429 | 超限流（100次/小时） |
| 500 | 服务端错误 |

---

## 六、注意事项

1. **首次认证必须走浏览器**，无法纯 curl 完成
2. `access_token` 30 分钟过期，用 `refresh_token` 自助续
3. 限流 100 次/小时/用户
4. 这是纯 API 服务，没有 Web 页面
5. 正式环境：`rag.openubmc.cn`（接口路径相同）

---

## 🔗 相关笔记

- [[RAG对外API使用说明]] — 接口使用说明（互补，面向接入方）
- [[Issue-921-测试命令]] — curl 测试命令
- [[issue-921-RAG对外域名全链路]] — 测试域名的网络链路
- [[issue-921-OIDC认证完整机制]] — 认证流程

> 专题索引：[[Issue 专题]] · 返回 [[首页]]
