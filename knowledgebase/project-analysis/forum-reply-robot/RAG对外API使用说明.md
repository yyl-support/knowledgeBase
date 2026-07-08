---
tags:
  - issue-921
  - API文档
  - RAG
  - forum-reply-robot
issue: 921
service: forum-reply-robot
---

# openUBMC RAG 对外查询接口 — 使用说明

> 对应 Issue: [backlog#921](https://github.com/opensourceways/backlog/issues/921)
> 所属服务: forum-reply-robot

## ⚠️ 重要：这是一个纯 API 服务，没有 Web 页面

forum-reply-robot 本身是一个**后台服务**，没有可视化网站。它原本的工作是：

1. 监听社区论坛新帖
2. 调 RAG 知识库检索相关内容
3. 自动生成回复

本次 Issue #921 给它新增了一个独立的 Flask 线程（端口 5001），暴露了一组 REST API 供外部程序调用。**在浏览器直接打开这些 URL 只会看到 JSON 字符串或 401 错误**，没有任何 UI 界面。这些接口是给以下场景用的：

- **Coding Agent** 通过 `/tokenize` + `/retrieve` 了解 openUBMC 代码和文档
- **开发者** 用 curl / Python SDK 调 RAG 知识库做检索分析
- **维护者** 通过 `/knowledge/upload` 上传知识更新 RAG
- **认证授权** 流程中的 Step 1 是浏览器跳转 OneID 登录页（由 `/authorize` 302 重定向触发），其余全走代码

> 简单说：**这是被"调"的服务，不是被"看"的网站。**

---

## 一、接口地址

| 环境 | 地址 |
|------|------|
| 预览环境 | `https://work-issue-921.preview.test.osinfra.cn` |
| 正式环境 | `https://rag.openubmc.cn`（上线后） |

---

## 二、认证流程

本服务使用 **OneID OIDC 授权码模式**，无需自建账号。

### 完整流程

```
1. 用户访问 /api/v1/rag/auth/authorize → 跳转 OneID 登录/授权
2. 用户登录后 → OneID 回调 /api/v1/rag/auth/callback?code=xxx&state=xxx
3. 服务端凭 code 换取 access_token + refresh_token + id_token
4. 后续请求 Header 携带 access_token
5. access_token 过期 → 用 refresh_token 调 /refresh 换取新 token
```

### token 机制

| 项 | 值 |
|----|-----|
| access_token 有效期 | 30 分钟 |
| 刷新方式 | 调 `/api/v1/rag/auth/refresh`，传入 refresh_token |
| 用户标识来源 | 从 OIDC id_token 的 `sub` 字段解析，不自建账号 |

---

## 三、接口列表

| 方法 | 路径 | 功能 | 认证 |
|------|------|------|------|
| `GET` | `/api/v1/rag/auth/authorize` | 发起 OIDC 授权 | 否 |
| `GET` | `/api/v1/rag/auth/callback` | OneID 授权回调 | 否 |
| `POST` | `/api/v1/rag/auth/refresh` | 刷新 token | 带 refresh_token |
| `POST` | `/api/v1/rag/tokenize` | 文本分词/向量化 | 是 |
| `POST` | `/api/v1/rag/retrieve` | 知识库检索 | 是 |
| `GET` | `/api/v1/rag/health` | RAG 健康检查 | 否 |
| `POST` | `/api/v1/rag/knowledge/upload` | 知识上传（仅授权角色） | 是 |

### 公共 Header

```
Authorization: Bearer <access_token>
Content-Type: application/json
```

---

## 四、调用示例

### tokenize（文本向量化）

```bash
curl -X POST https://rag.openubmc.cn/api/v1/rag/tokenize \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{"text": "鲲鹏服务器 BMC 管理芯片的启动流程"}'
```

### retrieve（知识库检索）

```bash
curl -X POST https://rag.openubmc.cn/api/v1/rag/retrieve \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{"query": "BMC 如何配置 IPMI"}'
```

### 刷新 token

```bash
curl -X POST https://rag.openubmc.cn/api/v1/rag/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "<your_refresh_token>"}'
```

响应：

```json
{
  "access_token": "eyJ...",
  "expires_in": 1800
}
```

### 健康检查

```bash
curl https://rag.openubmc.cn/api/v1/rag/health
```

### 上传知识（仅 huawei_maintainer / robot_service）

```bash
curl -X POST https://rag.openubmc.cn/api/v1/rag/knowledge/upload \
  -H "Authorization: Bearer <access_token>"
```

---

## 五、状态码

| 状态码 | 含义 | 场景 |
|--------|------|------|
| `200` | 成功 | 正常返回 |
| `401` | 未认证 | token 缺失或无效 |
| `403` | 无权限 | 普通用户调知识上传接口 |
| `429` | 限流 | 超过 100 次/小时/用户 |
| `500` | 服务端错误 | 内部异常 |

---

## 六、限流规则

| 规则 | 值 |
|------|-----|
| 每用户每小时上限 | 100 次 |
| 超限后返回 | `429 Too Many Requests` |
| 恢复周期 | 每个自然小时窗口滚动 |

---

## 七、权限模型

| 角色 | 接口权限 |
|------|---------|
| 普通注册用户 | tokenize / retrieve / refresh / health |
| `huawei_maintainer` | 上述全部 + knowledge/upload |
| `robot_service` | 上述全部 + knowledge/upload |
| `huawei_committer` | tokenize / retrieve / refresh / health |

权限校验基于 OIDC id_token 中携带的角色 claim。

---

## 八、错误响应示例

### token 缺失

```json
{"error":"TOKEN_MISSING","message":"请先完成 OneID 认证授权"}
```

### token 过期

```json
{"error":"TOKEN_EXPIRED","message":"access_token 已过期，请使用 refresh_token 刷新"}
```

### 无权限上传

```json
{"error":"FORBIDDEN","message":"仅华为 maintainer 和机器人服务角色可上传知识"}
```

---

## 九、外部程序完整接入流程

### 前置条件

- 用户已注册 openUBMC 社区账号（认证走 OneID，RAG 不管理用户注册）
- 你的程序能打开浏览器（CLI 工具）或本身就是一个 Web 应用

### 端到端流程

```
┌─────────────────────────────────────────────────────────────────┐
│  Step 1          Step 2         Step 3          Step 4+5        │
│  发起认证         用户授权        换取 token       使用 API        │
│                                                                 │
│  你的程序         用户浏览器      RAG 服务端       你的程序        │
│  ─────────       ─────────      ──────────       ──────────      │
│  调 /authorize → 跳转 OneID → 回调 /callback →  拿到 token →    │
│                  登录+授权      用 code 换       tokenize/       │
│                                 access_token     retrieve/       │
│                                 +refresh_token   upload          │
│                                                  ↓              │
│                              token 过期 → 调 /refresh 换新的     │
└─────────────────────────────────────────────────────────────────┘
```

---

### Step 1：发起认证

让用户的浏览器访问 `/api/v1/rag/auth/authorize`，服务端会 302 重定向到 OneID 登录页：

```
GET https://rag.openubmc.cn/api/v1/rag/auth/authorize
  → 302 → https://omapi.osinfra.cn/oneid/oidc/authorize?response_type=code&client_id=...&redirect_uri=...&scope=openid+profile&state=随机串
```

**你的程序怎么做**：

- **Web 应用**：直接 `<a href="...">` 或 `window.location` 跳转
- **CLI 工具**：用 `webbrowser.open()` 或 `open` 命令打开浏览器
- **纯后端脚本**：无法完成此步骤，必须有浏览器参与

---

### Step 2：用户在 OneID 登录并授权

用户在 OneID 页面输入凭据（或已是登录态则跳过），同意授权后，OneID 将浏览器重定向回：

```
GET https://rag.openubmc.cn/api/v1/rag/auth/callback?code=AUTH_CODE&state=随机串
```

**注意**：`redirect_uri` 是 RAG 服务端写死的 `https://rag.openubmc.cn/api/v1/rag/auth/callback`，用户程序不需要处理这个回调——RAG 服务自己处理。

---

### Step 3：RAG 服务端换取 token，返回给你的程序

RAG 的 `/callback` 端点收到授权码后，在服务端调用 OneID token 接口换取令牌，然后**直接将 token 返回给浏览器**：

```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "8x7k2m...",
  "expires_in": 1800,
  "user_id": "user_abc123",
  "roles": ["community_member"]
}
```

**你的程序拿到 token 后的职责**：
- 将 `access_token` 和 `refresh_token` 安全存储在本地（如 `~/.openubmc/credentials` 或浏览器 localStorage）
- **不要**把 token 打印到日志、提交到 git
- **不要**在前端明文暴露 `refresh_token`

---

### Step 4：用 access_token 调用 RAG API

```bash
# 检索
curl -X POST https://rag.openubmc.cn/api/v1/rag/retrieve \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "鲲鹏 BMC 固件升级流程"}'

# 分词
curl -X POST https://rag.openubmc.cn/api/v1/rag/tokenize \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text": "BMC 管理芯片介绍"}'

# 上传知识（需 huawei_maintainer 角色）
curl -X POST https://rag.openubmc.cn/api/v1/rag/knowledge/upload \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@bmc_guide.pdf"
```

---

### Step 5：access_token 过期后刷新

`access_token` 有效期 30 分钟。过期后 API 返回 401，此时用 `refresh_token` 换取新的：

```bash
curl -X POST https://rag.openubmc.cn/api/v1/rag/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "'$REFRESH_TOKEN'"}'
```

响应：

```json
{
  "access_token": "eyJhbGciOi...新的token...",
  "expires_in": 1800
}
```

刷新逻辑（伪代码）：

```python
def call_rag_api(endpoint, data):
    resp = requests.post(endpoint, json=data, headers=auth_header())
    if resp.status_code == 401:
        refresh_access_token()          # 用 refresh_token 换新的
        resp = requests.post(endpoint, json=data, headers=auth_header())  # 重试
    return resp
```

---

### Step 6（可选）：上传知识

仅限 `huawei_maintainer` 或 `robot_service` 角色。普通用户调用返回 403。

```bash
curl -X POST https://rag.openubmc.cn/api/v1/rag/knowledge/upload \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@document.pdf"
```

---

### Python 完整示例

```python
import json
import os
import webbrowser
import requests

RAG_BASE = "https://rag.openubmc.cn"
CRED_FILE = os.path.expanduser("~/.openubmc/credentials")

def load_credentials():
    if os.path.exists(CRED_FILE):
        with open(CRED_FILE) as f:
            return json.load(f)
    return None

def save_credentials(creds):
    os.makedirs(os.path.dirname(CRED_FILE), exist_ok=True)
    with open(CRED_FILE, "w") as f:
        json.dump(creds, f)

def login():
    """Step 1-3: 打开浏览器完成 OIDC 认证"""
    print("正在打开浏览器完成 OneID 登录...")
    webbrowser.open(f"{RAG_BASE}/api/v1/rag/auth/authorize")

    # 实际场景中，/callback 返回的 JSON 需要你的程序捕获。
    # Web 应用用 redirect URL fragment 或后端 session 传递。
    # CLI 工具可以用本地 HTTP server 接收回调，或让用户手动粘贴。
    print("授权完成后，请粘贴回调页面显示的 JSON：")
    token_json = input("> ").strip()
    creds = json.loads(token_json)
    save_credentials(creds)
    print(f"登录成功，用户 ID: {creds.get('user_id')}")
    return creds

def get_access_token():
    creds = load_credentials()
    if creds is None:
        creds = login()

    # 简单判断：如果快过期了就刷新（生产环境应解析 JWT exp 字段）
    # 这里省略到期判断逻辑，直接尝试调用，401 后刷新
    return creds["access_token"]

def refresh_token():
    creds = load_credentials()
    resp = requests.post(f"{RAG_BASE}/api/v1/rag/auth/refresh",
                         json={"refresh_token": creds["refresh_token"]})
    if resp.status_code != 200:
        print("refresh_token 已失效，需要重新登录")
        creds = login()
        return creds["access_token"]
    new_access = resp.json()["access_token"]
    creds["access_token"] = new_access
    save_credentials(creds)
    return new_access

def call_rag(endpoint, data):
    token = get_access_token()
    resp = requests.post(f"{RAG_BASE}{endpoint}",
                         json=data,
                         headers={"Authorization": f"Bearer {token}"})
    if resp.status_code == 401:
        token = refresh_token()
        resp = requests.post(f"{RAG_BASE}{endpoint}",
                             json=data,
                             headers={"Authorization": f"Bearer {token}"})
    return resp

# 使用示例
if __name__ == "__main__":
    # 检索知识库
    result = call_rag("/api/v1/rag/retrieve",
                      {"query": "BMC watchdog 机制"})
    print(result.json())
```

---

### 注意事项

1. **token 安全**：`access_token`/`refresh_token` 等效于用户名密码，不要打印到日志、不要提交到 git、不要在 URL query string 中传递
2. **限流**：单个用户每小时 100 次，调用方应实现重试逻辑（遇到 429 等待后重试）
3. **refresh_token 失效**：如果刷新接口也返回 401，说明 refresh_token 已作废（如用户主动登出），需要重新走 Step 1 登录流程
4. **角色变更**：用户在 OneID 侧的角色变更不会立即反映到已有 access_token 中，需等 token 自然过期或主动刷新后生效
5. **这个服务不管理用户注册**：用户注册在 openUBMC 社区完成，RAG 只做认证校验

---

> 创建日期: 2026-06-16

---

## 🔗 相关笔记

- [[RAG API 测试环境联调指南]] — 联调手册（面向测试环境）
- [[Issue-921-测试命令]] — curl 测试命令速查
- [[issue-921-OIDC认证完整机制]] — OIDC 认证机制详解
- [[openUBMC RAG对外查询接口-架构设计说明书]] — 架构设计总纲

> 专题索引：[[Issue 专题]] · 返回 [[首页]]
