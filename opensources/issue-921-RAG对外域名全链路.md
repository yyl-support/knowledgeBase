---
tags:
  - issue-921
  - 部署
  - 网络
  - RAG
  - forum-reply-robot
issue: 921
service: forum-reply-robot
---

# issue-921 RAG 对外域名全链路解析

> 关联：issue-921「openUBMC社区RAG支持对外查询接口」
> 
> 测试域名：`lightrag.test.osinfra.cn`
> TLS 证书：复用 `discourse-tls`（`*.test.osinfra.cn` 通配证书）

---

## 一、背景

issue-921 在 `forum-reply-robot`（部署在 k8s 时叫 `forum-robot`）中实现了 RAG API（`/api/v1/rag/*`），跑在 **5000 端口**。代码实现后，需要在 k8s 中打通外部访问通道——让用户通过域名 `https://lightrag.test.osinfra.cn` 能调用这些接口。

这项改动涉及三层：**代码层**（已有）、**chart 模板层**（helm-charts）、**取值层**（helm-chart-value）。

---

## 二、三层角色关系

```
forum-reply-robot (代码)
  │  main.py → :5000 提供 /api/v1/rag/*、/health
  │  external_api.enabled: true, host: 0.0.0.0, port: 5000
  │  构建为镜像: swr.../opensourceway/forum-robot
  ▼
helm-charts/charts/discourse/templates/ (模板 — "怎么部署")
  │  robot.yaml        → Deployment (容器 forum-robot, 端口 5000)
  │  robot-service.yaml → Service   (ClusterIP, 映射 pod:5000)
  │  robot-ingress.yaml → Ingress   (nginx, TLS 终止, 域名路由到 Service:5000)
  │  service.yaml      → web-server Service (8080, 论坛网站)
  │  ingress.yaml      → web-server Ingress  (论坛域名路由到 8080)
  │  secret.yaml       → SecretDefinition  (从 Vault 拉 TLS 证书创建 k8s Secret)
  ▼
helm-chart-value/openeuler/discourse/test/values.yaml (取值 — "部署成什么样")
  │  robot: { enabled, image, podLabels, service, ingress }
  │  ingress.host: lightrag.test.osinfra.cn
  │  ingress.secretName: discourse-tls  (复用通配证书)
  │  tlsDefinition: discourse-tls  (从 Vault 拉证书)
```

**关键区分**：
- `openeuler/robot/` chart（`helm-chart-value/openeuler/robot/test/`）部署的是 hook-delivery、access、assign、cla 等十几个 GitHub/GitCode 微服务机器人——**不是 forum-reply-robot**
- forum-reply-robot 由 `discourse` chart 的 `robot:` 段部署，镜像名 `forum-robot`，podLabels `app: forum-robot`

---

## 三、全链路流程（从浏览器到 Pod）

### 3.1 链路图

```
用户浏览器
  │  https://lightrag.test.osinfra.cn/api/v1/rag/retrieve
  │
  ▼ 步骤 1: DNS 解析
┌──────────────────────────────┐
│ DNS (华为云云解析/外部 DNS)     │
│ lightrag.test.osinfra.cn     │
│   → A 记录 → ELB 公网 IP       │
│                                │
│ discourse.test.osinfra.cn    │  ← 两条域名解析到**同一个 IP**
│   → A 记录 → 同一个 IP          │    分流靠 Host 头，不靠 IP
└──────────────────────────────┘
  │
  ▼ 步骤 2: ELB 负载均衡
┌──────────────────────────────┐
│ ELB (华为云负载均衡器)          │
│   - 提供固定公网/内网入口 IP     │
│   - 分发流量到健康的 Ingress Pod │
│   - Ingress Pod 漂移/扩缩容     │
│     不影响外部访问              │
└──────────────────────────────┘
  │
  ▼ 步骤 3: nginx Ingress Controller
┌──────────────────────────────────────┐
│ nginx Ingress Controller (集群内)      │
│                                        │
│ ① TLS 终止                            │
│    从 k8s Secret: discourse-tls       │
│    (由 SecretDefinition 从 Vault      │
│     自动拉取证书)                      │
│    HTTPS → HTTP 解密后转发给 Pod       │
│                                        │
│ ② Host 头路由                         │
│    Host: discourse.test.osinfra.cn    │
│      → web-server Service :8080       │
│    Host: lightrag.test.osinfra.cn     │
│      → web-server-robot Service :5000 │
│                                        │
│ ③ 附加能力                            │
│    proxy-body-size: 20m (上传文件)     │
│    limit-rpm: 限流                    │
└──────────────────────────────────────┘
  │
  ▼ 步骤 4: k8s Service
┌──────────────────────────────────┐
│ Service: web-server-robot        │
│   type: ClusterIP                │
│   port: 5000 → targetPort: 5000  │
│   selector: app: forum-robot     │  ← 通过 label 找到 Pod
└──────────────────────────────────┘
  │
  ▼ 步骤 5: Pod
┌────────────────────────────┐
│ Pod: forum-robot           │
│   container: forum-robot   │
│   5000 端口                 │
│   ├── GET  /health         │
│   ├── POST /api/v1/rag/retrieve
│   ├── POST /api/v1/rag/tokenize
│   ├── POST /api/v1/rag/knowledge/upload
│   ├── GET  /api/v1/rag/auth/authorize
│   ├── GET  /api/v1/rag/auth/callback
│   └── POST /api/v1/rag/auth/refresh
└────────────────────────────┘
```

