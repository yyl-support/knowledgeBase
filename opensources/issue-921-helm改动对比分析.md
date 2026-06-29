---
tags:
  - issue-921
  - 部署
  - helm
  - RAG
  - forum-reply-robot
issue: 921
service: forum-reply-robot
---

# issue-921 Helm 改动对比分析

> 对比基准：`origin/` 目录（原始 helm-charts、helm-chart-value）
> 改动目录：`/Users/gorden/huawei/git/common/helm-charts/`、`/Users/gorden/huawei/git/common/helm-chart-value/`
> 目的：为 forum-robot（forum-reply-robot）打通 RAG API 对外域名访问通道

---

## 一、改动总览

| 层 | 仓库 | 改动文件 | 改动类型 |
|----|------|---------|---------|
| 模板层 | helm-charts | `charts/discourse/templates/robot-service.yaml` | **新增** |
| 模板层 | helm-charts | `charts/discourse/templates/robot-ingress.yaml` | **新增** |
| 取值层 | helm-chart-value | `openeuler/discourse/test/values.yaml` | **追加** |
| 取值层 | helm-chart-value | `openeuler/discourse/prod/values.yaml` | **追加** |

其他 discourse 模板文件（`robot.yaml`、`service.yaml`、`ingress.yaml`、`secret.yaml` 等）**未做任何修改**。

---

## 二、模板层改动详情

### 2.1 robot-service.yaml（新增）

**文件路径**：`helm-charts/charts/discourse/templates/robot-service.yaml`

**作用**：创建 k8s Service `web-server-robot`，暴露 forum-robot pod 的 5000 端口。

**模板内容**：

```yaml
{{- if .Values.robot.enabled }}
{{- with .Values.robot.service }}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "discourse.fullname" $ }}-robot
  namespace: {{ $.Values.namespace.name }}
  labels:
    {{- include "discourse.labels" $ | nindent 4 }}
spec:
  type: {{ .type | default "ClusterIP" }}
  ports:
    - name: {{ .portName | default "http" }}
      port: {{ .port }}
      targetPort: {{ .targetPort | default .port }}
      protocol: TCP
  selector:
    {{- toYaml $.Values.robot.podLabels | nindent 4 }}
{{- end }}
{{- end }}
```

**渲染后效果**（结合 test values）：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-server-robot
  namespace: discourse
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 5000
      targetPort: 5000
      protocol: TCP
  selector:
    app: forum-robot
