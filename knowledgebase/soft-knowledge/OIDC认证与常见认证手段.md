---
tags:
  - 认证
  - OIDC
  - OAuth
  - JWT
  - 知识
---

# OIDC 认证与常见认证手段

---

## 一、什么是 OIDC

**OpenID Connect (OIDC)** 是建立在 OAuth 2.0 之上的**身份认证层**，解决了一个核心问题：**"我是谁？"**（而 OAuth 2.0 本身只解决"我能访问什么资源？"）。

### 核心概念

```
OAuth 2.0 = 授权框架（能干什么）
OIDC       = OAuth 2.0 + 身份层（你是谁）
```

OIDC 在 OAuth 2.0 的标准流程中额外返回一个 `id_token`（JWT 格式），里面携带了用户的身份信息。

### 核心角色

| 角色 | 说明 | 示例 |
|------|------|------|
| **End-User** | 最终用户 | 浏览器上登录的人 |
| **Relying Party (RP)** | 依赖方/客户端 | 你的应用（forum-reply-robot 的 RAG API） |
| **OpenID Provider (OP)** | 身份提供方 | OneID、Google、GitHub、微信 |
| **Id Token** | JWT 格式的身份令牌 | 包含 `sub`（用户唯一标识）、`name`、`email` 等 |
| **Access Token** | OAuth 2.0 访问令牌 | 用于调用受保护资源 |
| **Refresh Token** | 刷新令牌 | 用于在 access_token 过期后获取新的 |

---

## 二、OIDC 授权码模式（Authorization Code Flow）详解

这就是 Issue #921 中 RAG API 使用的流程。

```
## 步骤 1：用户触发登录
用户点击"登录" → RAG 服务重定向到 OneID 授权页面
GET https://omapi.osinfra.cn/oneid/oidc/authorize?
    response_type=code
    &client_id=xxx
    &redirect_uri=https://rag.openubmc.cn/api/v1/rag/auth/callback
    &scope=openid+profile
    &state=随机字符串（防 CSRF）

## 步骤 2：用户授权
用户输入凭据（或已登录态）→ 同意授权

## 步骤 3：OneID 回调，返回授权码
OneID 重定向回 RAG 服务：
GET https://rag.openubmc.cn/api/v1/rag/auth/callback?code=AUTH_CODE&state=xxx

## 步骤 4：用授权码换 token
RAG 服务 后端 凭授权码向 OneID 换 token：
POST https://omapi.osinfra.cn/oneid/oidc/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&code=AUTH_CODE
&client_id=xxx
&client_secret=xxx        ← 后端秘密，绝不暴露给前端
&redirect_uri=https://rag.openubmc.cn/api/v1/rag/auth/callback

## 步骤 5：OneID 返回 token
{
  "access_token":  "eyJhbGci...",    // 有效期 30 分钟
  "refresh_token": "xxxxx",           // 长期有效
  "id_token":      "eyJhbGci...",    // JWT，包含用户身份
  "expires_in":    1800
}

## 步骤 6：RAG 服务校验 id_token
解码 id_token (JWT) → 提取 sub（用户唯一标识）→ 完成登录

## 步骤 7：后续 API 调用
用户携带 access_token 调 RAG API → 后端验证 token → 返回结果
```

### 关键安全点

1. **授权码仅一次有效**，用完即废
2. **client_secret 只在后端使用**，绝不出现在前端代码
3. **state 参数**防 CSRF：回调时校验 state 是否与发起时一致
4. **redirect_uri 精确匹配**：防止授权码被重定向到恶意站点
5. **PKCE 增强**（可选）：移动端/SPA 推荐使用，防授权码拦截

---

## 三、常见认证手段对比

### 总览