### 3.2 为什么两个域名可以解析到同一个 IP

Ingress 的域名路由机制：同一个 IP 可以服务无限个域名。当请求到达 nginx Ingress 时，携带了 HTTP 请求头 `Host: xxx`，nginx 根据这个 Host 字段匹配 Ingress 规则中定义的 `host`，转发到对应的后端 Service。

```
请求: https://lightrag.test.osinfra.cn/health
  → Host 头: lightrag.test.osinfra.cn
  → 匹配 robot-ingress.yaml 的 host: lightrag.test.osinfra.cn
  → 转发到 web-server-robot:5000

请求: https://discourse.test.osinfra.cn/
  → Host 头: discourse.test.osinfra.cn
  → 匹配 ingress.yaml 的 host: discourse.test.osinfra.cn
  → 转发到 web-server:8080
```

DNS 只管"域名 → IP 是哪"，不管"到了之后去哪个服务"。后者是 Ingress 的职责。

### 3.3 DNS 和 Ingress 的分工

| DNS | Ingress |
|-----|---------|
| 域名 → IP 地址 | IP 到了之后 → 哪个 Service |
| 一次解析，全程不变 | 每个请求都看 Host 头分流 |
| 管入口在哪 | 管进门后去哪 |

### 3.4 ELB 的角色

没有 ELB：DNS → Ingress Pod IP，Pod 挂了/漂移了 IP 就变，DNS 更新有延迟。

有 ELB：DNS → 固定的 ELB IP → ELB 自动发现健康的 Ingress Pod 转发。Pod 扩缩容、重启都无缝。

---

## 四、TLS 证书流程

### 4.1 从 Vault 到 k8s Secret

```
HashiCorp Vault
  secrets/data/infra-test/domain-tls
    ├── tls.cert   (证书)
    ├── tls.key    (私钥)
    └── tls.cert   (CA)

        │  secrets-manager operator 自动同步
        ▼

k8s Secret: discourse-tls (namespace: discourse)
  ├── ca.crt
  ├── tls.crt
  └── tls.key

        │  Ingress 引用: secretName: discourse-tls
        ▼

nginx Ingress Controller (TLS 终止)
```

### 4.2 为什么可以复用 `discourse-tls`

当前方案复用 `discourse-tls`，因为：
1. `discourse-tls` 现有证书是 `*.test.osinfra.cn` 通配证书
2. `lightrag.test.osinfra.cn` 匹配通配规则
3. 不需要单独签发证书，不用改 Vault 配置

如果将来需要独立证书（例如不支持通配），则需要：
1. 在 Vault 中写入 `lightrag.test.osinfra.cn` 的证书
2. 在 values.yaml 中新增 `tlsDefinition` 指向新 Vault path
3. 修改 `robot.ingress.secretName` 为新 Secret 名

---

## 五、部署生效流程

### 5.1 涉及的代码仓库

| 仓库 | 改动文件 | 说明 |
|------|---------|------|
| `helm-charts` | `charts/discourse/templates/robot-service.yaml` | 新增，创建 robot Service |
| `helm-charts` | `charts/discourse/templates/robot-ingress.yaml` | 新增，创建 robot Ingress |
| `helm-chart-value` | `openeuler/discourse/test/values.yaml` | 修改，robot.service + robot.ingress 段 + 域名 |

### 5.2 生效步骤

```
┌─ 步骤 1 ───────────────────────────────┐
│ 推代码到 helm-charts repo                │
│ (robot-service.yaml, robot-ingress.yaml) │
└───────────────────────────────────────┬─┘
                                        │ ArgoCD 自动同步
                                        ▼
┌─ 步骤 2 ───────────────────────────────┐
│ 推代码到 helm-chart-value repo          │
│ (openeuler/discourse/test/values.yaml)  │
└───────────────────────────────────────┬─┘
                                        │ ArgoCD 自动同步
                                        ▼
┌─ 步骤 3 ───────────────────────────────┐
│ 配 DNS                                   │
│ lightrag.test.osinfra.cn → ELB IP       │
│ (华为云 DNS / 运维操作)                   │
└───────────────────────────────────────┬─┘
                                        │
                                        ▼
                  ┌──────────┐
                  │  完成！   │
                  │ https://  │
                  │ lightrag  │
                  │ .test.    │
                  │ osinfra.cn│
                  └──────────┘
```