```

### 2.2 robot-ingress.yaml（新增）

**文件路径**：`helm-charts/charts/discourse/templates/robot-ingress.yaml`

**作用**：创建 nginx Ingress `forum-robot-rag-ingress`，TLS 终止 + 域名路由到 robot Service。

**模板内容**：

```yaml
{{- if .Values.robot.enabled }}
{{- with .Values.robot.ingress }}
{{- if .enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .name }}
  namespace: {{ $.Values.namespace.name }}
  {{- with .annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - {{ .host }}
      secretName: {{ .secretName }}
  rules:
    - host: {{ .host }}
      http:
        paths:
          - path: {{ .path | default "/" }}
            pathType: {{ .pathType | default "Prefix" }}
            backend:
              service:
                name: {{ include "discourse.fullname" $ }}-robot
                port:
                  number: {{ $.Values.robot.service.port }}
{{- end }}
{{- end }}
{{- end }}
```

**渲染后效果**（结合 test values）：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: forum-robot-rag-ingress
  namespace: discourse
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "20m"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - lightrag.test.osinfra.cn
      secretName: discourse-tls
  rules:
    - host: lightrag.test.osinfra.cn
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-server-robot
                port:
                  number: 5000
```

---

## 三、取值层改动详情

### 3.1 test 环境

**文件**：`helm-chart-value/openeuler/discourse/test/values.yaml`
**行号**：255-271（在已有 `robot:` 段末尾追加）

```yaml
  # ===== RAG 对外接口（issue-921）：Service + nginx Ingress 暴露 forum-robot:5000 =====
  service:
    type: ClusterIP
    portName: http
    port: 5000
    targetPort: 5000
  ingress:
    enabled: true
    name: forum-robot-rag-ingress
    host: lightrag.test.osinfra.cn           # 测试域名
    path: /
    pathType: Prefix
    # 复用 *.test.osinfra.cn 通配证书
    secretName: discourse-tls                 # 复用现有通配证书
    annotations:
      nginx.ingress.kubernetes.io/proxy-body-size: "20m"  # 文件上传
      # 注意：forum-robot 为明文 HTTP:5000，切勿设置 backend-protocol: HTTPS
```

**改动说明**：
- `robot:` 段原有 `enabled`、`replicaCount`、`strategy`、`podLabels`、`podAnnotations`、`image`、`resources` 等**全部保持不变**
- 仅在末尾追加 `service` 和 `ingress` 两个子段
- `secretName: discourse-tls` 是最终确认值（复用通配证书，由此前对话改为原来的 `lightrag-rag-tls`）

### 3.2 prod 环境

**文件**：`helm-chart-value/openeuler/discourse/prod/values.yaml`
**行号**：255-271（同上结构，在 `robot:` 段末尾追加）

```yaml
  # ===== RAG 对外接口（issue-921）：Service + nginx Ingress 暴露 forum-robot:5000 =====
  service:
    type: ClusterIP
    portName: http
    port: 5000
    targetPort: 5000
  ingress:
    enabled: true
    name: forum-robot-rag-ingress
    # TODO: 确认 prod RAG 对外域名
    host: lightrag.osinfra.cn
    path: /
    pathType: Prefix
    # TODO: discourse-tls 是 forum.openeuler.org 证书，不适用；需新建证书 secret
    secretName: lightrag-rag-tls
    annotations:
      nginx.ingress.kubernetes.io/proxy-body-size: "20m"
      # 注意：forum-robot 为明文 HTTP:5000，切勿设置 backend-protocol: HTTPS
```

**改动说明**：
- test 和 prod 的 `service` 段完全一致
- `ingress` 段差异：test 域名 `lightrag.test.osinfra.cn`，prod 域名 `lightrag.osinfra.cn`；test 复用通配证书 `discourse-tls`，prod 需独立证书 `lightrag-rag-tls`

---

## 四、改动为什么充分

原来的 k8s 部署只有：

```
robot.yaml → Deployment: forum-robot (pod, :5000)
service.yaml → Service: web-server (论坛, :8080)
ingress.yaml → Ingress: discourse 入口 (论坛域名)
```

缺少的链路：
- ❌ robot pod 没有 Service → 集群内也无统一访问入口
- ❌ 没有 Ingress → 外部完全不可达

新增后补全：

```
robot.yaml        → Deployment: forum-robot     (已有, 未改)
robot-service.yaml → Service: web-server-robot   (新增)
robot-ingress.yaml → Ingress: RAG 入口            (新增)
```

流量全链路打通：

```
用户 → DNS → ELB → Ingress → Service → Pod
         lightrag.test.osinfra.cn → web-server-robot:5000 → forum-robot:5000
```

---

## 五、改动前后对比图示

```
【改动前】                          【改动后】

k8s resource                       k8s resource
┌────────────────┐                  ┌────────────────┐
│ web-server     │                  │ web-server     │
│ Deployment     │                  │ Deployment     │
│  ├─ Service    │                  │  ├─ Service    │
│  └─ Ingress    │                  │  └─ Ingress    │
│                │                  │                │
│ forum-robot    │                  │ forum-robot    │
│ Deployment     │                  │ Deployment     │
│  ├─ Service ❌ │  ← 缺失          │  ├─ Service ✓  │  ← 新增
│  └─ Ingress ❌ │  ← 缺失          │  └─ Ingress ✓  │  ← 新增
└────────────────┘                  └────────────────┘
```

---

## 六、部署生效前提

改动推到对应 repo 后（ArgoCD 自动同步），还需要：

1. **DNS**：`lightrag.test.osinfra.cn` → ELB/Ingress 入口 IP
2. **TLS 证书**（test 已满足）：`discourse-tls` 为 `*.test.osinfra.cn` 通配证书
3. **Vault**：`robotConf.redirect_uri` 为 `https://lightrag.test.osinfra.cn/api/v1/rag/auth/callback`
4. **OneID**：回调地址注册为上述 redirect_uri

---

## 七、历史变更记录

| 时间 | 变更 | 原因 |
|------|------|------|
| 初始 | secretName: `lightrag-rag-tls` | 独立证书方案 |
| 修改 | secretName: `discourse-tls`（test） | 确认有 `*.test.osinfra.cn` 通配证书，复用 |
| 修改 | `Issue-921-测试命令.md` 域名统一 | `lightrag-cn4.test.osinfra.cn` → `lightrag.test.osinfra.cn` |

---

## 🔗 相关笔记

- [[issue-921-RAG对外域名全链路]] — DNS→ELB→Ingress→Pod 全链路（与本文 helm 改动互补）
- [[Issue-921-测试命令]] — 域名统一变更记录的来源
- [[issue-921-OIDC认证完整机制]] — 同 Issue：认证机制
- [[openUBMC RAG对外查询接口-架构设计说明书]] — 架构设计总纲

> 专题索引：[[Issue 专题]] · 返回 [[首页]]