| 认证方式 | 适用场景 | 安全性 | 实现复杂度 | 用户体验 |
|---------|---------|--------|-----------|---------|
| **OIDC** | 现代 Web/移动应用，SSO | ⭐⭐⭐⭐⭐ | 中 | ⭐⭐⭐⭐⭐ |
| **OAuth 2.0** | 第三方授权（如"用GitHub登录"） | ⭐⭐⭐⭐ | 中 | ⭐⭐⭐⭐ |
| **JWT** | 无状态 API、微服务间 | ⭐⭐⭐⭐ | 低 | ⭐⭐⭐ |
| **Session/Cookie** | 传统 Web 应用 | ⭐⭐⭐ | 低 | ⭐⭐⭐⭐ |
| **Basic Auth** | 简单 API、内部工具 | ⭐⭐ | 极低 | ⭐ |
| **API Key** | 机器间通信 | ⭐⭐⭐ | 极低 | ⭐⭐⭐⭐ |
| **SAML** | 企业 SSO | ⭐⭐⭐⭐⭐ | 高 | ⭐⭐⭐ |
| **mTLS** | 服务网格、零信任 | ⭐⭐⭐⭐⭐ | 高 | ⭐⭐⭐ |
| **WebAuthn/Passkey** | 无密码登录 | ⭐⭐⭐⭐⭐ | 中 | ⭐⭐⭐⭐⭐ |
| **LDAP** | 企业内部系统 | ⭐⭐⭐ | 中 | ⭐⭐ |

---

### 3.1 OIDC（OpenID Connect）

**一句话**：基于 OAuth 2.0 的身份认证协议。

**适用**：需要"知道用户是谁"的场景，如社区登录、SSO。

**优点**：
- 标准化，几乎所有大厂提供支持（Google、Apple、微信）
- id_token 是 JWT，自包含用户信息
- 支持 SSO（单点登录）
- 支持 refresh_token 机制，长期会话

**缺点**：
- 需要用户交互（浏览器跳转）
- 依赖 OP（Identity Provider）可用性

---

### 3.2 OAuth 2.0

**一句话**：授权协议，让第三方应用在用户授权下访问资源。

**与 OIDC 的核心区别**：OAuth 2.0 告诉你"能做什么"，OIDC 额外告诉你"你是谁"。

**四钟授权模式**：

| 模式 | 适用场景 | 安全性 |
|------|---------|--------|
| 授权码模式 (Authorization Code) | 有后端服务的 Web 应用 | ⭐⭐⭐⭐⭐ |
| 简化模式 (Implicit) | **已废弃**，不推荐 | ⭐ |
| 密码模式 (Resource Owner Password) | **已废弃**，不推荐 | ⭐ |
| 客户端模式 (Client Credentials) | 机器间通信 | ⭐⭐⭐⭐ |

---

### 3.3 JWT（JSON Web Token）

**一句话**：自包含的 token 格式，不依赖服务端存储状态。

**结构**：`Header.Payload.Signature`

```json
// Header
{ "alg": "RS256", "typ": "JWT" }

// Payload
{
  "sub": "user_12345",
  "name": "张三",
  "iat": 1680000000,
  "exp": 1680003600
}
```

**适用**：无状态 API、微服务间认证、OIDC 的 id_token。

**优点**：
- 服务端无需存储 session，水平扩展友好
- 自包含用户信息（claims）
- 可跨域、跨服务传递

**缺点**：
- Token 体积较大（~1KB+）
- 一旦签发无法撤销（除非加入黑名单机制）
- 密钥泄露则全部 token 可伪造

**关键实践**：
- 用 RS256（非对称，推荐）而非 HS256（对称）
- 设置合理的过期时间（如 15-30 分钟）
- 配合 refresh_token 使用
- 不要在 jwt payload 放敏感数据（payload 仅 base64 编码，非加密）

---

### 3.4 Session / Cookie

**一句话**：服务端维护登录状态，客户端持有 session_id cookie。

**流程**：
```
用户登录 → 服务端创建 session → 返回 Set-Cookie: session_id=xxx
后续请求 → 浏览器自动带 Cookie → 服务端查 session 表验证
```

**适用**：传统服务端渲染 Web 应用。

**优点**：简单易懂，可随时在服务端撤销 session。

**缺点**：
- 服务端需要存储 session（DB/Redis），水平扩展需要 session 共享
- 不支持移动端原生 app
- CSRF 风险（需要额外防护）

**与 JWT 的选择**：
- 服务端渲染 → Session
- Web API / SPA → JWT

---

### 3.5 Basic Auth

**一句话**：HTTP 头里放 `username:password` 的 Base64 编码。

```
Authorization: Basic dXNlcm5hbWU6cGFzc3dvcmQ=
                         ↓ Base64 decode
                     username:password
```

**适用**：内部工具、调试、简单 API。

**缺点**：
- **必须配 HTTPS**，否则明文泄露
- 无过期机制，无法撤销
- 无多因素认证支持

**不推荐用于生产用户系统。**