### 5.3 部署前验证（集群内）

DNS 配好之前，可以在集群内直接验证 Service 和 Pod 是否正常：

```bash
# 端口转发到本地
kubectl port-forward -n discourse deploy/web-server-robot 5000:5000

# 验证健康检查
curl http://localhost:5000/health

# 验证 RAG 接口
curl -X POST http://localhost:5000/api/v1/rag/retrieve \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"query": "test"}'
```

### 5.4 部署后验证（外部）

```bash
# 健康检查
curl https://lightrag.test.osinfra.cn/health

# 验证 RAG 接口
curl -X POST https://lightrag.test.osinfra.cn/api/v1/rag/retrieve \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"query": "test"}'
```

---

## 六、常见问题排查

### Q: DNS 解析不到
```bash
nslookup lightrag.test.osinfra.cn
```
对比 `discourse.test.osinfra.cn` 的解析结果，应该指向同一个 IP。

### Q: TLS 证书错误
```bash
curl -v https://lightrag.test.osinfra.cn/health 2>&1 | grep -i "cert\|tls\|ssl"
```
检查 `kubectl get secret discourse-tls -n discourse` 是否存在、证书是否过期。

### Q: 502 Bad Gateway
Service 找不到 Pod：检查 `kubectl get pods -n discourse -l app=forum-robot` 和 `kubectl get svc -n discourse web-server-robot`，确认 selector 匹配。

### Q: 只能内网访问
检查 Ingress 是否创建成功：
```bash
kubectl get ingress -n discourse forum-robot-rag-ingress
```
确认 `ADDRESS` 列有 IP，`HOSTS` 列包含 `lightrag.test.osinfra.cn`。

---

## 七、涉及的文件索引

| 文件 | 关键内容 | 行号 |
|------|---------|------|
| `helm-charts/charts/discourse/templates/robot.yaml` | Deployment，容器 forum-robot，端口 5000 /health 探针 | 29, 41-54 |
| `helm-charts/charts/discourse/templates/robot-service.yaml` | Service，映射 forum-robot:5000 | 全文 |
| `helm-charts/charts/discourse/templates/robot-ingress.yaml` | Ingress，nginx，TLS，域名 → Service:5000 | 全文 |
| `helm-charts/charts/discourse/templates/secret.yaml` | SecretDefinition，从 Vault 拉证书 | 全文 |
| `helm-chart-value/openeuler/discourse/test/values.yaml` | robot 段，域名 `lightrag.test.osinfra.cn`，TLS `discourse-tls` | 203-271 |
| `forum-reply-robot/config.yaml` | redirect_uri，retrieval.base_url，external_api 配置 | 53, 180, 193-197 |
| `Issue-921-测试命令.md` | RAG API 测试命令（已统一为 `lightrag.test.osinfra.cn`） | 全文 |
| `issue-921-RAG对外域名开放方案.md` | 原始方案文档 | 全文 |

---

## 八、术语速查

| 术语 | 做什么的 | 在这套系统里的实例 |
|------|---------|-------------------|
| **DNS** | 域名 → IP | `lightrag.test.osinfra.cn` → ELB IP |
| **ELB** | 负载均衡入口，分发流量到 Ingress Pod | 华为云 ELB，cn-north-4 |
| **Ingress** | 基于 Host 头路由，TLS 终止 | nginx Ingress，规则在 robot-ingress.yaml |
| **Service** | 动态发现 Pod，端口映射 | `web-server-robot:5000`，selector: `app: forum-robot` |
| **Pod** | 跑业务代码的容器 | forum-robot，`main.py:5000` |
| **SecretDefinition** | 从 Vault 拉证书自动生成 k8s Secret | `discourse-tls`，Vault path `secrets/data/infra-test/domain-tls` |
| **ArgoCD** | GitOps，自动同步 repo 变更到集群 | helm-charts + helm-chart-value 的自动部署 |

---

## 🔗 相关笔记

- [[issue-921-helm改动对比分析]] — 本链路对应的 helm-charts 具体改动
- [[Issue-921-测试命令]] — 链路打通后的验证命令
- [[issue-921-OIDC认证完整机制]] — 同 Issue：认证机制
- [[RAG API 测试环境联调指南]] — 联调手册

> 专题索引：[[Issue 专题]] · 返回 [[首页]]