---

### 3.6 API Key

**一句话**：预先发放的固定字符串 key。

```
Authorization: Bearer sk-xxxxx
# 或
X-API-Key: sk-xxxxx
```

**适用**：机器间通信（如 webhook、SDK 调用、OpenAI API）。

**优点**：极简实现，无状态。

**缺点**：
- 无用户身份概念（key 是谁的——需要额外映射）
- 泄露则他人可无限使用
- 无过期机制（需额外实现轮换）

---

### 3.7 SAML（Security Assertion Markup Language）

**一句话**：企业级 SSO 协议，XML 格式，比 OIDC 更重但更成熟。

**与 OIDC 对比**：

| 维度 | SAML | OIDC |
|------|------|------|
| 格式 | XML | JSON |
| 年代 | 2005 | 2014 |
| 复杂度 | 高 | 中 |
| 移动端支持 | 差 | 原生支持 |
| 企业市场 | 统治地位 | 快速增长 |

**适用**：企业 SSO（如 Okta、Azure AD、OneLogin）。

---

### 3.8 mTLS（双向 TLS）

**一句话**：客户端和服务端都出示证书互相验证。

```
普通 TLS：浏览器验证服务器证书
mTLS：  服务器也验证客户端证书
```

**适用**：服务网格（如 Istio）、零信任架构、金融 API。

**优点**：不依赖 token，工作在传输层，极难伪造。

**缺点**：证书管理复杂，不适合 C 端用户场景。

---

### 3.9 WebAuthn / Passkey

**一句话**：基于公钥密码学的无密码认证。

**流程**：
```
用户注册 → 设备生成公私钥对 → 公钥存服务端，私钥存设备（Touch ID/Face ID/Windows Hello/YubiKey）
登录 → 服务端发 challenge → 设备用私钥签名 → 服务端公钥验证
```

**适用**：消除密码的新一代认证。

**优点**：
- 防钓鱼（域名绑定，假网站无法通过）
- 无密码泄露风险
- 生物识别体验好

**缺点**：需要用户设备支持，老系统兼容性差。

---

### 3.10 LDAP（Lightweight Directory Access Protocol）

**一句话**：企业内部目录服务协议，查用户名密码。

**适用**：企业内部系统（如公司邮箱登录、VPN）。

**缺点**：协议古老，无现代 Web 标准集成，正在被 OIDC/SAML 替代。

---

## 四、如何选型

```
你的应用是面向 C 端用户？
  ├── 是 → OIDC（对接微信/Google/GitHub 等）
  └── 否 → 企业内部？
            ├── 是 → SAML 或 LDAP（公司已有基础设施）
            └── 否 → 机器间通信？
                      ├── 是 → mTLS 或 API Key
                      └── 否 → 无状态 API → JWT + refresh_token
```

### Issue #921 的场景

RAG API 对外提供查询接口，面向社区注册用户：
- **选型**: OIDC 授权码模式（对接 OneID）
- **短期会话**: access_token 30 分钟
- **长期会话**: refresh_token + 服务端主动刷新
- **身份标识**: 从 OIDC id_token 的 `sub` 字段提取，不使用自建账号体系

---

## 五、OIDC 常见安全风险

| 风险 | 说明 | 防护 |
|------|------|------|
| **授权码拦截** | 恶意应用窃取回调 URL 中的 code | PKCE + 严格 redirect_uri 白名单 |
| **CSRF** | 攻击者构造恶意链接，绑定自己的身份到受害者 | state 参数 + SameSite Cookie |
| **JWT 伪造** | id_token 签名被破解 | 服务端验证签名 + 用 RS256 而非 HS256 |
| **Token 泄露** | access_token 在前端/日志中泄露 | 仅后端持有，不丢给前端；HTTPS 全程 |
| **重放攻击** | 截获 token 后重复使用 | Token 短有效期 + nonce 参数 |
| **redirect_uri 不精确** | 通配符 redirect_uri 被利用 | 精确匹配，不用通配符 |
| **混合 Token 响应** | 返回 code+id_token+access_token 到前端 | 仅 Authorization Code Flow，不混合返回 |

---

> 创建时间：2026-06-16

---

## 🔗 相关笔记

- [[issue-921-OIDC认证完整机制]] — OIDC 在 RAG API 的实战实现

> 索引：[[认证与安全]] · 返回 [[首页]]
